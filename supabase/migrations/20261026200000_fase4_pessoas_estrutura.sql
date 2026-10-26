-- =====================================================================
-- Fase 4 · Etapa 2 (parte 1/3) – Cadastro único de pessoas da igreja
-- Decisão de 26/10/2026 (opção B):
--   * pessoas ............... uma linha por pessoa, no nível da IGREJA
--                              (nome, nascimento, sexo, telefone, foto, login)
--   * relacoes_pessoas ...... parentesco pessoa ↔ pessoa (único lugar do parentesco)
--   * possiveis_duplicidades  pares duvidosos para a liderança conferir
--   * responsaveis, criancas, voluntarias e pessoas_autorizadas passam a
--     guardar só o que é do PAPEL e apontam para a pessoa (pessoa_id).
-- Esta parte só cria a estrutura. A parte 2 migra os dados e a parte 3
-- apaga as colunas antigas e refaz as regras de acesso.
-- =====================================================================

-- ---------- Utilitários de comparação de nomes ----------
-- "José da  Silva-Souza" -> "jose da silva souza"
create function private.normalizar_nome(p text) returns text
language sql immutable set search_path = '' as $$
  select nullif(btrim(regexp_replace(regexp_replace(lower(translate(coalesce(p, ''),
    'ÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäéèêëíìîïóòôõöúùûüçñ',
    'AAAAAEEEEIIIIOOOOOUUUUCNaaaaaeeeeiiiiooooouuuucn')),
    '[^a-z ]', ' ', 'g'), '\s+', ' ', 'g')), '')
$$;

-- Nomes compatíveis: mesmo primeiro nome e todas as palavras do nome mais
-- curto aparecem no mais longo ("maria silva" ~ "maria da silva").
create function private.nomes_compativeis(a text, b text) returns boolean
language sql immutable set search_path = '' as $$
  select coalesce(a, '') <> '' and coalesce(b, '') <> ''
     and split_part(a, ' ', 1) = split_part(b, ' ', 1)
     and (string_to_array(a, ' ') <@ string_to_array(b, ' ')
          or string_to_array(b, ' ') <@ string_to_array(a, ' '))
$$;

-- ---------- Tipos ----------
-- Leitura: "pessoa_id É <tipo> DE relacionada_id" (ex.: X é mãe de Y).
-- conjuge e irmao são simétricos (gravados uma vez só).
create type public.relacao_tipo as enum
  ('conjuge','mae','pai','madrasta','padrasto','avo','tio','irmao','responsavel_legal','outro');
comment on type public.relacao_tipo is
  'Rótulos: cônjuge, mãe, pai, madrasta, padrasto, avô/avó, tio/tia, irmão/irmã, responsável legal, outro. '
  'Inversos calculados no app: filho(a), enteado(a), neto(a), sobrinho(a).';

create type public.situacao_duplicidade as enum ('pendente','mesma_pessoa','pessoas_diferentes');

-- ---------- Pessoas ----------
create table public.pessoas (
  id               uuid primary key default gen_random_uuid(),
  igreja_id        uuid not null references public.igrejas(id) on delete restrict,
  nome             text not null check (char_length(btrim(nome)) between 1 and 150),
  nome_busca       text generated always as (private.normalizar_nome(nome)) stored,
  data_nascimento  date,
  sexo             public.sexo_tipo,
  telefone         text check (telefone is null or telefone ~ '^55[0-9]{10,11}$'),  -- contato (pode ser compartilhado)
  foto_public_id   text,                -- id da foto no Cloudinary (privada)
  criado_por       uuid references public.perfis(id) on delete set null default auth.uid(),
  criado_em        timestamptz not null default now(),
  atualizado_em    timestamptz not null default now()
);
comment on table public.pessoas is
  'Cadastro único da igreja. Telefone aqui é contato; o telefone de LOGIN fica em perfis.telefone (único).';
create index pessoas_igreja_idx     on public.pessoas (igreja_id);
create index pessoas_nome_busca_idx on public.pessoas (nome_busca);
create index pessoas_telefone_idx   on public.pessoas (telefone);
create index pessoas_criado_por_idx on public.pessoas (criado_por);
create trigger pessoas_atualizado before update on public.pessoas
  for each row execute function private.tocar_atualizado_em();

-- Login ↔ pessoa (1 para 1)
alter table public.perfis add column pessoa_id uuid unique references public.pessoas(id) on delete set null;

-- ---------- Relações familiares ----------
create table public.relacoes_pessoas (
  id              uuid primary key default gen_random_uuid(),
  pessoa_id       uuid not null references public.pessoas(id) on delete cascade,
  relacionada_id  uuid not null references public.pessoas(id) on delete cascade,
  tipo            public.relacao_tipo not null,
  detalhe         text check (detalhe is null or char_length(detalhe) <= 60),
  origem          text not null default 'app' check (origem in ('app','lideranca','legado')),
  informado_por   uuid references public.perfis(id) on delete set null default auth.uid(),
  criado_em       timestamptz not null default now(),
  atualizado_em   timestamptz not null default now(),
  check (pessoa_id <> relacionada_id),
  unique (pessoa_id, relacionada_id, tipo)
);
create index relacoes_relacionada_idx on public.relacoes_pessoas (relacionada_id);
create index relacoes_informado_idx   on public.relacoes_pessoas (informado_por);
create trigger relacoes_atualizado before update on public.relacoes_pessoas
  for each row execute function private.tocar_atualizado_em();

