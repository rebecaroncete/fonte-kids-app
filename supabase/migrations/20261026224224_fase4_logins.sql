-- =====================================================================
-- Fase 4 · Etapa 3 – Logins
-- Decisões (Rebeca, 26/10/2026):
--   • Login = telefone (o app converte para um e-mail técnico que não
--     recebe e-mail). Senha inicial: voluntária = data de nascimento
--     (DDMMAAAA); demais = telefone de login. Troca obrigatória no 1º acesso.
--   • Voluntárias menores de idade também recebem login.
--   • Telefone compartilhado: o login fica com a voluntária; entre dois
--     responsáveis, com o responsável principal (os outros ficam sem login
--     até informar um número próprio).
-- O que esta migração faz:
--   1. Quem ainda não trocou a senha inicial (ou não tem papel) NÃO vê
--      nenhum dado: só o próprio perfil e os próprios papéis.
--   2. concluir_troca_senha() só funciona se a senha realmente mudou.
--   3. Funções usadas SÓ pelo servidor (Edge Function gerenciar-login,
--      com a chave de serviço em variável de ambiente) para criar logins.
-- Nenhuma senha é guardada aqui: só um "carimbo" (md5 do hash do Auth)
-- para saber se a senha inicial já foi trocada.
-- =====================================================================

-- ---------------------------------------------------------------
-- 1. Sessão liberada = perfil ativo, senha inicial trocada
-- ---------------------------------------------------------------
create function private.sessao_liberada() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.perfis p
                 where p.id = (select auth.uid()) and p.ativo and not p.troca_senha_obrigatoria) $$;

create or replace function private.tem_papel_global(p_papeis public.papel_tipo[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.papeis_usuario pu
    join public.perfis p on p.id = pu.perfil_id
    where pu.perfil_id = (select auth.uid()) and p.ativo and not p.troca_senha_obrigatoria
      and pu.papel = any (p_papeis)) $$;

create or replace function private.tem_papel_dept(p_papeis public.papel_tipo[], p_dept uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.papeis_usuario pu
    join public.perfis p on p.id = pu.perfil_id
    where pu.perfil_id = (select auth.uid()) and p.ativo and not p.troca_senha_obrigatoria
      and pu.departamento_id = p_dept and pu.papel = any (p_papeis)) $$;

create or replace function private.e_lider_algum() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_pastor_ou_admin() or exists (
    select 1 from public.papeis_usuario pu join public.perfis p on p.id = pu.perfil_id
    where pu.perfil_id = (select auth.uid()) and p.ativo and not p.troca_senha_obrigatoria
      and pu.papel = 'lider') $$;

create or replace function private.tem_algum_papel() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.papeis_usuario pu join public.perfis p on p.id = pu.perfil_id
                 where pu.perfil_id = (select auth.uid()) and p.ativo and not p.troca_senha_obrigatoria) $$;

-- Sem papel = sem pessoa (não vê nem a própria família)
create or replace function private.minha_pessoa() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.pessoa_id from public.perfis p
  where p.id = (select auth.uid()) and p.ativo and not p.troca_senha_obrigatoria
    and exists (select 1 from public.papeis_usuario pu where pu.perfil_id = p.id) $$;

create or replace function private.minha_igreja() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.igreja_id from public.perfis p
  where p.id = (select auth.uid()) and p.ativo and not p.troca_senha_obrigatoria $$;

-- ---------------------------------------------------------------
-- 2. Carimbo da senha inicial e troca obrigatória
-- ---------------------------------------------------------------
create table private.senha_inicial (
  perfil_id     uuid primary key references auth.users(id) on delete cascade,
  carimbo       text,                 -- md5 do hash do Auth (não é a senha)
  definida_em   timestamptz not null default now()
);
revoke all on private.senha_inicial from public, anon, authenticated;

-- Ao criar o usuário no Auth, guarda o carimbo da senha inicial
create function private.registrar_senha_inicial()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into private.senha_inicial (perfil_id, carimbo)
  values (new.id, md5(new.encrypted_password))
  on conflict (perfil_id) do update set carimbo = excluded.carimbo, definida_em = now();
  return new;
end $$;
create trigger senha_inicial_registrar after insert on auth.users
  for each row execute function private.registrar_senha_inicial();

-- Só conclui se a senha atual for diferente da inicial
create or replace function public.concluir_troca_senha()
returns void language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from private.senha_inicial s join auth.users u on u.id = s.perfil_id
             where s.perfil_id = auth.uid() and s.carimbo = md5(u.encrypted_password)) then
    raise exception 'Troque a senha inicial antes de continuar';
  end if;
  update public.perfis set troca_senha_obrigatoria = false where id = auth.uid();
  delete from private.senha_inicial where perfil_id = auth.uid();
end $$;
revoke all on function public.concluir_troca_senha() from public, anon;
grant execute on function public.concluir_troca_senha() to authenticated;

