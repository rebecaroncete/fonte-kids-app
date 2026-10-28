-- =====================================================================
-- Fase 9 · Indicadores e relatórios (28/10/2026)
--   1. Indicadores só para a liderança (líder do Fonte Kids, pastor,
--      admin), por funções security definer SÓ DE LEITURA:
--        indicadores_semana(dia)  semana (domingo a sábado) + semana anterior
--        indicadores_mes(mes)     mês + mês anterior; SÓ NÚMEROS (sem nomes):
--                                 é a base do "Relatório do mês" e do texto
--                                 "Mandar no grupo"
--        ultimo_culto()           cartão do Início da liderança
--        sentimos_falta()         crianças que vinham (3+ vezes em 13 semanas)
--                                 e não aparecem há 4 semanas (com nomes e
--                                 WhatsApp dos responsáveis; só no app)
--        voluntarias_sem_escala() voluntárias ativas sem escala há 2 meses
--   2. "Primeira vez" = primeiro check-in da criança no Fonte Kids (o
--      histórico começa nos check-ins importados; o período que contém o
--      início do histórico volta "primeira_vez" nulo).
--   3. "Não poderei" passa a ficar registrado (escala_recusas), para a
--      cobertura da escala; o histórico anterior não tem esse dado.
--   4. Relatório automático: no dia 1 (ou até o dia 7, se o keep-alive
--      falhar), a liderança recebe "Relatório de <mês> pronto" uma vez só
--      (relatorios_avisados), pelo keep_alive() diário.
-- Escrita só por funções security definer; RLS em tudo.
-- Toda alteração com WHERE (a API usa pg_safeupdate).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Estrutura
-- ---------------------------------------------------------------------
create table if not exists public.escala_recusas (
  id             uuid primary key default gen_random_uuid(),
  item_id        uuid references public.escala_itens(id) on delete set null,
  escala_id      uuid not null references public.escalas(id) on delete cascade,
  culto_id       uuid not null references public.cultos(id) on delete cascade,
  voluntaria_id  uuid references public.voluntarias(id) on delete set null,
  em             timestamptz not null default now()
);
create index if not exists escala_recusas_item_idx on public.escala_recusas (item_id);
create index if not exists escala_recusas_escala_idx on public.escala_recusas (escala_id);
create index if not exists escala_recusas_culto_idx on public.escala_recusas (culto_id);
create index if not exists escala_recusas_voluntaria_idx on public.escala_recusas (voluntaria_id);
alter table public.escala_recusas enable row level security;
revoke all on public.escala_recusas from anon, authenticated;

create table if not exists public.relatorios_avisados (
  mes            date primary key,
  destinatarios  integer not null default 0,
  avisado_em     timestamptz not null default now()
);
alter table public.relatorios_avisados enable row level security;
revoke all on public.relatorios_avisados from anon, authenticated;

-- ---------------------------------------------------------------------
-- 2. Ajudantes (privados)
-- ---------------------------------------------------------------------
-- Primeiro check-in de cada criança no Fonte Kids (culto e data)
create or replace function private.ind_primeiras()
returns table (crianca_id uuid, culto_id uuid, data date) language sql stable security definer set search_path = '' as $$
  select distinct on (k.crianca_id) k.crianca_id, k.culto_id, c.data
    from public.checkins k
    join public.cultos c on c.id = k.culto_id
    join public.salas s on s.id = k.sala_id and s.departamento_id = private.dept_kids()
   order by k.crianca_id, c.data, c.horario $$;

-- Dia do primeiro check-in do histórico
create or replace function private.ind_inicio_historico()
returns date language sql stable security definer set search_path = '' as $$
  select min(c.data) from public.checkins k
    join public.cultos c on c.id = k.culto_id
    join public.salas s on s.id = k.sala_id and s.departamento_id = private.dept_kids() $$;

-- Totais de presença de um período (datas dos cultos)
create or replace function private.ind_totais(p_de date, p_ate date)
returns jsonb language sql stable security definer set search_path = '' as $$
  with k as (
    select k.crianca_id, k.culto_id, cr.perfil
      from public.checkins k
      join public.cultos c on c.id = k.culto_id
      join public.salas s on s.id = k.sala_id and s.departamento_id = private.dept_kids()
      join public.criancas cr on cr.id = k.crianca_id
     where c.data between p_de and p_ate)
  select jsonb_build_object(
    'presencas', (select count(*) from k),
    'criancas', (select count(distinct crianca_id) from k),
    'membros', (select count(distinct crianca_id) from k where perfil = 'membro'),
    'visitantes', (select count(distinct crianca_id) from k where perfil = 'visitante'),
    'cultos', (select count(distinct culto_id) from k),
    'primeira_vez', case when coalesce(private.ind_inicio_historico(), p_de) >= p_de then null
                         else (select count(*) from private.ind_primeiras() p where p.data between p_de and p_ate) end) $$;

