-- =====================================================================
-- Fase 6 · Etapa 6A – Motor de escala no banco
-- (proposta aprovada em 28/10/2026: decisões 118 a 125 do plano)
--  1. Vagas por sala no mês (escala_config_salas) agora com a linha
--     "juntas" (ex.: terça 7 a 12) e ajuste por culto (escala_vagas_culto).
--  2. Motor: mesmas travas do Apps Script (teto, 1 vaga por dia,
--     indisponibilidade, faixas e cultos preferidos, líder só professora
--     com 16+, regra da sala 10–12) e preenchimento das vagas mais
--     difíceis primeiro (ou na ordem das datas, para comparar).
--  3. Liderança: configurar o mês, gerar o rascunho (só em rascunho),
--     simular, trocar/adicionar/remover vaga, publicar, regras, teto.
--  4. Voluntária: minha escala, Ciente / Não poderei (libera a vaga e
--     avisa a liderança), pegar vaga aberta, indisponibilidade do mês.
--  5. Lembretes (6D): dados para o WhatsApp, só para a liderança.
--  6. Gravação só pelas funções, com auditoria.
-- Nada aqui devolve dado de criança.
-- =====================================================================

-- ---------- 1. Estrutura ----------
alter table public.escala_config_salas
  add column if not exists juntas boolean not null default false;
comment on column public.escala_config_salas.juntas is
  'true = vagas quando esta sala recebe outras (ex.: 7 a 9 + 10 a 12 na terça)';
alter table public.escala_config_salas
  drop constraint if exists escala_config_salas_escala_id_sala_id_key;
alter table public.escala_config_salas
  drop constraint if exists escala_config_salas_escala_sala_juntas_key;
alter table public.escala_config_salas
  add constraint escala_config_salas_escala_sala_juntas_key unique (escala_id, sala_id, juntas);
alter table public.escala_config_salas
  drop constraint if exists escala_config_salas_qtd_check;
alter table public.escala_config_salas
  add constraint escala_config_salas_qtd_check
  check (qtd_professora between 0 and 9 and qtd_auxiliar between 0 and 9 and qtd_reserva between 0 and 9);

-- vagas da sala junta de terça nas escalas que já existem (vinham de configuracoes)
insert into public.escala_config_salas (escala_id, sala_id, juntas, qtd_professora, qtd_auxiliar, qtd_reserva)
select e.id, s7.id, true,
       coalesce((cfg.valor::jsonb->>'professora')::smallint, 1),
       coalesce((cfg.valor::jsonb->>'auxiliar')::smallint, 1),
       coalesce((cfg.valor::jsonb->>'reserva')::smallint, 0)
from public.escalas e
join public.salas s7 on s7.departamento_id = e.departamento_id and s7.idade_min = 7
left join public.configuracoes cfg on cfg.chave = 'vagas_terca_sala_combinada_7_12'
on conflict (escala_id, sala_id, juntas) do nothing;

create table if not exists public.escala_vagas_culto (
  id uuid primary key default gen_random_uuid(),
  escala_id uuid not null references public.escalas(id) on delete cascade,
  culto_id uuid not null references public.cultos(id) on delete cascade,
  sala_id uuid not null references public.salas(id) on delete cascade,
  qtd_professora smallint not null check (qtd_professora between 0 and 9),
  qtd_auxiliar smallint not null check (qtd_auxiliar between 0 and 9),
  qtd_reserva smallint not null check (qtd_reserva between 0 and 9),
  criado_em timestamptz not null default now(),
  unique (escala_id, culto_id, sala_id)
);
comment on table public.escala_vagas_culto is
  'Vagas de uma sala só num culto (vale sobre o padrão do mês na hora de gerar)';
create index if not exists escala_vagas_culto_culto_idx on public.escala_vagas_culto (culto_id);
create index if not exists escala_vagas_culto_sala_idx on public.escala_vagas_culto (sala_id);

alter table public.escala_itens
  add column if not exists cobrindo_lider boolean not null default false;
comment on column public.escala_itens.cobrindo_lider is
  'Vaga de professora preenchida por auxiliar porque faltou professora';

-- quem já respondeu a indisponibilidade do mês (mesmo sem marcar nenhum culto)
create table if not exists public.indisponibilidade_respostas (
  id uuid primary key default gen_random_uuid(),
  voluntaria_id uuid not null references public.voluntarias(id) on delete cascade,
  mes date not null check (extract(day from mes) = 1),
  respondido_em timestamptz not null default now(),
  unique (voluntaria_id, mes)
);
insert into public.indisponibilidade_respostas (voluntaria_id, mes)
select distinct voluntaria_id, date_trunc('month', data)::date from public.indisponibilidades
on conflict (voluntaria_id, mes) do nothing;

-- vaga "ciente" sem ninguém (veio assim da planilha) volta a ser vaga aberta
update public.escala_itens set resposta = 'pendente', respondido_em = null
where voluntaria_id is null and nome_livre is null and resposta <> 'pendente';

-- ---------- 6. Gravação só pelas funções + auditoria ----------
alter table public.escala_vagas_culto enable row level security;
alter table public.indisponibilidade_respostas enable row level security;
drop policy if exists esc_vagas_culto_ler on public.escala_vagas_culto;
create policy esc_vagas_culto_ler on public.escala_vagas_culto for select to authenticated
  using (private.pode_ver_escala(escala_id));
drop policy if exists indisp_resp_ler on public.indisponibilidade_respostas;
create policy indisp_resp_ler on public.indisponibilidade_respostas for select to authenticated using (
  voluntaria_id in (select private.minhas_voluntarias())
  or private.e_lider(private.dept_voluntaria(voluntaria_id)));

drop policy if exists escalas_criar  on public.escalas;
drop policy if exists escalas_editar on public.escalas;
drop policy if exists escalas_apagar on public.escalas;
drop policy if exists esc_config_criar  on public.escala_config_salas;
drop policy if exists esc_config_editar on public.escala_config_salas;
drop policy if exists esc_config_apagar on public.escala_config_salas;
drop policy if exists esc_itens_criar  on public.escala_itens;
drop policy if exists esc_itens_editar on public.escala_itens;
drop policy if exists esc_itens_apagar on public.escala_itens;
drop policy if exists indisp_criar  on public.indisponibilidades;
drop policy if exists indisp_editar on public.indisponibilidades;
drop policy if exists indisp_apagar on public.indisponibilidades;
drop policy if exists regras_escala_criar  on public.regras_escala;
drop policy if exists regras_escala_editar on public.regras_escala;
drop policy if exists regras_escala_apagar on public.regras_escala;
revoke insert, update, delete on public.escalas, public.escala_config_salas, public.escala_itens,
  public.escala_vagas_culto, public.indisponibilidades, public.indisponibilidade_respostas,
  public.regras_escala from anon, authenticated;

drop trigger if exists escalas_auditoria on public.escalas;
create trigger escalas_auditoria after insert or update or delete
  on public.escalas for each row execute function private.auditar();
drop trigger if exists escala_config_salas_auditoria on public.escala_config_salas;
create trigger escala_config_salas_auditoria after insert or update or delete
  on public.escala_config_salas for each row execute function private.auditar();
drop trigger if exists escala_itens_auditoria on public.escala_itens;
create trigger escala_itens_auditoria after insert or update or delete
  on public.escala_itens for each row execute function private.auditar();
drop trigger if exists escala_vagas_culto_auditoria on public.escala_vagas_culto;
create trigger escala_vagas_culto_auditoria after insert or update or delete
  on public.escala_vagas_culto for each row execute function private.auditar();
