-- =====================================================================
-- Fase 7 · Comunicação (28/10/2026)
--   1. Avisos da liderança com escolha de público (enviar_aviso):
--      todos · equipe · só líderes · só responsáveis. Fim da inserção
--      direta em "notificacoes" (só as funções do banco avisam).
--   2. Push no celular: inscrição por aparelho (salvar_push/remover_push);
--      toda notificação nova de quem tem aparelho inscrito chama a Edge
--      Function "enviar-push" (pg_net). Na tela bloqueada, as automáticas
--      mostram só o título + "Abra o app para ver." (sem nomes); avisos da
--      liderança e enquetes mostram o texto.
--   3. Enquetes: criar, votar (muda o voto até encerrar), encerrar, apagar.
--      Liderança vê totais e quem votou; quem vota vê só os totais depois
--      de votar (ou quando a enquete encerra).
-- Escrita só por funções security definer; RLS em tudo; auditoria.
-- Toda alteração com WHERE (a API usa pg_safeupdate).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Avisos da liderança
-- ---------------------------------------------------------------------
create table if not exists public.avisos (
  id              uuid primary key default gen_random_uuid(),
  departamento_id uuid not null references public.departamentos(id) on delete cascade,
  publico         text not null check (publico in ('todos', 'equipe', 'lideres', 'responsaveis')),
  titulo          text not null check (char_length(titulo) between 3 and 80),
  texto           text not null check (char_length(texto) between 1 and 1000),
  destinatarios   integer not null default 0,
  criado_por      uuid references public.perfis(id) on delete set null default auth.uid(),
  criado_em       timestamptz not null default now()
);
create index if not exists avisos_departamento_idx on public.avisos (departamento_id, criado_em desc);
create index if not exists avisos_criado_por_idx on public.avisos (criado_por);
alter table public.avisos enable row level security;
drop policy if exists avisos_ler on public.avisos;
create policy avisos_ler on public.avisos for select to authenticated using (private.e_lider(departamento_id));
revoke all on public.avisos from anon;
revoke insert, update, delete on public.avisos from authenticated;

alter table public.notificacoes
  add column if not exists aviso_id uuid references public.avisos(id) on delete cascade,
  add column if not exists push_enviado_em timestamptz;
create index if not exists notificacoes_aviso_idx on public.notificacoes (aviso_id) where aviso_id is not null;

alter table public.enquetes add column if not exists destinatarios integer not null default 0;

-- Fim da inserção direta: só as funções do banco criam notificações.
drop policy if exists notif_criar on public.notificacoes;
revoke insert on public.notificacoes from authenticated;

-- Quem recebe, por público (logins ativos do Fonte Kids; quem envia fica de fora)
--   lideres      = líderes do Fonte Kids, pastores e admin
--   equipe       = líderes + recepção + voluntárias (e pastores/admin)
--   responsaveis = responsáveis de famílias do Fonte Kids
--   todos        = equipe + responsáveis
create or replace function private.destinatarios(p_publico text)
returns setof uuid language sql stable security definer set search_path = '' as $$
  select distinct p.id
    from public.perfis p
   where p.ativo and p.id is distinct from auth.uid()
     and (
       (p_publico in ('lideres', 'equipe', 'todos') and exists (
          select 1 from public.papeis_usuario pu
           where pu.perfil_id = p.id
             and (pu.papel in ('admin', 'pastor')
                  or (pu.papel = 'lider' and pu.departamento_id = private.dept_kids()))))
       or (p_publico in ('equipe', 'todos') and exists (
          select 1 from public.papeis_usuario pu
           where pu.perfil_id = p.id and pu.departamento_id = private.dept_kids()
             and pu.papel in ('recepcao', 'voluntaria')))
       or (p_publico in ('responsaveis', 'todos') and p.pessoa_id is not null and exists (
          select 1 from public.responsaveis r join public.familias f on f.id = r.familia_id
           where r.pessoa_id = p.pessoa_id and f.departamento_id = private.dept_kids()))
     ) $$;