-- Escala de um período (só escalas publicadas/encerradas)
create or replace function private.ind_escala(p_de date, p_ate date)
returns jsonb language sql stable security definer set search_path = '' as $$
  with i as (
    select i.* from public.escala_itens i
      join public.escalas e on e.id = i.escala_id and e.status <> 'rascunho' and e.departamento_id = private.dept_kids()
      join public.cultos c on c.id = i.culto_id and not c.cancelado
     where c.data between p_de and p_ate)
  select jsonb_build_object(
    'vagas', (select count(*) from i where funcao <> 'lider_culto'),
    'preenchidas', (select count(*) from i where funcao <> 'lider_culto' and (voluntaria_id is not null or nome_livre is not null)),
    'cientes', (select count(*) from i where funcao <> 'lider_culto' and resposta = 'ciente'),
    'sem_resposta', (select count(*) from i where funcao <> 'lider_culto' and voluntaria_id is not null and resposta = 'pendente'),
    'cultos_sem_lider', (select count(*) from i where funcao = 'lider_culto' and voluntaria_id is null and nome_livre is null),
    'escaladas', (select count(distinct voluntaria_id) from i where voluntaria_id is not null),
    'nao_poderei', (select count(*) from public.escala_recusas r
                      join public.cultos c on c.id = r.culto_id
                      join public.escalas e on e.id = r.escala_id and e.departamento_id = private.dept_kids()
                     where c.data between p_de and p_ate)) $$;

-- ---------------------------------------------------------------------
-- 3. Indicadores da semana (domingo a sábado)
-- ---------------------------------------------------------------------
create or replace function public.indicadores_semana(p_dia date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_dia date := coalesce(p_dia, private.hoje());
  v_ini date; v_fim date; v_igreja uuid;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  v_ini := v_dia - extract(dow from v_dia)::int;
  v_fim := v_ini + 6;
  select igreja_id into v_igreja from public.departamentos where id = private.dept_kids();
  return jsonb_build_object(
    'inicio', v_ini, 'fim', v_fim, 'inicio_historico', private.ind_inicio_historico(),
    'atual', private.ind_totais(v_ini, v_fim),
    'anterior', private.ind_totais(v_ini - 7, v_fim - 7),
    'escala', private.ind_escala(v_ini, v_fim),
    'cultos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'data', c.data, 'hora', private.esc_hora(c.horario), 'nome', c.nome, 'cancelado', c.cancelado,
               'presencas', (select count(*) from public.checkins k join public.salas s on s.id = k.sala_id
                              where k.culto_id = c.id and s.departamento_id = private.dept_kids()),
               'visitantes', (select count(*) from public.checkins k join public.salas s on s.id = k.sala_id
                               join public.criancas cr on cr.id = k.crianca_id
                              where k.culto_id = c.id and s.departamento_id = private.dept_kids() and cr.perfil = 'visitante'),
               'primeira_vez', case when private.ind_inicio_historico() >= c.data then null else (
                  select count(*) from private.ind_primeiras() p where p.culto_id = c.id) end,
               'salas', (select coalesce(jsonb_agg(jsonb_build_object('nome', s.nome, 'capacidade', s.capacidade,
                                   'presencas', (select count(*) from public.checkins k where k.culto_id = c.id and k.sala_id = s.id))
                                 order by s.ordem), '[]'::jsonb)
                           from public.salas s
                          where s.departamento_id = private.dept_kids()
                            and (s.ativa or exists (select 1 from public.checkins k where k.culto_id = c.id and k.sala_id = s.id))))
             order by c.data, c.horario), '[]'::jsonb)
        from public.cultos c
       where c.igreja_id = v_igreja and c.data between v_ini and v_fim
         and (not c.cancelado or exists (select 1 from public.checkins k where k.culto_id = c.id))));
end $$;

