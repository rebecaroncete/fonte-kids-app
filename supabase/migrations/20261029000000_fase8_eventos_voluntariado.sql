-- =====================================================================
-- Fase 8 · Eventos, voluntariado e convites (28/10/2026)
--   1. Eventos do Fonte Kids: a liderança (líder do Fonte Kids, pastor,
--      admin) cria, edita, publica (aviso + push para o público escolhido),
--      cancela (avisa os inscritos) e apaga (só sem inscrições).
--      Campos novos: faixa de idade, prazo de inscrição, "precisa de
--      autorização", ajuda da equipe (com vagas opcionais).
--   2. Inscrições: o responsável inscreve só as crianças da própria
--      família, dentro da idade, do prazo e das vagas (sem lista de
--      espera); se o evento pedir, marca "Autorizo a participação"
--      (gravado com data e quem marcou). A liderança vê os inscritos,
--      inscreve e tira qualquer criança (mesmo passando do limite),
--      marca "Presente" e manda "Avisar inscritos".
--   3. "Quero ajudar": voluntárias ativas se oferecem no evento.
--   4. Voluntariado: a liderança edita função, salas e cultos preferidos,
--      e-mail e profissão; desativa/reativa a voluntária (inativa sai das
--      vagas dos meses em RASCUNHO, das ajudas em eventos futuros e perde
--      os papéis de voluntária e recepção; o login continua). A própria
--      voluntária edita as salas e os cultos preferidos.
-- Escrita só por funções security definer; RLS em tudo; auditoria.
-- Toda alteração com WHERE (a API usa pg_safeupdate).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Estrutura
-- ---------------------------------------------------------------------
alter table public.eventos
  add column if not exists idade_min smallint check (idade_min between 0 and 12),
  add column if not exists idade_max smallint check (idade_max between 0 and 12),
  add column if not exists inscricoes_ate date,
  add column if not exists precisa_autorizacao boolean not null default false,
  add column if not exists aceita_ajuda boolean not null default false,
  add column if not exists vagas_ajuda smallint check (vagas_ajuda between 1 and 50),
  add column if not exists publico text check (publico in ('todos', 'equipe', 'lideres', 'responsaveis')),
  add column if not exists publicado_em timestamptz,
  add column if not exists publicado_por uuid references public.perfis(id) on delete set null,
  add column if not exists destinatarios integer not null default 0,
  add column if not exists cancelado_em timestamptz,
  add column if not exists cancelado_por uuid references public.perfis(id) on delete set null,
  add column if not exists ultimo_lembrete_em timestamptz;
create index if not exists eventos_publicado_por_idx on public.eventos (publicado_por);
create index if not exists eventos_cancelado_por_idx on public.eventos (cancelado_por);
create index if not exists eventos_inicio_idx on public.eventos (departamento_id, inicio);

-- Inscrição é sempre de criança cadastrada: "nome" e "telefone" ficam sem uso
alter table public.inscricoes_evento alter column nome drop not null;
alter table public.inscricoes_evento
  add column if not exists autorizado_em timestamptz,
  add column if not exists autorizado_por uuid references public.perfis(id) on delete set null,
  add column if not exists observacao text check (char_length(observacao) <= 300),
  add column if not exists presente boolean,
  add column if not exists presenca_em timestamptz;
create unique index if not exists inscricoes_evento_crianca_uk on public.inscricoes_evento (evento_id, crianca_id)
  where crianca_id is not null;
create index if not exists inscricoes_autorizado_por_idx on public.inscricoes_evento (autorizado_por);

create table if not exists public.ajudas_evento (
  id             uuid primary key default gen_random_uuid(),
  evento_id      uuid not null references public.eventos(id) on delete cascade,
  voluntaria_id  uuid not null references public.voluntarias(id) on delete cascade,
  criado_em      timestamptz not null default now(),
  unique (evento_id, voluntaria_id)
);
create index if not exists ajudas_evento_voluntaria_idx on public.ajudas_evento (voluntaria_id);
alter table public.ajudas_evento enable row level security;
drop policy if exists ajudas_ler on public.ajudas_evento;
create policy ajudas_ler on public.ajudas_evento for select to authenticated using (
  voluntaria_id in (select private.minhas_voluntarias()) or private.e_lider(private.dept_evento(evento_id)));
revoke all on public.ajudas_evento from anon;
revoke insert, update, delete on public.ajudas_evento from authenticated;

-- Gravação de eventos e inscrições só pelas funções
drop policy if exists eventos_criar on public.eventos;
drop policy if exists eventos_editar on public.eventos;
drop policy if exists eventos_apagar on public.eventos;
drop policy if exists inscricoes_criar on public.inscricoes_evento;
drop policy if exists inscricoes_editar on public.inscricoes_evento;
drop policy if exists inscricoes_apagar on public.inscricoes_evento;
revoke insert, update, delete on public.eventos, public.inscricoes_evento from authenticated;
revoke all on public.eventos, public.inscricoes_evento from anon;

