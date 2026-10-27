-- =====================================================================
-- Fase 10 · Etapa 5A – Gestão de logins
-- Leituras para a tela #/logins (liderança do Fonte Kids, pastores, admin)
-- e fechamento dos pedidos de nova senha.
--   • listar_pedidos_redefinicao()         – pedidos pendentes
--   • situacao_logins()                    – situação de login de cada pessoa
--   • encerrar_pedido_redefinicao(pedido)  – encerra sem redefinir
--   • marcar_pedidos_atendidos(perfil,por) – só service_role (Edge Function
--                                            gerenciar-login, ao redefinir)
-- Telefone sai SEMPRE mascarado: (DD) •••••-1234.
-- =====================================================================

-- Novo status "encerrado" (pedido fechado sem redefinir).
alter table public.pedidos_redefinicao_senha
  drop constraint if exists pedidos_redefinicao_senha_status_check,
  drop constraint if exists pedidos_redefinicao_senha_check;
alter table public.pedidos_redefinicao_senha
  add constraint pedidos_redefinicao_senha_status_check
    check (status in ('pendente', 'atendido', 'encerrado')),
  add constraint pedidos_redefinicao_senha_check
    check ((status = 'pendente') = (atendido_em is null));

-- Quem pode usar a gestão de logins
create or replace function private.gere_logins_kids()
returns boolean language sql stable security definer set search_path = '' as $$
  select private.sessao_liberada() and (
    private.e_pastor_ou_admin()
    or private.e_lider((select d.id from public.departamentos d where d.slug = 'kids' limit 1)))
$$;

create or replace function private.mascarar_telefone(t text)
returns text language sql immutable set search_path = '' as $$
  select case when t ~ '^55[0-9]{10,11}$'
              then '(' || substr(t, 3, 2) || ') •••••-' || right(t, 4)
              else null end
$$;

-- ---------- Pedidos pendentes ----------
create or replace function public.listar_pedidos_redefinicao()
returns table (id uuid, perfil_id uuid, pessoa_id uuid, nome text,
               telefone_mascarado text, criado_em timestamptz, pode_redefinir boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.gere_logins_kids() then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  return query
    select pr.id, pr.perfil_id, pf.pessoa_id, coalesce(pe.nome, 'Sem nome'),
           private.mascarar_telefone(pf.telefone), pr.criado_em,
           public.posso_redefinir_senha(pr.perfil_id)
    from public.pedidos_redefinicao_senha pr
    join public.perfis pf on pf.id = pr.perfil_id
    left join public.pessoas pe on pe.id = pf.pessoa_id
    where pr.status = 'pendente'
    order by pr.criado_em;
end $$;

-- ---------- Situação dos logins ----------
-- situacao: ativo | primeiro_acesso | inativo (com login)
--           sem_login | sem_telefone | telefone_invalido | telefone_em_uso
--           | telefone_compartilhado (sem login)
create or replace function public.situacao_logins()
returns table (pessoa_id uuid, nome text, telefone_mascarado text,
               e_voluntaria boolean, e_responsavel boolean, situacao text,
               perfil_id uuid, pode_redefinir boolean)
language plpgsql stable security definer set search_path = '' as $$
declare v_kids uuid;
begin
  if not private.gere_logins_kids() then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  select d.id into v_kids from public.departamentos d where d.slug = 'kids' limit 1;
  return query
    with c as (select * from public.candidatos_login(v_kids)),
    base as (
      select c.pessoa_id, c.telefone_login as tel, c.e_voluntaria, c.e_responsavel, c.situacao as sit
      from c
      union all
      select pf.pessoa_id, pf.telefone, false, false, 'ja_tem_login'
      from public.perfis pf
      where pf.pessoa_id is not null
        and not exists (select 1 from c where c.pessoa_id = pf.pessoa_id)
    )
    select b.pessoa_id, coalesce(pe.nome, 'Sem nome'),
           private.mascarar_telefone(coalesce(pf.telefone, b.tel)),
           b.e_voluntaria, b.e_responsavel,
           case when pf.id is not null then
                  case when not pf.ativo then 'inativo'
                       when pf.troca_senha_obrigatoria then 'primeiro_acesso'
                       else 'ativo' end
                when b.sit = 'criar' then 'sem_login'
                else b.sit end,
           pf.id,
           case when pf.id is null then false else public.posso_redefinir_senha(pf.id) end
    from base b
    left join public.pessoas pe on pe.id = b.pessoa_id
    left join public.perfis pf on pf.pessoa_id = b.pessoa_id
    order by pe.nome_busca;
end $$;

-- ---------- Encerrar pedido sem redefinir ----------
create or replace function public.encerrar_pedido_redefinicao(p_pedido uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if not private.gere_logins_kids() then
    raise exception 'sem_permissao' using errcode = '42501';
  end if;
  update public.pedidos_redefinicao_senha
     set status = 'encerrado', atendido_por = (select auth.uid()), atendido_em = now()
   where id = p_pedido and status = 'pendente';
  return found;
end $$;

-- ---------- Marcar atendidos (chamada pela Edge Function ao redefinir) ----------
create or replace function public.marcar_pedidos_atendidos(p_perfil uuid, p_por uuid)
returns integer language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  update public.pedidos_redefinicao_senha
     set status = 'atendido', atendido_por = p_por, atendido_em = now()
   where perfil_id = p_perfil and status = 'pendente';
  get diagnostics n = row_count;
  return n;
end $$;

-- ---------- Permissões ----------
revoke all on function private.gere_logins_kids() from public, anon;
revoke all on function public.listar_pedidos_redefinicao() from public, anon;
revoke all on function public.situacao_logins() from public, anon;
revoke all on function public.encerrar_pedido_redefinicao(uuid) from public, anon;
revoke all on function public.marcar_pedidos_atendidos(uuid, uuid) from public, anon, authenticated;
grant execute on function public.listar_pedidos_redefinicao() to authenticated;
grant execute on function public.situacao_logins() to authenticated;
grant execute on function public.encerrar_pedido_redefinicao(uuid) to authenticated;
grant execute on function public.marcar_pedidos_atendidos(uuid, uuid) to service_role;