drop trigger if exists indisponibilidades_auditoria on public.indisponibilidades;
create trigger indisponibilidades_auditoria after insert or update or delete
  on public.indisponibilidades for each row execute function private.auditar();
drop trigger if exists regras_escala_auditoria on public.regras_escala;
create trigger regras_escala_auditoria after insert or update or delete
  on public.regras_escala for each row execute function private.auditar();

-- ---------- Regras (valores iniciais = Apps Script) ----------
insert into public.regras_escala (departamento_id, chave, valor, descricao)
select d.id, x.chave, x.valor, x.descricao
from public.departamentos d
cross join (values
  ('teto_padrao', '3'::jsonb, 'Máximo de vagas por mês quando a voluntária não tem teto próprio'),
  ('uma_vaga_por_dia', 'true'::jsonb, 'No máximo uma vaga por dia para cada voluntária'),
  ('idade_minima_lider', '16'::jsonb, 'Idade mínima para a vaga de professora (líder da sala)'),
  ('auxiliar_feminina_lider_masculino', '{"ativo": true, "idade_min_sala": 10}'::jsonb,
   'Sala de 10 anos ou mais com professor: as auxiliares que faltam são só mulheres'),
  ('dia_limite_indisponibilidade', 'null'::jsonb, 'Dia do mês anterior até quando as voluntárias marcam a indisponibilidade'),
  ('ordem_preenchimento', '"dificeis"'::jsonb, 'dificeis = vagas com menos candidatas primeiro; datas = na ordem do mês'),
  ('mensagem_lembrete', to_jsonb('Oi, {nome_voluntaria}! 🔔 Lembrete: você está escalada para o culto de {data_culto} às {horario_culto}, na sala {sala}, como {papel}. Contamos com você! 💙'::text),
   'Texto do lembrete pelo WhatsApp')
) as x(chave, valor, descricao)
where d.slug = 'kids'
on conflict (departamento_id, chave) do nothing;

-- ---------- Funções auxiliares (privadas) ----------
create or replace function private.esc_regra(p_chave text)
returns jsonb language sql stable security definer set search_path = '' as $$
  select valor from public.regras_escala
  where departamento_id = private.dept_kids() and chave = p_chave
$$;

create or replace function private.esc_nome_mes(p_mes date)
returns text language sql immutable set search_path = '' as $$
  select (array['janeiro','fevereiro','março','abril','maio','junho','julho','agosto',
                'setembro','outubro','novembro','dezembro'])[extract(month from p_mes)::int]
         || ' de ' || extract(year from p_mes)::int
$$;

create or replace function private.esc_hora(p_horario time)
returns text language sql immutable set search_path = '' as $$
  select case when extract(minute from p_horario) = 0 then extract(hour from p_horario)::int || 'h'
              else to_char(p_horario, 'HH24"h"MI') end
$$;

create or replace function private.esc_funcao_rotulo(p_funcao public.funcao_escala)
returns text language sql immutable set search_path = '' as $$
  select case p_funcao when 'professora' then 'professora(o)' when 'auxiliar' then 'auxiliar'
                       when 'reserva' then 'reserva' else 'líder do culto' end
$$;

-- cria os cultos da agenda até o fim do mês pedido
create or replace function private.esc_garantir_cultos(p_mes date)
returns void language plpgsql security definer set search_path = '' as $$
declare v_fim date := (p_mes + interval '1 month' - interval '1 day')::date;
begin
  if v_fim >= private.hoje() then
    perform private.gerar_cultos(v_fim - private.hoje());
  end if;
end $$;

-- salas abertas de um culto: a principal e as que estão juntas com ela
create or replace function private.esc_grupos(p_culto uuid)
returns table (sala_id uuid, salas uuid[], juntas boolean, ordem int, nome text, idade_min_max int)
language sql stable security definer set search_path = '' as $$
  with base as (
    select s.id, s.ordem, s.nome, s.idade_min, s.idade_max,
           coalesce(cs.cancelada, false) as cancelada, cs.combinada_com_sala_id as junto
    from public.salas s
    left join public.culto_salas cs on cs.culto_id = p_culto and cs.sala_id = s.id
    where s.departamento_id = private.dept_kids() and s.ativa
  )
  select p.id, array_agg(m.id order by m.ordem), count(*) > 1, p.ordem::int,
         case when count(*) > 1 then min(m.idade_min) || ' a ' || max(m.idade_max) || ' anos' else p.nome end,
         max(m.idade_min)::int
  from base p
  join base m on m.id = p.id or (m.junto = p.id and not m.cancelada)
  where not p.cancelada and p.junto is null
  group by p.id, p.ordem, p.nome
$$;

-- nome da sala de uma vaga (com as salas juntas daquele culto)
create or replace function private.esc_nome_sala(p_culto uuid, p_sala uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select g.nome from private.esc_grupos(p_culto) g where g.sala_id = p_sala),
                  (select s.nome from public.salas s where s.id = p_sala), 'Geral')
$$;

-- pode ser professora (líder da sala)?
create or replace function private.esc_pode_liderar(p_voluntaria uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select v.funcao = 'professora'
     and (p.data_nascimento is null
          or p.data_nascimento <= private.hoje()
             - make_interval(years => coalesce((private.esc_regra('idade_minima_lider'))::int, 16)))
  from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id
  where v.id = p_voluntaria
$$;

-- avisa uma voluntária no app (se ela tiver login)
create or replace function private.avisar_voluntaria(p_voluntaria uuid, p_titulo text, p_corpo text, p_link text, p_tipo text)
returns void language sql security definer set search_path = '' as $$
  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por)
  select distinct pf.id, p_titulo, p_corpo, p_link, p_tipo, auth.uid()
  from public.voluntarias v
  join public.perfis pf on pf.pessoa_id = v.pessoa_id and pf.ativo
  where v.id = p_voluntaria and pf.id is distinct from auth.uid()
$$;

-- a escala do mês (ou nada)
create or replace function private.esc_do_mes(p_mes date)
returns public.escalas language sql stable security definer set search_path = '' as $$
  select e.* from public.escalas e
  where e.departamento_id = private.dept_kids() and e.mes_referencia = date_trunc('month', p_mes)::date
$$;

