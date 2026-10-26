-- =====================================================================
-- Fase 4 · Etapa 2 – ajuste encontrado pelo teste de segurança
-- Quem cadastrou a pessoa a vê já no mesmo comando (insert ... returning):
-- a checagem é feita na própria linha, não por consulta à tabela
-- (a consulta não enxerga a linha que acabou de ser criada).
-- =====================================================================
drop policy pessoas_ler on public.pessoas;
create policy pessoas_ler on public.pessoas for select to authenticated
  using (criado_por = (select auth.uid()) or private.pode_ver_pessoa(id));
