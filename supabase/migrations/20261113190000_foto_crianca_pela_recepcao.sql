-- =====================================================================
-- 0.29.0 – A recepção (voluntárias do check-in) pode trocar a foto da
-- criança na tela de check-in ("Corrigir dados").
-- Antes: só a família, a liderança e pastores/admin.
-- private.e_recepcao() já inclui a liderança do departamento.
-- A troca continua avisando a liderança (gravar_foto) e fica na auditoria.
-- =====================================================================
create or replace function public.alvo_foto(p_tipo text, p_id uuid)
returns table(pessoa_id uuid, foto_atual text, pasta text)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_eu uuid := private.minha_pessoa();
begin
  if v_eu is null then raise exception 'Conclua o primeiro acesso antes de continuar'; end if;
  if p_tipo = 'eu' then
    return query select p.id, p.foto_public_id, 'pessoas/adultos'::text from public.pessoas p where p.id = v_eu;
  elsif p_tipo = 'crianca' then
    return query
      select p.id, p.foto_public_id, 'pessoas/criancas'::text
      from public.criancas c join public.pessoas p on p.id = c.pessoa_id
      where c.id = p_id
        and (c.familia_id in (select private.minhas_familias())
             or private.e_recepcao(private.dept_familia(c.familia_id))
             or private.e_pastor_ou_admin());
  end if;
  if not found then raise exception 'Sem permissão para trocar esta foto'; end if;
end;
$$;
revoke all on function public.alvo_foto(text, uuid) from public, anon;
grant execute on function public.alvo_foto(text, uuid) to authenticated;
