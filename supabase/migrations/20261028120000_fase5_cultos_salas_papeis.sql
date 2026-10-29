-- =====================================================================
-- Fase 5 · Etapa 5A – Agenda de cultos, salas por culto e papéis das voluntárias
-- (decisões 79, 84, 85, 89 e 90 do plano)
--  1. Padrão de salas por culto da agenda (culto_recorrente_salas):
--     só as exceções (sala fechada ou junto com outra); sala sem linha = aberta.
--     Terça 20h já entra com "10 a 12" junto com "7 a 9" (= sala 7 a 12).
--  2. Cultos gerados sozinhos a partir da agenda (próximos 14 dias), sempre que
--     a agenda ou o check-in são consultados (sem pg_cron).
--  3. Funções da liderança (líder, pastor, admin) para a agenda, as salas
--     (todas as semanas ou um dia), cancelar culto e criar culto extra.
--  4. definir_papel(): líder/recepção das voluntárias; ninguém tira o próprio
--     acesso de líder; pastor e admin só pelo admin.
--  5. Configuração link_grupo_whatsapp (vazia).
--  6. cultos, culto_salas e cultos_recorrentes: gravação só pelas funções.
-- Nada aqui lê ou devolve dado pessoal de criança.
-- =====================================================================

-- ---------- 1. Estrutura ----------
alter table public.cultos
  add column if not exists salas_personalizadas boolean not null default false;
comment on column public.cultos.salas_personalizadas is
  'true = salas ajustadas só para este dia (ou culto extra); mudanças na agenda não mexem nele';

create table if not exists public.culto_recorrente_salas (
  id uuid primary key default gen_random_uuid(),
  culto_recorrente_id uuid not null references public.cultos_recorrentes(id) on delete cascade,
  sala_id uuid not null references public.salas(id) on delete cascade,
  cancelada boolean not null default false,
  combinada_com_sala_id uuid references public.salas(id) on delete set null,
  criado_em timestamptz not null default now(),
  unique (culto_recorrente_id, sala_id),
  check (combinada_com_sala_id is null or combinada_com_sala_id <> sala_id),
  check (not (cancelada and combinada_com_sala_id is not null))
);
comment on table public.culto_recorrente_salas is
  'Padrão de salas de cada culto da agenda: só exceções (fechada ou junto com outra sala)';

alter table public.culto_recorrente_salas enable row level security;
drop policy if exists crs_ler on public.culto_recorrente_salas;
create policy crs_ler on public.culto_recorrente_salas for select to authenticated using (true);
revoke insert, update, delete on public.culto_recorrente_salas from anon, authenticated;

-- auditoria (só nomes de campos)
drop trigger if exists culto_recorrente_salas_auditoria on public.culto_recorrente_salas;
create trigger culto_recorrente_salas_auditoria after insert or update or delete
  on public.culto_recorrente_salas for each row execute function private.auditar();
drop trigger if exists cultos_auditoria on public.cultos;
create trigger cultos_auditoria after insert or update or delete
  on public.cultos for each row execute function private.auditar();
drop trigger if exists culto_salas_auditoria on public.culto_salas;
create trigger culto_salas_auditoria after insert or update or delete
  on public.culto_salas for each row execute function private.auditar();
drop trigger if exists cultos_recorrentes_auditoria on public.cultos_recorrentes;
create trigger cultos_recorrentes_auditoria after insert or update or delete
  on public.cultos_recorrentes for each row execute function private.auditar();

-- ---------- 6. Gravação só pelas funções ----------
drop policy if exists cultos_criar  on public.cultos;
drop policy if exists cultos_editar on public.cultos;
drop policy if exists cultos_apagar on public.cultos;
drop policy if exists culto_salas_criar  on public.culto_salas;
drop policy if exists culto_salas_editar on public.culto_salas;
drop policy if exists culto_salas_apagar on public.culto_salas;
drop policy if exists recorrentes_criar  on public.cultos_recorrentes;
drop policy if exists recorrentes_editar on public.cultos_recorrentes;
drop policy if exists recorrentes_apagar on public.cultos_recorrentes;