-- ---------------------------------------------------------------------
-- 4. Indicadores do mês (SÓ NÚMEROS: base do relatório para fora)
-- ---------------------------------------------------------------------
create or replace function public.indicadores_mes(p_mes date default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  v_mes date := date_trunc('month', coalesce(p_mes, private.hoje()))::date;
  v_fim date; v_ant date; v_dept uuid := private.dept_kids(); v_hist date;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  v_ant := (v_mes - interval '1 month')::date;
  v_hist := private.ind_inicio_historico();
  return jsonb_build_object(
    'mes', v_mes, 'nome_mes', private.esc_nome_mes(v_mes), 'inicio_historico', v_hist,
    'atual', private.ind_totais(v_mes, v_fim)
             || jsonb_build_object('familias_novas', (select count(*) from public.familias f
                   where f.departamento_id = v_dept and private.dia_evento(f.criado_em) between v_mes and v_fim)),
    'anterior', private.ind_totais(v_ant, v_mes - 1)
             || jsonb_build_object('familias_novas', (select count(*) from public.familias f
                   where f.departamento_id = v_dept and private.dia_evento(f.criado_em) between v_ant and v_mes - 1)),
    -- média por tipo de culto (só cultos com check-in)
    'por_tipo', (
      select coalesce(jsonb_agg(jsonb_build_object('nome', t.nome, 'cultos', t.cultos, 'media', t.media, 'maximo', t.maximo)
               order by t.ordem, t.nome), '[]'::jsonb)
        from (select coalesce(r.nome, 'Cultos extras') nome, count(*) cultos, round(avg(x.n), 1) media, max(x.n) maximo,
                     coalesce(r.dia_semana * 10000 + extract(epoch from r.horario)::int / 60, 999999) ordem
                from (select k.culto_id, count(*) n from public.checkins k
                        join public.cultos c on c.id = k.culto_id
                        join public.salas s on s.id = k.sala_id and s.departamento_id = v_dept
                       where c.data between v_mes and v_fim group by k.culto_id) x
                join public.cultos c on c.id = x.culto_id
                left join public.cultos_recorrentes r on r.id = c.culto_recorrente_id
               group by r.id, r.nome, r.dia_semana, r.horario) t),
    -- por sala: média e máximo nos cultos em que a sala recebeu crianças
    'por_sala', (
      select coalesce(jsonb_agg(jsonb_build_object('nome', t.nome, 'capacidade', t.capacidade, 'cultos', t.cultos,
                                                   'media', t.media, 'maximo', t.maximo, 'lotou', t.lotou) order by t.ordem), '[]'::jsonb)
        from (select s.nome, s.capacidade, s.ordem, count(*) cultos, round(avg(x.n), 1) media, max(x.n) maximo,
                     count(*) filter (where s.capacidade is not null and x.n >= s.capacidade) lotou
                from (select k.culto_id, k.sala_id, count(*) n from public.checkins k
                        join public.cultos c on c.id = k.culto_id
                       where c.data between v_mes and v_fim group by k.culto_id, k.sala_id) x
                join public.salas s on s.id = x.sala_id and s.departamento_id = v_dept
               group by s.id, s.nome, s.capacidade, s.ordem) t),
    -- presenças por semana (domingo a sábado) dentro do mês
    'semanas', (
      select coalesce(jsonb_agg(jsonb_build_object('inicio', w.inicio, 'presencas', w.n) order by w.inicio), '[]'::jsonb)
        from (select c.data - extract(dow from c.data)::int inicio, count(k.id) n
                from public.cultos c
                left join public.checkins k on k.culto_id = c.id
                 and exists (select 1 from public.salas s where s.id = k.sala_id and s.departamento_id = v_dept)
               where c.data between v_mes and v_fim and c.data <= private.hoje()
                 and c.igreja_id = (select igreja_id from public.departamentos where id = v_dept)
               group by 1) w),
    -- visitantes de primeira vez no mês que voltaram em outro culto (até hoje)
    'retorno', case when v_hist is null or v_hist >= v_mes then null else (
      select jsonb_build_object('visitantes_novos', count(*),
               'voltaram', count(*) filter (where exists (
                  select 1 from public.checkins k2 join public.cultos c2 on c2.id = k2.culto_id
                   where k2.crianca_id = p.crianca_id and c2.data > p.data)))
        from private.ind_primeiras() p join public.criancas cr on cr.id = p.crianca_id
       where p.data between v_mes and v_fim and cr.perfil = 'visitante') end,
    'voluntarias', private.ind_escala(v_mes, v_fim) || jsonb_build_object(
       'ativas', (select count(*) from public.voluntarias v where v.departamento_id = v_dept and v.status = 'ativa'),
       'escala_status', (select e.status from public.escalas e where e.departamento_id = v_dept and e.mes_referencia = v_mes)),
    'eventos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'titulo', e.titulo, 'inicio', e.inicio, 'cancelado', e.cancelado_em is not null,
               'inscritos', (select count(*) from public.inscricoes_evento i where i.evento_id = e.id),
               'presentes', (select count(*) from public.inscricoes_evento i where i.evento_id = e.id and i.presente),
               'ajudantes', (select count(*) from public.ajudas_evento a where a.evento_id = e.id))
             order by e.inicio), '[]'::jsonb)
        from public.eventos e
       where e.departamento_id = v_dept and e.publicado and private.dia_evento(e.inicio) between v_mes and v_fim));