-- ---------- 2. Motor (trabalha em tabelas temporárias da própria chamada) ----------
create or replace function private.esc_preparar(p_escala uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_mes date; v_fim date; v_teto int;
begin
  select mes_referencia into v_mes from public.escalas where id = p_escala;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  v_teto := coalesce((private.esc_regra('teto_padrao'))::int, 3);

  drop table if exists pg_temp.esc_vg;
  drop table if exists pg_temp.esc_cand;
  drop table if exists pg_temp.esc_ind;
  create temp table esc_vg (
    id uuid primary key default gen_random_uuid(), culto_id uuid, data date, horario time,
    rec_id uuid, sala_id uuid, salas uuid[], sala_ordem int, idade_min_max int,
    funcao public.funcao_escala, n int, voluntaria_id uuid, cobrindo boolean not null default false,
    n_cand int, esgotada boolean not null default false
  ) on commit drop;
  create temp table esc_cand (
    id uuid primary key, sexo text, pode_liderar boolean, teto int,
    salas_pref uuid[], cultos_pref uuid[], alocadas int not null default 0, dias date[] not null default '{}'
  ) on commit drop;
  create temp table esc_ind (voluntaria_id uuid, culto_id uuid) on commit drop;

  insert into pg_temp.esc_vg (culto_id, data, horario, rec_id, sala_id, salas, sala_ordem, idade_min_max, funcao, n)
  select c.id, c.data, c.horario, c.culto_recorrente_id, g.sala_id, g.salas, g.ordem, g.idade_min_max, f.funcao, gs.n
  from public.cultos c
  join public.departamentos d on d.id = private.dept_kids() and d.igreja_id = c.igreja_id
  cross join lateral private.esc_grupos(c.id) g
  left join public.escala_vagas_culto vc on vc.escala_id = p_escala and vc.culto_id = c.id and vc.sala_id = g.sala_id
  left join public.escala_config_salas cj on cj.escala_id = p_escala and cj.sala_id = g.sala_id and cj.juntas = g.juntas
  left join public.escala_config_salas cs on cs.escala_id = p_escala and cs.sala_id = g.sala_id and not cs.juntas
  cross join lateral (values
    ('professora'::public.funcao_escala, coalesce(vc.qtd_professora, cj.qtd_professora, cs.qtd_professora, 0)),
    ('auxiliar'::public.funcao_escala,   coalesce(vc.qtd_auxiliar,   cj.qtd_auxiliar,   cs.qtd_auxiliar,   0)),
    ('reserva'::public.funcao_escala,    coalesce(vc.qtd_reserva,    cj.qtd_reserva,    cs.qtd_reserva,    0))
  ) as f(funcao, qtd)
  cross join lateral generate_series(1, f.qtd) as gs(n)
  where c.data between v_mes and v_fim and not c.cancelado;

  insert into pg_temp.esc_cand (id, sexo, pode_liderar, teto, salas_pref, cultos_pref)
  select v.id, p.sexo::text, private.esc_pode_liderar(v.id), coalesce(v.teto_mensal, v_teto),
         coalesce(v.salas_preferidas, '{}'), coalesce(v.cultos_preferidos, '{}')
  from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id
  where v.departamento_id = private.dept_kids() and v.status = 'ativa';

  insert into pg_temp.esc_ind (voluntaria_id, culto_id)
  select i.voluntaria_id, c.id
  from public.indisponibilidades i
  join public.cultos c on c.data = i.data and c.horario = i.horario
  where i.data between v_mes and v_fim;
end $$;

-- candidatas de uma vaga: modo 1 = todas as regras; modo 2 = cobrir professora com auxiliar
create or replace function private.esc_candidatas(p_vaga uuid, p_modo int)
returns table (vol uuid, rk_culto int, rk_sala int, n_aloc int, desempate text)
language plpgsql volatile security definer set search_path = '' as $$
declare
  v record; v_dia boolean; v_fem jsonb; v_so_fem boolean := false;
begin
  select * into v from pg_temp.esc_vg g where g.id = p_vaga;
  v_dia := coalesce((private.esc_regra('uma_vaga_por_dia'))::boolean, true);
  v_fem := private.esc_regra('auxiliar_feminina_lider_masculino');
  if p_modo = 1 and v.funcao = 'auxiliar' and coalesce((v_fem->>'ativo')::boolean, false)
     and v.idade_min_max >= coalesce((v_fem->>'idade_min_sala')::int, 10)
     and exists (select 1 from pg_temp.esc_vg l join pg_temp.esc_cand c on c.id = l.voluntaria_id
                 where l.culto_id = v.culto_id and l.sala_id = v.sala_id
                   and l.funcao = 'professora' and c.sexo = 'M') then
    v_so_fem := true;
  end if;
  return query
  select c.id,
         case when v.rec_id is null then 9 else array_position(c.cultos_pref, v.rec_id) end,
         (select min(array_position(c.salas_pref, s)) from unnest(v.salas) s),
         c.alocadas,
         md5(c.id::text || v.id::text)
  from pg_temp.esc_cand c
  where c.alocadas < c.teto
    and not (v_dia and v.data = any (c.dias))
    and not exists (select 1 from pg_temp.esc_ind i where i.voluntaria_id = c.id and i.culto_id = v.culto_id)
    and c.salas_pref && v.salas
    and (v.rec_id is null or v.rec_id = any (c.cultos_pref))
    and (p_modo = 2 or v.funcao <> 'professora' or c.pode_liderar)
    and (not v_so_fem or c.sexo = 'F');
end $$;

create or replace function private.esc_atribuir(p_vaga uuid, p_vol uuid, p_cobrindo boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_data date;
begin
  update pg_temp.esc_vg set voluntaria_id = p_vol, cobrindo = p_cobrindo where id = p_vaga
  returning data into v_data;
  update pg_temp.esc_cand set alocadas = alocadas + 1, dias = dias || v_data where id = p_vol;
end $$;

create or replace function private.esc_motor(p_ordem text)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v record; x record; p int; v_fun public.funcao_escala; v_modo int;
begin
  if p_ordem = 'datas' then
    -- como o Apps Script: culto a culto, sala a sala, professora → auxiliar → reserva
    for v in select g.id, g.funcao from pg_temp.esc_vg g
             order by g.data, g.horario, g.sala_ordem,
                      case g.funcao when 'professora' then 1 when 'auxiliar' then 2 else 3 end, g.n loop
      select * into x from private.esc_candidatas(v.id, 1) c order by c.rk_culto, c.rk_sala, c.n_aloc, c.desempate limit 1;
      if found then
        perform private.esc_atribuir(v.id, x.vol, false);
      elsif v.funcao = 'professora' then
        select * into x from private.esc_candidatas(v.id, 2) c order by c.n_aloc, c.desempate limit 1;
        if found then perform private.esc_atribuir(v.id, x.vol, true); end if;
      end if;
    end loop;
    return;
  end if;

  -- vagas mais difíceis primeiro: 1 professoras, 2 professora coberta por auxiliar, 3 auxiliares, 4 reservas
  for p in 1..4 loop
    v_fun := case when p <= 2 then 'professora' when p = 3 then 'auxiliar' else 'reserva' end;
    v_modo := case when p = 2 then 2 else 1 end;
    update pg_temp.esc_vg set esgotada = false where esgotada;  -- WHERE obrigatório: a API usa pg_safeupdate
    loop
      update pg_temp.esc_vg g set n_cand = (select count(*) from private.esc_candidatas(g.id, v_modo))
       where g.voluntaria_id is null and g.funcao = v_fun and not g.esgotada;
      update pg_temp.esc_vg g set esgotada = true
       where g.voluntaria_id is null and g.funcao = v_fun and g.n_cand = 0;
      select g.id into v from pg_temp.esc_vg g
       where g.voluntaria_id is null and g.funcao = v_fun and not g.esgotada
       order by g.n_cand, g.data, g.horario, g.sala_ordem, g.n limit 1;
      exit when not found;
      if v_modo = 1 then
        select * into x from private.esc_candidatas(v.id, 1) c order by c.rk_culto, c.rk_sala, c.n_aloc, c.desempate limit 1;
      else
        select * into x from private.esc_candidatas(v.id, 2) c order by c.n_aloc, c.desempate limit 1;
      end if;
      perform private.esc_atribuir(v.id, x.vol, v_modo = 2);
    end loop;
  end loop;
end $$;

-- ---------- 3. Liderança ----------
-- configura o mês (cria a escala em rascunho). p_vagas: [{sala_id, juntas, professora, auxiliar, reserva}]
-- sem p_vagas: copia o último mês configurado (ou 1 professora + 1 auxiliar por sala)
create or replace function public.configurar_escala(p_mes date, p_vagas jsonb default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_mes date := date_trunc('month', p_mes)::date;
  v_dept uuid := private.dept_kids(); v_id uuid; v_status public.status_escala; v_ant uuid; e jsonb;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  if v_mes < date_trunc('month', private.hoje())::date then raise exception 'Esse mês já passou'; end if;
  if v_mes > date_trunc('month', private.hoje())::date + interval '6 months' then raise exception 'Mês muito distante'; end if;

  select id, status into v_id, v_status from public.escalas where departamento_id = v_dept and mes_referencia = v_mes;
  if v_id is null then
    insert into public.escalas (departamento_id, mes_referencia) values (v_dept, v_mes) returning id into v_id;
    v_status := 'rascunho';
  end if;
  if v_status <> 'rascunho' then
    raise exception 'A escala de % já foi publicada. Ajuste vaga a vaga.', private.esc_nome_mes(v_mes);
  end if;

  if p_vagas is null then
    if not exists (select 1 from public.escala_config_salas where escala_id = v_id) then
      select id into v_ant from public.escalas
       where departamento_id = v_dept and mes_referencia < v_mes
         and exists (select 1 from public.escala_config_salas c where c.escala_id = escalas.id)
       order by mes_referencia desc limit 1;
      if v_ant is not null then
        insert into public.escala_config_salas (escala_id, sala_id, juntas, qtd_professora, qtd_auxiliar, qtd_reserva)
        select v_id, sala_id, juntas, qtd_professora, qtd_auxiliar, qtd_reserva
        from public.escala_config_salas where escala_id = v_ant;
      else
        insert into public.escala_config_salas (escala_id, sala_id, juntas, qtd_professora, qtd_auxiliar, qtd_reserva)
        select v_id, s.id, false, 1, 1, 0 from public.salas s where s.departamento_id = v_dept and s.ativa;
      end if;
    end if;
  else
    if jsonb_typeof(p_vagas) <> 'array' then raise exception 'Lista de vagas inválida'; end if;
    for e in select * from jsonb_array_elements(p_vagas) loop
      if not exists (select 1 from public.salas s where s.id = (e->>'sala_id')::uuid and s.departamento_id = v_dept) then
        raise exception 'Sala não encontrada';
      end if;
      if coalesce((e->>'professora')::int, 0) not between 0 and 9 or coalesce((e->>'auxiliar')::int, 0) not between 0 and 9
         or coalesce((e->>'reserva')::int, 0) not between 0 and 9 then
        raise exception 'Use de 0 a 9 vagas';
      end if;
      insert into public.escala_config_salas (escala_id, sala_id, juntas, qtd_professora, qtd_auxiliar, qtd_reserva)
      values (v_id, (e->>'sala_id')::uuid, coalesce((e->>'juntas')::boolean, false),
              coalesce((e->>'professora')::smallint, 0), coalesce((e->>'auxiliar')::smallint, 0),
              coalesce((e->>'reserva')::smallint, 0))
      on conflict (escala_id, sala_id, juntas) do update
        set qtd_professora = excluded.qtd_professora, qtd_auxiliar = excluded.qtd_auxiliar,
            qtd_reserva = excluded.qtd_reserva;
    end loop;
  end if;

  perform private.esc_garantir_cultos(v_mes);
  return v_id;
end $$;

-- vagas de uma sala só num culto (p_vagas null = volta ao padrão do mês); vale na próxima geração
create or replace function public.definir_vagas_culto(p_culto uuid, p_sala uuid, p_vagas jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare v_esc public.escalas; v_data date;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  select data into v_data from public.cultos where id = p_culto;
  if v_data is null then raise exception 'Culto não encontrado'; end if;
  v_esc := private.esc_do_mes(v_data);
  if v_esc.id is null then raise exception 'Configure a escala do mês primeiro'; end if;
  if v_esc.status <> 'rascunho' then raise exception 'Escala publicada: use "Adicionar vaga" ou "Remover vaga"'; end if;
  if p_vagas is null then
    delete from public.escala_vagas_culto where escala_id = v_esc.id and culto_id = p_culto and sala_id = p_sala;
    return;
  end if;
  if not exists (select 1 from private.esc_grupos(p_culto) g where g.sala_id = p_sala) then
    raise exception 'Essa sala não está aberta neste culto';
  end if;
  if coalesce((p_vagas->>'professora')::int, 0) not between 0 and 9 or coalesce((p_vagas->>'auxiliar')::int, 0) not between 0 and 9
     or coalesce((p_vagas->>'reserva')::int, 0) not between 0 and 9 then
    raise exception 'Use de 0 a 9 vagas';
  end if;
  insert into public.escala_vagas_culto (escala_id, culto_id, sala_id, qtd_professora, qtd_auxiliar, qtd_reserva)
  values (v_esc.id, p_culto, p_sala, coalesce((p_vagas->>'professora')::smallint, 0),
          coalesce((p_vagas->>'auxiliar')::smallint, 0), coalesce((p_vagas->>'reserva')::smallint, 0))
  on conflict (escala_id, culto_id, sala_id) do update
    set qtd_professora = excluded.qtd_professora, qtd_auxiliar = excluded.qtd_auxiliar, qtd_reserva = excluded.qtd_reserva;
end $$;

-- gera (ou refaz) o rascunho do mês; nunca mexe em escala publicada
create or replace function public.gerar_rascunho(p_mes date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_esc public.escalas; v_ordem text;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  v_esc := private.esc_do_mes(p_mes);
  if v_esc.id is null then raise exception 'Configure as vagas do mês primeiro'; end if;
  if v_esc.status <> 'rascunho' then
    raise exception 'A escala de % já foi publicada. Ajuste vaga a vaga.', private.esc_nome_mes(v_esc.mes_referencia);
  end if;
  perform private.esc_garantir_cultos(v_esc.mes_referencia);
  delete from public.escala_itens where escala_id = v_esc.id;

  v_ordem := coalesce(private.esc_regra('ordem_preenchimento') #>> '{}', 'dificeis');
  perform private.esc_preparar(v_esc.id);
  perform private.esc_motor(v_ordem);

  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao, voluntaria_id, cobrindo_lider)
  select v_esc.id, g.culto_id, g.sala_id, g.funcao, g.voluntaria_id, g.cobrindo from pg_temp.esc_vg g;
  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao)
  select v_esc.id, c.id, null, 'lider_culto'
  from public.cultos c join public.departamentos d on d.id = private.dept_kids() and d.igreja_id = c.igreja_id
  where c.data between v_esc.mes_referencia and (v_esc.mes_referencia + interval '1 month' - interval '1 day')::date
    and not c.cancelado;

  return jsonb_build_object(
    'vagas', (select count(*) from pg_temp.esc_vg),
    'preenchidas', (select count(*) from pg_temp.esc_vg where voluntaria_id is not null),
    'vazias', (select count(*) from pg_temp.esc_vg where voluntaria_id is null),
    'cobrindo_lider', (select count(*) from pg_temp.esc_vg where cobrindo));
end $$;

-- simula sem gravar nada (para comparar as duas ordens); só contagens
create or replace function public.simular_escala(p_mes date, p_ordem text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_esc public.escalas;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  if p_ordem not in ('dificeis', 'datas') then raise exception 'Ordem inválida'; end if;
  v_esc := private.esc_do_mes(p_mes);
  if v_esc.id is null then raise exception 'Configure as vagas do mês primeiro'; end if;
  perform private.esc_preparar(v_esc.id);
  perform private.esc_motor(p_ordem);
  return jsonb_build_object(
    'ordem', p_ordem,
    'vagas', (select count(*) from pg_temp.esc_vg),
    'preenchidas', (select count(*) from pg_temp.esc_vg where voluntaria_id is not null),
    'vazias', (select count(*) from pg_temp.esc_vg where voluntaria_id is null),
    'professora_vazias', (select count(*) from pg_temp.esc_vg where voluntaria_id is null and funcao = 'professora'),
    'cobrindo_lider', (select count(*) from pg_temp.esc_vg where cobrindo),
    'voluntarias_usadas', (select count(*) from pg_temp.esc_cand where alocadas > 0),
    'voluntarias_sem_vaga', (select count(*) from pg_temp.esc_cand where alocadas = 0));
end $$;

-- a escala do mês para a tela (liderança vê o rascunho; equipe só a publicada). Só nomes, sem telefone.
create or replace function public.escala_do_mes(p_mes date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids(); v_mes date := date_trunc('month', p_mes)::date;
  v_fim date; v_lider boolean; v_esc public.escalas; v_minhas uuid[];
begin
  v_lider := private.e_lider(v_dept);
  if not (v_lider or private.e_equipe(v_dept)) then raise exception 'Sem permissão'; end if;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  v_esc := private.esc_do_mes(v_mes);
  v_minhas := array(select private.minhas_voluntarias());
  if v_esc.id is null or (v_esc.status = 'rascunho' and not v_lider) then
    return jsonb_build_object('mes', v_mes, 'nome_mes', private.esc_nome_mes(v_mes), 'escala', null, 'pode_editar', v_lider);
  end if;

  return jsonb_build_object(
    'mes', v_mes, 'nome_mes', private.esc_nome_mes(v_mes), 'pode_editar', v_lider,
    'escala', jsonb_build_object('id', v_esc.id, 'status', v_esc.status, 'publicada_em', v_esc.publicada_em),
    'config', case when v_lider then (
       select coalesce(jsonb_agg(jsonb_build_object('sala_id', c.sala_id, 'sala', s.nome, 'juntas', c.juntas,
                 'professora', c.qtd_professora, 'auxiliar', c.qtd_auxiliar, 'reserva', c.qtd_reserva)
               order by s.ordem, c.juntas), '[]'::jsonb)
       from public.escala_config_salas c join public.salas s on s.id = c.sala_id where c.escala_id = v_esc.id) end,
    'ajustes', case when v_lider then (
       select coalesce(jsonb_agg(jsonb_build_object('culto_id', a.culto_id, 'sala_id', a.sala_id,
                 'professora', a.qtd_professora, 'auxiliar', a.qtd_auxiliar, 'reserva', a.qtd_reserva)), '[]'::jsonb)
       from public.escala_vagas_culto a where a.escala_id = v_esc.id) end,
    'cultos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'data', c.data, 'horario', to_char(c.horario, 'HH24:MI'), 'hora', private.esc_hora(c.horario),
               'nome', c.nome, 'cancelado', c.cancelado,
               'salas', (select coalesce(jsonb_agg(jsonb_build_object('sala_id', g.sala_id, 'nome', g.nome) order by g.ordem), '[]'::jsonb)
                         from private.esc_grupos(c.id) g),
               'itens', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'id', i.id, 'sala_id', i.sala_id, 'sala', case when i.sala_id is null then 'Geral' else private.esc_nome_sala(c.id, i.sala_id) end,
                          'funcao', i.funcao, 'voluntaria_id', i.voluntaria_id, 'nome', coalesce(p.nome, i.nome_livre),
                          'nome_livre', i.nome_livre is not null, 'resposta', i.resposta,
                          'cobrindo_lider', i.cobrindo_lider, 'minha', i.voluntaria_id = any (v_minhas))
                        order by i.sala_id is null, s.ordem nulls last,
                                 case i.funcao when 'professora' then 1 when 'auxiliar' then 2 when 'reserva' then 3 else 4 end,
                                 i.criado_em, i.id), '[]'::jsonb)
                 from public.escala_itens i
                 left join public.salas s on s.id = i.sala_id
                 left join public.voluntarias v on v.id = i.voluntaria_id
                 left join public.pessoas p on p.id = v.pessoa_id
                 where i.escala_id = v_esc.id and i.culto_id = c.id))
             order by c.data, c.horario), '[]'::jsonb)
      from public.cultos c
      where c.data between v_mes and v_fim
        and (exists (select 1 from public.escala_itens i where i.escala_id = v_esc.id and i.culto_id = c.id)
             or (v_lider and v_esc.status = 'rascunho' and not c.cancelado
                 and c.igreja_id = (select igreja_id from public.departamentos where id = v_dept)))),
    'resumo', (select jsonb_build_object(
                 'vagas', count(*) filter (where funcao <> 'lider_culto'),
                 'vazias', count(*) filter (where funcao <> 'lider_culto' and voluntaria_id is null and nome_livre is null),
                 'cientes', count(*) filter (where resposta = 'ciente'),
                 'lider_culto_vazias', count(*) filter (where funcao = 'lider_culto' and voluntaria_id is null and nome_livre is null))
               from public.escala_itens where escala_id = v_esc.id),
    'indisponibilidade', case when v_lider then (
       select jsonb_build_object('ativas', count(*), 'responderam',
                count(*) filter (where exists (select 1 from public.indisponibilidade_respostas r
                                                where r.voluntaria_id = v.id and r.mes = v_mes)))
       from public.voluntarias v where v.departamento_id = v_dept and v.status = 'ativa') end
  );
