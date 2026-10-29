-- =====================================================================
-- Fonte Kids → app da igreja | Migração 0001: estrutura base
-- Igrejas, departamentos, perfis (ligados ao Supabase Auth) e papéis.
-- =====================================================================

-- Schema privado: funções auxiliares de segurança (NÃO exposto pela API)
create schema if not exists private;
revoke all on schema private from public;

-- ---------- Tipos ----------
create type public.papel_tipo        as enum ('admin','pastor','lider','recepcao','voluntaria','responsavel');
create type public.status_voluntaria as enum ('pendente','ativa','inativa');
create type public.funcao_voluntaria as enum ('professora','auxiliar');
create type public.funcao_escala     as enum ('lider_culto','professora','auxiliar','reserva');
create type public.status_escala     as enum ('rascunho','publicada','encerrada');
create type public.resposta_escala   as enum ('pendente','ciente','recusado');
create type public.perfil_crianca    as enum ('membro','visitante');
create type public.publico_alvo      as enum ('equipe','familias','todos');
create type public.status_impressao  as enum ('pendente','imprimindo','impresso','erro');
create type public.sexo_tipo         as enum ('F','M');

-- ---------- Utilitário: carimbo de atualização ----------
create function private.tocar_atualizado_em()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.atualizado_em := now();
  return new;
end $$;

-- ---------- Igrejas e departamentos ----------
create table public.igrejas (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  criado_em  timestamptz not null default now()
);

create table public.departamentos (
  id         uuid primary key default gen_random_uuid(),
  igreja_id  uuid not null references public.igrejas(id) on delete restrict,
  nome       text not null,
  slug       text not null,
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now(),
  unique (igreja_id, slug)
);

-- ---------- Perfis (1 por usuário do Auth) ----------
create table public.perfis (
  id                       uuid primary key references auth.users(id) on delete cascade,
  igreja_id                uuid references public.igrejas(id) on delete set null,
  nome                     text not null default '',
  telefone                 text,
  foto_public_id           text,
  ativo                    boolean not null default true,
  troca_senha_obrigatoria  boolean not null default true,
  criado_em                timestamptz not null default now(),
  atualizado_em            timestamptz not null default now()
);
create unique index perfis_telefone_uk on public.perfis (telefone) where telefone is not null;
create index perfis_igreja_idx on public.perfis (igreja_id);
create trigger perfis_atualizado before update on public.perfis
  for each row execute function private.tocar_atualizado_em();

-- ---------- Papéis ----------
-- admin, pastor e responsavel valem para a igreja toda (sem departamento);
-- lider, recepcao e voluntaria são sempre de um departamento.
create table public.papeis_usuario (
  id              uuid primary key default gen_random_uuid(),
  perfil_id       uuid not null references public.perfis(id) on delete cascade,
  departamento_id uuid references public.departamentos(id) on delete cascade,
  papel           public.papel_tipo not null,
  concedido_por   uuid references public.perfis(id) on delete set null default auth.uid(),
  criado_em       timestamptz not null default now(),
  constraint papel_escopo_ok check (
    (papel in ('admin','pastor','responsavel') and departamento_id is null) or
    (papel in ('lider','recepcao','voluntaria') and departamento_id is not null)
  ),
  constraint papel_unico unique nulls not distinct (perfil_id, departamento_id, papel)
);
create index papeis_departamento_idx on public.papeis_usuario (departamento_id);
create index papeis_concedido_por_idx on public.papeis_usuario (concedido_por);
