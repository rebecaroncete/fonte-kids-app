-- =====================================================================
-- Migração 0004: escala mensal de voluntárias
-- =====================================================================

create table public.escalas (
  id               uuid primary key default gen_random_uuid(),
  departamento_id  uuid not null references public.departamentos(id) on delete cascade,
  mes_referencia   date not null check (extract(day from mes_referencia) = 1), -- sempre dia 1
  status           public.status_escala not null default 'rascunho',
  teto_mensal      smallint,          -- máx. de cultos por voluntária no mês
  criado_por       uuid references public.perfis(id) on delete set null default auth.uid(),
  publicada_em     timestamptz,
  publicada_por    uuid references public.perfis(id) on delete set null,
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now(),
  unique (departamento_id, mes_referencia)
);
create index escalas_criado_por_idx on public.escalas (criado_por);
create index escalas_publicada_por_idx on public.escalas (publicada_por);
create trigger escalas_atualizado before update on public.escalas
  for each row execute function private.tocar_atualizado_em();

-- Vagas por sala no mês (antiga aba Config_Escala)
create table public.escala_config_salas (
  id              uuid primary key default gen_random_uuid(),
  escala_id       uuid not null references public.escalas(id) on delete cascade,
  sala_id         uuid not null references public.salas(id) on delete cascade,
  qtd_professora  smallint not null default 1,
  qtd_auxiliar    smallint not null default 1,
  qtd_reserva     smallint not null default 0,
  unique (escala_id, sala_id)
);
create index escala_config_sala_idx on public.escala_config_salas (sala_id);

create table public.escala_itens (
  id             uuid primary key default gen_random_uuid(),
  escala_id      uuid not null references public.escalas(id) on delete cascade,
  culto_id       uuid not null references public.cultos(id) on delete cascade,
  sala_id        uuid references public.salas(id) on delete cascade,  -- nulo só para "Líder do Culto"
  funcao         public.funcao_escala not null,
  voluntaria_id  uuid references public.voluntarias(id) on delete set null,
  nome_livre     text,       -- alocação manual de alguém sem cadastro
  resposta       public.resposta_escala not null default 'pendente',
  respondido_em  timestamptz,
  observacao     text,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  check (funcao = 'lider_culto' or sala_id is not null)
);
create index escala_itens_escala_idx on public.escala_itens (escala_id);
create index escala_itens_culto_idx on public.escala_itens (culto_id);
create index escala_itens_sala_idx on public.escala_itens (sala_id);
create index escala_itens_voluntaria_idx on public.escala_itens (voluntaria_id);
create trigger escala_itens_atualizado before update on public.escala_itens
  for each row execute function private.tocar_atualizado_em();

-- Regras parametrizadas por departamento (o motor de escala lê daqui)
create table public.regras_escala (
  id               uuid primary key default gen_random_uuid(),
  departamento_id  uuid not null references public.departamentos(id) on delete cascade,
  chave            text not null,
  valor            jsonb not null,
  descricao        text,
  atualizado_em    timestamptz not null default now(),
  unique (departamento_id, chave)
);
create trigger regras_escala_atualizado before update on public.regras_escala
  for each row execute function private.tocar_atualizado_em();