end $$;

-- quem pode ir numa vaga, com avisos (Max, No dia, Indisponível…); liderança
create or replace function public.candidatas_vaga(p_item uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids(); i record; v_teto int; v_fem jsonb; v_lider_m boolean;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  select ei.*, c.data, c.horario, c.culto_recorrente_id as rec_id
    into i from public.escala_itens ei join public.cultos c on c.id = ei.culto_id where ei.id = p_item;
  if i.id is null then raise exception 'Vaga não encontrada'; end if;
  v_teto := coalesce((private.esc_regra('teto_padrao'))::int, 3);
  return (
    select coalesce(jsonb_agg(x order by jsonb_array_length(x->'avisos'), x->>'nome'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'voluntaria_id', v.id, 'nome', p.nome, 'funcao', v.funcao,
        'no_mes', aloc.n, 'teto', coalesce(v.teto_mensal, v_teto),
        'avisos', to_jsonb(array_remove(array[
          case when aloc.n >= coalesce(v.teto_mensal, v_teto) then 'max' end,
          case when exists (select 1 from public.escala_itens o join public.cultos oc on oc.id = o.culto_id
                            where o.voluntaria_id = v.id and oc.data = i.data and o.id <> i.id) then 'no_dia' end,
          case when exists (select 1 from public.indisponibilidades d
                            where d.voluntaria_id = v.id and d.data = i.data and d.horario = i.horario) then 'indisponivel' end,
          case when i.sala_id is not null and not (coalesce(v.salas_preferidas, '{}') &&
                 coalesce((select g.salas from private.esc_grupos(i.culto_id) g where g.sala_id = i.sala_id), array[i.sala_id]))
               then 'fora_da_faixa' end,
          case when i.rec_id is not null and not (i.rec_id = any (coalesce(v.cultos_preferidos, '{}'))) then 'fora_do_culto' end,
          case when i.funcao = 'professora' and not private.esc_pode_liderar(v.id) then 'nao_lidera' end
        ], null))) as x
      from public.voluntarias v
      join public.pessoas p on p.id = v.pessoa_id
      cross join lateral (select count(*)::int as n from public.escala_itens o
                          where o.escala_id = i.escala_id and o.voluntaria_id = v.id and o.funcao <> 'lider_culto') aloc
      where v.departamento_id = v_dept and v.status = 'ativa'
    ) z
  );
end $$;

-- troca quem está numa vaga (voluntária, nome livre ou ninguém); liderança
create or replace function public.trocar_vaga(p_item uuid, p_voluntaria uuid, p_nome_livre text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids(); i record; v_nome text := nullif(btrim(coalesce(p_nome_livre, '')), '');
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  select ei.*, e.status, c.data, c.horario, c.id as cid
    into i from public.escala_itens ei join public.escalas e on e.id = ei.escala_id
    join public.cultos c on c.id = ei.culto_id where ei.id = p_item for update of ei;
  if i.id is null then raise exception 'Vaga não encontrada'; end if;
  if i.status = 'encerrada' then raise exception 'Escala encerrada'; end if;
  if p_voluntaria is not null and v_nome is not null then raise exception 'Escolha uma voluntária ou um nome, não os dois'; end if;
  if v_nome is not null and char_length(v_nome) not between 2 and 80 then raise exception 'Nome inválido'; end if;
  if p_voluntaria is not null and not exists (select 1 from public.voluntarias v
       where v.id = p_voluntaria and v.departamento_id = v_dept and v.status = 'ativa') then
    raise exception 'Voluntária não encontrada';
  end if;
  if p_voluntaria is not distinct from i.voluntaria_id and v_nome is not distinct from i.nome_livre then return; end if;

  update public.escala_itens
     set voluntaria_id = p_voluntaria, nome_livre = v_nome, cobrindo_lider = false,
         resposta = 'pendente', respondido_em = null
   where id = p_item;

  if i.status = 'publicada' then
    if i.voluntaria_id is not null then
      perform private.avisar_voluntaria(i.voluntaria_id, 'Escala alterada',
        'A liderança tirou você da vaga de ' || to_char(i.data, 'DD/MM') || ' às ' || private.esc_hora(i.horario) || '.',
        '#/minha-escala', 'escala');
    end if;
    if p_voluntaria is not null then
      perform private.avisar_voluntaria(p_voluntaria, 'Você foi escalada',
        to_char(i.data, 'DD/MM') || ' às ' || private.esc_hora(i.horario) || ' · '
          || case when i.sala_id is null then 'Líder do culto' else private.esc_nome_sala(i.cid, i.sala_id) end
          || '. Abra "Minha escala" e marque Ciente.',
        '#/minha-escala', 'escala');
    end if;
  end if;
end $$;

-- acrescenta uma vaga (qualquer momento, inclusive depois de publicar); liderança
create or replace function public.adicionar_vaga(p_culto uuid, p_sala uuid, p_funcao text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_esc public.escalas; v_data date; v_id uuid;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  if p_funcao not in ('professora', 'auxiliar', 'reserva', 'lider_culto') then raise exception 'Função inválida'; end if;
  select data into v_data from public.cultos where id = p_culto and not cancelado;
  if v_data is null then raise exception 'Culto não encontrado ou cancelado'; end if;
  v_esc := private.esc_do_mes(v_data);
  if v_esc.id is null then raise exception 'Configure a escala do mês primeiro'; end if;
  if v_esc.status = 'encerrada' then raise exception 'Escala encerrada'; end if;
  if p_funcao = 'lider_culto' then
    if p_sala is not null then raise exception 'Líder do culto não tem sala'; end if;
  elsif not exists (select 1 from private.esc_grupos(p_culto) g where g.sala_id = p_sala) then
    raise exception 'Essa sala não está aberta neste culto';
  end if;
  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao)
  values (v_esc.id, p_culto, case when p_funcao = 'lider_culto' then null else p_sala end, p_funcao::public.funcao_escala)
  returning id into v_id;
  return v_id;
end $$;

-- tira uma vaga; avisa quem estava nela (se publicada); liderança
create or replace function public.remover_vaga(p_item uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare i record;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  select ei.*, e.status, c.data, c.horario into i
    from public.escala_itens ei join public.escalas e on e.id = ei.escala_id
    join public.cultos c on c.id = ei.culto_id where ei.id = p_item;
  if i.id is null then raise exception 'Vaga não encontrada'; end if;
  if i.status = 'encerrada' then raise exception 'Escala encerrada'; end if;
  delete from public.escala_itens where id = p_item;
  if i.status = 'publicada' and i.voluntaria_id is not null then
    perform private.avisar_voluntaria(i.voluntaria_id, 'Escala alterada',
      'A vaga de ' || to_char(i.data, 'DD/MM') || ' às ' || private.esc_hora(i.horario) || ' foi retirada da escala.',
      '#/minha-escala', 'escala');
  end if;
end $$;

-- publica o rascunho e avisa cada voluntária escalada; liderança
create or replace function public.publicar_escala(p_mes date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_esc public.escalas; v record; n int := 0;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  v_esc := private.esc_do_mes(p_mes);
  if v_esc.id is null then raise exception 'Não há escala neste mês'; end if;
  if v_esc.status <> 'rascunho' then raise exception 'Esta escala já foi publicada'; end if;
  if not exists (select 1 from public.escala_itens where escala_id = v_esc.id) then
    raise exception 'Gere o rascunho antes de publicar';
  end if;
  update public.escalas set status = 'publicada', publicada_em = now(), publicada_por = auth.uid()
   where id = v_esc.id;
  for v in select distinct voluntaria_id from public.escala_itens
           where escala_id = v_esc.id and voluntaria_id is not null loop
    perform private.avisar_voluntaria(v.voluntaria_id, 'Escala de ' || private.esc_nome_mes(v_esc.mes_referencia) || ' publicada',
      'Confira suas datas em "Minha escala" e marque Ciente em cada uma.', '#/minha-escala', 'escala');
    n := n + 1;
  end loop;
  return jsonb_build_object('voluntarias', n,
    'vazias', (select count(*) from public.escala_itens where escala_id = v_esc.id
               and funcao <> 'lider_culto' and voluntaria_id is null and nome_livre is null));
end $$;

-- regras da escala (só as chaves conhecidas); liderança
create or replace function public.definir_regras_escala(p_regras jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare k text; v jsonb; v_dept uuid := private.dept_kids();
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  if jsonb_typeof(p_regras) <> 'object' then raise exception 'Regras inválidas'; end if;
  for k, v in select * from jsonb_each(p_regras) loop
    if k = 'teto_padrao' and not (jsonb_typeof(v) = 'number' and (v)::int between 1 and 10) then raise exception 'Teto: de 1 a 10';
    elsif k = 'uma_vaga_por_dia' and jsonb_typeof(v) <> 'boolean' then raise exception 'Valor inválido';
    elsif k = 'idade_minima_lider' and not (jsonb_typeof(v) = 'number' and (v)::int between 12 and 18) then raise exception 'Idade: de 12 a 18';
    elsif k = 'auxiliar_feminina_lider_masculino' and not (jsonb_typeof(v) = 'object'
          and jsonb_typeof(v->'ativo') = 'boolean' and jsonb_typeof(v->'idade_min_sala') = 'number') then raise exception 'Valor inválido';
    elsif k = 'dia_limite_indisponibilidade' and not (jsonb_typeof(v) = 'null'
          or (jsonb_typeof(v) = 'number' and (v)::int between 1 and 28)) then raise exception 'Dia limite: de 1 a 28';
    elsif k = 'ordem_preenchimento' and not (v #>> '{}') in ('dificeis', 'datas') then raise exception 'Ordem inválida';
    elsif k = 'mensagem_lembrete' and not (jsonb_typeof(v) = 'string' and char_length(v #>> '{}') between 10 and 1000) then
      raise exception 'Mensagem: de 10 a 1000 letras';
    elsif k not in ('teto_padrao', 'uma_vaga_por_dia', 'idade_minima_lider', 'auxiliar_feminina_lider_masculino',
                    'dia_limite_indisponibilidade', 'ordem_preenchimento', 'mensagem_lembrete') then
      raise exception 'Regra desconhecida: %', k;
    end if;
    insert into public.regras_escala (departamento_id, chave, valor) values (v_dept, k, v)
    on conflict (departamento_id, chave) do update set valor = excluded.valor;
  end loop;
end $$;

create or replace function public.regras_escala_atuais()
returns jsonb language sql stable security definer set search_path = '' as $$
  select case when private.e_lider(private.dept_kids()) or private.e_equipe(private.dept_kids())
         then (select coalesce(jsonb_object_agg(chave, valor), '{}'::jsonb) from public.regras_escala
               where departamento_id = private.dept_kids()) end
$$;

-- teto mensal de uma voluntária (null = usa o padrão); liderança
create or replace function public.definir_teto_voluntaria(p_voluntaria uuid, p_teto int)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  if p_teto is not null and p_teto not between 0 and 10 then raise exception 'Teto: de 0 a 10'; end if;
  update public.voluntarias set teto_mensal = p_teto
   where id = p_voluntaria and departamento_id = private.dept_kids();
  if not found then raise exception 'Voluntária não encontrada'; end if;
end $$;

-- lista para a liderança: teto e preferências de cada voluntária ativa (sem telefone)
create or replace function public.voluntarias_escala()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_teto int := coalesce((private.esc_regra('teto_padrao'))::int, 3);
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'id', v.id, 'nome', p.nome, 'funcao', v.funcao, 'teto', v.teto_mensal, 'teto_efetivo', coalesce(v.teto_mensal, v_teto),
            'pode_liderar', private.esc_pode_liderar(v.id),
            'salas', (select coalesce(jsonb_agg(s.nome order by x.o), '[]'::jsonb)
                      from unnest(v.salas_preferidas) with ordinality x(id, o) join public.salas s on s.id = x.id),
            'cultos', (select coalesce(jsonb_agg(cr.nome order by x.o), '[]'::jsonb)
                       from unnest(v.cultos_preferidos) with ordinality x(id, o) join public.cultos_recorrentes cr on cr.id = x.id))
          order by p.nome), '[]'::jsonb)
          from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id
          where v.departamento_id = private.dept_kids() and v.status = 'ativa');
end $$;

-- ---------- 4. Voluntária ----------
-- Ciente / Não poderei. "Não poderei" libera a vaga na hora e avisa a liderança (decisão 123).
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

-- pegar uma vaga aberta da escala publicada (entra como ciente)
create or replace function public.pegar_vaga(p_item uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare i record; v_vol uuid; v_nome text;
begin
  select id into v_vol from public.voluntarias
   where id in (select private.minhas_voluntarias()) and departamento_id = private.dept_kids() limit 1;
  if v_vol is null then raise exception 'Só voluntárias do Fonte Kids podem pegar vagas'; end if;
  select ei.*, c.data, c.horario, c.cancelado, c.id as cid into i
    from public.escala_itens ei
    join public.escalas e on e.id = ei.escala_id and e.status = 'publicada'
    join public.cultos c on c.id = ei.culto_id
   where ei.id = p_item for update of ei;
  if i.id is null then raise exception 'Vaga não encontrada'; end if;
  if i.voluntaria_id is not null or i.nome_livre is not null then raise exception 'Essa vaga acabou de ser preenchida'; end if;
  if i.funcao = 'lider_culto' then raise exception 'Essa vaga só pode ser preenchida pela liderança'; end if;
  if i.cancelado or i.data < private.hoje() then raise exception 'Esse culto já passou ou foi cancelado'; end if;
  if i.funcao = 'professora' and not private.esc_pode_liderar(v_vol) then
    raise exception 'Esta vaga é de professora(o). Escolha uma vaga de auxiliar.';
  end if;
  if coalesce((private.esc_regra('uma_vaga_por_dia'))::boolean, true) and exists (
       select 1 from public.escala_itens o join public.cultos oc on oc.id = o.culto_id
       join public.escalas oe on oe.id = o.escala_id and oe.status = 'publicada'
       where o.voluntaria_id = v_vol and oc.data = i.data) then
    raise exception 'Você já está escalada neste dia';
  end if;
  update public.escala_itens set voluntaria_id = v_vol, nome_livre = null, resposta = 'ciente', respondido_em = now()
   where id = p_item;
  select p.nome into v_nome from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id where v.id = v_vol;
  perform private.avisar_lideranca_kids('Vaga preenchida pela voluntária',
    coalesce(private.primeiro_ultimo(v_nome), 'Uma voluntária') || ' pegou a vaga de '
      || to_char(i.data, 'DD/MM') || ' às ' || private.esc_hora(i.horario) || ' · '
      || private.esc_nome_sala(i.cid, i.sala_id) || '.',
    '#/escala?mes=' || to_char(i.data, 'YYYY-MM'), 'escala');
end $$;

-- "Minha escala": próximas vagas, colegas da mesma sala, vagas abertas e a indisponibilidade pendente
create or replace function public.minha_escala()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_vols uuid[] := array(select private.minhas_voluntarias()); v_prox date; v_resp boolean; v_lim jsonb;
  v_esc_prox public.escalas;
begin
  if cardinality(v_vols) = 0 then raise exception 'Sem permissão'; end if;
  v_prox := (date_trunc('month', private.hoje()) + interval '1 month')::date;
  v_esc_prox := private.esc_do_mes(v_prox);
  v_resp := exists (select 1 from public.indisponibilidade_respostas r where r.voluntaria_id = any (v_vols) and r.mes = v_prox);
  v_lim := private.esc_regra('dia_limite_indisponibilidade');
  return jsonb_build_object(
    'minhas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', i.id, 'culto_id', c.id, 'data', c.data, 'horario', to_char(c.horario, 'HH24:MI'), 'hora', private.esc_hora(c.horario),
               'culto', c.nome, 'cancelado', c.cancelado, 'funcao', i.funcao, 'cobrindo_lider', i.cobrindo_lider,
               'sala', case when i.sala_id is null then 'Líder do culto' else private.esc_nome_sala(c.id, i.sala_id) end,
               'resposta', i.resposta,
               'colegas', (select coalesce(jsonb_agg(jsonb_build_object('nome', coalesce(p.nome, o.nome_livre), 'funcao', o.funcao)
                                   order by o.funcao, coalesce(p.nome, o.nome_livre)), '[]'::jsonb)
                           from public.escala_itens o
                           left join public.voluntarias ov on ov.id = o.voluntaria_id
                           left join public.pessoas p on p.id = ov.pessoa_id
                           where o.culto_id = i.culto_id and o.id <> i.id
                             and (o.sala_id = i.sala_id or o.funcao = 'lider_culto')
                             and (o.voluntaria_id is not null or o.nome_livre is not null)))
             order by c.data, c.horario), '[]'::jsonb)
      from public.escala_itens i
      join public.escalas e on e.id = i.escala_id and e.status = 'publicada'
      join public.cultos c on c.id = i.culto_id
      where i.voluntaria_id = any (v_vols) and c.data >= private.hoje()),
    'abertas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', i.id, 'data', c.data, 'horario', to_char(c.horario, 'HH24:MI'), 'hora', private.esc_hora(c.horario),
               'culto', c.nome, 'funcao', i.funcao, 'sala', private.esc_nome_sala(c.id, i.sala_id))
             order by c.data, c.horario), '[]'::jsonb)
      from public.escala_itens i
      join public.escalas e on e.id = i.escala_id and e.status = 'publicada' and e.departamento_id = private.dept_kids()
      join public.cultos c on c.id = i.culto_id and not c.cancelado
      where i.voluntaria_id is null and i.nome_livre is null and i.funcao <> 'lider_culto' and c.data >= private.hoje()),
    'indisponibilidade', jsonb_build_object(
      'mes', v_prox, 'nome_mes', private.esc_nome_mes(v_prox), 'respondeu', v_resp,
      'aberta', v_esc_prox.id is null or v_esc_prox.status = 'rascunho',
      'dia_limite', case when jsonb_typeof(v_lim) = 'number' then (v_lim)::int end)
  );