-- Voluntárias: gravação só pelas funções (o app nunca gravou direto)
drop policy if exists voluntarias_criar on public.voluntarias;
drop policy if exists voluntarias_editar on public.voluntarias;
drop policy if exists voluntarias_apagar on public.voluntarias;
revoke insert, update, delete on public.voluntarias from authenticated;

-- ---------------------------------------------------------------------
-- 2. Funções internas
-- ---------------------------------------------------------------------
-- Dia do evento (Brasília)
create or replace function private.dia_evento(p_inicio timestamptz)
returns date language sql immutable set search_path = '' as $$
  select (p_inicio at time zone 'America/Sao_Paulo')::date $$;

-- Idade (anos completos) numa data
create or replace function private.idade_em(p_nasc date, p_dia date)
returns integer language sql immutable set search_path = '' as $$
  select case when p_nasc is null then null else extract(year from age(p_dia, p_nasc))::int end $$;

-- "dd/mm às hh:mi" do início do evento
create or replace function private.quando_evento(p_inicio timestamptz)
returns text language sql immutable set search_path = '' as $$
  select to_char(p_inicio at time zone 'America/Sao_Paulo', 'DD/MM "às" HH24:MI') $$;

-- Inscrições abertas para os responsáveis agora?
create or replace function private.inscricao_aberta(e public.eventos)
returns boolean language sql stable set search_path = '' as $$
  select e.publicado and e.cancelado_em is null and e.inscricoes_abertas
     and e.inicio > now()
     and (e.inscricoes_ate is null or private.hoje() <= e.inscricoes_ate) $$;

-- Logins dos responsáveis das crianças inscritas (sem quem envia)
create or replace function private.responsaveis_inscritos(p_evento uuid)
returns setof uuid language sql stable security definer set search_path = '' as $$
  select distinct pf.id
    from public.inscricoes_evento i
    join public.criancas c on c.id = i.crianca_id
    join public.responsaveis r on r.familia_id = c.familia_id
    join public.perfis pf on pf.pessoa_id = r.pessoa_id and pf.ativo
   where i.evento_id = p_evento and pf.id is distinct from auth.uid() $$;

-- Logins das voluntárias que vão ajudar (sem quem envia)
create or replace function private.ajudantes_evento(p_evento uuid)
returns setof uuid language sql stable security definer set search_path = '' as $$
  select distinct pf.id
    from public.ajudas_evento a
    join public.voluntarias v on v.id = a.voluntaria_id
    join public.perfis pf on pf.pessoa_id = v.pessoa_id and pf.ativo
   where a.evento_id = p_evento and pf.id is distinct from auth.uid() $$;

-- Valida salas (1–4) e cultos (1–3) preferidos, sem repetir
create or replace function private.validar_preferencias(p_salas uuid[], p_cultos uuid[])
returns void language plpgsql stable security definer set search_path = '' as $$
begin
  if coalesce(cardinality(p_salas), 0) not between 1 and 4
     or cardinality(p_salas) <> (select count(distinct s) from unnest(p_salas) s)
     or exists (select 1 from unnest(p_salas) s where not exists (
          select 1 from public.salas x where x.id = s and x.departamento_id = private.dept_kids() and x.ativa)) then
    raise exception 'Escolha de 1 a 4 faixas de idade';
  end if;
  if coalesce(cardinality(p_cultos), 0) not between 1 and 3
     or cardinality(p_cultos) <> (select count(distinct c) from unnest(p_cultos) c)
     or exists (select 1 from unnest(p_cultos) c where not exists (
          select 1 from public.cultos_recorrentes r where r.id = c and r.ativo)) then
    raise exception 'Escolha de 1 a 3 cultos';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 3. Eventos (liderança)