create or replace function public.enviar_aviso(p_publico text, p_titulo text, p_texto text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids(); v_titulo text := btrim(coalesce(p_titulo, ''));
        v_texto text := btrim(coalesce(p_texto, '')); v_id uuid; n int;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  if p_publico is null or p_publico not in ('todos', 'equipe', 'lideres', 'responsaveis') then
    raise exception 'Escolha para quem é o aviso'; end if;
  if char_length(v_titulo) < 3 or char_length(v_titulo) > 80 then raise exception 'O título precisa ter de 3 a 80 letras'; end if;
  if char_length(v_texto) < 1 or char_length(v_texto) > 1000 then raise exception 'O texto precisa ter de 1 a 1000 letras'; end if;
  if (select count(*) from public.avisos where departamento_id = v_dept and criado_em > now() - interval '24 hours') >= 30 then
    raise exception 'Limite de 30 avisos em 24 horas'; end if;

  insert into public.avisos (departamento_id, publico, titulo, texto)
  values (v_dept, p_publico, v_titulo, v_texto) returning id into v_id;

  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por, aviso_id)
  select d, v_titulo, v_texto, null, 'aviso', auth.uid(), v_id from private.destinatarios(p_publico) d;
  get diagnostics n = row_count;

  update public.avisos set destinatarios = n where id = v_id;
  return jsonb_build_object('id', v_id, 'destinatarios', n);
end $$;

-- Avisos enviados (liderança): quantas pessoas receberam e quantas já leram
create or replace function public.avisos_enviados(p_limite integer default 30)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids();
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  return (
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', a.id, 'publico', a.publico, 'titulo', a.titulo, 'texto', a.texto, 'criado_em', a.criado_em,
             'autor', coalesce(pe.nome, 'Liderança'), 'destinatarios', a.destinatarios,
             'lidas', (select count(*) from public.notificacoes n where n.aviso_id = a.id and n.lida_em is not null))
           order by a.criado_em desc), '[]'::jsonb)
      from (select * from public.avisos where departamento_id = v_dept
             order by criado_em desc limit least(greatest(coalesce(p_limite, 30), 1), 100)) a
      left join public.perfis pf on pf.id = a.criado_por
      left join public.pessoas pe on pe.id = pf.pessoa_id);
end $$;

-- ---------------------------------------------------------------------
-- 2. Push: inscrição por aparelho
-- ---------------------------------------------------------------------
-- Gravação só pelas funções (o app não grava direto na tabela)
drop policy if exists push_criar on public.push_subscriptions;
drop policy if exists push_editar on public.push_subscriptions;
drop policy if exists push_apagar on public.push_subscriptions;
revoke insert, update, delete on public.push_subscriptions from authenticated;

