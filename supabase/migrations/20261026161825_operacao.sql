-- =====================================================================
-- Migração 0006: fila de impressão (Brother QL-800), log de erros, auditoria
-- =====================================================================

-- O agente local da recepção escuta esta tabela via Realtime e imprime.
create table public.fila_impressao (
  id               uuid primary key default gen_random_uuid(),
  departamento_id  uuid not null references public.departamentos(id) on delete cascade,
  checkin_id       uuid references public.checkins(id) on delete cascade,
  tipo             text not null default 'etiqueta',
  payload          jsonb not null default '{}',
  status           public.status_impressao not null default 'pendente',
  tentativas       smallint not null default 0,
  erro             text,
  criado_por       uuid references public.perfis(id) on delete set null default auth.uid(),
  criado_em        timestamptz not null default now(),
  impresso_em      timestamptz
);
create index fila_impressao_status_idx on public.fila_impressao (departamento_id, status);
create index fila_impressao_checkin_idx on public.fila_impressao (checkin_id);
create index fila_impressao_criado_por_idx on public.fila_impressao (criado_por);

create table public.log_erros (
  id          uuid primary key default gen_random_uuid(),
  perfil_id   uuid references public.perfis(id) on delete set null default auth.uid(),
  mensagem    text not null check (char_length(mensagem) <= 2000),
  contexto    jsonb check (contexto is null or pg_column_size(contexto) <= 8000),
  url         text check (url is null or char_length(url) <= 500),
  user_agent  text check (user_agent is null or char_length(user_agent) <= 500),
  criado_em   timestamptz not null default now()
);
create index log_erros_perfil_idx on public.log_erros (perfil_id);
create index log_erros_data_idx on public.log_erros (criado_em);

-- Auditoria: QUEM alterou O QUÊ e QUANDO. Guarda só o nome dos campos
-- alterados (não copia dados pessoais, para respeitar a LGPD).
create table public.auditoria (
  id                uuid primary key default gen_random_uuid(),
  perfil_id         uuid,
  tabela            text not null,
  registro_id       uuid,
  acao              text not null,
  campos_alterados  text[],
  em                timestamptz not null default now()
);
create index auditoria_registro_idx on public.auditoria (tabela, registro_id);
create index auditoria_em_idx on public.auditoria (em);
