-- Fase 5 · Etapa 5C – Presentes, "Saiu", fechamento automático, "Chamar responsável" e telão
-- * presentes_do_culto(), marcar_saida(), desfazer_saida()
-- * Fechamento automático: cada check-in aberto fecha 3 h depois do início do culto dele
--   (sem pg_cron: roda ao abrir o check-in/Presentes/telão e no keep-alive diário).
-- * chamadas_responsavel + chamar_responsavel(), cancelar_chamada()
-- * Telão sem login: link fixo com código secreto (o banco guarda só o hash);
--   telao_chamadas() e telao_anunciar() são as únicas funções liberadas para quem não tem login.

-- 1) Check-ins: marca de saída automática -----------------------------------------
alter table public.checkins add column if not exists saida_automatica boolean not null default false;

create or replace function private.trava_checkins()
returns trigger language plpgsql set search_path = '' as $$
begin
  if private.chamada_do_app() and not private.e_lider(private.dept_sala(old.sala_id)) and (
       new.culto_id is distinct from old.culto_id or
       new.crianca_id is distinct from old.crianca_id or
       new.codigo_seguranca is distinct from old.codigo_seguranca or
       new.entrada_em is distinct from old.entrada_em or
       new.entrada_por is distinct from old.entrada_por) then
    raise exception 'Dados de entrada do check-in não podem ser alterados';
  end if;
  if new.saida_automatica then
    new.saida_por := null;                       -- saída automática: ninguém registrou
  elsif new.saida_em is not null and old.saida_em is null then
    new.saida_por := coalesce(new.saida_por, auth.uid());
  end if;
  return new;
end $$;

-- 2) Chamadas do responsável ------------------------------------------------------
create table if not exists public.chamadas_responsavel (
  id              uuid primary key default gen_random_uuid(),
  checkin_id      uuid not null references public.checkins(id) on delete cascade,
  culto_id        uuid not null references public.cultos(id) on delete cascade,
  departamento_id uuid not null references public.departamentos(id),
  situacao        text not null default 'aguardando'
                  check (situacao in ('aguardando', 'anunciada', 'cancelada')),
  chamada_em      timestamptz not null default now(),
  chamada_por     uuid,
  anunciada_em    timestamptz,
  encerrada_em    timestamptz,
  encerrada_por   uuid
);
create unique index if not exists chamadas_uma_aberta_uk
  on public.chamadas_responsavel (checkin_id) where situacao = 'aguardando';
create index if not exists chamadas_culto_idx on public.chamadas_responsavel (culto_id, situacao);

alter table public.chamadas_responsavel enable row level security;
revoke all on public.chamadas_responsavel from anon, authenticated;
grant select on public.chamadas_responsavel to authenticated;
create policy chamadas_ler on public.chamadas_responsavel for select to authenticated
  using (private.e_recepcao(departamento_id));

create trigger chamadas_responsavel_auditoria after insert or update or delete
  on public.chamadas_responsavel for each row execute function private.auditar();

alter publication supabase_realtime add table public.chamadas_responsavel;

-- 3) Acesso do telão (só o hash do código; fora da API) ---------------------------
create table if not exists private.telao_acesso (
  id              uuid primary key default gen_random_uuid(),
  departamento_id uuid not null unique references public.departamentos(id),
  codigo_hash     text not null,
  criado_em       timestamptz not null default now(),
  criado_por      uuid
);
revoke all on private.telao_acesso from public, anon, authenticated;
create trigger telao_acesso_auditoria after insert or update or delete
  on private.telao_acesso for each row execute function private.auditar();

-- 4) Funções internas -------------------------------------------------------------
-- Fim do culto = início + 3 h (horário de Brasília)
create or replace function private.fim_do_culto(p_data date, p_horario time) returns timestamptz
language sql stable set search_path to '' as $$
  select ((p_data + p_horario) + interval '3 hours') at time zone 'America/Sao_Paulo' $$;