-- ---------- Padrão inicial: terça 20h, 10 a 12 junto com 7 a 9 ----------
insert into public.culto_recorrente_salas (culto_recorrente_id, sala_id, combinada_com_sala_id)
select cr.id, s10.id, s7.id
from public.cultos_recorrentes cr
join public.departamentos d on d.slug = 'kids'
join public.salas s10 on s10.departamento_id = d.id and s10.idade_min = 10
join public.salas s7  on s7.departamento_id  = d.id and s7.idade_min  = 7
where cr.dia_semana = 2 and cr.horario = '20:00'
on conflict (culto_recorrente_id, sala_id) do nothing;

-- ---------- Funções auxiliares (privadas) ----------
create or replace function private.e_equipe_alguma()
returns boolean language sql stable security definer set search_path = '' as $$
  select private.e_lider_algum()
      or exists (select 1 from public.departamentos d where private.e_equipe(d.id))
$$;

-- assinatura das salas (para comparar o dia com o padrão da agenda)
create or replace function private.assinatura_salas_culto(p_culto uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(string_agg(x.sala_id::text || ':' || x.cancelada::text || ':' ||
                             coalesce(x.combinada_com_sala_id::text, ''), ',' order by x.sala_id), '')
  from public.culto_salas x where x.culto_id = p_culto
$$;
create or replace function private.assinatura_salas_agenda(p_rec uuid)
returns text language sql stable security definer set search_path = '' as $$
  select coalesce(string_agg(x.sala_id::text || ':' || x.cancelada::text || ':' ||
                             coalesce(x.combinada_com_sala_id::text, ''), ',' order by x.sala_id), '')
  from public.culto_recorrente_salas x where x.culto_recorrente_id = p_rec
$$;

-- copia o padrão da agenda para um culto
create or replace function private.copiar_salas_agenda(p_culto uuid, p_rec uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.culto_salas where culto_id = p_culto;
  insert into public.culto_salas (culto_id, sala_id, cancelada, combinada_com_sala_id)
  select p_culto, x.sala_id, x.cancelada, x.combinada_com_sala_id
  from public.culto_recorrente_salas x where x.culto_recorrente_id = p_rec;
end $$;

-- cria os cultos da agenda dos próximos dias (não mexe nos que já existem)
create or replace function private.gerar_cultos(p_dias int default 14)
returns int language plpgsql security definer set search_path = '' as $$
declare
  r record; v_id uuid; v_n int := 0;
begin
  for r in
    select cr.id as rec_id, cr.igreja_id, cr.nome, cr.horario, d::date as dia
    from public.cultos_recorrentes cr
    cross join generate_series(private.hoje(), private.hoje() + p_dias, interval '1 day') d
    where cr.ativo and extract(dow from d)::int = cr.dia_semana
  loop
    v_id := null;
    insert into public.cultos (igreja_id, culto_recorrente_id, data, horario, nome)
    values (r.igreja_id, r.rec_id, r.dia, r.horario, r.nome)
    on conflict (igreja_id, data, horario) do nothing
    returning id into v_id;
    if v_id is not null then
      perform private.copiar_salas_agenda(v_id, r.rec_id);
      v_n := v_n + 1;
    end if;
  end loop;
  return v_n;
end $$;

-- tira da agenda os cultos futuros de um culto da agenda (sem check-in):
-- apaga se não tiver escala; se tiver escala, só marca como cancelado
create or replace function private.retirar_cultos_futuros(p_rec uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  delete from public.cultos c
  where c.culto_recorrente_id = p_rec and c.data >= private.hoje()
    and not exists (select 1 from public.checkins k where k.culto_id = c.id)
    and not exists (select 1 from public.escala_itens e where e.culto_id = c.id);
  update public.cultos c set cancelado = true, observacao = 'Retirado da agenda'
  where c.culto_recorrente_id = p_rec and c.data >= private.hoje() and not c.cancelado
    and not exists (select 1 from public.checkins k where k.culto_id = c.id);
end $$;

-- confere a lista de exceções de salas: [{"sala_id":…, "cancelada":bool, "junto_com":uuid|null}]
create or replace function private.validar_salas(p_salas jsonb)
returns void language plpgsql stable security definer set search_path = '' as $$
declare
  e jsonb; v_sala uuid; v_junto uuid; v_canc boolean;
  v_ids uuid[] := '{}';
begin
  if p_salas is null or jsonb_typeof(p_salas) <> 'array' then
    raise exception 'Lista de salas inválida';
  end if;
  for e in select * from jsonb_array_elements(p_salas) loop
    v_sala := nullif(e->>'sala_id', '')::uuid;
    v_junto := nullif(e->>'junto_com', '')::uuid;
    v_canc := coalesce((e->>'cancelada')::boolean, false);
    if v_sala is null then raise exception 'Sala não informada'; end if;
    if v_sala = any (v_ids) then raise exception 'A mesma sala apareceu duas vezes'; end if;
    v_ids := v_ids || v_sala;
    if not exists (select 1 from public.salas s where s.id = v_sala and s.ativa
                   and private.e_lider(s.departamento_id)) then
      raise exception 'Sala não encontrada ou sem permissão';
    end if;
    if v_canc and v_junto is not null then
      raise exception 'Uma sala não pode estar fechada e junto com outra ao mesmo tempo';
    end if;
    if v_junto is not null then
      if v_junto = v_sala then raise exception 'Uma sala não pode ficar junto com ela mesma'; end if;
      if not exists (select 1 from public.salas s where s.id = v_junto and s.ativa
                     and s.departamento_id = (select departamento_id from public.salas where id = v_sala)) then
        raise exception 'A sala escolhida para juntar não existe';
      end if;
    end if;
  end loop;
  -- a sala que recebe as outras precisa estar aberta e não pode estar junto com outra
  if exists (
    select 1
    from jsonb_array_elements(p_salas) a
    join jsonb_array_elements(p_salas) b on (b->>'sala_id') = (a->>'junto_com')
    where coalesce((b->>'cancelada')::boolean, false) or nullif(b->>'junto_com', '') is not null
  ) then
    raise exception 'A sala que recebe as outras precisa estar aberta e separada';
  end if;
end $$;

-- monta as salas de um culto: grupos abertos (principal + salas juntas) e fechadas
create or replace function private.salas_do_culto_json(p_culto uuid, p_rec uuid, p_agenda boolean)
returns jsonb language sql stable security definer set search_path = '' as $$
  with base as (
    select s.id, s.nome, s.idade_min, s.idade_max, s.ordem,
           coalesce(x.cancelada, false) as cancelada, x.combinada_com_sala_id as junto_com
    from public.salas s
    join public.departamentos d on d.id = s.departamento_id and d.slug = 'kids'
    left join lateral (
      select cs.cancelada, cs.combinada_com_sala_id from public.culto_salas cs
      where not p_agenda and cs.culto_id = p_culto and cs.sala_id = s.id
      union all
      select rs.cancelada, rs.combinada_com_sala_id from public.culto_recorrente_salas rs
      where p_agenda and rs.culto_recorrente_id = p_rec and rs.sala_id = s.id
    ) x on true
    where s.ativa
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'sala_id', g.id,
           'nome', case when g.n > 1 then g.mn || ' a ' || g.mx || ' anos' else g.nome end,
           'idade_min', g.mn, 'idade_max', g.mx,
           'salas', g.salas, 'cancelada', g.cancelada) order by g.ordem), '[]'::jsonb)
  from (
    select p.id, p.nome, p.ordem, p.cancelada,
           count(*) as n, min(m.idade_min) as mn, max(m.idade_max) as mx,
           jsonb_agg(m.id order by m.ordem) as salas
    from base p
    join base m on m.id = p.id or m.junto_com = p.id
    where p.junto_com is null
    group by p.id, p.nome, p.ordem, p.cancelada
  ) g
$$;

-- ---------- 2. Leitura: cultos dos próximos dias e agenda ----------
create or replace function public.cultos_proximos(p_dias int default 14)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not private.e_equipe_alguma() then
    raise exception 'Sem permissão';
  end if;
  perform private.gerar_cultos(14);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', c.id, 'data', c.data, 'horario', to_char(c.horario, 'HH24:MI'), 'nome', c.nome,
      'cancelado', c.cancelado, 'extra', c.culto_recorrente_id is null,
      'personalizado', c.salas_personalizadas,
      'salas', private.salas_do_culto_json(c.id, c.culto_recorrente_id, false))
      order by c.data, c.horario)
    from public.cultos c
    where c.data between private.hoje() and private.hoje() + least(greatest(coalesce(p_dias, 14), 0), 60)
  ), '[]'::jsonb);
