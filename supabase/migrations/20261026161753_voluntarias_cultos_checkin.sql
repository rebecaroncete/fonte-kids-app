-- =====================================================================
-- Migração 0003: voluntárias, indisponibilidades, cultos e check-in
-- =====================================================================

create table public.voluntarias (
  id                 uuid primary key default gen_random_uuid(),
  departamento_id    uuid not null references public.departamentos(id) on delete cascade,
  perfil_id          uuid references public.perfis(id) on delete set null,
  nome               text not null,
  telefone           text,
  email              text,
  data_nascimento    date,
  sexo               public.sexo_tipo,
  profissao          text,
  funcao             public.funcao_voluntaria not null default 'auxiliar',
  salas_preferidas   uuid[] not null default '{}',  -- em ordem de preferência (até 4)
  cultos_preferidos  uuid[] not null default '{}',  -- ids de cultos_recorrentes, em ordem
  status             public.status_voluntaria not null default 'pendente',
  foto_public_id     text,
  aprovada_por       uuid references public.perfis(id) on delete set null,
  aprovada_em        timestamptz,
  codigo_legado      text,   -- ID_Professora da planilha
  criado_em          timestamptz not null default now(),
  atualizado_em      timestamptz not null default now(),
  unique (departamento_id, perfil_id)
);
create index voluntarias_perfil_idx on public.voluntarias (perfil_id);
create index voluntarias_aprovada_por_idx on public.voluntarias (aprovada_por);
create trigger voluntarias_atualizado before update on public.voluntarias
  for each row execute function private.tocar_atualizado_em();

-- horario nulo = indisponível o dia todo
create table public.indisponibilidades (
  id             uuid primary key default gen_random_uuid(),
  voluntaria_id  uuid not null references public.voluntarias(id) on delete cascade,
  data           date not null,
  horario        time,
  motivo         text,
  criado_em      timestamptz not null default now(),
  unique nulls not distinct (voluntaria_id, data, horario)
);

-- Cultos fixos da semana (ex.: Dom 10h, Dom 19h, Ter 20h)
create table public.cultos_recorrentes (
  id          uuid primary key default gen_random_uuid(),
  igreja_id   uuid not null references public.igrejas(id) on delete cascade,
  nome        text not null,
  dia_semana  smallint not null check (dia_semana between 0 and 6), -- 0 = domingo
  horario     time not null,
  ativo       boolean not null default true,
  criado_em   timestamptz not null default now(),
  unique (igreja_id, dia_semana, horario)
);

-- Cada culto real (uma data)
create table public.cultos (
  id                   uuid primary key default gen_random_uuid(),
  igreja_id            uuid not null references public.igrejas(id) on delete cascade,
  culto_recorrente_id  uuid references public.cultos_recorrentes(id) on delete set null,
  data                 date not null,
  horario              time not null,
  nome                 text,
  cancelado            boolean not null default false,
  observacao           text,
  criado_em            timestamptz not null default now(),
  unique (igreja_id, data, horario)
);
create index cultos_recorrente_idx on public.cultos (culto_recorrente_id);
create index cultos_data_idx on public.cultos (data);

-- Exceções por sala em um culto: sala cancelada ou combinada (ex.: terça)
create table public.culto_salas (
  id                     uuid primary key default gen_random_uuid(),
  culto_id               uuid not null references public.cultos(id) on delete cascade,
  sala_id                uuid not null references public.salas(id) on delete cascade,
  cancelada              boolean not null default false,
  combinada_com_sala_id  uuid references public.salas(id) on delete set null,
  observacao             text,
  unique (culto_id, sala_id),
  check (combinada_com_sala_id is null or combinada_com_sala_id <> sala_id)
);
create index culto_salas_sala_idx on public.culto_salas (sala_id);
create index culto_salas_comb_idx on public.culto_salas (combinada_com_sala_id);

create table public.checkins (
  id                       uuid primary key default gen_random_uuid(),
  culto_id                 uuid not null references public.cultos(id) on delete restrict,
  crianca_id               uuid not null references public.criancas(id) on delete cascade,
  sala_id                  uuid not null references public.salas(id) on delete restrict,
  codigo_seguranca         text not null,   -- gerado automaticamente (4 caracteres)
  entrada_em               timestamptz not null default now(),
  entrada_por              uuid references public.perfis(id) on delete set null default auth.uid(),
  saida_em                 timestamptz,
  saida_por                uuid references public.perfis(id) on delete set null,
  retirado_por_nome        text,
  retirado_por_autorizado  boolean,
  observacao               text,
  criado_em                timestamptz not null default now(),
  unique (culto_id, crianca_id),
  unique (culto_id, codigo_seguranca),
  check (saida_em is null or saida_em >= entrada_em)
);
create index checkins_crianca_idx on public.checkins (crianca_id);
create index checkins_sala_idx on public.checkins (sala_id);
create index checkins_entrada_por_idx on public.checkins (entrada_por);
create index checkins_saida_por_idx on public.checkins (saida_por);