-- Liga o push neste aparelho para o login atual. O mesmo aparelho (endpoint)
-- usado por outro login passa para quem está conectado agora.
-- Máximo de 10 aparelhos por login (sai o mais antigo).
create or replace function public.salvar_push(p_endpoint text, p_p256dh text, p_auth text, p_aparelho text default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (select 1 from public.perfis where id = v_uid and ativo) then
    raise exception 'Sem permissão'; end if;
  if p_endpoint is null or p_endpoint !~ '^https://[^\s]+$' or char_length(p_endpoint) > 1000 then
    raise exception 'Inscrição inválida'; end if;
  if p_p256dh is null or p_p256dh !~ '^[A-Za-z0-9_-]{80,100}$' then raise exception 'Inscrição inválida'; end if;
  if p_auth is null or p_auth !~ '^[A-Za-z0-9_-]{16,30}$' then raise exception 'Inscrição inválida'; end if;

  delete from public.push_subscriptions where endpoint = p_endpoint;
  insert into public.push_subscriptions (perfil_id, endpoint, p256dh, auth, user_agent)
  values (v_uid, p_endpoint, p_p256dh, p_auth, left(nullif(btrim(coalesce(p_aparelho, '')), ''), 60));

  delete from public.push_subscriptions
   where perfil_id = v_uid
     and id not in (select id from public.push_subscriptions where perfil_id = v_uid order by criado_em desc limit 10);
end $$;

-- Desliga o push deste aparelho (também chamado ao sair)
create or replace function public.remover_push(p_endpoint text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'Sem permissão'; end if;
  delete from public.push_subscriptions where endpoint = p_endpoint and perfil_id = auth.uid();
end $$;

-- Endereço das Edge Functions deste projeto (público, igual ao app/config.js)
create or replace function private.url_funcao(p_nome text)
returns text language sql immutable set search_path = '' as $$
  select 'https://pnujayydfuimfhcgrxjo.supabase.co/functions/v1/' || p_nome $$;

-- Notificação nova → chama a Edge Function "enviar-push" (uma chamada por
-- comando, com todos os ids de quem tem aparelho inscrito). Se a chamada
-- falhar, a notificação continua no app normalmente.
create or replace function private.disparar_push()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_ids uuid[];
begin
  select array_agg(n.id) into v_ids from novas n
   where exists (select 1 from public.push_subscriptions s where s.perfil_id = n.destinatario_id);
  if v_ids is null then return null; end if;
  begin
    perform net.http_post(
      url := private.url_funcao('enviar-push'),
      body := jsonb_build_object('ids', to_jsonb(v_ids)),
      headers := '{"Content-Type": "application/json"}'::jsonb,
      timeout_milliseconds := 10000);
  exception when others then
    null; -- o push nunca impede o aviso dentro do app
  end;
  return null;
end $$;

drop trigger if exists notificacoes_push on public.notificacoes;
create trigger notificacoes_push after insert on public.notificacoes
  referencing new table as novas
  for each statement execute function private.disparar_push();

-- Usada SÓ pela Edge Function (chave de serviço): marca as notificações como
-- enviadas (cada uma vai uma única vez, e só nos primeiros 15 minutos) e
-- devolve o que mostrar + os aparelhos de cada destinatário.
create or replace function public.push_preparar(p_ids uuid[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb;
begin
  with marcadas as (
    update public.notificacoes n set push_enviado_em = now()
     where n.id = any (p_ids) and n.push_enviado_em is null and n.criado_em > now() - interval '15 minutes'
    returning n.id, n.destinatario_id, n.titulo, n.corpo, n.tipo, n.link)
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id,
           'titulo', left(m.titulo, 80),
           'corpo', case when m.tipo in ('aviso', 'enquete') then left(coalesce(m.corpo, ''), 300)
                         else 'Abra o app para ver.' end,
           'link', m.link,
           'inscricoes', i.lista)), '[]'::jsonb)
    into v
    from marcadas m
    join lateral (select jsonb_agg(jsonb_build_object('endpoint', s.endpoint, 'p256dh', s.p256dh, 'auth', s.auth)) lista
                    from public.push_subscriptions s where s.perfil_id = m.destinatario_id) i on i.lista is not null;
  return v;
end $$;

-- Usada SÓ pela Edge Function: apaga aparelhos que o serviço de push
-- recusou de vez (app desinstalado, permissão retirada).
create or replace function public.push_remover_inscricoes(p_endpoints text[])
returns integer language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  delete from public.push_subscriptions where endpoint = any (p_endpoints);
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 3. Enquetes
-- ---------------------------------------------------------------------
-- Gravação só pelas funções
drop policy if exists enquetes_criar on public.enquetes;
drop policy if exists enquetes_editar on public.enquetes;
drop policy if exists enquetes_apagar on public.enquetes;
drop policy if exists opcoes_criar on public.enquete_opcoes;
drop policy if exists opcoes_editar on public.enquete_opcoes;
drop policy if exists opcoes_apagar on public.enquete_opcoes;
drop policy if exists votos_criar on public.votos;
drop policy if exists votos_apagar on public.votos;
revoke insert, update, delete on public.enquetes, public.enquete_opcoes, public.votos from authenticated;

-- A pessoa faz parte do público da enquete? (pode votar)
create or replace function private.no_publico_enquete(p_publico public.publico_alvo)
returns boolean language sql stable security definer set search_path = '' as $$
  select (p_publico in ('equipe', 'todos') and private.e_equipe(private.dept_kids()))
      or (p_publico in ('familias', 'todos') and private.perfil_liberado() and exists (
            select 1 from public.familias f
             where f.id in (select private.minhas_familias()) and f.departamento_id = private.dept_kids())) $$;

-- Cria e já publica; avisa (e manda push para) o público escolhido.
-- p_ate: último dia para responder (opcional; encerra no fim desse dia).
create or replace function public.criar_enquete(p_pergunta text, p_publico public.publico_alvo, p_opcoes text[],
                                                p_multipla boolean default false, p_ate date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids(); v_perg text := btrim(coalesce(p_pergunta, ''));
        v_ops text[]; v_id uuid; v_fim timestamptz; n int; k int := 0; o text;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  if p_publico is null then raise exception 'Escolha para quem é a enquete'; end if;
  if char_length(v_perg) < 3 or char_length(v_perg) > 200 then raise exception 'A pergunta precisa ter de 3 a 200 letras'; end if;
  select array_agg(x order by ord) into v_ops
    from (select distinct on (lower(btrim(t))) btrim(t) x, ord
            from unnest(coalesce(p_opcoes, '{}')) with ordinality u(t, ord)
           where btrim(coalesce(t, '')) <> '' order by lower(btrim(t)), ord) z;
  if coalesce(cardinality(v_ops), 0) < 2 or cardinality(v_ops) > 10 then raise exception 'Informe de 2 a 10 opções diferentes'; end if;
  if exists (select 1 from unnest(v_ops) x where char_length(x) > 80) then raise exception 'Cada opção pode ter até 80 letras'; end if;
  if p_ate is not null then
    if p_ate < private.hoje() or p_ate > private.hoje() + 90 then raise exception 'O prazo precisa ser de hoje até 90 dias'; end if;
    v_fim := ((p_ate + 1)::timestamp at time zone 'America/Sao_Paulo');
  end if;
  if (select count(*) from public.enquetes where departamento_id = v_dept and criado_em > now() - interval '24 hours') >= 10 then
    raise exception 'Limite de 10 enquetes em 24 horas'; end if;

  insert into public.enquetes (departamento_id, pergunta, publico, multipla_escolha, publicada, encerra_em)
  values (v_dept, v_perg, p_publico, coalesce(p_multipla, false), true, v_fim) returning id into v_id;
  foreach o in array v_ops loop
    k := k + 1;
    insert into public.enquete_opcoes (enquete_id, texto, ordem) values (v_id, o, k);
  end loop;

  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por)
  select d, 'Nova enquete',
         v_perg || case when p_ate is not null then ' Responda até ' || to_char(p_ate, 'DD/MM') || '.' else '' end,
         '#/enquetes', 'enquete', auth.uid()
    from private.destinatarios(case p_publico when 'equipe' then 'equipe' when 'familias' then 'responsaveis' else 'todos' end) d;
  get diagnostics n = row_count;

  update public.enquetes set destinatarios = n where id = v_id;
  return jsonb_build_object('id', v_id, 'destinatarios', n);
end $$;

create or replace function public.encerrar_enquete(p_enquete uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.e_lider(private.dept_enquete(p_enquete)) then raise exception 'Sem permissão'; end if;
  update public.enquetes set encerra_em = now()
   where id = p_enquete and (encerra_em is null or encerra_em > now());
end $$;

create or replace function public.apagar_enquete(p_enquete uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not private.e_lider(private.dept_enquete(p_enquete)) then raise exception 'Sem permissão'; end if;
  delete from public.enquetes where id = p_enquete;
end $$;

-- Grava o voto (substitui o anterior). Lista vazia = tirar o voto.
create or replace function public.votar_enquete(p_enquete uuid, p_opcoes uuid[])
returns void language plpgsql security definer set search_path = '' as $$
declare q public.enquetes; v_ops uuid[] := array(select distinct x from unnest(coalesce(p_opcoes, '{}')) x where x is not null);
begin
  select * into q from public.enquetes where id = p_enquete;
  if q.id is null or not q.publicada or not private.no_publico_enquete(q.publico) then raise exception 'Sem permissão'; end if;
  if q.encerra_em is not null and q.encerra_em <= now() then raise exception 'Esta enquete já foi encerrada'; end if;
  if not q.multipla_escolha and cardinality(v_ops) > 1 then raise exception 'Escolha só uma opção'; end if;
  if exists (select 1 from unnest(v_ops) x
              where not exists (select 1 from public.enquete_opcoes o where o.id = x and o.enquete_id = p_enquete)) then
    raise exception 'Opção inválida'; end if;

  delete from public.votos where enquete_id = p_enquete and perfil_id = auth.uid();
  insert into public.votos (enquete_id, opcao_id, perfil_id)
  select p_enquete, x, auth.uid() from unnest(v_ops) x;
end $$;

-- Enquetes que a pessoa pode ver (liderança: todas do Fonte Kids).
create or replace function public.enquetes_lista()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids(); v_lider boolean; v_uid uuid := auth.uid();
begin
  v_lider := private.e_lider(v_dept);
  if v_uid is null or not (v_lider or private.e_equipe(v_dept) or exists (select private.minhas_familias())) then
    raise exception 'Sem permissão'; end if;
  return (
    select coalesce(jsonb_agg(item order by aberta desc, criado_em desc), '[]'::jsonb) from (
      select q.criado_em, (q.encerra_em is null or q.encerra_em > now()) aberta,
        jsonb_build_object(
          'id', q.id, 'pergunta', q.pergunta, 'publico', q.publico, 'multipla', q.multipla_escolha,
          'encerra_em', q.encerra_em, 'criado_em', q.criado_em,
          'aberta', (q.encerra_em is null or q.encerra_em > now()),
          'pode_votar', private.no_publico_enquete(q.publico) and (q.encerra_em is null or q.encerra_em > now()),
          'meus_votos', (select coalesce(jsonb_agg(vt.opcao_id), '[]'::jsonb) from public.votos vt
                          where vt.enquete_id = q.id and vt.perfil_id = v_uid),
          've_totais', ver.totais,
          'votantes', case when ver.totais then (select count(distinct vt.perfil_id) from public.votos vt where vt.enquete_id = q.id) end,
          'destinatarios', case when v_lider then q.destinatarios end,
          'lider', v_lider,
          'opcoes', (select coalesce(jsonb_agg(jsonb_build_object(
                       'id', o.id, 'texto', o.texto,
                       'votos', case when ver.totais then (select count(*) from public.votos vt where vt.opcao_id = o.id) end)
                     order by o.ordem), '[]'::jsonb)
                     from public.enquete_opcoes o where o.enquete_id = q.id),
          'quem_votou', case when v_lider then (
             select coalesce(jsonb_agg(jsonb_build_object('nome', coalesce(pe.nome, 'Sem nome'), 'opcoes', x.textos)
                      order by pe.nome), '[]'::jsonb)
               from (select vt.perfil_id, jsonb_agg(o.texto order by o.ordem) textos
                       from public.votos vt join public.enquete_opcoes o on o.id = vt.opcao_id
                      where vt.enquete_id = q.id group by vt.perfil_id) x
               left join public.perfis pf on pf.id = x.perfil_id
               left join public.pessoas pe on pe.id = pf.pessoa_id) end
        ) item
      from public.enquetes q
      cross join lateral (select v_lider
                             or (q.encerra_em is not null and q.encerra_em <= now())
                             or exists (select 1 from public.votos vt where vt.enquete_id = q.id and vt.perfil_id = v_uid) totais) ver
      where q.departamento_id = v_dept and q.publicada
        and (v_lider or private.no_publico_enquete(q.publico))
        and q.criado_em > now() - interval '180 days'
      order by q.criado_em desc limit 50) z);
end $$;

-- Quantas enquetes abertas a pessoa ainda não respondeu (cartão no Início/Avisos)
create or replace function public.enquetes_pendentes()
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::int from public.enquetes q
   where q.departamento_id = private.dept_kids() and q.publicada
     and (q.encerra_em is null or q.encerra_em > now())
     and private.no_publico_enquete(q.publico)
     and not exists (select 1 from public.votos vt where vt.enquete_id = q.id and vt.perfil_id = auth.uid()) $$;

-- ---------------------------------------------------------------------
-- Auditoria (quem, o quê, quando – sem copiar o conteúdo)
-- ---------------------------------------------------------------------
drop trigger if exists avisos_auditoria on public.avisos;
create trigger avisos_auditoria after insert or update or delete on public.avisos
  for each row execute function private.auditar();
drop trigger if exists enquetes_auditoria on public.enquetes;
create trigger enquetes_auditoria after insert or update or delete on public.enquetes
  for each row execute function private.auditar();
drop trigger if exists votos_auditoria on public.votos;
create trigger votos_auditoria after insert or update or delete on public.votos
  for each row execute function private.auditar();

-- ---------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------
revoke all on function private.destinatarios(text) from public, anon, authenticated;
revoke all on function private.url_funcao(text) from public, anon, authenticated;
revoke all on function private.disparar_push() from public, anon, authenticated;
revoke all on function private.no_publico_enquete(public.publico_alvo) from public, anon, authenticated;

revoke all on function public.enviar_aviso(text, text, text) from public, anon;
grant execute on function public.enviar_aviso(text, text, text) to authenticated;
revoke all on function public.avisos_enviados(integer) from public, anon;
grant execute on function public.avisos_enviados(integer) to authenticated;
revoke all on function public.salvar_push(text, text, text, text) from public, anon;
grant execute on function public.salvar_push(text, text, text, text) to authenticated;
revoke all on function public.remover_push(text) from public, anon;
grant execute on function public.remover_push(text) to authenticated;
revoke all on function public.criar_enquete(text, public.publico_alvo, text[], boolean, date) from public, anon;
grant execute on function public.criar_enquete(text, public.publico_alvo, text[], boolean, date) to authenticated;
revoke all on function public.encerrar_enquete(uuid) from public, anon;
grant execute on function public.encerrar_enquete(uuid) to authenticated;
revoke all on function public.apagar_enquete(uuid) from public, anon;
grant execute on function public.apagar_enquete(uuid) to authenticated;
revoke all on function public.votar_enquete(uuid, uuid[]) from public, anon;
grant execute on function public.votar_enquete(uuid, uuid[]) to authenticated;
revoke all on function public.enquetes_lista() from public, anon;
grant execute on function public.enquetes_lista() to authenticated;
revoke all on function public.enquetes_pendentes() from public, anon;
grant execute on function public.enquetes_pendentes() to authenticated;

-- Só a Edge Function (chave de serviço)
revoke all on function public.push_preparar(uuid[]) from public, anon, authenticated;
grant execute on function public.push_preparar(uuid[]) to service_role;
revoke all on function public.push_remover_inscricoes(text[]) from public, anon, authenticated;
grant execute on function public.push_remover_inscricoes(text[]) to service_role;
