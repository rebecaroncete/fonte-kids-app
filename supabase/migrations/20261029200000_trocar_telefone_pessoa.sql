-- =====================================================================
-- 0.28.1 · Trocar telefone (contato + login) pelo servidor
-- A Edge Function gerenciar-login ("trocar_telefone") troca o e-mail
-- técnico no Auth e chama esta função para gravar o telefone novo em
-- perfis e pessoas na MESMA transação. Ela existe porque a chave de
-- serviço não enxerga o schema private, onde ficam os gatilhos dessas
-- tabelas: o update direto pela API dava "permission denied".
-- Só a chave de serviço chama (quem pode trocar é conferido na função).
-- =====================================================================
create or replace function public.trocar_telefone_pessoa(p_pessoa uuid, p_telefone text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_telefone !~ '^55[0-9]{10,11}$' then
    raise exception 'Telefone fora do padrão 55 + DDD + número';
  end if;
  update public.perfis set telefone = p_telefone where pessoa_id = p_pessoa;
  update public.pessoas set telefone = p_telefone where id = p_pessoa;
  if not found then
    raise exception 'Pessoa não encontrada';
  end if;
end $$;

revoke all on function public.trocar_telefone_pessoa(uuid, text) from public, anon, authenticated;
grant execute on function public.trocar_telefone_pessoa(uuid, text) to service_role;
