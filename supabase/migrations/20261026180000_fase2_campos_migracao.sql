-- Fase 2 – campos que a planilha tem e o banco ainda não tinha.
-- Aplicada em 26/10/2026 após o OK da Rebeca.

-- 1) Link antigo da foto no Google Drive. Temporário: a Fase 3 move as fotos
--    para o Cloudinary (privado), preenche foto_public_id e apaga esta coluna.
alter table public.criancas    add column if not exists foto_legado_url text;
alter table public.voluntarias add column if not exists foto_legado_url text;

comment on column public.criancas.foto_legado_url    is 'TEMPORÁRIO (Fase 2→3): link antigo do Drive. Remover após migrar para Cloudinary.';
comment on column public.voluntarias.foto_legado_url is 'TEMPORÁRIO (Fase 2→3): link antigo do Drive. Remover após migrar para Cloudinary.';

-- 2) Teto mensal individual da voluntária (coluna Teto_Mensal da planilha).
--    Vazio = usa o teto geral da escala do mês (escalas.teto_mensal).
alter table public.voluntarias add column if not exists teto_mensal smallint
  check (teto_mensal is null or teto_mensal between 0 and 31);

comment on column public.voluntarias.teto_mensal is 'Máximo de cultos por mês desta voluntária; nulo = teto geral do mês.';

-- 3) Parentesco de CADA responsável com CADA criança (decisão de 26/10/2026).
--    Na importação todos ficam "a confirmar" (parentesco nulo); no 1º login o app
--    pergunta ao responsável qual a relação dele com cada criança.
create type public.parentesco_tipo as enum
  ('mae','pai','madrasta','padrasto','avo','tio','irmao','responsavel_legal','outro');
comment on type public.parentesco_tipo is
  'Rótulos no app: mãe, pai, madrasta, padrasto, avô/avó, tio/tia, irmão/irmã, responsável legal, outro';

create table public.responsaveis_criancas (
  id                 uuid primary key default gen_random_uuid(),
  responsavel_id     uuid not null references public.responsaveis(id) on delete cascade,
  crianca_id         uuid not null references public.criancas(id) on delete cascade,
  parentesco         public.parentesco_tipo,           -- nulo = a confirmar
  parentesco_detalhe text check (parentesco_detalhe is null or char_length(parentesco_detalhe) <= 60),
  confirmado_em      timestamptz,
  criado_em          timestamptz not null default now(),
  unique (responsavel_id, crianca_id)
);
create index on public.responsaveis_criancas (crianca_id);

-- responsável e criança precisam ser da mesma família
create function private.trava_responsaveis_criancas()
returns trigger language plpgsql set search_path = '' as $$
begin
  if (select familia_id from public.responsaveis where id = new.responsavel_id)
     is distinct from (select familia_id from public.criancas where id = new.crianca_id) then
    raise exception 'Responsável e criança precisam ser da mesma família';
  end if;
  return new;
end $$;
create trigger responsaveis_criancas_trava before insert or update on public.responsaveis_criancas
  for each row execute function private.trava_responsaveis_criancas();

-- 4) Pendências de cadastro: avisos que o responsável verá ao entrar no app (Fase 4).
create table public.pendencias_cadastro (
  id            uuid primary key default gen_random_uuid(),
  familia_id    uuid not null references public.familias(id) on delete cascade,
  crianca_id    uuid references public.criancas(id) on delete cascade,
  tipo          text not null,      -- ex.: conferir_nascimento, nome_responsavel
  mensagem      text not null check (char_length(mensagem) <= 300),
  criado_em     timestamptz not null default now(),
  resolvida_em  timestamptz,
  resolvida_por uuid references public.perfis(id)
);
create index on public.pendencias_cadastro (familia_id) where resolvida_em is null;

-- RLS: mesmas regras de quem vê os responsáveis da família
alter table public.responsaveis_criancas enable row level security;
alter table public.pendencias_cadastro  enable row level security;

create policy resp_cri_ler on public.responsaveis_criancas for select to authenticated using (
  exists (select 1 from public.criancas c where c.id = crianca_id and (
    c.familia_id in (select private.minhas_familias())
    or private.e_recepcao(private.dept_familia(c.familia_id))
    or c.familia_id in (select private.familias_visiveis_hoje()))));
create policy resp_cri_criar on public.responsaveis_criancas for insert to authenticated with check (
  exists (select 1 from public.criancas c where c.id = crianca_id and (
    c.familia_id in (select private.minhas_familias())
    or private.e_recepcao(private.dept_familia(c.familia_id)))));
create policy resp_cri_editar on public.responsaveis_criancas for update to authenticated
  using (exists (select 1 from public.criancas c where c.id = crianca_id and (
    c.familia_id in (select private.minhas_familias())
    or private.e_recepcao(private.dept_familia(c.familia_id)))))
  with check (exists (select 1 from public.criancas c where c.id = crianca_id and (
    c.familia_id in (select private.minhas_familias())
    or private.e_recepcao(private.dept_familia(c.familia_id)))));
create policy resp_cri_apagar on public.responsaveis_criancas for delete to authenticated using (
  exists (select 1 from public.criancas c where c.id = crianca_id and (
    c.familia_id in (select private.minhas_familias())
    or private.e_lider(private.dept_familia(c.familia_id)))));

create policy pend_ler on public.pendencias_cadastro for select to authenticated using (
  familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));
create policy pend_criar on public.pendencias_cadastro for insert to authenticated with check (
  private.e_recepcao(private.dept_familia(familia_id)));
create policy pend_resolver on public.pendencias_cadastro for update to authenticated
  using (familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)))
  with check (familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));
create policy pend_apagar on public.pendencias_cadastro for delete to authenticated using (
  private.e_lider(private.dept_familia(familia_id)));

grant select, insert, update, delete on public.responsaveis_criancas, public.pendencias_cadastro to authenticated;
revoke all on public.responsaveis_criancas, public.pendencias_cadastro from anon;

create trigger responsaveis_criancas_auditoria after insert or update or delete on public.responsaveis_criancas
  for each row execute function private.auditar();
create trigger pendencias_cadastro_auditoria after insert or update or delete on public.pendencias_cadastro
  for each row execute function private.auditar();
