-- Fase 2 – campos que a planilha tem e o banco ainda não tinha.
-- (Aplicar só após o OK da Rebeca para a importação.)

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