end $$;

-- cultos do mês com a marcação de indisponibilidade da própria voluntária
create or replace function public.minha_indisponibilidade(p_mes date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_vol uuid; v_mes date := date_trunc('month', p_mes)::date; v_fim date; v_esc public.escalas;
begin
  select id into v_vol from public.voluntarias
   where id in (select private.minhas_voluntarias()) and departamento_id = private.dept_kids() limit 1;
  if v_vol is null then raise exception 'Sem permissão'; end if;
  if v_mes < date_trunc('month', private.hoje())::date then raise exception 'Esse mês já passou'; end if;
  if v_mes > date_trunc('month', private.hoje())::date + interval '6 months' then raise exception 'Mês muito distante'; end if;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  perform private.esc_garantir_cultos(v_mes);
  v_esc := private.esc_do_mes(v_mes);
  return jsonb_build_object(
    'mes', v_mes, 'nome_mes', private.esc_nome_mes(v_mes),
    'aberta', v_esc.id is null or v_esc.status = 'rascunho',
    'respondeu', exists (select 1 from public.indisponibilidade_respostas r where r.voluntaria_id = v_vol and r.mes = v_mes),
    'cultos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'data', c.data, 'horario', to_char(c.horario, 'HH24:MI'), 'hora', private.esc_hora(c.horario),
               'nome', c.nome,
               'indisponivel', exists (select 1 from public.indisponibilidades i
                                       where i.voluntaria_id = v_vol and i.data = c.data and i.horario = c.horario))
             order by c.data, c.horario), '[]'::jsonb)
      from public.cultos c
      join public.departamentos d on d.id = private.dept_kids() and d.igreja_id = c.igreja_id
      where c.data between v_mes and v_fim and not c.cancelado));
