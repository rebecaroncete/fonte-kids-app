-- =====================================================================
-- Migração 0005: configurações, lições, eventos, enquetes, notificações
-- =====================================================================

create table public.configuracoes (
  id               uuid primary key default gen_random_uuid(),
  departamento_id  uuid not null references public.departamentos(id) on delete cascade,
  chave            text not null,
  valor            text,
  descricao        text,
  atualizado_em    timestamptz not null default now(),
  unique (departamento_id, chave)
);
create trigger configuracoes_atualizado before update on public.configuracoes
  for each row execute function private.tocar_atualizado_em();

-- Modelos de mensagem WhatsApp (choro, telão, lembrete de escala...)
create table public.mensagens_whatsapp_modelos (
  id               uuid primary key default gen_random_uuid(),
  departamento_id  uuid not null references public.departamentos(id) on delete cascade,
  chave            text not null,
  titulo           text,
  texto            text not null,
  atualizado_em    timestamptz not null default now(),
  unique (departamento_id, chave)
);
create trigger mensagens_atualizado before update on public.mensagens_whatsapp_modelos
  for each row execute function private.tocar_atualizado_em();

create table public.licoes (
  id               uuid primary key default gen_random_uuid(),
  departamento_id  uuid not null references public.departamentos(id) on delete cascade,
  sala_id          uuid references public.salas(id) on delete set null,
  titulo           text not null,
  data_inicio      date not null,
  data_fim         date not null,
  arquivo_url      text,
  enviado_por      uuid references public.perfis(id) on delete set null default auth.uid(),
  criado_em        timestamptz not null default now(),
  check (data_fim >= data_inicio)
);
create index licoes_departamento_idx on public.licoes (departamento_id);
create index licoes_sala_idx on public.licoes (sala_id);
create index licoes_enviado_por_idx on public.licoes (enviado_por);

create table public.eventos (
  id                  uuid primary key default gen_random_uuid(),
  departamento_id     uuid not null references public.departamentos(id) on delete cascade,
  titulo              text not null,
  descricao           text,
  inicio              timestamptz,
  fim                 timestamptz,
  local               text,
  foto_public_id      text,
  publicado           boolean not null default false,
  inscricoes_abertas  boolean not null default false,
  limite_inscricoes   integer,
  criado_por          uuid references public.perfis(id) on delete set null default auth.uid(),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now()
);
create index eventos_departamento_idx on public.eventos (departamento_id);
create index eventos_criado_por_idx on public.eventos (criado_por);
create trigger eventos_atualizado before update on public.eventos
  for each row execute function private.tocar_atualizado_em();

create table public.inscricoes_evento (
  id            uuid primary key default gen_random_uuid(),
  evento_id     uuid not null references public.eventos(id) on delete cascade,
  inscrito_por  uuid references public.perfis(id) on delete set null default auth.uid(),
  nome          text not null,
  telefone      text,
  crianca_id    uuid references public.criancas(id) on delete set null,
  dados         jsonb not null default '{}',
  criado_em     timestamptz not null default now()
);
create index inscricoes_evento_idx on public.inscricoes_evento (evento_id);
create index inscricoes_inscrito_idx on public.inscricoes_evento (inscrito_por);
create index inscricoes_crianca_idx on public.inscricoes_evento (crianca_id);

create table public.enquetes (
  id                uuid primary key default gen_random_uuid(),
  departamento_id   uuid not null references public.departamentos(id) on delete cascade,
  pergunta          text not null,
  publico           public.publico_alvo not null default 'equipe',
  multipla_escolha  boolean not null default false,
  publicada         boolean not null default false,
  encerra_em        timestamptz,
  criado_por        uuid references public.perfis(id) on delete set null default auth.uid(),
  criado_em         timestamptz not null default now()
);
create index enquetes_departamento_idx on public.enquetes (departamento_id);
create index enquetes_criado_por_idx on public.enquetes (criado_por);

create table public.enquete_opcoes (
  id         uuid primary key default gen_random_uuid(),
  enquete_id uuid not null references public.enquetes(id) on delete cascade,
  texto      text not null,
  ordem      smallint not null default 0,
  unique (id, enquete_id)
);
create index enquete_opcoes_enquete_idx on public.enquete_opcoes (enquete_id);

create table public.votos (
  id          uuid primary key default gen_random_uuid(),
  enquete_id  uuid not null references public.enquetes(id) on delete cascade,
  opcao_id    uuid not null,
  perfil_id   uuid not null references public.perfis(id) on delete cascade default auth.uid(),
  criado_em   timestamptz not null default now(),
  foreign key (opcao_id, enquete_id) references public.enquete_opcoes(id, enquete_id) on delete cascade,
  unique (enquete_id, opcao_id, perfil_id)
);
create index votos_opcao_idx on public.votos (opcao_id, enquete_id);
create index votos_perfil_idx on public.votos (perfil_id);

-- Sino dentro do app
create table public.notificacoes (
  id               uuid primary key default gen_random_uuid(),
  destinatario_id  uuid not null references public.perfis(id) on delete cascade,
  titulo           text not null,
  corpo            text,
  link             text,
  tipo             text,
  criado_por       uuid references public.perfis(id) on delete set null default auth.uid(),
  lida_em          timestamptz,
  criado_em        timestamptz not null default now()
);
create index notificacoes_dest_idx on public.notificacoes (destinatario_id, lida_em);
create index notificacoes_criado_por_idx on public.notificacoes (criado_por);

create table public.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  perfil_id   uuid not null references public.perfis(id) on delete cascade default auth.uid(),
  endpoint    text not null unique,
  p256dh      text not null,
  auth        text not null,
  user_agent  text,
  criado_em   timestamptz not null default now()
);
create index push_perfil_idx on public.push_subscriptions (perfil_id);