-- Fecha os check-ins abertos de cultos que já terminaram e encerra chamadas paradas
create or replace function private.fechar_checkins_vencidos() returns int
language plpgsql security definer set search_path to '' as $$
declare v_n int;
begin
  update public.checkins k
     set saida_em = greatest(private.fim_do_culto(c.data, c.horario), k.entrada_em),  -- nunca antes da entrada
         saida_automatica = true
    from public.cultos c
   where c.id = k.culto_id and k.saida_em is null
     and private.fim_do_culto(c.data, c.horario) <= now();
  get diagnostics v_n = row_count;

  update public.chamadas_responsavel ch
     set situacao = 'cancelada', encerrada_em = now()
    from public.cultos c
   where c.id = ch.culto_id and ch.situacao = 'aguardando'
     and private.fim_do_culto(c.data, c.horario) <= now();
  return v_n;
end $$;

-- "Maria Clara da Silva" -> "Maria Silva"
create or replace function private.primeiro_ultimo(p_nome text) returns text
language sql immutable set search_path to '' as $$
  select case when cardinality(a) > 1 then a[1] || ' ' || a[cardinality(a)] else a[1] end
    from (select regexp_split_to_array(btrim(coalesce(p_nome, '')), '\s+') a) x $$;

-- Departamento do código do telão (null se inválido)
create or replace function private.telao_dept(p_codigo text) returns uuid
language sql stable security definer set search_path to '' as $$
  select t.departamento_id from private.telao_acesso t
   where p_codigo ~ '^[0-9a-f]{32}$'
     and t.codigo_hash = encode(sha256(convert_to(p_codigo, 'UTF8')), 'hex') $$;

-- Check-in do dia (para Saiu/Chamar): confere permissão e devolve a linha
create or replace function private.checkin_do_dia(p_checkin uuid) returns public.checkins
language plpgsql stable security definer set search_path to '' as $$
declare v_k public.checkins%rowtype;
begin
  select k.* into v_k from public.checkins k
    join public.cultos c on c.id = k.culto_id
   where k.id = p_checkin and c.data = private.hoje();
  if not found or not private.e_recepcao(private.dept_sala(v_k.sala_id)) then
    raise exception 'Check-in de hoje não encontrado ou sem permissão';
  end if;
  return v_k;
end $$;

-- 5) cultos_de_hoje() passa a fechar os vencidos antes -----------------------------
create or replace function public.cultos_de_hoje() returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_agora time := (now() at time zone 'America/Sao_Paulo')::time;
begin
  if not private.e_recepcao(private.dept_kids()) then
    raise exception 'Sem permissão';
  end if;
  perform private.gerar_cultos(14);
  perform private.fechar_checkins_vencidos();
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

-- 6) keep_alive() também fecha os vencidos (continua só respondendo "ok") ----------
create or replace function public.keep_alive() returns text
language plpgsql security definer set search_path to '' as $$
begin
  perform private.fechar_checkins_vencidos();
  return 'ok';
end $$;

-- 7) presentes_do_culto(culto) ------------------------------------------------------
create or replace function public.presentes_do_culto(p_culto uuid) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v_c public.cultos%rowtype;
  v_salas jsonb;
  v_lider boolean;
  v_fim timestamptz;
  v_ids uuid[];
