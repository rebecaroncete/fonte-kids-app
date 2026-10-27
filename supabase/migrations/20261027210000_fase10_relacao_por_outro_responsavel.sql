-- =====================================================================
-- Fase 10 · Etapa 5D (complemento) – relações informadas por outro
-- responsável da família e cônjuge/parceiro(a) (27/10/2026)
--
-- 1. pode_ver_relacao(): a família e a recepção/liderança também veem a
--    relação ENTRE os responsáveis da mesma família (cônjuge).
-- 2. relacoes_da_familia(família): relações dos responsáveis com as
--    crianças e entre si, dizendo se foi informada pela própria pessoa.
-- 3. informar_relacoes_de(responsável, lista): um responsável informa a
--    relação de OUTRO responsável da mesma família com as crianças, sem
--    que ele precise entrar no app. Não sobrescreve o que a própria
--    pessoa já informou no login dela (vale o dela). Aviso à liderança.
-- 4. informar_conjuge(responsável, sim/não): marca ou desmarca
--    cônjuge/parceiro(a) entre o login e outro responsável da família.
-- A pendência "relação não informada" continua somindo sozinha pelos
-- gatilhos da Fase 4.
-- Aplicada pelo MCP em 3 partes: fase10_relacao_por_outro_responsavel,
-- ..._correcao (coluna ambígua) e fase10_relacoes_da_familia_trava (família vazia).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Quem vê a relação entre dois adultos responsáveis da mesma família
-- ---------------------------------------------------------------------
create or replace function private.pode_ver_relacao(a uuid, b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select private.e_lider_algum()
    or (select private.minha_pessoa()) in (a, b)
    or exists (select 1 from public.criancas c where c.pessoa_id in (a, b) and (
         c.familia_id in (select private.minhas_familias())
         or private.e_recepcao(private.dept_familia(c.familia_id))
         or c.familia_id in (select private.familias_visiveis_hoje())))
    or exists (select 1 from public.responsaveis ra
               join public.responsaveis rb on rb.familia_id = ra.familia_id
               where ra.pessoa_id = a and rb.pessoa_id = b and (
                 ra.familia_id in (select private.minhas_familias())
                 or private.e_recepcao(private.dept_familia(ra.familia_id))))
$$;

-- ---------------------------------------------------------------------
-- 2. Relações da família (para "Minha família" e a ficha da família)
-- ---------------------------------------------------------------------
create or replace function public.relacoes_da_familia(p_familia uuid)
returns table (pessoa_id uuid, relacionada_id uuid, tipo text, detalhe text, pelo_proprio boolean)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if p_familia is null
     or not coalesce(p_familia in (select private.minhas_familias())
                     or private.e_recepcao(private.dept_familia(p_familia)), false) then
    raise exception 'Família não encontrada ou sem permissão';
  end if;
  return query
  with adultos as (select r.pessoa_id as pid from public.responsaveis r where r.familia_id = p_familia),
       criancas as (select c.pessoa_id as pid from public.criancas c where c.familia_id = p_familia)
  select x.pessoa_id, x.relacionada_id, x.tipo::text, x.detalhe,
         exists (select 1 from public.perfis pf where pf.id = x.informado_por and pf.pessoa_id = x.pessoa_id)
  from public.relacoes_pessoas x
  where (x.pessoa_id in (select a.pid from adultos a) and x.relacionada_id in (select k.pid from criancas k))
     or (x.relacionada_id in (select a.pid from adultos a) and x.pessoa_id in (select k.pid from criancas k))
     or (x.tipo = 'conjuge' and x.pessoa_id in (select a.pid from adultos a)
         and x.relacionada_id in (select a.pid from adultos a));
end $$;
revoke all on function public.relacoes_da_familia(uuid) from public, anon;
grant execute on function public.relacoes_da_familia(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Informar a relação de outro responsável com as crianças
--    p_relacoes: [{"crianca": "<id da criança>", "tipo": "pai", "detalhe": null}, ...]
--    Retorna {"gravadas": n, "mantidas": n} (mantidas = a própria pessoa já informou).
-- ---------------------------------------------------------------------
create or replace function public.informar_relacoes_de(p_responsavel uuid, p_relacoes jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eu uuid := private.minha_pessoa();
  v_fam uuid;
  v_alvo uuid;
  v_item jsonb;
  v_cri uuid;
  v_tipo public.relacao_tipo;
  v_det text;
  v_rel public.relacoes_pessoas%rowtype;
  v_proprio boolean;
  v_gravadas int := 0;
  v_mantidas int := 0;
  v_nome_eu text;
  v_nome_alvo text;
begin
  if v_eu is null then raise exception 'Conclua o primeiro acesso antes de continuar'; end if;
  select r.familia_id, r.pessoa_id into v_fam, v_alvo from public.responsaveis r where r.id = p_responsavel;
  if v_fam is null or not exists (select 1 from public.responsaveis r where r.familia_id = v_fam and r.pessoa_id = v_eu) then
    raise exception 'Responsável não encontrado ou sem permissão';
  end if;
  if jsonb_typeof(p_relacoes) <> 'array' or jsonb_array_length(p_relacoes) > 20 then
    raise exception 'Lista de relações inválida';
  end if;

  for v_item in select * from jsonb_array_elements(p_relacoes) loop
    select c.pessoa_id into v_cri from public.criancas c
     where c.id = (v_item->>'crianca')::uuid and c.familia_id = v_fam;
    if v_cri is null then raise exception 'Criança não encontrada ou sem permissão'; end if;
    begin
      v_tipo := (v_item->>'tipo')::public.relacao_tipo;
    exception when others then
      raise exception 'Tipo de relação inválido para uma criança';
    end;
    if v_tipo is null or v_tipo = 'conjuge' then raise exception 'Tipo de relação inválido para uma criança'; end if;
    v_det := nullif(btrim(coalesce(v_item->>'detalhe', '')), '');
    if v_tipo = 'outro' and v_det is null then raise exception 'Descreva a relação (ex.: madrinha)'; end if;
    if char_length(coalesce(v_det, '')) > 60 then raise exception 'Descreva a relação em até 60 letras'; end if;

    select * into v_rel from public.relacoes_pessoas
     where (pessoa_id = v_alvo and relacionada_id = v_cri) or (pessoa_id = v_cri and relacionada_id = v_alvo)
     order by criado_em limit 1;

    if found then
      v_proprio := v_alvo <> v_eu and exists (select 1 from public.perfis pf where pf.id = v_rel.informado_por and pf.pessoa_id = v_alvo);
      if v_proprio then
        v_mantidas := v_mantidas + 1;
        continue;
      end if;
      delete from public.relacoes_pessoas
       where id <> v_rel.id
         and ((pessoa_id = v_alvo and relacionada_id = v_cri) or (pessoa_id = v_cri and relacionada_id = v_alvo));
      update public.relacoes_pessoas
         set pessoa_id = v_alvo, relacionada_id = v_cri, tipo = v_tipo, detalhe = v_det,
             origem = 'responsavel', informado_por = auth.uid()
       where id = v_rel.id;
    else
      insert into public.relacoes_pessoas (pessoa_id, relacionada_id, tipo, detalhe, origem, informado_por)
      values (v_alvo, v_cri, v_tipo, v_det, 'responsavel', auth.uid());
    end if;
    v_gravadas := v_gravadas + 1;
  end loop;

  if v_gravadas > 0 and v_alvo <> v_eu then
    select nome into v_nome_eu from public.pessoas where id = v_eu;
    select nome into v_nome_alvo from public.pessoas where id = v_alvo;
    perform private.avisar_lideranca_kids('Relação informada pela família',
      coalesce(v_nome_eu, 'Um responsável') || ' informou a relação de ' || coalesce(v_nome_alvo, 'outro responsável')
        || ' com ' || v_gravadas || case when v_gravadas > 1 then ' crianças.' else ' criança.' end,
      '#/ficha?tipo=familia&id=' || v_fam, 'cadastro_editado');
  end if;
  return jsonb_build_object('gravadas', v_gravadas, 'mantidas', v_mantidas);
end $$;
revoke all on function public.informar_relacoes_de(uuid, jsonb) from public, anon;
grant execute on function public.informar_relacoes_de(uuid, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Cônjuge/parceiro(a) entre o login e outro responsável da família
-- ---------------------------------------------------------------------
create or replace function public.informar_conjuge(p_responsavel uuid, p_conjuge boolean)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eu uuid := private.minha_pessoa();
  v_fam uuid;
  v_alvo uuid;
  v_existe boolean;
  v_nome_eu text;
  v_nome_alvo text;
begin
  if v_eu is null then raise exception 'Conclua o primeiro acesso antes de continuar'; end if;
  select r.familia_id, r.pessoa_id into v_fam, v_alvo from public.responsaveis r where r.id = p_responsavel;
  if v_fam is null or v_alvo = v_eu
     or not exists (select 1 from public.responsaveis r where r.familia_id = v_fam and r.pessoa_id = v_eu) then
    raise exception 'Responsável não encontrado ou sem permissão';
  end if;

  v_existe := exists (select 1 from public.relacoes_pessoas
                      where tipo = 'conjuge'
                        and ((pessoa_id = v_eu and relacionada_id = v_alvo) or (pessoa_id = v_alvo and relacionada_id = v_eu)));
  if coalesce(p_conjuge, false) = v_existe then return 'sem mudança'; end if;

  if p_conjuge then
    insert into public.relacoes_pessoas (pessoa_id, relacionada_id, tipo, origem, informado_por)
    values (v_eu, v_alvo, 'conjuge', 'responsavel', auth.uid())
    on conflict do nothing;
  else
    delete from public.relacoes_pessoas
     where tipo = 'conjuge'
       and ((pessoa_id = v_eu and relacionada_id = v_alvo) or (pessoa_id = v_alvo and relacionada_id = v_eu));
  end if;

  select nome into v_nome_eu from public.pessoas where id = v_eu;
  select nome into v_nome_alvo from public.pessoas where id = v_alvo;
  perform private.avisar_lideranca_kids('Cônjuge informado pela família',
    coalesce(v_nome_eu, 'Um responsável')
      || case when p_conjuge then ' informou que é cônjuge/parceiro(a) de ' else ' desmarcou como cônjuge/parceiro(a) ' end
      || coalesce(v_nome_alvo, 'outro responsável') || '.',
    '#/ficha?tipo=familia&id=' || v_fam, 'cadastro_editado');
  return case when p_conjuge then 'cônjuge registrado' else 'cônjuge removido' end;
end $$;
revoke all on function public.informar_conjuge(uuid, boolean) from public, anon;
grant execute on function public.informar_conjuge(uuid, boolean) to authenticated;
