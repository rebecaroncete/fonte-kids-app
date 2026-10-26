-- =====================================================================
-- Migração 0002: salas, famílias, responsáveis, crianças e termo LGPD
-- =====================================================================

create table public.salas (
  id              uuid primary key default gen_random_uuid(),
  departamento_id uuid not null references public.departamentos(id) on delete cascade,
  nome            text not null,
  idade_min       smallint not null,
  idade_max       smallint not null,
  capacidade      smallint,
  ordem           smallint not null default 0,
  ativa           boolean not null default true,
  criado_em       timestamptz not null default now(),
  check (idade_min <= idade_max),
  unique (departamento_id, nome)
);

create table public.familias (
  id              uuid primary key default gen_random_uuid(),
  departamento_id uuid not null references public.departamentos(id) on delete restrict,
  codigo_legado   text,            -- ID_Familia da planilha (usado só na importação)
  observacoes     text,
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now()
);
create index familias_departamento_idx on public.familias (departamento_id);
create trigger familias_atualizado before update on public.familias
  for each row execute function private.tocar_atualizado_em();

create table public.responsaveis (
  id            uuid primary key default gen_random_uuid(),
  familia_id    uuid not null references public.familias(id) on delete cascade,
  perfil_id     uuid references public.perfis(id) on delete set null,  -- login do pai/mãe
  nome          text not null,
  telefone      text,
  parentesco    text,
  principal     boolean not null default false,
  criado_em     timestamptz not null default now(),
  atualizado_em timestamptz not null default now()
);
create unique index responsaveis_principal_uk on public.responsaveis (familia_id) where principal;
create index responsaveis_familia_idx on public.responsaveis (familia_id);
create index responsaveis_perfil_idx  on public.responsaveis (perfil_id);
create index responsaveis_telefone_idx on public.responsaveis (telefone);
create trigger responsaveis_atualizado before update on public.responsaveis
  for each row execute function private.tocar_atualizado_em();

-- Quem pode buscar a criança (alerta na saída se não estiver aqui)
create table public.pessoas_autorizadas (
  id          uuid primary key default gen_random_uuid(),
  familia_id  uuid not null references public.familias(id) on delete cascade,
  nome        text not null,
  telefone    text,
  parentesco  text,
  criado_em   timestamptz not null default now()
);
create index pessoas_autorizadas_familia_idx on public.pessoas_autorizadas (familia_id);

create table public.criancas (
  id                    uuid primary key default gen_random_uuid(),
  familia_id            uuid not null references public.familias(id) on delete cascade,
  nome                  text not null,
  data_nascimento       date,
  sexo                  public.sexo_tipo,
  alergias_observacoes  text,
  foto_public_id        text,     -- id da foto no Cloudinary (privada)
  perfil                public.perfil_crianca not null default 'membro',
  sala_fixa_id          uuid references public.salas(id) on delete set null, -- exceção manual à faixa etária
  ativo                 boolean not null default true,
  codigo_legado         text,     -- ID_Crianca da planilha
  criado_em             timestamptz not null default now(),
  atualizado_em         timestamptz not null default now()
);
create index criancas_familia_idx on public.criancas (familia_id);
create index criancas_sala_fixa_idx on public.criancas (sala_fixa_id);
create trigger criancas_atualizado before update on public.criancas
  for each row execute function private.tocar_atualizado_em();

-- Aceite do termo LGPD (imutável, versionado)
create table public.termos_lgpd (
  id                 uuid primary key default gen_random_uuid(),
  familia_id         uuid not null references public.familias(id) on delete cascade,
  versao             text not null,
  aceito_em          timestamptz not null default now(),
  aceito_por_nome    text not null,
  aceito_por_perfil  uuid references public.perfis(id) on delete set null default auth.uid(),
  criado_em          timestamptz not null default now()
);
create index termos_familia_idx on public.termos_lgpd (familia_id);
create index termos_perfil_idx  on public.termos_lgpd (aceito_por_perfil);
