-- =====================================================================
-- Fase 4 · Etapa 2 (parte 2/3) – Migração dos cadastros para "pessoas"
-- Só lógica; nenhum dado pessoal neste arquivo.
-- Regras (aprovadas em 26/10/2026):
--   * junta AUTOMATICAMENTE só com critério forte:
--       - mesmo telefone + nomes compatíveis, ou
--       - mesmo nome + mesma data de nascimento;
--   * casos duvidosos NÃO são juntados: vão para possiveis_duplicidades;
--   * o id da pessoa é o mesmo id do cadastro de origem (criança/voluntária/
--     responsável), então o identificador da foto no Cloudinary
--     (pessoas/criancas/<id>, pessoas/voluntarias/<id>) continua batendo;
--   * a foto é copiada (foto_public_id); nada é reenviado ao Cloudinary.
-- =====================================================================
do $$
declare
  r record;
  v_cands uuid[];
  v_nome text;
begin
  -- 1) Crianças: uma pessoa por criança (crianças repetidas só vão para conferência)
  insert into public.pessoas (id, igreja_id, nome, data_nascimento, sexo, foto_public_id, criado_por, criado_em)
  select c.id, d.igreja_id, c.nome, c.data_nascimento, c.sexo, c.foto_public_id, null, c.criado_em
  from public.criancas c
  join public.familias f on f.id = c.familia_id
  join public.departamentos d on d.id = f.departamento_id;
  update public.criancas set pessoa_id = id;

  -- 2) Voluntárias
  for r in
    select v.id, v.nome, v.telefone, v.data_nascimento, v.sexo, v.foto_public_id, v.criado_em,
           v.departamento_id, d.igreja_id
    from public.voluntarias v join public.departamentos d on d.id = v.departamento_id
    order by v.criado_em, v.id
  loop
    v_nome := private.normalizar_nome(r.nome);
    select array_agg(p.id) into v_cands
    from public.pessoas p
    where p.igreja_id = r.igreja_id
      and ((r.telefone is not null and p.telefone = r.telefone and private.nomes_compativeis(p.nome_busca, v_nome))
        or (r.data_nascimento is not null and p.data_nascimento = r.data_nascimento and p.nome_busca = v_nome))
      and not exists (select 1 from public.voluntarias x
                      where x.pessoa_id = p.id and x.departamento_id = r.departamento_id);
    if coalesce(array_length(v_cands, 1), 0) = 1 then
      update public.pessoas p set
        telefone        = coalesce(p.telefone, r.telefone),
        data_nascimento = coalesce(p.data_nascimento, r.data_nascimento),
        sexo            = coalesce(p.sexo, r.sexo),
        foto_public_id  = coalesce(p.foto_public_id, r.foto_public_id)
      where p.id = v_cands[1];
      update public.voluntarias set pessoa_id = v_cands[1] where id = r.id;
    else
      insert into public.pessoas (id, igreja_id, nome, telefone, data_nascimento, sexo, foto_public_id, criado_por, criado_em)
      values (r.id, r.igreja_id, r.nome, r.telefone, r.data_nascimento, r.sexo, r.foto_public_id, null, r.criado_em);
      update public.voluntarias set pessoa_id = r.id where id = r.id;
    end if;
  end loop;

  -- 3) Responsáveis (sem data de nascimento na planilha: só a regra do telefone)
  for r in
    select x.id, x.nome, x.telefone, x.criado_em, x.familia_id, d.igreja_id
    from public.responsaveis x
    join public.familias f on f.id = x.familia_id
    join public.departamentos d on d.id = f.departamento_id
    order by x.principal desc, x.criado_em, x.id
  loop
    v_nome := private.normalizar_nome(r.nome);
    select array_agg(p.id) into v_cands
    from public.pessoas p
    where p.igreja_id = r.igreja_id
      and r.telefone is not null and p.telefone = r.telefone
      and private.nomes_compativeis(p.nome_busca, v_nome)
      and not exists (select 1 from public.responsaveis y
                      where y.pessoa_id = p.id and y.familia_id = r.familia_id);
    if coalesce(array_length(v_cands, 1), 0) = 1 then
      update public.responsaveis set pessoa_id = v_cands[1] where id = r.id;
    else
      insert into public.pessoas (id, igreja_id, nome, telefone, criado_por, criado_em)
      values (r.id, r.igreja_id, r.nome, r.telefone, null, r.criado_em);
      update public.responsaveis set pessoa_id = r.id where id = r.id;
    end if;
  end loop;

  -- 4) Pessoas autorizadas a buscar (tabela vazia hoje; mantido por segurança)
  insert into public.pessoas (id, igreja_id, nome, telefone, criado_por, criado_em)
  select a.id, d.igreja_id, a.nome, a.telefone, null, a.criado_em
  from public.pessoas_autorizadas a
  join public.familias f on f.id = a.familia_id
  join public.departamentos d on d.id = f.departamento_id;
  update public.pessoas_autorizadas set pessoa_id = id, observacao = left(parentesco, 120);

  -- 5) Pares duvidosos para conferência manual
  perform private.detectar_duplicidades();
end $$;
