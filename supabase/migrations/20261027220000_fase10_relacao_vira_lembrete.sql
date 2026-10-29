-- =====================================================================
-- Fase 10 · Etapa 7 – "Relação não informada" deixa de ser pendência
-- (decidido em 27/10/2026)
-- Quem é só responsável não é obrigado a usar o app nesse primeiro
-- momento (só incentivado). A relação com a criança vira lembrete para
-- quem entra no app (Início e "Minha família"), não pendência de cadastro.
-- Pendências de voluntárias sem acesso ao app são montadas pela tela a
-- partir de situacao_logins() (só liderança do Fonte Kids, pastores, admin);
-- nada novo no banco para isso.
-- Continuam como pendência: nascimento_vazio (automática) e as manuais
-- (conferir_nascimento, nome_responsavel).
-- =====================================================================

-- 1) Pendências automáticas: só "nascimento_vazio". As de relação que
--    ainda estiverem abertas são fechadas aqui também (por segurança).
create or replace function private.atualizar_pendencias(p_familia uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_familia is null then return; end if;

  insert into public.pendencias_cadastro (familia_id, crianca_id, tipo, mensagem)
  select c.familia_id, c.id, 'nascimento_vazio', 'Falta a data de nascimento desta criança.'
  from public.criancas c join public.pessoas pe on pe.id = c.pessoa_id
  where c.familia_id = p_familia and c.ativo and pe.data_nascimento is null
    and not exists (select 1 from public.pendencias_cadastro p
                    where p.crianca_id = c.id and p.tipo = 'nascimento_vazio' and p.resolvida_em is null);

  update public.pendencias_cadastro p
     set resolvida_em = now(), resolvida_por = auth.uid()
   where p.familia_id = p_familia and p.resolvida_em is null
     and p.tipo = 'nascimento_vazio'
     and not exists (select 1 from public.criancas c join public.pessoas pe on pe.id = c.pessoa_id
                     where c.id = p.crianca_id and c.familia_id = p_familia and c.ativo
                       and pe.data_nascimento is null);

  delete from public.pendencias_cadastro p
   where p.familia_id = p_familia and p.resolvida_em is null and p.tipo = 'relacao_nao_informada';
end $$;

-- 2) Apaga as pendências de relação ainda abertas (eram 208 em 27/10/2026).
--    O histórico das já resolvidas fica.
delete from public.pendencias_cadastro
 where tipo = 'relacao_nao_informada' and resolvida_em is null;
