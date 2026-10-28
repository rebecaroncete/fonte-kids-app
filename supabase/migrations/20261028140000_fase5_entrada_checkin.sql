-- Fase 5 · Etapa 5B – Entrada do check-in
-- * Check-in gravado só pelas funções (sem inserir/alterar/apagar direto pelo app).
-- * Regra da sala no culto (sala fixa ou faixa de idade na data do culto; salas juntas; sala fechada).
-- * cultos_de_hoje(), buscar_para_checkin(), fazer_checkin(), desfazer_checkin(), meus_checkins_hoje().
-- * editar_crianca() passa a aceitar a recepção/liderança do departamento (aviso só quando é o responsável).

-- 1) Gravação só pelas funções -------------------------------------------------
drop policy if exists checkins_criar on public.checkins;
drop policy if exists checkins_editar on public.checkins;
drop policy if exists checkins_apagar on public.checkins;
revoke insert, update, delete, truncate on public.checkins from anon, authenticated;

-- 2) Funções internas -----------------------------------------------------------
create or replace function private.dept_kids() returns uuid
language sql stable security definer set search_path to '' as $$
  select id from public.departamentos where slug = 'kids' limit 1 $$;

-- Aniversário de 7 dias antes a 7 dias depois da data (29/02 vira 28/02 em ano comum)
create or replace function private.aniversario_perto(p_nasc date, p_data date) returns boolean
language sql immutable set search_path to '' as $$
  select p_nasc is not null and exists (
    select 1 from generate_series(-1, 1) a,
    lateral (select extract(year from p_data)::int + a as ano) y,
    lateral (select case when extract(month from p_nasc) = 2 and extract(day from p_nasc) = 29
                          and not (y.ano % 4 = 0 and (y.ano % 100 <> 0 or y.ano % 400 = 0))
                     then make_date(y.ano, 2, 28)
                     else make_date(y.ano, extract(month from p_nasc)::int, extract(day from p_nasc)::int) end as dia) d
    where abs(d.dia - p_data) <= 7) $$;

-- Sala da criança num culto. motivo: sem_data | data_invalida | acima_idade | sem_faixa | sala_fechada
create or replace function private.sala_no_culto(p_crianca uuid, p_culto uuid,
  out sala_id uuid, out motivo text)
language plpgsql stable security definer set search_path to '' as $$
declare
  v_c public.criancas%rowtype;
  v_nasc date;
  v_data date;
  v_base uuid;
  v_idade int;
  v_cs record;
begin
  select * into v_c from public.criancas where id = p_crianca;
  select data into v_data from public.cultos where id = p_culto;
  select data_nascimento into v_nasc from public.pessoas where id = v_c.pessoa_id;

  if v_c.sala_fixa_id is not null
     and exists (select 1 from public.salas s where s.id = v_c.sala_fixa_id and s.ativa) then
    v_base := v_c.sala_fixa_id;
  elsif v_nasc is null then
    motivo := 'sem_data'; return;
  elsif v_nasc > v_data then
    motivo := 'data_invalida'; return;
  else
    v_idade := extract(year from age(v_data, v_nasc))::int;
    select s.id into v_base from public.salas s
     where s.ativa and s.departamento_id = private.dept_kids()
       and v_idade between s.idade_min and s.idade_max
     order by s.ordem limit 1;
    if v_base is null then
      if v_idade > coalesce((select max(idade_max) from public.salas
                              where ativa and departamento_id = private.dept_kids()), 12) then
        motivo := 'acima_idade';
      else
        motivo := 'sem_faixa';
      end if;
      return;
    end if;
  end if;

  select cs.cancelada, cs.combinada_com_sala_id into v_cs
    from public.culto_salas cs where cs.culto_id = p_culto and cs.sala_id = v_base;
  if found and v_cs.combinada_com_sala_id is not null then
    v_base := v_cs.combinada_com_sala_id;
    select cs.cancelada, cs.combinada_com_sala_id into v_cs
      from public.culto_salas cs where cs.culto_id = p_culto and cs.sala_id = v_base;
  end if;
  if found and coalesce(v_cs.cancelada, false) then
    motivo := 'sala_fechada'; return;
  end if;
  sala_id := v_base;