end $$;

-- grava a indisponibilidade do mês (lista completa dos cultos em que NÃO pode)
create or replace function public.salvar_indisponibilidade(p_mes date, p_cultos uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare v_vol uuid; v_mes date := date_trunc('month', p_mes)::date; v_fim date; v_esc public.escalas;
begin
  select id into v_vol from public.voluntarias
   where id in (select private.minhas_voluntarias()) and departamento_id = private.dept_kids() limit 1;
  if v_vol is null then raise exception 'Sem permissão'; end if;
  if v_mes < date_trunc('month', private.hoje())::date then raise exception 'Esse mês já passou'; end if;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  v_esc := private.esc_do_mes(v_mes);
  if v_esc.id is not null and v_esc.status <> 'rascunho' then
    raise exception 'A escala de % já foi publicada. Use "Não poderei" na sua vaga.', private.esc_nome_mes(v_mes);
  end if;
  if exists (select 1 from unnest(coalesce(p_cultos, '{}')) x
             where not exists (select 1 from public.cultos c where c.id = x and c.data between v_mes and v_fim)) then
    raise exception 'Culto fora do mês';
  end if;
  delete from public.indisponibilidades where voluntaria_id = v_vol and data between v_mes and v_fim;
  insert into public.indisponibilidades (voluntaria_id, data, horario)
  select distinct v_vol, c.data, c.horario from public.cultos c where c.id = any (coalesce(p_cultos, '{}'));
  insert into public.indisponibilidade_respostas (voluntaria_id, mes) values (v_vol, v_mes)
  on conflict (voluntaria_id, mes) do update set respondido_em = now();
end $$;

-- liderança: quem respondeu a indisponibilidade do mês e quantos cultos marcou
create or replace function public.indisponibilidade_do_mes(p_mes date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_mes date := date_trunc('month', p_mes)::date; v_fim date;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'voluntaria_id', v.id, 'nome', p.nome,
            'respondeu', exists (select 1 from public.indisponibilidade_respostas r where r.voluntaria_id = v.id and r.mes = v_mes),
            'cultos', (select count(*) from public.indisponibilidades i where i.voluntaria_id = v.id and i.data between v_mes and v_fim))
          order by p.nome), '[]'::jsonb)
          from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id
          where v.departamento_id = private.dept_kids() and v.status = 'ativa');