end $$;

-- ---------------------------------------------------------------------
-- 5. Último culto (cartão do Início da liderança)
-- ---------------------------------------------------------------------
create or replace function public.ultimo_culto()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare c public.cultos;
begin
  if not private.e_lider(private.dept_kids()) then return null; end if;
  select x.* into c from public.cultos x
   where x.data <= private.hoje() and not x.cancelado
     and exists (select 1 from public.checkins k join public.salas s on s.id = k.sala_id
                  where k.culto_id = x.id and s.departamento_id = private.dept_kids())
   order by x.data desc, x.horario desc limit 1;
  if c.id is null then return null; end if;
  return jsonb_build_object(
    'id', c.id, 'data', c.data, 'hora', private.esc_hora(c.horario), 'nome', c.nome,
    'presencas', (select count(*) from public.checkins k where k.culto_id = c.id),
    'visitantes', (select count(*) from public.checkins k join public.criancas cr on cr.id = k.crianca_id
                    where k.culto_id = c.id and cr.perfil = 'visitante'),
    'primeira_vez', case when private.ind_inicio_historico() >= c.data then null else (
       select count(*) from private.ind_primeiras() p where p.culto_id = c.id) end);
end $$;

-- ---------------------------------------------------------------------
-- 6. Cuidado (com nomes; só no app, para a liderança)
-- ---------------------------------------------------------------------
-- Crianças ativas com 3+ check-ins nas últimas 13 semanas e nenhum há 4 semanas
create or replace function public.sentimos_falta()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_hoje date := private.hoje();
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'crianca_id', cr.id, 'nome', pe.nome, 'idade', private.idade_em(pe.data_nascimento, v_hoje),
             'perfil', cr.perfil, 'vezes', a.vezes, 'ultima_vez', a.ultima,
             'responsaveis', (select coalesce(jsonb_agg(jsonb_build_object('nome', rp.nome, 'telefone', rp.telefone)
                                       order by r.principal desc, rp.nome), '[]'::jsonb)
                                from public.responsaveis r join public.pessoas rp on rp.id = r.pessoa_id
                               where r.familia_id = cr.familia_id))
           order by a.ultima desc, pe.nome), '[]'::jsonb)
      from (select k.crianca_id, count(*) vezes, max(c.data) ultima
              from public.checkins k
              join public.cultos c on c.id = k.culto_id
              join public.salas s on s.id = k.sala_id and s.departamento_id = private.dept_kids()
             where c.data > v_hoje - 91 and c.data <= v_hoje
             group by k.crianca_id) a
      join public.criancas cr on cr.id = a.crianca_id and cr.ativo
      join public.pessoas pe on pe.id = cr.pessoa_id
     where a.vezes >= 3 and a.ultima <= v_hoje - 28);
end $$;

-- Voluntárias ativas sem nenhuma vaga (publicada) nos últimos 2 meses nem adiante
create or replace function public.voluntarias_sem_escala()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_hoje date := private.hoje(); v_dept uuid := private.dept_kids();
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'voluntaria_id', v.id, 'nome', pe.nome, 'telefone', pe.telefone, 'funcao', v.funcao,
             'desde', private.dia_evento(v.criado_em), 'ultima_vez', u.ultima)
           order by u.ultima nulls first, pe.nome), '[]'::jsonb)
      from public.voluntarias v
      join public.pessoas pe on pe.id = v.pessoa_id
      left join lateral (select max(c.data) ultima from public.escala_itens i
                           join public.escalas e on e.id = i.escala_id and e.status <> 'rascunho'
                           join public.cultos c on c.id = i.culto_id
                          where i.voluntaria_id = v.id) u on true
     where v.departamento_id = v_dept and v.status = 'ativa'
       and (u.ultima is null or u.ultima < v_hoje - 60));
end $$;