begin
  if not private.e_recepcao(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  select * into v_c from public.cultos where id = p_culto and data = private.hoje();
  if not found then raise exception 'Escolha um culto de hoje'; end if;
  perform private.fechar_checkins_vencidos();
  v_salas := private.salas_do_culto_json(v_c.id, v_c.culto_recorrente_id, false);
  v_lider := private.e_lider(private.dept_kids());
  v_fim := private.fim_do_culto(v_c.data, v_c.horario);
  select array_agg(x::uuid) into v_ids
    from jsonb_array_elements(v_salas) g, jsonb_array_elements_text(g->'salas') x;

  return jsonb_build_object(
    'culto', jsonb_build_object('id', v_c.id, 'nome', v_c.nome,
               'horario', to_char(v_c.horario, 'HH24:MI'), 'encerrado', v_fim <= now()),
    'salas', coalesce((
      select jsonb_agg(sl order by ord) from (
        -- grupos do dia (salas juntas = um grupo)
        select g.ordinality as ord, jsonb_build_object(
                 'sala_id', g.value->>'sala_id', 'nome', g.value->>'nome',
                 'cancelada', (g.value->>'cancelada')::boolean,
                 'criancas', private.presentes_json(v_c, array(
                     select x::uuid from jsonb_array_elements_text(g.value->'salas') x), v_lider)) sl
          from jsonb_array_elements(v_salas) with ordinality g
        union all
        -- check-ins em sala que não está mais no culto (raro)
        select 1000 + row_number() over (order by s.ordem), jsonb_build_object(
                 'sala_id', s.id, 'nome', s.nome, 'cancelada', true,
                 'criancas', private.presentes_json(v_c, array[s.id], v_lider))
          from public.salas s
         where s.id in (select k.sala_id from public.checkins k where k.culto_id = v_c.id)
           and not (s.id = any (coalesce(v_ids, '{}')))
      ) z
    ), '[]'::jsonb));
end $$;

-- crianças de um grupo de salas no culto (usada por presentes_do_culto)
create or replace function private.presentes_json(p_culto public.cultos, p_salas uuid[], p_lider boolean)
returns jsonb language sql stable security definer set search_path to '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'checkin_id', k.id, 'crianca_id', c.id, 'pessoa_id', c.pessoa_id, 'nome', p.nome,
    'codigo', k.codigo_seguranca, 'alergias', c.alergias_observacoes,
    'aniversario', private.aniversario_perto(p.data_nascimento, p_culto.data),
    'entrada_em', k.entrada_em, 'saiu', k.saida_em is not null, 'saida_em', k.saida_em,
    'saida_automatica', k.saida_automatica,
    'pode_desfazer', p_lider or k.entrada_em > now() - interval '30 minutes',
    'chamada', (select jsonb_build_object('id', ch.id, 'situacao', ch.situacao,
                                          'chamada_em', ch.chamada_em, 'anunciada_em', ch.anunciada_em)
                  from public.chamadas_responsavel ch
                 where ch.checkin_id = k.id and ch.situacao <> 'cancelada'
                 order by ch.chamada_em desc limit 1))
    order by (k.saida_em is not null), p.nome), '[]'::jsonb)
  from public.checkins k
  join public.criancas c on c.id = k.crianca_id
  join public.pessoas p on p.id = c.pessoa_id
  where k.culto_id = p_culto.id and k.sala_id = any (p_salas) $$;

-- 8) "Saiu" opcional -------------------------------------------------------------------
create or replace function public.marcar_saida(p_checkin uuid) returns text
language plpgsql security definer set search_path to '' as $$
declare v_k public.checkins%rowtype;
begin
  v_k := private.checkin_do_dia(p_checkin);
  if v_k.saida_em is not null then return 'ok'; end if;
  update public.checkins set saida_em = now(), saida_por = auth.uid() where id = v_k.id;
  update public.chamadas_responsavel set situacao = 'cancelada', encerrada_em = now(), encerrada_por = auth.uid()
   where checkin_id = v_k.id and situacao = 'aguardando';
  return 'ok';
end $$;

create or replace function public.desfazer_saida(p_checkin uuid) returns text
language plpgsql security definer set search_path to '' as $$
declare v_k public.checkins%rowtype; v_c public.cultos%rowtype;
begin
  v_k := private.checkin_do_dia(p_checkin);
  if v_k.saida_em is null then return 'ok'; end if;
  select * into v_c from public.cultos where id = v_k.culto_id;
  if v_k.saida_automatica or private.fim_do_culto(v_c.data, v_c.horario) <= now() then
    raise exception 'O culto já terminou: a saída não pode ser desfeita';
  end if;
  update public.checkins set saida_em = null, saida_por = null where id = v_k.id;
  return 'ok';