-- ---------------------------------------------------------------------
-- Cria (p_evento nulo, fica em rascunho) ou edita. Editar não avisa ninguém.
-- p_dados: titulo, descricao, inicio, fim, local, idade_min, idade_max,
--          vagas, inscricoes_ate (data), autorizacao, inscricoes_abertas,
--          aceita_ajuda, vagas_ajuda
create or replace function public.salvar_evento(p_evento uuid, p_dados jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids(); e public.eventos;
  v_titulo text := btrim(coalesce(p_dados->>'titulo', ''));
  v_desc text := nullif(btrim(coalesce(p_dados->>'descricao', '')), '');
  v_local text := nullif(btrim(coalesce(p_dados->>'local', '')), '');
  v_inicio timestamptz; v_fim timestamptz; v_ate date;
  v_imin smallint; v_imax smallint; v_vagas int; v_vagas_aj smallint;
  v_aut boolean := coalesce((p_dados->>'autorizacao')::boolean, false);
  v_abertas boolean := coalesce((p_dados->>'inscricoes_abertas')::boolean, true);
  v_ajuda boolean := coalesce((p_dados->>'aceita_ajuda')::boolean, false);
  v_id uuid;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  if p_evento is not null then
    select * into e from public.eventos where id = p_evento and departamento_id = v_dept for update;
    if e.id is null then raise exception 'Evento não encontrado'; end if;
    if e.cancelado_em is not null then raise exception 'Este evento foi cancelado'; end if;
  end if;

  begin
    v_inicio := nullif(p_dados->>'inicio', '')::timestamptz;
    v_fim := nullif(p_dados->>'fim', '')::timestamptz;
    v_ate := nullif(p_dados->>'inscricoes_ate', '')::date;
    v_imin := nullif(p_dados->>'idade_min', '')::smallint;
    v_imax := nullif(p_dados->>'idade_max', '')::smallint;
    v_vagas := nullif(p_dados->>'vagas', '')::int;
    v_vagas_aj := nullif(p_dados->>'vagas_ajuda', '')::smallint;
  exception when others then raise exception 'Confira as datas e os números';
  end;

  if char_length(v_titulo) < 3 or char_length(v_titulo) > 80 then raise exception 'O nome do evento precisa ter de 3 a 80 letras'; end if;
  if char_length(coalesce(v_desc, '')) > 2000 then raise exception 'A descrição pode ter até 2000 letras'; end if;
  if char_length(coalesce(v_local, '')) > 120 then raise exception 'O local pode ter até 120 letras'; end if;
  if v_inicio is null then raise exception 'Informe a data e a hora do evento'; end if;
  if (p_evento is null or v_inicio is distinct from e.inicio)
     and (v_inicio < now() or private.dia_evento(v_inicio) > private.hoje() + 365) then
    raise exception 'A data do evento precisa ser de hoje até 1 ano';
  end if;
  if v_fim is not null and (v_fim <= v_inicio or v_fim > v_inicio + interval '7 days') then
    raise exception 'O fim precisa ser depois do início (até 7 dias)';
  end if;
  if v_imin is not null and v_imin not between 0 and 12 then raise exception 'A idade vai de 0 a 12 anos'; end if;
  if v_imax is not null and v_imax not between 0 and 12 then raise exception 'A idade vai de 0 a 12 anos'; end if;
  if v_imin is not null and v_imax is not null and v_imin > v_imax then raise exception 'A idade mínima passa da máxima'; end if;
  if v_vagas is not null and v_vagas not between 1 and 500 then raise exception 'As vagas vão de 1 a 500'; end if;
  if v_ate is not null and v_ate > private.dia_evento(v_inicio) then raise exception 'O prazo de inscrição passa da data do evento'; end if;
  if v_vagas_aj is not null and v_vagas_aj not between 1 and 50 then raise exception 'As vagas de ajuda vão de 1 a 50'; end if;
  if not v_ajuda then v_vagas_aj := null; end if;

  if p_evento is null then
    if (select count(*) from public.eventos where departamento_id = v_dept and criado_em > now() - interval '24 hours') >= 20 then
      raise exception 'Limite de 20 eventos novos em 24 horas'; end if;
    insert into public.eventos (departamento_id, titulo, descricao, inicio, fim, local, idade_min, idade_max,
                                limite_inscricoes, inscricoes_ate, precisa_autorizacao, inscricoes_abertas,
                                aceita_ajuda, vagas_ajuda)
    values (v_dept, v_titulo, v_desc, v_inicio, v_fim, v_local, v_imin, v_imax, v_vagas, v_ate, v_aut, v_abertas,
            v_ajuda, v_vagas_aj)
    returning id into v_id;
  else
    update public.eventos
       set titulo = v_titulo, descricao = v_desc, inicio = v_inicio, fim = v_fim, local = v_local,
           idade_min = v_imin, idade_max = v_imax, limite_inscricoes = v_vagas, inscricoes_ate = v_ate,
           precisa_autorizacao = v_aut, inscricoes_abertas = v_abertas, aceita_ajuda = v_ajuda, vagas_ajuda = v_vagas_aj
     where id = p_evento;
    v_id := p_evento;
  end if;
  return v_id;
end $$;

-- Publica e avisa (com push) o público escolhido
create or replace function public.publicar_evento(p_evento uuid, p_publico text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids(); e public.eventos; n int;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  if p_publico is null or p_publico not in ('todos', 'equipe', 'lideres', 'responsaveis') then
    raise exception 'Escolha para quem é o aviso'; end if;
  select * into e from public.eventos where id = p_evento and departamento_id = v_dept for update;
  if e.id is null then raise exception 'Evento não encontrado'; end if;
  if e.publicado then raise exception 'Este evento já foi publicado'; end if;
  if e.inicio <= now() then raise exception 'A data do evento já passou: corrija antes de publicar'; end if;
  if (select count(*) from public.eventos where departamento_id = v_dept and publicado_em > now() - interval '24 hours') >= 10 then
    raise exception 'Limite de 10 eventos publicados em 24 horas'; end if;

  update public.eventos set publicado = true, publicado_em = now(), publicado_por = auth.uid(), publico = p_publico
   where id = p_evento;

  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por)
  select d, 'Novo evento: ' || left(e.titulo, 60),
         private.quando_evento(e.inicio) || coalesce(' · ' || e.local, '')
           || case when e.inscricoes_abertas then '. Inscrições pelo app.' else '.' end,
         '#/eventos?id=' || e.id, 'evento', auth.uid()
    from private.destinatarios(p_publico) d;
  get diagnostics n = row_count;
  update public.eventos set destinatarios = n where id = p_evento;
  return jsonb_build_object('destinatarios', n);
end $$;

-- Cancela (avisa os responsáveis dos inscritos e quem ia ajudar)
create or replace function public.cancelar_evento(p_evento uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids(); e public.eventos; n int;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  select * into e from public.eventos where id = p_evento and departamento_id = v_dept for update;
  if e.id is null then raise exception 'Evento não encontrado'; end if;
  if not e.publicado then raise exception 'Evento em rascunho: use Apagar'; end if;
  if e.cancelado_em is not null then raise exception 'Este evento já foi cancelado'; end if;

  update public.eventos set cancelado_em = now(), cancelado_por = auth.uid(), inscricoes_abertas = false
   where id = p_evento;

  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por)
  select d, 'Evento cancelado: ' || left(e.titulo, 60),
         'O evento de ' || private.quando_evento(e.inicio) || ' foi cancelado.',
         '#/eventos?id=' || e.id, 'evento', auth.uid()
    from (select private.responsaveis_inscritos(p_evento) d union select private.ajudantes_evento(p_evento)) x;
  get diagnostics n = row_count;
  return n;
end $$;

-- Apaga (só sem inscrições e sem ajudas)
create or replace function public.apagar_evento(p_evento uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.e_lider(private.dept_kids()) or private.dept_evento(p_evento) is distinct from private.dept_kids() then
    raise exception 'Sem permissão'; end if;
  if exists (select 1 from public.inscricoes_evento where evento_id = p_evento)
     or exists (select 1 from public.ajudas_evento where evento_id = p_evento) then
    raise exception 'Este evento tem inscrições: cancele em vez de apagar';
  end if;
  delete from public.eventos where id = p_evento;
end $$;

-- Lembrete para os responsáveis dos inscritos (no máximo 1 por hora)
create or replace function public.avisar_inscritos(p_evento uuid, p_texto text default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids(); e public.eventos; v_texto text := nullif(btrim(coalesce(p_texto, '')), ''); n int;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  select * into e from public.eventos where id = p_evento and departamento_id = v_dept for update;
  if e.id is null then raise exception 'Evento não encontrado'; end if;
  if not e.publicado or e.cancelado_em is not null then raise exception 'Só eventos publicados e não cancelados'; end if;
  if coalesce(e.fim, e.inicio) < now() then raise exception 'Este evento já terminou'; end if;
  if char_length(coalesce(v_texto, '')) > 500 then raise exception 'O texto pode ter até 500 letras'; end if;
  if e.ultimo_lembrete_em > now() - interval '1 hour' then raise exception 'Espere 1 hora entre um lembrete e outro'; end if;

  update public.eventos set ultimo_lembrete_em = now() where id = p_evento;
  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por)
  select d, 'Lembrete: ' || left(e.titulo, 60),
         coalesce(v_texto, 'O evento é ' || private.quando_evento(e.inicio) || coalesce(' · ' || e.local, '') || '.'),
         '#/eventos?id=' || e.id, 'evento', auth.uid()
    from private.responsaveis_inscritos(p_evento) d;
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 4. Inscrições
-- ---------------------------------------------------------------------
-- Inscreve (ou atualiza a autorização/observação de quem já está inscrito).
-- Responsável: só as crianças da própria família, dentro das regras.
-- Liderança: qualquer criança ativa do Fonte Kids, mesmo fora do prazo ou
-- passando do limite (a autorização continua sendo só do responsável).
create or replace function public.inscrever_crianca(p_evento uuid, p_crianca uuid,
                                                    p_autorizo boolean default false, p_observacao text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids(); e public.eventos; c record; v_id uuid; v_idade int;
  v_lider boolean := private.e_lider(private.dept_kids());
  v_meu boolean := p_crianca in (select private.minhas_criancas());
  v_obs text := nullif(btrim(coalesce(p_observacao, '')), '');
begin
  if not (v_lider or (v_meu and private.perfil_liberado())) then raise exception 'Sem permissão'; end if;
  select * into e from public.eventos where id = p_evento and departamento_id = v_dept for update;
  if e.id is null or not e.publicado then raise exception 'Evento não encontrado'; end if;
  if e.cancelado_em is not null then raise exception 'Este evento foi cancelado'; end if;
  if coalesce(e.fim, e.inicio) < now() then raise exception 'Este evento já aconteceu'; end if;
  select cr.id, cr.ativo, f.departamento_id, pe.data_nascimento into c
    from public.criancas cr join public.familias f on f.id = cr.familia_id join public.pessoas pe on pe.id = cr.pessoa_id
   where cr.id = p_crianca;
  if c.id is null or not c.ativo or c.departamento_id is distinct from v_dept then raise exception 'Criança não encontrada'; end if;
  if char_length(coalesce(v_obs, '')) > 300 then raise exception 'A observação pode ter até 300 letras'; end if;

  select id into v_id from public.inscricoes_evento where evento_id = p_evento and crianca_id = p_crianca;
  if v_id is not null then
    if v_meu then
      if e.precisa_autorizacao and not coalesce(p_autorizo, false) then
        raise exception 'Marque "Autorizo a participação"'; end if;
      update public.inscricoes_evento
         set observacao = v_obs,
             autorizado_em = case when e.precisa_autorizacao then coalesce(autorizado_em, now()) end,
             autorizado_por = case when e.precisa_autorizacao then coalesce(autorizado_por, auth.uid()) end
       where id = v_id;
    else
      update public.inscricoes_evento set observacao = v_obs where id = v_id;
    end if;
    return v_id;
  end if;

  if not v_lider then
    if not private.inscricao_aberta(e) then raise exception 'As inscrições deste evento estão fechadas'; end if;
    v_idade := private.idade_em(c.data_nascimento, private.dia_evento(e.inicio));
    if (e.idade_min is not null or e.idade_max is not null) and (v_idade is null
        or v_idade < coalesce(e.idade_min, 0) or v_idade > coalesce(e.idade_max, 12)) then
      raise exception 'Este evento é para crianças de % a % anos', coalesce(e.idade_min, 0), coalesce(e.idade_max, 12);
    end if;
    if e.limite_inscricoes is not null
       and (select count(*) from public.inscricoes_evento where evento_id = p_evento) >= e.limite_inscricoes then
      raise exception 'Vagas esgotadas';
    end if;
  end if;
  if v_meu and e.precisa_autorizacao and not coalesce(p_autorizo, false) then
    raise exception 'Marque "Autorizo a participação"'; end if;

  insert into public.inscricoes_evento (evento_id, crianca_id, inscrito_por, observacao, autorizado_em, autorizado_por)
  values (p_evento, p_crianca, auth.uid(), v_obs,
          case when v_meu and e.precisa_autorizacao then now() end,
          case when v_meu and e.precisa_autorizacao then auth.uid() end)
  returning id into v_id;
  return v_id;
end $$;

-- Tira a inscrição. Responsável: até o prazo e antes do evento; liderança: sempre.
create or replace function public.cancelar_inscricao(p_inscricao uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare i record;
begin
  select ins.id, ins.crianca_id, e.departamento_id, e.inicio, e.inscricoes_ate, e.cancelado_em into i
    from public.inscricoes_evento ins join public.eventos e on e.id = ins.evento_id
   where ins.id = p_inscricao;
  if i.id is null then raise exception 'Inscrição não encontrada'; end if;
  if not private.e_lider(i.departamento_id) then
    if not (i.crianca_id in (select private.minhas_criancas()) and private.perfil_liberado()) then
      raise exception 'Sem permissão'; end if;
    if i.cancelado_em is null and (i.inicio <= now() or (i.inscricoes_ate is not null and private.hoje() > i.inscricoes_ate)) then
      raise exception 'O prazo para tirar a inscrição já passou: fale com a liderança';
    end if;
  end if;
  delete from public.inscricoes_evento where id = p_inscricao;
end $$;

-- Presença no dia (liderança). p_presente nulo = desmarcar.
create or replace function public.marcar_presenca_evento(p_inscricao uuid, p_presente boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare v_evento uuid;
begin
  select evento_id into v_evento from public.inscricoes_evento where id = p_inscricao;
  if v_evento is null then raise exception 'Inscrição não encontrada'; end if;
  if not private.e_lider(private.dept_evento(v_evento)) then raise exception 'Sem permissão'; end if;
  update public.inscricoes_evento
     set presente = p_presente, presenca_em = case when p_presente is null then null else now() end
   where id = p_inscricao;
end $$;

-- ---------------------------------------------------------------------
-- 5. "Quero ajudar" (voluntária ativa)
-- ---------------------------------------------------------------------
create or replace function public.ajudar_evento(p_evento uuid, p_sim boolean)
returns void language plpgsql security definer set search_path = '' as $$
declare e public.eventos; v_vol uuid;
begin
  select id into v_vol from public.voluntarias
   where id in (select private.minhas_voluntarias()) and departamento_id = private.dept_kids() limit 1;
  if v_vol is null then raise exception 'Só voluntárias ativas podem se oferecer'; end if;
  select * into e from public.eventos where id = p_evento and departamento_id = private.dept_kids() for update;
  if e.id is null or not e.publicado then raise exception 'Evento não encontrado'; end if;
  if not coalesce(p_sim, false) then
    delete from public.ajudas_evento where evento_id = p_evento and voluntaria_id = v_vol;
    return;
  end if;
  if e.cancelado_em is not null then raise exception 'Este evento foi cancelado'; end if;
  if e.inicio <= now() then raise exception 'Este evento já começou'; end if;
  if not e.aceita_ajuda then raise exception 'Este evento não está pedindo ajuda'; end if;
  if exists (select 1 from public.ajudas_evento where evento_id = p_evento and voluntaria_id = v_vol) then return; end if;
  if e.vagas_ajuda is not null and (select count(*) from public.ajudas_evento where evento_id = p_evento) >= e.vagas_ajuda then
    raise exception 'As vagas de ajuda já foram preenchidas';
  end if;
  insert into public.ajudas_evento (evento_id, voluntaria_id) values (p_evento, v_vol);
end $$;

-- ---------------------------------------------------------------------
-- 6. Leitura
-- ---------------------------------------------------------------------
-- Eventos que a pessoa pode ver. Liderança: rascunhos e passados (até 180
-- dias) também. Responsável: as próprias crianças, com a idade no dia,
-- se cabem na faixa e a inscrição de cada uma. Voluntária: "Quero ajudar".
create or replace function public.eventos_lista()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids(); v_lider boolean; v_vol uuid;
  v_criancas uuid[];
begin
  if auth.uid() is null or not private.perfil_liberado() or not private.tem_algum_papel() then
    raise exception 'Sem permissão'; end if;
  v_lider := private.e_lider(v_dept);
  select id into v_vol from public.voluntarias
   where id in (select private.minhas_voluntarias()) and departamento_id = v_dept limit 1;
  select array_agg(c.id) into v_criancas from public.criancas c
   where c.id in (select private.minhas_criancas()) and c.ativo;

  return (
    select coalesce(jsonb_agg(item order by passado, ordem_inicio), '[]'::jsonb) from (
      select (coalesce(e.fim, e.inicio) < now()) passado,
             case when coalesce(e.fim, e.inicio) < now() then -extract(epoch from e.inicio) else extract(epoch from e.inicio) end ordem_inicio,
        jsonb_build_object(
          'id', e.id, 'titulo', e.titulo, 'descricao', e.descricao, 'inicio', e.inicio, 'fim', e.fim, 'local', e.local,
          'idade_min', e.idade_min, 'idade_max', e.idade_max, 'vagas', e.limite_inscricoes,
          'inscricoes_ate', e.inscricoes_ate, 'autorizacao', e.precisa_autorizacao,
          'inscricoes_abertas', e.inscricoes_abertas, 'aberta', private.inscricao_aberta(e),
          'publicado', e.publicado, 'publicado_em', e.publicado_em, 'publico', e.publico,
          'cancelado', e.cancelado_em is not null, 'passado', coalesce(e.fim, e.inicio) < now(),
          'inscritos', (select count(*) from public.inscricoes_evento i where i.evento_id = e.id),
          'aceita_ajuda', e.aceita_ajuda, 'vagas_ajuda', e.vagas_ajuda,
          'ajudantes', (select count(*) from public.ajudas_evento a where a.evento_id = e.id),
          'eu_ajudo', v_vol is not null and exists (select 1 from public.ajudas_evento a where a.evento_id = e.id and a.voluntaria_id = v_vol),
          'pode_ajudar', v_vol is not null,
          'lider', v_lider,
          'destinatarios', case when v_lider then e.destinatarios end,
          'ultimo_lembrete_em', case when v_lider then e.ultimo_lembrete_em end,
          'minhas_criancas', case when e.publicado and v_criancas is not null then (
             select coalesce(jsonb_agg(jsonb_build_object(
                      'id', c.id, 'nome', pe.nome,
                      'idade', private.idade_em(pe.data_nascimento, private.dia_evento(e.inicio)),
                      'cabe', (e.idade_min is null and e.idade_max is null)
                              or private.idade_em(pe.data_nascimento, private.dia_evento(e.inicio))
                                 between coalesce(e.idade_min, 0) and coalesce(e.idade_max, 12),
                      'inscricao', (select jsonb_build_object('id', i.id, 'autorizado', i.autorizado_em is not null,
                                                              'observacao', i.observacao)
                                      from public.inscricoes_evento i where i.evento_id = e.id and i.crianca_id = c.id))
                    order by pe.nome), '[]'::jsonb)
               from public.criancas c join public.pessoas pe on pe.id = c.pessoa_id
              where c.id = any (v_criancas)) end
        ) item
      from public.eventos e
      where e.departamento_id = v_dept
        and (e.publicado or v_lider)
        and (case when v_lider then coalesce(e.fim, e.inicio) > now() - interval '180 days'
                  else coalesce(e.fim, e.inicio) > now() - interval '1 day' end)
      order by e.inicio limit 100) z);
end $$;

-- Inscritos e ajudantes de um evento (liderança)
create or replace function public.evento_inscritos(p_evento uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare e public.eventos;
begin
  select * into e from public.eventos where id = p_evento;
  if e.id is null or not private.e_lider(e.departamento_id) then raise exception 'Sem permissão'; end if;
  return jsonb_build_object(
    'inscritos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', i.id, 'crianca_id', i.crianca_id, 'nome', coalesce(pe.nome, 'Cadastro apagado'),
               'idade', private.idade_em(pe.data_nascimento, private.dia_evento(e.inicio)),
               'alergias', c.alergias_observacoes, 'observacao', i.observacao,
               'autorizado_em', i.autorizado_em, 'presente', i.presente, 'criado_em', i.criado_em,
               'pela_lideranca', not exists (select 1 from public.perfis pf join public.responsaveis r on r.pessoa_id = pf.pessoa_id
                                              where pf.id = i.inscrito_por and r.familia_id = c.familia_id),
               'responsaveis', (select coalesce(jsonb_agg(jsonb_build_object('nome', rp.nome, 'telefone', rp.telefone)
                                         order by r.principal desc, rp.nome), '[]'::jsonb)
                                  from public.responsaveis r join public.pessoas rp on rp.id = r.pessoa_id
                                 where r.familia_id = c.familia_id))
             order by pe.nome), '[]'::jsonb)
        from public.inscricoes_evento i
        left join public.criancas c on c.id = i.crianca_id
        left join public.pessoas pe on pe.id = c.pessoa_id
       where i.evento_id = p_evento),
    'ajudantes', (
      select coalesce(jsonb_agg(jsonb_build_object('voluntaria_id', v.id, 'nome', pe.nome, 'telefone', pe.telefone)
               order by pe.nome), '[]'::jsonb)
        from public.ajudas_evento a join public.voluntarias v on v.id = a.voluntaria_id
        join public.pessoas pe on pe.id = v.pessoa_id
       where a.evento_id = p_evento));
end $$;

-- Quantos eventos publicados vêm por aí (cartão do Início)
create or replace function public.proximos_eventos()
returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', e.id, 'titulo', e.titulo, 'inicio', e.inicio, 'local', e.local,
                                               'aberta', private.inscricao_aberta(e)) order by e.inicio), '[]'::jsonb)
    from public.eventos e
   where e.id in (select x.id from public.eventos x
                   where x.departamento_id = private.dept_kids() and x.publicado and x.cancelado_em is null
                     and coalesce(x.fim, x.inicio) > now() and private.perfil_liberado() and private.tem_algum_papel()
                   order by x.inicio limit 3) $$;