end $$;

-- Nome da sala como aparece no culto (salas juntas = "7 a 12 anos")
create or replace function private.nome_sala_culto(p_salas jsonb, p_sala uuid) returns text
language sql immutable set search_path to '' as $$
  select e->>'nome' from jsonb_array_elements(coalesce(p_salas, '[]'::jsonb)) e
   where (e->>'sala_id')::uuid = p_sala limit 1 $$;

-- Culto de hoje válido para check-in (erro se não for)
create or replace function private.culto_hoje_valido(p_culto uuid) returns public.cultos
language plpgsql stable security definer set search_path to '' as $$
declare v public.cultos%rowtype;
begin
  select * into v from public.cultos where id = p_culto;
  if not found or v.data <> private.hoje() then
    raise exception 'Escolha um culto de hoje';
  end if;
  if v.cancelado then raise exception 'Este culto foi cancelado'; end if;
  return v;
end $$;

-- 3) cultos_de_hoje() -----------------------------------------------------------
create or replace function public.cultos_de_hoje() returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_agora time := (now() at time zone 'America/Sao_Paulo')::time;
begin
  if not private.e_recepcao(private.dept_kids()) then
    raise exception 'Sem permissão';
  end if;
  perform private.gerar_cultos(14);
  return coalesce((
    with c as (
      select c.*, row_number() over (order by c.horario) as n,
             count(*) over () as total
        from public.cultos c
       where c.data = private.hoje() and not c.cancelado
    ),
    sug as (  -- o primeiro que ainda não terminou (horário + 3h); senão o último
      select coalesce(
        (select id from c where c.horario + interval '3 hours' >= v_agora order by c.horario limit 1),
        (select id from c order by c.horario desc limit 1)) as id
    )
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'nome', c.nome, 'horario', to_char(c.horario, 'HH24:MI'),
      'extra', c.culto_recorrente_id is null,
      'sugerido', c.id = (select id from sug),
      'presentes', (select count(*) from public.checkins k where k.culto_id = c.id and k.saida_em is null),
      'salas', private.salas_do_culto_json(c.id, c.culto_recorrente_id, false))
      order by c.horario)
    from c
  ), '[]'::jsonb);
end $$;

