-- =====================================================================
-- Fase 10 · Etapa 2 – Pedido de nova senha ("Esqueci minha senha")
-- Plano, seção 4.2:
--   • a pessoa pede pelo app (telefone + captcha) → Edge Function pedir-redefinicao;
--   • a função NUNCA redefine a senha: só registra o pedido e avisa no sino
--     os líderes do Fonte Kids, admin e pastores;
--   • máx. 1 pedido por login a cada 24 h;
--   • telefone digitado e IP NÃO são guardados.
-- Gravação só pelo servidor (service_role). Pelo app, só leitura para a liderança.
-- =====================================================================

create table if not exists public.pedidos_redefinicao_senha (
  id            uuid primary key default gen_random_uuid(),
  perfil_id     uuid not null references public.perfis(id) on delete cascade,
  pessoa_id     uuid references public.pessoas(id) on delete set null,
  status        text not null default 'pendente' check (status in ('pendente', 'atendido')),
  criado_em     timestamptz not null default now(),
  atendido_por  uuid references public.perfis(id) on delete set null,
  atendido_em   timestamptz,
  check ((status = 'atendido') = (atendido_em is not null))
);

comment on table public.pedidos_redefinicao_senha is
  'Pedidos de nova senha feitos pelo app. Só registro: quem redefine é a liderança (gerenciar-login).';

create index if not exists pedidos_redef_perfil_idx
  on public.pedidos_redefinicao_senha (perfil_id, criado_em desc);
create index if not exists pedidos_redef_pendentes_idx
  on public.pedidos_redefinicao_senha (criado_em desc) where status = 'pendente';

alter table public.pedidos_redefinicao_senha enable row level security;

-- Quem pode ver: pastores/admin (nível igreja) e líderes do Fonte Kids.
drop policy if exists pedidos_redef_ler on public.pedidos_redefinicao_senha;
create policy pedidos_redef_ler on public.pedidos_redefinicao_senha
  for select to authenticated
  using (
    private.e_pastor_ou_admin()
    or private.e_lider((select d.id from public.departamentos d where d.slug = 'kids' limit 1))
  );
-- Sem políticas de inserir/alterar/apagar: pelo app ninguém grava.

revoke all on public.pedidos_redefinicao_senha from anon;
revoke insert, update, delete on public.pedidos_redefinicao_senha from authenticated;
grant select on public.pedidos_redefinicao_senha to authenticated;

-- Auditoria (mesmo gatilho das outras tabelas)
drop trigger if exists auditoria on public.pedidos_redefinicao_senha;
create trigger auditoria after insert or update or delete on public.pedidos_redefinicao_senha
  for each row execute function private.auditar();

-- ---------------------------------------------------------------------
-- registrar_pedido_redefinicao(perfil): chamada SÓ pela Edge Function
-- (service_role). Respeita o limite de 24 h e cria os avisos no sino.
-- Retorna true se criou o pedido; false se já havia um nas últimas 24 h
-- ou se o login não está ativo. A Edge Function responde igual nos dois casos.
-- ---------------------------------------------------------------------
create or replace function public.registrar_pedido_redefinicao(p_perfil uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_perfil   public.perfis%rowtype;
  v_nome     text;
  v_pedido   uuid;
  v_kids     uuid;
begin
  select * into v_perfil from public.perfis where id = p_perfil;
  if not found or not v_perfil.ativo then
    return false;
  end if;

  -- trava simples contra dois pedidos simultâneos do mesmo login
  perform pg_advisory_xact_lock(hashtextextended('pedido_redef:' || p_perfil::text, 0));

  if exists (select 1 from public.pedidos_redefinicao_senha
             where perfil_id = p_perfil and criado_em > now() - interval '24 hours') then
    return false;
  end if;

  insert into public.pedidos_redefinicao_senha (perfil_id, pessoa_id)
  values (p_perfil, v_perfil.pessoa_id)
  returning id into v_pedido;

  select nome into v_nome from public.pessoas where id = v_perfil.pessoa_id;
  select id into v_kids from public.departamentos where slug = 'kids' limit 1;

  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo)
  select distinct pu.perfil_id,
         'Pedido de nova senha',
         coalesce(v_nome, 'Uma pessoa') || ' pediu uma nova senha. '
           || 'Confirme com a pessoa antes de redefinir e peça que entre logo em seguida.',
         '#/logins',
         'pedido_senha'
  from public.papeis_usuario pu
  join public.perfis p on p.id = pu.perfil_id and p.ativo
  where pu.perfil_id <> p_perfil
    and (pu.papel in ('admin', 'pastor')
         or (pu.papel = 'lider' and pu.departamento_id = v_kids));

  return true;
end;
$$;

revoke all on function public.registrar_pedido_redefinicao(uuid) from public, anon, authenticated;
grant execute on function public.registrar_pedido_redefinicao(uuid) to service_role;