-- Redefinição pela liderança (chamada pelo servidor depois de pôr a senha
-- inicial de novo): volta a exigir a troca
create function public.marcar_senha_inicial(p_perfil uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  insert into private.senha_inicial (perfil_id, carimbo)
  select u.id, md5(u.encrypted_password) from auth.users u where u.id = p_perfil
  on conflict (perfil_id) do update set carimbo = excluded.carimbo, definida_em = now();
  update public.perfis set troca_senha_obrigatoria = true where id = p_perfil;
end $$;

-- ---------------------------------------------------------------
-- 3. Funções do servidor (só a chave de serviço chama)
-- ---------------------------------------------------------------
-- Dados para criar o login de UMA pessoa
create function public.dados_login(p_pessoa uuid)
returns table (igreja_id uuid, telefone_contato text, data_nascimento date,
               depts_voluntaria uuid[], e_responsavel boolean, ja_tem_login boolean)
language sql stable security definer set search_path = '' as $$
  select p.igreja_id, p.telefone, p.data_nascimento,
    coalesce((select array_agg(v.departamento_id) from public.voluntarias v
              where v.pessoa_id = p.id and v.status = 'ativa'), '{}'),
    exists (select 1 from public.responsaveis r where r.pessoa_id = p.id),
    exists (select 1 from public.perfis x where x.pessoa_id = p.id)
  from public.pessoas p where p.id = p_pessoa $$;

-- Quem do departamento recebe login (e por que não, quando não recebe)
create function public.candidatos_login(p_departamento uuid)
returns table (pessoa_id uuid, telefone_login text, data_nascimento date,
               e_voluntaria boolean, e_responsavel boolean, situacao text)
language sql stable security definer set search_path = '' as $$
  with base as (
    select p.id, p.telefone, p.data_nascimento, p.criado_em,
      exists (select 1 from public.voluntarias v where v.pessoa_id = p.id
              and v.departamento_id = p_departamento and v.status = 'ativa') as vol,
      exists (select 1 from public.responsaveis r join public.familias f on f.id = r.familia_id
              where r.pessoa_id = p.id and f.departamento_id = p_departamento) as resp,
      exists (select 1 from public.responsaveis r join public.familias f on f.id = r.familia_id
              where r.pessoa_id = p.id and f.departamento_id = p_departamento and r.principal) as principal,
      exists (select 1 from public.perfis x where x.pessoa_id = p.id) as tem_login
    from public.pessoas p
    where p.id in (select v.pessoa_id from public.voluntarias v
                   where v.departamento_id = p_departamento and v.status = 'ativa'
                   union
                   select r.pessoa_id from public.responsaveis r join public.familias f on f.id = r.familia_id
                   where f.departamento_id = p_departamento)
  ), ordem as (
    select b.*, row_number() over (partition by b.telefone
                                   order by b.tem_login desc, b.vol desc, b.principal desc, b.criado_em, b.id) as pos
    from base b
  )
  select o.id, o.telefone, o.data_nascimento, o.vol, o.resp,
    case when o.tem_login then 'ja_tem_login'
         when o.telefone is null then 'sem_telefone'
         when o.telefone !~ '^55[1-9][0-9]9?[0-9]{8}$' then 'telefone_invalido'
         when exists (select 1 from public.perfis x where x.telefone = o.telefone) then 'telefone_em_uso'
         when o.pos > 1 then 'telefone_compartilhado'
         else 'criar' end
  from ordem o $$;

revoke all on function public.dados_login(uuid), public.candidatos_login(uuid),
                       public.marcar_senha_inicial(uuid) from public, anon, authenticated;
grant execute on function public.dados_login(uuid), public.candidatos_login(uuid),
                          public.marcar_senha_inicial(uuid) to service_role;

-- ---------------------------------------------------------------
-- 4. Conferências de permissão (chamadas com o token de quem pede)
-- ---------------------------------------------------------------
-- Quem pede pode dar TODOS estes papéis? [{ "papel": "...", "departamento_id": "..." }]
create function public.posso_dar_papeis(p_papeis jsonb)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.sessao_liberada() and coalesce((
    select bool_and(private.pode_gerir_papel((e ->> 'papel')::public.papel_tipo,
                                             nullif(e ->> 'departamento_id', '')::uuid))
    from jsonb_array_elements(p_papeis) e), false) $$;

-- Quem pede pode redefinir a senha deste perfil? (precisa poder gerir todos os papéis dele)
create function public.posso_redefinir_senha(p_perfil uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select private.sessao_liberada() and p_perfil <> (select auth.uid()) and (
    private.e_pastor_ou_admin()
    or (exists (select 1 from public.papeis_usuario pu where pu.perfil_id = p_perfil)
        and not exists (select 1 from public.papeis_usuario pu where pu.perfil_id = p_perfil
                        and not private.pode_gerir_papel(pu.papel, pu.departamento_id)))) $$;

revoke all on function public.posso_dar_papeis(jsonb), public.posso_redefinir_senha(uuid) from public, anon;
grant execute on function public.posso_dar_papeis(jsonb), public.posso_redefinir_senha(uuid) to authenticated, service_role;