-- 4) buscar_para_checkin(culto, texto) -----------------------------------------
-- Nome da criança ou do responsável (2+ letras, sem acento, todas as palavras)
-- ou os 4 últimos dígitos do telefone de um responsável. Até 20 famílias.
create or replace function public.buscar_para_checkin(p_culto uuid, p_texto text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v_culto public.cultos%rowtype;
  v_dept uuid := private.dept_kids();
  v_txt text := private.normalizar_nome(p_texto);
  v_dig text := regexp_replace(coalesce(p_texto, ''), '\D', '', 'g');
  v_pal text[];
  v_salas jsonb;
  v_fams uuid[];
begin
  if not private.e_recepcao(v_dept) then raise exception 'Sem permissão'; end if;
  v_culto := private.culto_hoje_valido(p_culto);
  v_salas := private.salas_do_culto_json(v_culto.id, v_culto.culto_recorrente_id, false);

  if char_length(v_dig) = 4 and v_txt is null then
    select array_agg(distinct r.familia_id) into v_fams
      from public.responsaveis r
      join public.pessoas p on p.id = r.pessoa_id
      join public.familias f on f.id = r.familia_id and f.departamento_id = v_dept
     where right(regexp_replace(coalesce(p.telefone, ''), '\D', '', 'g'), 4) = v_dig;
  elsif char_length(coalesce(v_txt, '')) >= 2 then
    v_pal := array(select '%' || w || '%' from unnest(string_to_array(v_txt, ' ')) w where w <> '');
    select array_agg(x.familia_id order by x.pri, x.nome) into v_fams from (
      select familia_id, min(pri) pri, min(nome) nome from (
        select c.familia_id, 1 pri, p.nome_busca nome
          from public.criancas c join public.pessoas p on p.id = c.pessoa_id
         where c.ativo and p.nome_busca like all (v_pal)
        union all
        select r.familia_id, 2, p.nome_busca
          from public.responsaveis r join public.pessoas p on p.id = r.pessoa_id
         where p.nome_busca like all (v_pal)
      ) m
      join public.familias f on f.id = m.familia_id and f.departamento_id = v_dept
      where exists (select 1 from public.criancas c2 where c2.familia_id = m.familia_id and c2.ativo)
      group by familia_id
      order by min(pri), min(nome)
      limit 20
    ) x;
  else
    raise exception 'Digite ao menos 2 letras do nome ou os 4 últimos números do telefone';
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'familia_id', f.id,
      'responsaveis', coalesce((
        select jsonb_agg(jsonb_build_object('nome', p.nome, 'principal', r.principal)
                         order by r.principal desc, p.nome)
          from public.responsaveis r join public.pessoas p on p.id = r.pessoa_id
         where r.familia_id = f.id), '[]'::jsonb),
      'criancas', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', c.id, 'pessoa_id', c.pessoa_id, 'nome', p.nome,
          'alergias', c.alergias_observacoes,
          'aniversario', private.aniversario_perto(p.data_nascimento, v_culto.data),
          'sala_id', s.sala_id,
          'sala_nome', private.nome_sala_culto(v_salas, s.sala_id),
          'sem_sala', s.motivo,
          'checkin', (select jsonb_build_object('id', k.id, 'codigo', k.codigo_seguranca,
                                                'sala_nome', private.nome_sala_culto(v_salas, k.sala_id),
                                                'entrada_em', k.entrada_em, 'saiu', k.saida_em is not null)
                        from public.checkins k where k.culto_id = v_culto.id and k.crianca_id = c.id))
          order by p.nome)
          from public.criancas c
          join public.pessoas p on p.id = c.pessoa_id
          cross join lateral private.sala_no_culto(c.id, v_culto.id) s
         where c.familia_id = f.id and c.ativo), '[]'::jsonb),
      'pendencias', coalesce((
        select jsonb_agg(jsonb_build_object('id', pc.id, 'tipo', pc.tipo, 'mensagem', pc.mensagem,
                                            'automatica', pc.tipo = 'nascimento_vazio',
                                            'crianca_id', pc.crianca_id) order by pc.criado_em)
          from public.pendencias_cadastro pc
         where pc.familia_id = f.id and pc.resolvida_em is null), '[]'::jsonb))
      order by array_position(v_fams, f.id))
    from public.familias f
    where f.id = any (coalesce(v_fams, '{}'))
  ), '[]'::jsonb);
end $$;

-- 5) fazer_checkin(culto, crianças) --------------------------------------------
create or replace function public.fazer_checkin(p_culto uuid, p_criancas uuid[]) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v_culto public.cultos%rowtype;
  v_dept uuid := private.dept_kids();
  v_salas jsonb;
  v_id uuid;
  v_c record;
  v_s record;
  v_k public.checkins%rowtype;
  v_ja boolean;
  v_saida jsonb := '[]'::jsonb;
