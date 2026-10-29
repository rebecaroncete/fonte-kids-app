-- Fase 3 concluída: as 259 fotos (210 crianças + 49 voluntárias) estão no
-- Cloudinary privado e foto_public_id está preenchido em todos os registros.
-- O link antigo do Google Drive (temporário desde a Fase 2) deixa de existir.
alter table public.criancas    drop column foto_legado_url;
alter table public.voluntarias drop column foto_legado_url;