end $$;

create or replace function public.agenda_cultos()
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if not private.e_equipe_alguma() then
    raise exception 'Sem permissão';
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', cr.id, 'nome', cr.nome, 'dia_semana', cr.dia_semana,
      'horario', to_char(cr.horario, 'HH24:MI'), 'ativo', cr.ativo,
      'salas', private.salas_do_culto_json(null, cr.id, true))
      order by cr.ativo desc, cr.dia_semana, cr.horario)
    from public.cultos_recorrentes cr
  ), '[]'::jsonb);
end $$;

-- ---------- 3. Liderança: agenda, salas, cancelar, culto extra ----------
create or replace function public.salvar_culto_agenda(
  p_id uuid, p_nome text, p_dia_semana int, p_horario time, p_ativo boolean default true)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_old public.cultos_recorrentes%rowtype;
  v_id uuid;
  v_nome text := btrim(coalesce(p_nome, ''));
begin
  if not private.e_lider_algum() then raise exception 'Sem permissão'; end if;
  if char_length(v_nome) < 3 or char_length(v_nome) > 60 then
    raise exception 'O nome do culto deve ter de 3 a 60 letras';
  end if;
  if p_dia_semana is null or p_dia_semana not between 0 and 6 then raise exception 'Dia da semana inválido'; end if;
  if p_horario is null then raise exception 'Informe o horário'; end if;

  if p_id is null then
    begin
      insert into public.cultos_recorrentes (igreja_id, nome, dia_semana, horario, ativo)
      values ((select igreja_id from public.departamentos where slug = 'kids'),
              v_nome, p_dia_semana, p_horario, coalesce(p_ativo, true))
      returning id into v_id;
    exception when unique_violation then
      raise exception 'Já existe um culto na agenda nesse dia e horário';
    end;
  else
    select * into v_old from public.cultos_recorrentes where id = p_id;
    if not found then raise exception 'Culto da agenda não encontrado'; end if;
    begin
      update public.cultos_recorrentes
         set nome = v_nome, dia_semana = p_dia_semana, horario = p_horario, ativo = coalesce(p_ativo, true)
       where id = p_id;
    exception when unique_violation then
      raise exception 'Já existe um culto na agenda nesse dia e horário';
    end;
    v_id := p_id;
    if v_old.dia_semana <> p_dia_semana or v_old.horario <> p_horario
       or (v_old.ativo and not coalesce(p_ativo, true)) then
      perform private.retirar_cultos_futuros(p_id);
    elsif v_old.nome <> v_nome then
      update public.cultos set nome = v_nome
       where culto_recorrente_id = p_id and data >= private.hoje();
    end if;
  end if;
  perform private.gerar_cultos(14);
  return v_id;