begin
  if not private.e_recepcao(v_dept) then raise exception 'Sem permissão'; end if;
  v_culto := private.culto_hoje_valido(p_culto);
  if p_criancas is null or cardinality(p_criancas) = 0 then
    raise exception 'Marque ao menos uma criança';
  end if;
  if cardinality(p_criancas) > 20 then raise exception 'No máximo 20 crianças por vez'; end if;
  v_salas := private.salas_do_culto_json(v_culto.id, v_culto.culto_recorrente_id, false);

  -- Confere todas antes de gravar (ou faz todas, ou nenhuma)
  foreach v_id in array p_criancas loop
    select c.id, c.ativo, f.departamento_id, p.nome into v_c
      from public.criancas c
      join public.familias f on f.id = c.familia_id
      join public.pessoas p on p.id = c.pessoa_id
     where c.id = v_id;
    if not found or v_c.departamento_id is distinct from v_dept or not v_c.ativo then
      raise exception 'Criança não encontrada ou inativa';
    end if;
    if not exists (select 1 from public.checkins where culto_id = v_culto.id and crianca_id = v_id) then
      select * into v_s from private.sala_no_culto(v_id, v_culto.id);
      if v_s.sala_id is null then
        raise exception '% está sem sala neste culto (%). Corrija os dados antes do check-in',
          v_c.nome, case v_s.motivo
            when 'sem_data' then 'sem data de nascimento'
            when 'data_invalida' then 'data de nascimento inválida'
            when 'acima_idade' then 'acima de 12 anos'
            when 'sala_fechada' then 'a sala está fechada hoje'
            else 'nenhuma sala para a idade' end;
      end if;
    end if;
  end loop;

  foreach v_id in array (select array_agg(distinct x) from unnest(p_criancas) x) loop
    v_ja := true;
    select * into v_k from public.checkins where culto_id = v_culto.id and crianca_id = v_id;
    if not found then
      select * into v_s from private.sala_no_culto(v_id, v_culto.id);
      insert into public.checkins (culto_id, crianca_id, sala_id, codigo_seguranca, entrada_por)
      values (v_culto.id, v_id, v_s.sala_id, '', auth.uid())
      on conflict (culto_id, crianca_id) do nothing
      returning * into v_k;
      if v_k.id is null then
        select * into v_k from public.checkins where culto_id = v_culto.id and crianca_id = v_id;
      else
        v_ja := false;
      end if;
    end if;
    v_saida := v_saida || jsonb_build_object(
      'crianca_id', v_id,
      'nome', (select p.nome from public.criancas c join public.pessoas p on p.id = c.pessoa_id where c.id = v_id),
      'checkin_id', v_k.id, 'codigo', v_k.codigo_seguranca,
      'sala_nome', private.nome_sala_culto(v_salas, v_k.sala_id),
      'ja_tinha', v_ja);
  end loop;
  return v_saida;
end $$;

-- 6) desfazer_checkin(id) -------------------------------------------------------
create or replace function public.desfazer_checkin(p_checkin uuid) returns text
language plpgsql security definer set search_path to '' as $$
declare v_k public.checkins%rowtype; v_dept uuid;
begin
  select * into v_k from public.checkins where id = p_checkin;
  if not found then raise exception 'Check-in não encontrado'; end if;
  v_dept := private.dept_sala(v_k.sala_id);
  if private.e_lider(v_dept) then
    null;
  elsif private.e_recepcao(v_dept) then
    if v_k.entrada_em < now() - interval '30 minutes' then
      raise exception 'Passaram 30 minutos: peça à liderança para desfazer';
    end if;
  else
    raise exception 'Sem permissão';
  end if;
  delete from public.checkins where id = p_checkin;
  return 'ok';
end $$;

-- 7) meus_checkins_hoje() (responsável) -----------------------------------------
create or replace function public.meus_checkins_hoje() returns jsonb
language plpgsql stable security definer set search_path to '' as $$
begin
  if private.minha_pessoa() is null then raise exception 'Sem permissão'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'crianca_id', c.id, 'nome', p.nome,
      'culto', cu.nome, 'horario', to_char(cu.horario, 'HH24:MI'),
      'sala_nome', private.nome_sala_culto(
                     private.salas_do_culto_json(cu.id, cu.culto_recorrente_id, false), k.sala_id),
      'codigo', k.codigo_seguranca, 'entrada_em', k.entrada_em, 'saiu', k.saida_em is not null)
      order by cu.horario, p.nome)
    from public.checkins k
    join public.cultos cu on cu.id = k.culto_id and cu.data = private.hoje()
    join public.criancas c on c.id = k.crianca_id
    join public.pessoas p on p.id = c.pessoa_id
    where c.familia_id in (select private.minhas_familias())
  ), '[]'::jsonb);
end $$;