end $$;

-- 9) Chamar responsável ------------------------------------------------------------------
create or replace function public.chamar_responsavel(p_checkin uuid) returns uuid
language plpgsql security definer set search_path to '' as $$
declare v_k public.checkins%rowtype; v_c public.cultos%rowtype; v_id uuid;
begin
  v_k := private.checkin_do_dia(p_checkin);
  if v_k.saida_em is not null then raise exception 'A criança já saiu'; end if;
  select * into v_c from public.cultos where id = v_k.culto_id;
  if private.fim_do_culto(v_c.data, v_c.horario) <= now() then
    raise exception 'O culto já terminou';
  end if;
  select id into v_id from public.chamadas_responsavel
   where checkin_id = v_k.id and situacao = 'aguardando';
  if found then return v_id; end if;
  insert into public.chamadas_responsavel (checkin_id, culto_id, departamento_id, chamada_por)
  values (v_k.id, v_k.culto_id, private.dept_sala(v_k.sala_id), auth.uid())
  on conflict do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.chamadas_responsavel
     where checkin_id = v_k.id and situacao = 'aguardando';
  end if;
  return v_id;
end $$;

create or replace function public.cancelar_chamada(p_chamada uuid) returns text
language plpgsql security definer set search_path to '' as $$
declare v_ch public.chamadas_responsavel%rowtype;
begin
  select * into v_ch from public.chamadas_responsavel where id = p_chamada;
  if not found or not private.e_recepcao(v_ch.departamento_id) then
    raise exception 'Chamada não encontrada ou sem permissão';
  end if;
  if v_ch.situacao <> 'aguardando' then return 'ok'; end if;
  update public.chamadas_responsavel
     set situacao = 'cancelada', encerrada_em = now(), encerrada_por = auth.uid()
   where id = p_chamada;
  return 'ok';
end $$;

-- 10) Link do telão (liderança) ------------------------------------------------------------
-- Gera (ou troca) o código. O código só é devolvido aqui, uma vez; o banco guarda o hash.
create or replace function public.gerar_link_telao() returns text
language plpgsql security definer set search_path to '' as $$
declare v_dept uuid := private.dept_kids(); v_cod text;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  v_cod := replace(gen_random_uuid()::text, '-', '');   -- 32 caracteres, 122 bits aleatórios
  insert into private.telao_acesso (departamento_id, codigo_hash, criado_por)
  values (v_dept, encode(sha256(convert_to(v_cod, 'UTF8')), 'hex'), auth.uid())
  on conflict (departamento_id) do update
    set codigo_hash = excluded.codigo_hash, criado_em = now(), criado_por = excluded.criado_por;
  return v_cod;
end $$;

create or replace function public.situacao_telao() returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare v_dept uuid := private.dept_kids();
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  return coalesce((
    select jsonb_build_object('ativo', true, 'criado_em', t.criado_em,
             'criado_por', (select private.primeiro_ultimo(p.nome) from public.perfis pf
                              join public.pessoas p on p.id = pf.pessoa_id where pf.id = t.criado_por))
      from private.telao_acesso t where t.departamento_id = v_dept),
    jsonb_build_object('ativo', false));
end $$;

create or replace function public.desligar_telao() returns text
language plpgsql security definer set search_path to '' as $$
declare v_dept uuid := private.dept_kids();
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  delete from private.telao_acesso where departamento_id = v_dept;
  return 'ok';
end $$;