end $$;

-- ---------- 5. Lembretes (6D): só a liderança, para montar o wa.me ----------
create or replace function public.lembretes_escala(p_de date, p_ate date)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  if p_ate < p_de or p_ate - p_de > 40 then raise exception 'Período inválido'; end if;
  return jsonb_build_object(
    'mensagem', private.esc_regra('mensagem_lembrete') #>> '{}',
    'itens', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', i.id, 'data', c.data, 'hora', private.esc_hora(c.horario), 'culto', c.nome,
               'sala', case when i.sala_id is null then 'Geral' else private.esc_nome_sala(c.id, i.sala_id) end,
               'funcao', i.funcao, 'papel', private.esc_funcao_rotulo(i.funcao), 'resposta', i.resposta,
               'nome', p.nome, 'telefone', p.telefone)
             order by c.data, c.horario, p.nome), '[]'::jsonb)
      from public.escala_itens i
      join public.escalas e on e.id = i.escala_id and e.status = 'publicada' and e.departamento_id = private.dept_kids()
      join public.cultos c on c.id = i.culto_id and not c.cancelado
      join public.voluntarias v on v.id = i.voluntaria_id
      join public.pessoas p on p.id = v.pessoa_id
      where c.data between p_de and p_ate));
end $$;

-- ---------- Permissões das funções ----------
revoke all on function private.esc_regra(text) from public, anon, authenticated;
revoke all on function private.esc_garantir_cultos(date) from public, anon, authenticated;
revoke all on function private.esc_grupos(uuid) from public, anon, authenticated;
revoke all on function private.esc_nome_sala(uuid, uuid) from public, anon, authenticated;
revoke all on function private.esc_pode_liderar(uuid) from public, anon, authenticated;
revoke all on function private.avisar_voluntaria(uuid, text, text, text, text) from public, anon, authenticated;
revoke all on function private.esc_do_mes(date) from public, anon, authenticated;
revoke all on function private.esc_preparar(uuid) from public, anon, authenticated;
revoke all on function private.esc_candidatas(uuid, int) from public, anon, authenticated;
revoke all on function private.esc_atribuir(uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function private.esc_motor(text) from public, anon, authenticated;

do $$
declare f text;
begin
  foreach f in array array[
    'public.configurar_escala(date, jsonb)', 'public.definir_vagas_culto(uuid, uuid, jsonb)',
    'public.gerar_rascunho(date)', 'public.simular_escala(date, text)', 'public.escala_do_mes(date)',
    'public.candidatas_vaga(uuid)', 'public.trocar_vaga(uuid, uuid, text)', 'public.adicionar_vaga(uuid, uuid, text)',
    'public.remover_vaga(uuid)', 'public.publicar_escala(date)', 'public.definir_regras_escala(jsonb)',
    'public.regras_escala_atuais()', 'public.definir_teto_voluntaria(uuid, integer)', 'public.voluntarias_escala()',
    'public.responder_escala(uuid, public.resposta_escala)', 'public.pegar_vaga(uuid)', 'public.minha_escala()',
    'public.minha_indisponibilidade(date)', 'public.salvar_indisponibilidade(date, uuid[])',
    'public.indisponibilidade_do_mes(date)', 'public.lembretes_escala(date, date)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