-- ---------------------------------------------------------------------
-- 7. "Não poderei" fica registrado (resto igual à Fase 6)
-- ---------------------------------------------------------------------
create or replace function public.responder_escala(p_item uuid, p_resposta public.resposta_escala)
returns void language plpgsql security definer set search_path = '' as $$
declare i record; v_nome text;
begin
  if p_resposta = 'pendente' then raise exception 'Resposta inválida'; end if;
  select ei.*, c.data, c.horario, c.id as cid into i
    from public.escala_itens ei
    join public.escalas e on e.id = ei.escala_id and e.status = 'publicada'
    join public.cultos c on c.id = ei.culto_id
   where ei.id = p_item and ei.voluntaria_id in (select private.minhas_voluntarias())
   for update of ei;
  if i.id is null then raise exception 'Item de escala não encontrado ou não pertence a você'; end if;
  if i.data < private.hoje() then raise exception 'Esse culto já passou'; end if;

  if p_resposta = 'ciente' then
    update public.escala_itens set resposta = 'ciente', respondido_em = now() where id = p_item;
  else
    insert into public.escala_recusas (item_id, escala_id, culto_id, voluntaria_id)
    values (i.id, i.escala_id, i.cid, i.voluntaria_id);
    update public.escala_itens set voluntaria_id = null, resposta = 'pendente', respondido_em = null,
           cobrindo_lider = false
     where id = p_item;
    select p.nome into v_nome from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id where v.id = i.voluntaria_id;
    perform private.avisar_lideranca_kids('Vaga liberada na escala',
      coalesce(private.primeiro_ultimo(v_nome), 'Uma voluntária') || ' não poderá servir em '
        || to_char(i.data, 'DD/MM') || ' às ' || private.esc_hora(i.horario) || ' · '
        || case when i.sala_id is null then 'Líder do culto' else private.esc_nome_sala(i.cid, i.sala_id) end || '.',
      '#/escala?mes=' || to_char(i.data, 'YYYY-MM'), 'escala');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 8. Relatório automático do mês (pelo keep-alive diário)
-- ---------------------------------------------------------------------
-- Do dia 1 ao dia 7, uma vez por mês: avisa a liderança (líderes do Fonte
-- Kids, pastores e admin) que o relatório do mês anterior está pronto.
-- Só se o mês anterior teve check-in. p_dia é só para o teste.
create or replace function private.avisar_relatorio_mes(p_dia date default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_dia date := coalesce(p_dia, private.hoje()); v_mes date; n integer;
begin
  if extract(day from v_dia) > 7 then return 0; end if;
  v_mes := (date_trunc('month', v_dia) - interval '1 month')::date;
  if not exists (select 1 from public.checkins k join public.cultos c on c.id = k.culto_id
                  where c.data between v_mes and (v_mes + interval '1 month' - interval '1 day')::date) then
    return 0;
  end if;
  insert into public.relatorios_avisados (mes) values (v_mes) on conflict (mes) do nothing;
  if not found then return 0; end if;

  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por)
  select d, 'Relatório de ' || private.esc_nome_mes(v_mes) || ' pronto',
         'Presença, visitantes, escala e eventos do mês. Só números, para mandar ao pastor ou no grupo.',
         '#/indicadores?aba=mes&mes=' || to_char(v_mes, 'YYYY-MM') || '&ver=relatorio', 'relatorio', null
    from private.destinatarios('lideres') d;
  get diagnostics n = row_count;
  update public.relatorios_avisados set destinatarios = n where mes = v_mes;
  return n;
end $$;

create or replace function public.keep_alive() returns text
language plpgsql security definer set search_path to '' as $$
begin
  perform private.fechar_checkins_vencidos();
  perform private.avisar_relatorio_mes();
  return 'ok';
end $$;

-- ---------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------
revoke all on function private.ind_primeiras() from public, anon, authenticated;
revoke all on function private.ind_inicio_historico() from public, anon, authenticated;
revoke all on function private.ind_totais(date, date) from public, anon, authenticated;
revoke all on function private.ind_escala(date, date) from public, anon, authenticated;
revoke all on function private.avisar_relatorio_mes(date) from public, anon, authenticated;
revoke all on function public.keep_alive() from public;
grant execute on function public.keep_alive() to anon, authenticated;

do $p$
declare f text;
begin
  foreach f in array array[
    'public.indicadores_semana(date)', 'public.indicadores_mes(date)', 'public.ultimo_culto()',
    'public.sentimos_falta()', 'public.voluntarias_sem_escala()',
    'public.responder_escala(uuid, public.resposta_escala)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;