-- Simétricas sempre na mesma ordem (evita "A cônjuge de B" e "B cônjuge de A")
create function private.normalizar_relacao()
returns trigger language plpgsql set search_path = '' as $$
declare tmp uuid;
begin
  if new.tipo in ('conjuge','irmao') and new.pessoa_id > new.relacionada_id then
    tmp := new.pessoa_id; new.pessoa_id := new.relacionada_id; new.relacionada_id := tmp;
  end if;
  if new.tipo <> 'outro' then new.detalhe := null; end if;
  return new;
end $$;
create trigger relacoes_normalizar before insert or update on public.relacoes_pessoas
  for each row execute function private.normalizar_relacao();

-- ---------- Possíveis duplicidades (conferência manual) ----------
create table public.possiveis_duplicidades (
  id             uuid primary key default gen_random_uuid(),
  pessoa_a       uuid not null references public.pessoas(id) on delete cascade,
  pessoa_b       uuid not null references public.pessoas(id) on delete cascade,
  motivo         text not null check (motivo in
                   ('mesmo_nome','nome_parecido','nome_parecido_mesmo_nascimento','telefone_compartilhado')),
  situacao       public.situacao_duplicidade not null default 'pendente',
  resolvido_por  uuid references public.perfis(id) on delete set null,
  resolvido_em   timestamptz,
  criado_em      timestamptz not null default now(),
  check (pessoa_a < pessoa_b),
  unique (pessoa_a, pessoa_b)
);
create index duplicidades_b_idx on public.possiveis_duplicidades (pessoa_b);
create index duplicidades_pendentes_idx on public.possiveis_duplicidades (situacao) where situacao = 'pendente';
create index duplicidades_resolvido_idx on public.possiveis_duplicidades (resolvido_por);

-- RLS ligada já na criação (as regras vêm na parte 3; até lá ninguém do app lê)
alter table public.pessoas                enable row level security;
alter table public.relacoes_pessoas       enable row level security;
alter table public.possiveis_duplicidades enable row level security;

-- ---------- Papéis apontam para a pessoa ----------
alter table public.responsaveis        add column pessoa_id uuid references public.pessoas(id) on delete cascade;
alter table public.criancas            add column pessoa_id uuid references public.pessoas(id) on delete cascade;
alter table public.voluntarias         add column pessoa_id uuid references public.pessoas(id) on delete cascade;
alter table public.pessoas_autorizadas add column pessoa_id uuid references public.pessoas(id) on delete cascade;
alter table public.pessoas_autorizadas add column observacao text check (observacao is null or char_length(observacao) <= 120);

-- ---------- Detecção de duplicidades (reutilizável, ex.: reimportação da Fase 12) ----------
create function private.detectar_duplicidades() returns integer
language plpgsql security definer set search_path = '' as $$
declare n integer;
begin
  with pares as (
    select a.id x, b.id y,
      case
        when a.nome_busca = b.nome_busca
             and (a.data_nascimento is null or b.data_nascimento is null or a.data_nascimento = b.data_nascimento)
          then 'mesmo_nome'
        when a.data_nascimento = b.data_nascimento
             and split_part(a.nome_busca, ' ', 1) = split_part(b.nome_busca, ' ', 1)
             and (regexp_replace(a.nome_busca, '^.* ', '') = regexp_replace(b.nome_busca, '^.* ', '')
                  or private.nomes_compativeis(a.nome_busca, b.nome_busca))
          then 'nome_parecido_mesmo_nascimento'
        when a.telefone = b.telefone and not private.nomes_compativeis(a.nome_busca, b.nome_busca)
          then 'telefone_compartilhado'
        -- ex.: "ana silva" e "ana maria silva" (com sobrenome em comum), sem telefone/nascimento que os diferencie
        when private.nomes_compativeis(a.nome_busca, b.nome_busca)
             and array_length(string_to_array(a.nome_busca, ' '), 1) >= 2
             and array_length(string_to_array(b.nome_busca, ' '), 1) >= 2
             and (a.data_nascimento is null or b.data_nascimento is null or a.data_nascimento = b.data_nascimento)
             and (a.telefone is null or b.telefone is null or a.telefone <> b.telefone)
          then 'nome_parecido'
      end motivo
    from public.pessoas a
    join public.pessoas b on a.id < b.id and a.igreja_id = b.igreja_id
     and (a.nome_busca = b.nome_busca or a.data_nascimento = b.data_nascimento or a.telefone = b.telefone
          or split_part(a.nome_busca, ' ', 1) = split_part(b.nome_busca, ' ', 1))
  )
  insert into public.possiveis_duplicidades (pessoa_a, pessoa_b, motivo)
  select x, y, motivo from pares where motivo is not null
  on conflict (pessoa_a, pessoa_b) do nothing;
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function private.detectar_duplicidades() from public, anon, authenticated;