end $$;

-- salas de um culto da agenda (vale para todas as semanas)
create or replace function public.definir_salas_agenda(p_recorrente uuid, p_salas jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  e jsonb; v_n int := 0; c record;
begin
  if not private.e_lider_algum() then raise exception 'Sem permissão'; end if;
  if not exists (select 1 from public.cultos_recorrentes where id = p_recorrente) then
    raise exception 'Culto da agenda não encontrado';
  end if;
  perform private.validar_salas(coalesce(p_salas, '[]'::jsonb));

  delete from public.culto_recorrente_salas where culto_recorrente_id = p_recorrente;
  for e in select * from jsonb_array_elements(coalesce(p_salas, '[]'::jsonb)) loop
    if coalesce((e->>'cancelada')::boolean, false) or nullif(e->>'junto_com', '') is not null then
      insert into public.culto_recorrente_salas (culto_recorrente_id, sala_id, cancelada, combinada_com_sala_id)
      values (p_recorrente, (e->>'sala_id')::uuid, coalesce((e->>'cancelada')::boolean, false),
              nullif(e->>'junto_com', '')::uuid);
    end if;
  end loop;

  -- vale para os próximos cultos ainda sem check-in que não foram ajustados no dia
  for c in
    select id from public.cultos
    where culto_recorrente_id = p_recorrente and data >= private.hoje()
      and not salas_personalizadas
      and not exists (select 1 from public.checkins k where k.culto_id = cultos.id)
  loop
    perform private.copiar_salas_agenda(c.id, p_recorrente);
    v_n := v_n + 1;
  end loop;
  perform private.gerar_cultos(14);
  return format('salas da agenda salvas; %s cultos futuros atualizados', v_n);
end $$;

-- salas de um dia só (p_salas null = voltar ao padrão da agenda)
create or replace function public.definir_salas_dia(p_culto uuid, p_salas jsonb)
returns text language plpgsql security definer set search_path = '' as $$
declare
  v public.cultos%rowtype; e jsonb;
begin
  if not private.e_lider_algum() then raise exception 'Sem permissão'; end if;
  select * into v from public.cultos where id = p_culto;
  if not found then raise exception 'Culto não encontrado'; end if;
  if v.data < private.hoje() then raise exception 'Não é possível mudar um culto que já passou'; end if;

  if p_salas is null then
    if v.culto_recorrente_id is null then raise exception 'Culto extra não tem padrão da agenda'; end if;
    perform private.copiar_salas_agenda(p_culto, v.culto_recorrente_id);
    update public.cultos set salas_personalizadas = false where id = p_culto;
  else
    perform private.validar_salas(p_salas);
    if exists (
      select 1 from jsonb_array_elements(p_salas) a
      join public.checkins k on k.culto_id = p_culto and k.sala_id = (a->>'sala_id')::uuid
      where coalesce((a->>'cancelada')::boolean, false)
    ) then
      raise exception 'Há crianças com check-in nessa sala. Junte com outra sala em vez de fechar';
    end if;
    delete from public.culto_salas where culto_id = p_culto;
    for e in select * from jsonb_array_elements(p_salas) loop
      if coalesce((e->>'cancelada')::boolean, false) or nullif(e->>'junto_com', '') is not null then
        insert into public.culto_salas (culto_id, sala_id, cancelada, combinada_com_sala_id)
        values (p_culto, (e->>'sala_id')::uuid, coalesce((e->>'cancelada')::boolean, false),
                nullif(e->>'junto_com', '')::uuid);
      end if;
    end loop;
    update public.cultos set salas_personalizadas = true where id = p_culto;
  end if;

  -- crianças já no check-in de uma sala que foi juntada passam para a sala que recebe
  update public.checkins k set sala_id = cs.combinada_com_sala_id
  from public.culto_salas cs
  where k.culto_id = p_culto and cs.culto_id = p_culto
    and cs.sala_id = k.sala_id and cs.combinada_com_sala_id is not null;
  return 'salas do dia salvas';
end $$;

create or replace function public.cancelar_culto(p_culto uuid, p_cancelar boolean default true)
returns text language plpgsql security definer set search_path = '' as $$
declare v public.cultos%rowtype;
begin
  if not private.e_lider_algum() then raise exception 'Sem permissão'; end if;
  select * into v from public.cultos where id = p_culto;
  if not found then raise exception 'Culto não encontrado'; end if;
  if v.data < private.hoje() then raise exception 'Não é possível mudar um culto que já passou'; end if;
  if coalesce(p_cancelar, true) and exists (select 1 from public.checkins where culto_id = p_culto) then
    raise exception 'Este culto já tem check-in';
  end if;
  update public.cultos
     set cancelado = coalesce(p_cancelar, true),
         observacao = case when coalesce(p_cancelar, true) then 'Cancelado pela liderança' else null end
   where id = p_culto;
  return case when coalesce(p_cancelar, true) then 'culto cancelado' else 'culto reativado' end;
end $$;

create or replace function public.criar_culto_extra(
  p_data date, p_horario time, p_nome text, p_salas jsonb default '[]'::jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid; e jsonb;
  v_nome text := btrim(coalesce(p_nome, ''));
begin
  if not private.e_lider_algum() then raise exception 'Sem permissão'; end if;
  if p_data is null or p_data < private.hoje() then raise exception 'Escolha uma data a partir de hoje'; end if;
  if p_data > private.hoje() + 366 then raise exception 'Escolha uma data dentro de um ano'; end if;
  if p_horario is null then raise exception 'Informe o horário'; end if;
  if char_length(v_nome) < 3 or char_length(v_nome) > 60 then
    raise exception 'O nome do culto deve ter de 3 a 60 letras';
  end if;
  perform private.validar_salas(coalesce(p_salas, '[]'::jsonb));
  begin
    insert into public.cultos (igreja_id, culto_recorrente_id, data, horario, nome, salas_personalizadas)
    values ((select igreja_id from public.departamentos where slug = 'kids'), null, p_data, p_horario, v_nome, true)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'Já existe um culto nesse dia e horário';
  end;
  for e in select * from jsonb_array_elements(coalesce(p_salas, '[]'::jsonb)) loop
    if coalesce((e->>'cancelada')::boolean, false) or nullif(e->>'junto_com', '') is not null then
      insert into public.culto_salas (culto_id, sala_id, cancelada, combinada_com_sala_id)
      values (v_id, (e->>'sala_id')::uuid, coalesce((e->>'cancelada')::boolean, false),
              nullif(e->>'junto_com', '')::uuid);
    end if;
  end loop;
  return v_id;
end $$;

-- ---------- 4. Papéis das voluntárias ----------
-- pastor só pelo admin (decisão 90)
create or replace function private.pode_gerir_papel(p_papel public.papel_tipo, p_dept uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select case
    when p_papel in ('admin', 'pastor') then private.e_admin()
    when p_papel = 'responsavel'        then private.e_lider_algum()
    else private.e_lider(p_dept)
  end
$$;

-- ninguém tira o próprio acesso de líder
drop policy if exists papeis_tirar on public.papeis_usuario;
create policy papeis_tirar on public.papeis_usuario for delete to authenticated
  using (private.pode_gerir_papel(papel, departamento_id)
         and not (papel = 'lider' and perfil_id = (select auth.uid())));

create or replace function public.definir_papel(p_perfil uuid, p_papel text, p_ativo boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare v_dept uuid;
begin
  if p_papel not in ('lider', 'recepcao') then
    raise exception 'Papel inválido (use líder ou recepção)';
  end if;
  select departamento_id into v_dept from public.papeis_usuario
   where perfil_id = p_perfil and papel = 'voluntaria' limit 1;
  if v_dept is null then raise exception 'Só é possível para voluntárias com login'; end if;
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  if not coalesce(p_ativo, false) and p_papel = 'lider' and p_perfil = auth.uid() then
    raise exception 'Você não pode tirar o seu próprio acesso de líder';
  end if;

  if coalesce(p_ativo, false) then
    insert into public.papeis_usuario (perfil_id, departamento_id, papel, concedido_por)
    values (p_perfil, v_dept, p_papel::public.papel_tipo, auth.uid())
    on conflict (perfil_id, departamento_id, papel) do nothing;
    return 'acesso concedido';
  else
    delete from public.papeis_usuario
     where perfil_id = p_perfil and departamento_id = v_dept and papel = p_papel::public.papel_tipo;
    return 'acesso retirado';
  end if;
end $$;

-- lista das voluntárias com login e seus acessos (só liderança)
create or replace function public.papeis_voluntarias()
returns table (perfil_id uuid, nome text, lider boolean, recepcao boolean, sou_eu boolean)
language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := (select id from public.departamentos where slug = 'kids');
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  return query
    select v.perfil_id, pe.nome,
           exists (select 1 from public.papeis_usuario x where x.perfil_id = v.perfil_id and x.departamento_id = v_dept and x.papel = 'lider'),
           exists (select 1 from public.papeis_usuario x where x.perfil_id = v.perfil_id and x.departamento_id = v_dept and x.papel = 'recepcao'),
           v.perfil_id = auth.uid()
    from public.papeis_usuario v
    join public.perfis pf on pf.id = v.perfil_id
    join public.pessoas pe on pe.id = pf.pessoa_id
    where v.departamento_id = v_dept and v.papel = 'voluntaria'
    order by pe.nome;
end $$;

-- ---------- 5. Configuração do link do grupo de WhatsApp ----------
insert into public.configuracoes (departamento_id, chave, valor, descricao)
select d.id, 'link_grupo_whatsapp', '', 'Link de convite do grupo de WhatsApp dos responsáveis (enviado após o cadastro)'
from public.departamentos d where d.slug = 'kids'
on conflict (departamento_id, chave) do nothing;

-- ---------- Ajuste dos cultos futuros já existentes ----------
-- futuros sem check-in e sem nenhuma sala definida recebem o padrão da agenda;
-- os que já tinham ajuste próprio e diferente do padrão ficam como "ajustados no dia"
update public.cultos c set salas_personalizadas = true
where c.data >= private.hoje() and c.culto_recorrente_id is not null
  and exists (select 1 from public.culto_salas cs where cs.culto_id = c.id)
  and private.assinatura_salas_culto(c.id) <> private.assinatura_salas_agenda(c.culto_recorrente_id);

do $$
declare c record;
begin
  for c in
    select id, culto_recorrente_id from public.cultos
    where data >= private.hoje() and culto_recorrente_id is not null and not salas_personalizadas
      and not exists (select 1 from public.checkins k where k.culto_id = cultos.id)
  loop
    perform private.copiar_salas_agenda(c.id, c.culto_recorrente_id);
  end loop;
end $$;

-- ---------- Permissões das funções ----------
revoke all on function private.e_equipe_alguma() from public, anon, authenticated;
revoke all on function private.assinatura_salas_culto(uuid) from public, anon, authenticated;
revoke all on function private.assinatura_salas_agenda(uuid) from public, anon, authenticated;
revoke all on function private.copiar_salas_agenda(uuid, uuid) from public, anon, authenticated;
revoke all on function private.gerar_cultos(int) from public, anon, authenticated;
revoke all on function private.retirar_cultos_futuros(uuid) from public, anon, authenticated;
revoke all on function private.validar_salas(jsonb) from public, anon, authenticated;
revoke all on function private.salas_do_culto_json(uuid, uuid, boolean) from public, anon, authenticated;

revoke all on function public.cultos_proximos(int) from public, anon;
revoke all on function public.agenda_cultos() from public, anon;
revoke all on function public.salvar_culto_agenda(uuid, text, int, time, boolean) from public, anon;
revoke all on function public.definir_salas_agenda(uuid, jsonb) from public, anon;
revoke all on function public.definir_salas_dia(uuid, jsonb) from public, anon;
revoke all on function public.cancelar_culto(uuid, boolean) from public, anon;
revoke all on function public.criar_culto_extra(date, time, text, jsonb) from public, anon;
revoke all on function public.definir_papel(uuid, text, boolean) from public, anon;
revoke all on function public.papeis_voluntarias() from public, anon;
grant execute on function public.cultos_proximos(int) to authenticated;
grant execute on function public.agenda_cultos() to authenticated;
grant execute on function public.salvar_culto_agenda(uuid, text, int, time, boolean) to authenticated;
grant execute on function public.definir_salas_agenda(uuid, jsonb) to authenticated;
grant execute on function public.definir_salas_dia(uuid, jsonb) to authenticated;
grant execute on function public.cancelar_culto(uuid, boolean) to authenticated;
grant execute on function public.criar_culto_extra(date, time, text, jsonb) to authenticated;
grant execute on function public.definir_papel(uuid, text, boolean) to authenticated;
grant execute on function public.papeis_voluntarias() to authenticated;