-- ---------------------------------------------------------------------
-- 7. Voluntariado
-- ---------------------------------------------------------------------
-- Preferências e opções (salas e cultos). p_voluntaria nulo = a própria.
create or replace function public.voluntaria_preferencias(p_voluntaria uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.voluntarias; v_lider boolean := private.e_lider(private.dept_kids());
begin
  if p_voluntaria is null then
    select * into v from public.voluntarias where id in (select private.minhas_voluntarias()) limit 1;
    if v.id is null then raise exception 'Sem cadastro de voluntária ativa'; end if;
  else
    select * into v from public.voluntarias where id = p_voluntaria and departamento_id = private.dept_kids();
    if v.id is null or not (v_lider or v.id in (select private.minhas_voluntarias())) then raise exception 'Sem permissão'; end if;
  end if;
  return jsonb_build_object(
    'id', v.id, 'status', v.status, 'funcao', v.funcao, 'email', v.email, 'profissao', v.profissao,
    'salas', to_jsonb(v.salas_preferidas), 'cultos', to_jsonb(v.cultos_preferidos),
    'pode_tudo', v_lider,
    'opcoes_salas', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome) order by s.ordem, s.idade_min), '[]'::jsonb)
                       from public.salas s where s.departamento_id = private.dept_kids() and s.ativa),
    'opcoes_cultos', (select coalesce(jsonb_agg(jsonb_build_object('id', r.id, 'nome', r.nome) order by r.dia_semana, r.horario), '[]'::jsonb)
                        from public.cultos_recorrentes r where r.ativo));