-- 11) Funções do telão (sem login) ---------------------------------------------------------
-- Só as chamadas aguardando de hoje: primeiro e último nome da criança e do responsável
-- principal, código e sala. Nada de telefone, alergia, foto ou data de nascimento.
create or replace function public.telao_chamadas(p_codigo text) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_dept uuid := private.telao_dept(p_codigo);
begin
  if v_dept is null then raise exception 'Link do telão inválido'; end if;
  perform private.fechar_checkins_vencidos();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', ch.id,
      'crianca', private.primeiro_ultimo(pc.nome),
      'responsavel', (select private.primeiro_ultimo(pr.nome)
                        from public.responsaveis r join public.pessoas pr on pr.id = r.pessoa_id
                       where r.familia_id = c.familia_id
                       order by r.principal desc, pr.nome limit 1),
      'codigo', k.codigo_seguranca,
      'sala', private.nome_sala_culto(
                private.salas_do_culto_json(cu.id, cu.culto_recorrente_id, false), k.sala_id),
      'chamada_em', ch.chamada_em) order by ch.chamada_em)
    from public.chamadas_responsavel ch
    join public.checkins k on k.id = ch.checkin_id
    join public.cultos cu on cu.id = ch.culto_id and cu.data = private.hoje()
    join public.criancas c on c.id = k.crianca_id
    join public.pessoas pc on pc.id = c.pessoa_id
    where ch.departamento_id = v_dept and ch.situacao = 'aguardando'
  ), '[]'::jsonb);
end $$;

create or replace function public.telao_anunciar(p_codigo text, p_chamada uuid) returns text
language plpgsql security definer set search_path to '' as $$
declare v_dept uuid := private.telao_dept(p_codigo);
begin
  if v_dept is null then raise exception 'Link do telão inválido'; end if;
  update public.chamadas_responsavel
     set situacao = 'anunciada', anunciada_em = now(), encerrada_em = now()
   where id = p_chamada and departamento_id = v_dept and situacao = 'aguardando';
  return 'ok';
end $$;

-- Permissões -----------------------------------------------------------------------------
revoke all on function private.fim_do_culto(date, time) from public, anon, authenticated;
revoke all on function private.fechar_checkins_vencidos() from public, anon, authenticated;
revoke all on function private.primeiro_ultimo(text) from public, anon, authenticated;
revoke all on function private.telao_dept(text) from public, anon, authenticated;
revoke all on function private.checkin_do_dia(uuid) from public, anon, authenticated;
revoke all on function private.presentes_json(public.cultos, uuid[], boolean) from public, anon, authenticated;

revoke all on function public.cultos_de_hoje() from public, anon;
revoke all on function public.presentes_do_culto(uuid) from public, anon;
revoke all on function public.marcar_saida(uuid) from public, anon;
revoke all on function public.desfazer_saida(uuid) from public, anon;
revoke all on function public.chamar_responsavel(uuid) from public, anon;
revoke all on function public.cancelar_chamada(uuid) from public, anon;
revoke all on function public.gerar_link_telao() from public, anon;
revoke all on function public.situacao_telao() from public, anon;
revoke all on function public.desligar_telao() from public, anon;
grant execute on function public.cultos_de_hoje() to authenticated;
grant execute on function public.presentes_do_culto(uuid) to authenticated;
grant execute on function public.marcar_saida(uuid) to authenticated;
grant execute on function public.desfazer_saida(uuid) to authenticated;
grant execute on function public.chamar_responsavel(uuid) to authenticated;
grant execute on function public.cancelar_chamada(uuid) to authenticated;
grant execute on function public.gerar_link_telao() to authenticated;
grant execute on function public.situacao_telao() to authenticated;
grant execute on function public.desligar_telao() to authenticated;

revoke all on function public.keep_alive() from public;
revoke all on function public.telao_chamadas(text) from public;
revoke all on function public.telao_anunciar(text, uuid) from public;
grant execute on function public.keep_alive() to anon, authenticated;
grant execute on function public.telao_chamadas(text) to anon, authenticated;
grant execute on function public.telao_anunciar(text, uuid) to anon, authenticated;