-- 8) editar_crianca: também recepção/liderança do departamento -------------------
create or replace function public.editar_crianca(p_crianca uuid, p_nome text, p_nascimento date, p_alergias text)
 returns text
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare
  v_eu uuid := private.minha_pessoa();
  v_c public.criancas%rowtype;
  v_p public.pessoas%rowtype;
  v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
  v_alerg text := nullif(btrim(coalesce(p_alergias, '')), '');
  v_campos text[] := '{}';
  v_quem text;
  v_equipe boolean;
begin
  if v_eu is null then raise exception 'Conclua o primeiro acesso antes de continuar'; end if;
  select * into v_c from public.criancas where id = p_crianca;
  if not found then raise exception 'Criança não encontrada ou sem permissão'; end if;
  v_equipe := private.e_recepcao(private.dept_familia(v_c.familia_id));
  if not v_equipe and v_c.familia_id not in (select private.minhas_familias()) then
    raise exception 'Criança não encontrada ou sem permissão';
  end if;
  if char_length(v_nome) < 3 or char_length(v_nome) > 120 then
    raise exception 'Informe o nome completo (de 3 a 120 letras)';
  end if;
  if p_nascimento is null or p_nascimento > private.hoje() or p_nascimento <= private.hoje() - interval '18 years' then
    raise exception 'Data de nascimento inválida para uma criança';
  end if;
  if char_length(coalesce(v_alerg, '')) > 500 then
    raise exception 'Alergias e cuidados: use no máximo 500 caracteres';
  end if;
  select * into v_p from public.pessoas where id = v_c.pessoa_id;
  if v_p.nome is distinct from v_nome then v_campos := array_append(v_campos, 'nome'); end if;
  if v_p.data_nascimento is distinct from p_nascimento then v_campos := array_append(v_campos, 'data de nascimento'); end if;
  if v_c.alergias_observacoes is distinct from v_alerg then v_campos := array_append(v_campos, 'alergias e cuidados'); end if;
  if array_length(v_campos, 1) is null then return 'sem alterações'; end if;
  update public.pessoas set nome = v_nome, data_nascimento = p_nascimento
   where id = v_c.pessoa_id and (nome is distinct from v_nome or data_nascimento is distinct from p_nascimento);
  update public.criancas set alergias_observacoes = v_alerg
   where id = p_crianca and alergias_observacoes is distinct from v_alerg;
  if not v_equipe then
    select nome into v_quem from public.pessoas where id = v_eu;
    perform private.avisar_lideranca_kids('Dados de criança atualizados',
      coalesce(v_quem, 'Um responsável') || ' alterou ' || private.lista_campos(v_campos) || ' de ' || v_nome || '.',
      '#/ficha?tipo=crianca&id=' || p_crianca, 'cadastro_editado');
  end if;
  return 'ok';
end;
$function$;

-- Permissões --------------------------------------------------------------------
revoke all on function private.dept_kids() from public, anon, authenticated;
revoke all on function private.aniversario_perto(date, date) from public, anon, authenticated;
revoke all on function private.sala_no_culto(uuid, uuid) from public, anon, authenticated;
revoke all on function private.nome_sala_culto(jsonb, uuid) from public, anon, authenticated;
revoke all on function private.culto_hoje_valido(uuid) from public, anon, authenticated;

revoke all on function public.cultos_de_hoje() from public, anon;
revoke all on function public.buscar_para_checkin(uuid, text) from public, anon;
revoke all on function public.fazer_checkin(uuid, uuid[]) from public, anon;
revoke all on function public.desfazer_checkin(uuid) from public, anon;
revoke all on function public.meus_checkins_hoje() from public, anon;
revoke all on function public.editar_crianca(uuid, text, date, text) from public, anon;
grant execute on function public.cultos_de_hoje() to authenticated;
grant execute on function public.buscar_para_checkin(uuid, text) to authenticated;
grant execute on function public.fazer_checkin(uuid, uuid[]) to authenticated;
grant execute on function public.desfazer_checkin(uuid) to authenticated;
grant execute on function public.meus_checkins_hoje() to authenticated;
grant execute on function public.editar_crianca(uuid, text, date, text) to authenticated;