end $$;

-- Grava. Liderança: função, e-mail, profissão, salas e cultos.
-- A própria voluntária (sem ser líder): só salas e cultos.
create or replace function public.salvar_voluntaria(p_voluntaria uuid, p_dados jsonb)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v public.voluntarias; v_lider boolean := private.e_lider(private.dept_kids());
  v_salas uuid[]; v_cultos uuid[]; v_email text; v_prof text; v_funcao text;
begin
  select * into v from public.voluntarias where id = p_voluntaria and departamento_id = private.dept_kids() for update;
  if v.id is null or not (v_lider or v.id in (select private.minhas_voluntarias())) then raise exception 'Sem permissão'; end if;
  begin
    select array_agg(x::uuid order by o) into v_salas
      from jsonb_array_elements_text(coalesce(p_dados->'salas', '[]'::jsonb)) with ordinality t(x, o);
    select array_agg(x::uuid order by o) into v_cultos
      from jsonb_array_elements_text(coalesce(p_dados->'cultos', '[]'::jsonb)) with ordinality t(x, o);
  exception when others then raise exception 'Preferências inválidas';
  end;
  perform private.validar_preferencias(v_salas, v_cultos);

  if not v_lider then
    update public.voluntarias set salas_preferidas = v_salas, cultos_preferidos = v_cultos where id = v.id;
    return;
  end if;

  v_email := nullif(lower(btrim(coalesce(p_dados->>'email', ''))), '');
  v_prof := nullif(btrim(coalesce(p_dados->>'profissao', '')), '');
  v_funcao := coalesce(p_dados->>'funcao', v.funcao::text);
  if v_email is not null and (char_length(v_email) > 120 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'E-mail inválido'; end if;
  if char_length(coalesce(v_prof, '')) > 80 then raise exception 'A profissão pode ter até 80 letras'; end if;
  if v_funcao not in ('professora', 'auxiliar') then raise exception 'Função inválida'; end if;
  update public.voluntarias
     set salas_preferidas = v_salas, cultos_preferidos = v_cultos, email = v_email, profissao = v_prof,
         funcao = v_funcao::public.funcao_voluntaria
   where id = v.id;
end $$;

-- Desativa / reativa (liderança). Desativar: sai das vagas dos meses em
-- rascunho e das ajudas em eventos futuros; perde os papéis de voluntária e
-- recepção (o login continua). Escalas publicadas não mudam.
-- Reativar: devolve o papel de voluntária (o gatilho devolve a recepção).
create or replace function public.definir_status_voluntaria(p_voluntaria uuid, p_ativa boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v public.voluntarias; n_vagas int := 0; n_ajudas int := 0;
begin
  if not private.pode_aprovar_voluntaria() then raise exception 'Sem permissão'; end if;
  if p_ativa is null then raise exception 'Informe ativar ou desativar'; end if;
  select * into v from public.voluntarias where id = p_voluntaria and departamento_id = private.dept_kids() for update;
  if v.id is null then raise exception 'Voluntária não encontrada'; end if;
  if v.pessoa_id = private.minha_pessoa() and not p_ativa then raise exception 'Você não pode desativar o próprio cadastro'; end if;

  if p_ativa then
    if v.status = 'ativa' then return jsonb_build_object('vagas', 0, 'ajudas', 0); end if;
    update public.voluntarias set status = 'ativa' where id = v.id;
    insert into public.papeis_usuario (perfil_id, departamento_id, papel, concedido_por)
    select pf.id, v.departamento_id, 'voluntaria', auth.uid()
      from public.perfis pf where pf.pessoa_id = v.pessoa_id
    on conflict do nothing;
    return jsonb_build_object('vagas', 0, 'ajudas', 0);
  end if;

  if v.status = 'inativa' then return jsonb_build_object('vagas', 0, 'ajudas', 0); end if;
  update public.voluntarias set status = 'inativa' where id = v.id;
  update public.escala_itens ei
     set voluntaria_id = null, cobrindo_lider = false, resposta = 'pendente', respondido_em = null
    from public.escalas e
   where e.id = ei.escala_id and e.status = 'rascunho' and ei.voluntaria_id = v.id;
  get diagnostics n_vagas = row_count;
  delete from public.ajudas_evento a using public.eventos e
   where e.id = a.evento_id and a.voluntaria_id = v.id and e.inicio > now();
  get diagnostics n_ajudas = row_count;
  delete from public.papeis_usuario
   where perfil_id in (select pf.id from public.perfis pf where pf.pessoa_id = v.pessoa_id)
     and departamento_id = v.departamento_id and papel in ('voluntaria', 'recepcao');
  return jsonb_build_object('vagas', n_vagas, 'ajudas', n_ajudas);
end $$;

-- ---------------------------------------------------------------------
-- Auditoria (quem, o quê, quando – sem copiar o conteúdo)
-- ---------------------------------------------------------------------
drop trigger if exists eventos_auditoria on public.eventos;
create trigger eventos_auditoria after insert or update or delete on public.eventos
  for each row execute function private.auditar();
drop trigger if exists inscricoes_evento_auditoria on public.inscricoes_evento;
create trigger inscricoes_evento_auditoria after insert or update or delete on public.inscricoes_evento
  for each row execute function private.auditar();
drop trigger if exists ajudas_evento_auditoria on public.ajudas_evento;
create trigger ajudas_evento_auditoria after insert or update or delete on public.ajudas_evento
  for each row execute function private.auditar();

-- ---------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------
revoke all on function private.dia_evento(timestamptz) from public, anon, authenticated;
revoke all on function private.idade_em(date, date) from public, anon, authenticated;
revoke all on function private.quando_evento(timestamptz) from public, anon, authenticated;
revoke all on function private.inscricao_aberta(public.eventos) from public, anon, authenticated;
revoke all on function private.responsaveis_inscritos(uuid) from public, anon, authenticated;
revoke all on function private.ajudantes_evento(uuid) from public, anon, authenticated;
revoke all on function private.validar_preferencias(uuid[], uuid[]) from public, anon, authenticated;

do $p$
declare f text;
begin
  foreach f in array array[
    'public.salvar_evento(uuid, jsonb)', 'public.publicar_evento(uuid, text)', 'public.cancelar_evento(uuid)',
    'public.apagar_evento(uuid)', 'public.avisar_inscritos(uuid, text)',
    'public.inscrever_crianca(uuid, uuid, boolean, text)', 'public.cancelar_inscricao(uuid)',
    'public.marcar_presenca_evento(uuid, boolean)', 'public.ajudar_evento(uuid, boolean)',
    'public.eventos_lista()', 'public.evento_inscritos(uuid)', 'public.proximos_eventos()',
    'public.voluntaria_preferencias(uuid)', 'public.salvar_voluntaria(uuid, jsonb)',
    'public.definir_status_voluntaria(uuid, boolean)']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $p$;
