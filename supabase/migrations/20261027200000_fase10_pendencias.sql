-- =====================================================================
-- Fase 10 · Etapa 5D – Pendências de cadastro (27/10/2026)
--
-- 1. listar_pendencias(situacao): lista para a tela de pendências
--    (recepção, liderança, pastores, admin: o departamento; responsável:
--    só a própria família). Traz nome da criança, nome da família
--    (responsável principal) e quem resolveu.
-- 2. confirmar_pendencia(): continua aceitando o responsável da família
--    e a recepção/liderança; quando quem resolve é o responsável
--    (sem papel de recepção no departamento), avisa a liderança no sino.
-- 3. Sem gravação direta: resolver só pela confirmar_pendencia() (fica
--    registrado quem e quando). Criar pendência manual continua com a
--    recepção; apagar, com a liderança. Os gatilhos automáticos não mudam.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Lista
-- ---------------------------------------------------------------------
create or replace function public.listar_pendencias(p_situacao text default 'abertas')
returns table (
  id uuid,
  tipo text,
  mensagem text,
  automatica boolean,
  criado_em timestamptz,
  resolvida_em timestamptz,
  resolvida_por_nome text,
  familia_id uuid,
  familia_nome text,
  crianca_id uuid,
  crianca_nome text
)
language sql
stable
security definer
set search_path = ''
as $$
  with visiveis as (
    select p.*
    from public.pendencias_cadastro p
    where (p.familia_id in (select private.minhas_familias())
           or private.e_recepcao(private.dept_familia(p.familia_id)))
      and case when p_situacao = 'resolvidas' then p.resolvida_em is not null
               else p.resolvida_em is null end
    order by case when p_situacao = 'resolvidas' then p.resolvida_em end desc nulls last,
             p.criado_em
    limit case when p_situacao = 'resolvidas' then 300 else 2000 end
  )
  select v.id, v.tipo, v.mensagem,
         v.tipo in ('relacao_nao_informada', 'nascimento_vazio'),
         v.criado_em, v.resolvida_em,
         (select pe.nome from public.perfis pf join public.pessoas pe on pe.id = pf.pessoa_id
           where pf.id = v.resolvida_por),
         v.familia_id,
         (select pe.nome from public.responsaveis r join public.pessoas pe on pe.id = r.pessoa_id
           where r.familia_id = v.familia_id
           order by r.principal desc, pe.nome limit 1),
         v.crianca_id,
         (select pe.nome from public.criancas c join public.pessoas pe on pe.id = c.pessoa_id
           where c.id = v.crianca_id)
  from visiveis v
$$;
revoke all on function public.listar_pendencias(text) from public, anon;
grant execute on function public.listar_pendencias(text) to authenticated;

-- ---------------------------------------------------------------------
-- 2. Resolver (pendências manuais)
-- ---------------------------------------------------------------------
create or replace function public.confirmar_pendencia(p_pendencia uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v public.pendencias_cadastro%rowtype;
  v_equipe boolean;
  v_nome text;
  v_assunto text;
begin
  select * into v from public.pendencias_cadastro where id = p_pendencia and resolvida_em is null;
  if not found then
    raise exception 'Pendência não encontrada ou sem permissão';
  end if;
  v_equipe := private.e_recepcao(private.dept_familia(v.familia_id));
  if not (v_equipe or v.familia_id in (select private.minhas_familias())) then
    raise exception 'Pendência não encontrada ou sem permissão';
  end if;
  if v.tipo in ('relacao_nao_informada', 'nascimento_vazio') then
    raise exception 'Este aviso some sozinho quando o dado for preenchido';
  end if;

  update public.pendencias_cadastro
     set resolvida_em = now(), resolvida_por = auth.uid()
   where id = p_pendencia;

  -- Resolvida pelo responsável: a liderança fica sabendo
  if not v_equipe then
    select nome into v_nome from public.pessoas where id = private.minha_pessoa();
    v_assunto := case v.tipo
      when 'conferir_nascimento' then 'conferir a data de nascimento'
      when 'nome_responsavel'    then 'conferir o nome do responsável'
      else 'uma pendência do cadastro' end;
    perform private.avisar_lideranca_kids('Pendência resolvida pela família',
      coalesce(v_nome, 'Um responsável') || ' marcou como resolvida: ' || v_assunto || '.',
      '#/ficha?tipo=familia&id=' || v.familia_id, 'pendencia_resolvida');
  end if;
  return 'pendência resolvida';
end $$;
revoke all on function public.confirmar_pendencia(uuid) from public, anon;
grant execute on function public.confirmar_pendencia(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Sem alteração direta pelo app (só pelas funções e gatilhos)
-- ---------------------------------------------------------------------
drop policy if exists pend_editar on public.pendencias_cadastro;
revoke update on public.pendencias_cadastro from authenticated;
