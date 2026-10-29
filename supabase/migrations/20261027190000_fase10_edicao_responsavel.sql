-- =====================================================================
-- Fase 10 · Etapa 5C (extensão) – edição pelo responsável
-- Decidido em 27/10/2026: a alteração vale na hora, fica na auditoria e a
-- liderança do Fonte Kids (e a admin) recebe um aviso no sino.
--
-- O responsável grava SÓ por estas funções (que conferem a família):
--   editar_meu_perfil(nome, nascimento)
--   editar_crianca(criança, nome, nascimento, alergias)
--   incluir_autorizado(família, nome, telefone, observação)
--   remover_autorizado(autorizado)
-- Fotos: alvo_foto() (confere a permissão, chamada pela Edge Function
-- "enviar-foto" com o token do usuário) e gravar_foto() (só service_role).
-- Foto do responsável: fotos_pessoas() (ele mesmo, a própria família,
-- recepção/liderança do departamento, pastor/admin).
--
-- Reforço: gravação direta pelo app (sem estas funções) fica proibida para
--   * sala fixa / ativo / perfil / família da criança, se não for
--     recepção ou liderança do departamento;
--   * foto de qualquer pessoa (só pela Edge Function), salvo admin;
--   * telefone de quem tem login, salvo liderança ou admin.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Aviso no sino para a liderança do Fonte Kids e a admin
-- ---------------------------------------------------------------------
create or replace function private.avisar_lideranca_kids(p_titulo text, p_corpo text, p_link text, p_tipo text)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por)
  select distinct pu.perfil_id, p_titulo, p_corpo, p_link, p_tipo, auth.uid()
  from public.papeis_usuario pu
  join public.perfis p on p.id = pu.perfil_id and p.ativo
  where pu.perfil_id is distinct from auth.uid()
    and (pu.papel = 'admin'
         or (pu.papel = 'lider'
             and pu.departamento_id = (select id from public.departamentos where slug = 'kids' limit 1)));
$$;
revoke all on function private.avisar_lideranca_kids(text, text, text, text) from public, anon, authenticated;

-- Texto curto com os campos alterados ("nome e data de nascimento")
create or replace function private.lista_campos(p text[])
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce(array_length(p, 1), 0) = 0 then ''
    when array_length(p, 1) = 1 then p[1]
    else array_to_string(p[1:array_length(p, 1) - 1], ', ') || ' e ' || p[array_length(p, 1)]
  end
$$;

-- ---------------------------------------------------------------------
-- 2. Editar o próprio perfil (nome e data de nascimento)
-- ---------------------------------------------------------------------
create or replace function public.editar_meu_perfil(p_nome text, p_nascimento date)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eu uuid := private.minha_pessoa();
  v_old public.pessoas%rowtype;
  v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
  v_campos text[] := '{}';
  v_link text;
begin
  if v_eu is null then raise exception 'Conclua o primeiro acesso antes de continuar'; end if;
  if char_length(v_nome) < 3 or char_length(v_nome) > 120 then
    raise exception 'Informe o nome completo (de 3 a 120 letras)';
  end if;
  if p_nascimento is not null and (p_nascimento > private.hoje() or p_nascimento < date '1900-01-01') then
    raise exception 'Data de nascimento inválida';
  end if;

  select * into v_old from public.pessoas where id = v_eu;
  if v_old.nome is distinct from v_nome then v_campos := array_append(v_campos, 'nome'); end if;
  if p_nascimento is not null and v_old.data_nascimento is distinct from p_nascimento then
    v_campos := array_append(v_campos, 'data de nascimento');
  end if;
  if array_length(v_campos, 1) is null then return 'sem alterações'; end if;

  update public.pessoas
     set nome = v_nome, data_nascimento = coalesce(p_nascimento, data_nascimento)
   where id = v_eu;

  select '#/ficha?tipo=familia&id=' || r.familia_id into v_link
  from public.responsaveis r where r.pessoa_id = v_eu limit 1;
  if v_link is null then
    select '#/ficha?tipo=voluntaria&id=' || v.id into v_link
    from public.voluntarias v where v.pessoa_id = v_eu limit 1;
  end if;

  perform private.avisar_lideranca_kids('Perfil atualizado',
    v_nome || ' alterou ' || private.lista_campos(v_campos) || ' no próprio perfil.', v_link, 'cadastro_editado');
  return 'ok';
end;
$$;
revoke all on function public.editar_meu_perfil(text, date) from public, anon;
grant execute on function public.editar_meu_perfil(text, date) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Editar dados da criança (nome, nascimento, alergias e cuidados)
-- ---------------------------------------------------------------------
create or replace function public.editar_crianca(p_crianca uuid, p_nome text, p_nascimento date, p_alergias text)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eu uuid := private.minha_pessoa();
  v_c public.criancas%rowtype;
  v_p public.pessoas%rowtype;
  v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
  v_alerg text := nullif(btrim(coalesce(p_alergias, '')), '');
  v_campos text[] := '{}';
  v_quem text;
begin
  if v_eu is null then raise exception 'Conclua o primeiro acesso antes de continuar'; end if;
  select * into v_c from public.criancas where id = p_crianca;
  if not found or v_c.familia_id not in (select private.minhas_familias()) then
    raise exception 'Criança não encontrada ou sem permissão';
  end if;
  if char_length(v_nome) < 3 or char_length(v_nome) > 120 then
    raise exception 'Informe o nome completo (de 3 a 120 letras)';
  end if;
  if p_nascimento is null or p_nascimento > private.hoje() or p_nascimento <= private.hoje() - interval '18 years' then
    raise exception 'Data de nascimento inválida para uma criança';
  end if;
  if char_length(coalesce(v_alerg, '')) > 500 then
    raise exception 'Alergias e cuidados: use no máximo 500 caracteres';
  end if;

  select * into v_p from public.pessoas where id = v_c.pessoa_id;
  if v_p.nome is distinct from v_nome then v_campos := array_append(v_campos, 'nome'); end if;
  if v_p.data_nascimento is distinct from p_nascimento then v_campos := array_append(v_campos, 'data de nascimento'); end if;
  if v_c.alergias_observacoes is distinct from v_alerg then v_campos := array_append(v_campos, 'alergias e cuidados'); end if;
  if array_length(v_campos, 1) is null then return 'sem alterações'; end if;

  update public.pessoas set nome = v_nome, data_nascimento = p_nascimento
   where id = v_c.pessoa_id and (nome is distinct from v_nome or data_nascimento is distinct from p_nascimento);
  update public.criancas set alergias_observacoes = v_alerg
   where id = p_crianca and alergias_observacoes is distinct from v_alerg;

  select nome into v_quem from public.pessoas where id = v_eu;
  perform private.avisar_lideranca_kids('Dados de criança atualizados',
    coalesce(v_quem, 'Um responsável') || ' alterou ' || private.lista_campos(v_campos) || ' de ' || v_nome || '.',
    '#/ficha?tipo=crianca&id=' || p_crianca, 'cadastro_editado');
  return 'ok';
end;
$$;
revoke all on function public.editar_crianca(uuid, text, date, text) from public, anon;
grant execute on function public.editar_crianca(uuid, text, date, text) to authenticated;

-- ---------------------------------------------------------------------
-- 4. Autorizados a retirar: incluir e remover
-- ---------------------------------------------------------------------
create or replace function public.incluir_autorizado(p_familia uuid, p_nome text, p_telefone text, p_observacao text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eu uuid := private.minha_pessoa();
  v_nome text := regexp_replace(btrim(coalesce(p_nome, '')), '\s+', ' ', 'g');
  v_tel text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_obs text := nullif(btrim(coalesce(p_observacao, '')), '');
  v_igreja uuid;
  v_pessoa uuid;
  v_aut uuid;
  v_quem text;
begin
  if v_eu is null then raise exception 'Conclua o primeiro acesso antes de continuar'; end if;
  if p_familia is null or p_familia not in (select private.minhas_familias()) then
    raise exception 'Família não encontrada ou sem permissão';
  end if;
  if char_length(v_nome) < 3 or char_length(v_nome) > 120 then
    raise exception 'Informe o nome completo (de 3 a 120 letras)';
  end if;
  if char_length(v_tel) in (10, 11) then v_tel := '55' || v_tel; end if;
  if v_tel !~ '^55[1-9][0-9]9?[0-9]{8}$' then
    raise exception 'Telefone inválido: use DDD + número';
  end if;
  if char_length(coalesce(v_obs, '')) > 120 then
    raise exception 'Observação: use no máximo 120 caracteres';
  end if;
  if (select count(*) from public.pessoas_autorizadas where familia_id = p_familia) >= 10 then
    raise exception 'Limite de 10 pessoas autorizadas por família. Remova alguém antes de incluir.';
  end if;

  select d.igreja_id into v_igreja
  from public.familias f join public.departamentos d on d.id = f.departamento_id
  where f.id = p_familia;

  insert into public.pessoas (igreja_id, nome, telefone, criado_por)
  values (v_igreja, v_nome, v_tel, auth.uid())
  returning id into v_pessoa;
  insert into public.pessoas_autorizadas (familia_id, pessoa_id, observacao)
  values (p_familia, v_pessoa, v_obs)
  returning id into v_aut;

  select nome into v_quem from public.pessoas where id = v_eu;
  perform private.avisar_lideranca_kids('Autorizado a retirar incluído',
    coalesce(v_quem, 'Um responsável') || ' incluiu ' || v_nome || ' como autorizado(a) a retirar as crianças.',
    '#/ficha?tipo=familia&id=' || p_familia, 'cadastro_editado');
  return v_aut;
end;
$$;
revoke all on function public.incluir_autorizado(uuid, text, text, text) from public, anon;
grant execute on function public.incluir_autorizado(uuid, text, text, text) to authenticated;

create or replace function public.remover_autorizado(p_autorizado uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_eu uuid := private.minha_pessoa();
  v_fam uuid;
  v_nome text;
  v_quem text;
begin
  if v_eu is null then raise exception 'Conclua o primeiro acesso antes de continuar'; end if;
  select a.familia_id, p.nome into v_fam, v_nome
  from public.pessoas_autorizadas a join public.pessoas p on p.id = a.pessoa_id
  where a.id = p_autorizado;
  if v_fam is null or v_fam not in (select private.minhas_familias()) then
    raise exception 'Autorizado não encontrado ou sem permissão';
  end if;

  delete from public.pessoas_autorizadas where id = p_autorizado; -- a pessoa sem outro vínculo é apagada pelo gatilho

  select nome into v_quem from public.pessoas where id = v_eu;
  perform private.avisar_lideranca_kids('Autorizado a retirar removido',
    coalesce(v_quem, 'Um responsável') || ' removeu ' || coalesce(v_nome, 'uma pessoa') || ' dos autorizados a retirar as crianças.',
    '#/ficha?tipo=familia&id=' || v_fam, 'cadastro_editado');
  return 'ok';
end;
$$;
revoke all on function public.remover_autorizado(uuid) from public, anon;
grant execute on function public.remover_autorizado(uuid) to authenticated;

-- ---------------------------------------------------------------------
-- 5. Fotos
-- ---------------------------------------------------------------------
-- 5a. Foto do responsável (por id da PESSOA)
create or replace function public.fotos_pessoas(p_ids uuid[])
returns table(id uuid, foto_public_id text)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.foto_public_id
  from public.pessoas p
  where p.id = any (p_ids) and p.foto_public_id is not null
    and (p.id = (select private.minha_pessoa())
      or private.e_pastor_ou_admin()
      or exists (select 1 from public.responsaveis r where r.pessoa_id = p.id and (
           r.familia_id in (select private.minhas_familias())
           or private.e_recepcao(private.dept_familia(r.familia_id)))))
$$;
revoke all on function public.fotos_pessoas(uuid[]) from public, anon;
grant execute on function public.fotos_pessoas(uuid[]) to authenticated;

-- 5b. Quem pode trocar qual foto (chamada pela Edge Function COM o token do usuário)
--     p_tipo: 'eu' (própria foto) | 'crianca' (p_id = id da criança)
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
             or private.e_lider(private.dept_familia(c.familia_id))
             or private.e_pastor_ou_admin());
  end if;
  if not found then raise exception 'Sem permissão para trocar esta foto'; end if;
end;
$$;
revoke all on function public.alvo_foto(text, uuid) from public, anon;
grant execute on function public.alvo_foto(text, uuid) to authenticated;

-- 5c. Grava a foto nova (só a Edge Function, com service_role)
create or replace function public.gravar_foto(p_perfil uuid, p_pessoa uuid, p_public_id text, p_tipo text, p_crianca uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare v_quem text; v_nome text; v_link text;
begin
  -- a auditoria registra quem trocou a foto
  perform set_config('request.jwt.claims', json_build_object('sub', p_perfil, 'role', 'authenticated')::text, true);
  update public.pessoas set foto_public_id = p_public_id where id = p_pessoa;

  select p.nome into v_quem from public.perfis f join public.pessoas p on p.id = f.pessoa_id where f.id = p_perfil;
  select nome into v_nome from public.pessoas where id = p_pessoa;
  if p_tipo = 'crianca' then
    v_link := '#/ficha?tipo=crianca&id=' || p_crianca;
  else
    select '#/ficha?tipo=familia&id=' || r.familia_id into v_link from public.responsaveis r where r.pessoa_id = p_pessoa limit 1;
  end if;
  perform private.avisar_lideranca_kids('Foto atualizada',
    coalesce(v_quem, 'Uma pessoa') || case when p_tipo = 'crianca' then ' trocou a foto de ' || coalesce(v_nome, 'uma criança') || '.'
                                           else ' trocou a própria foto.' end,
    v_link, 'cadastro_editado');
end;
$$;
revoke all on function public.gravar_foto(uuid, uuid, text, text, uuid) from public, anon, authenticated;
grant execute on function public.gravar_foto(uuid, uuid, text, text, uuid) to service_role;

-- ---------------------------------------------------------------------
-- 6. Reforço das travas para gravação direta pelo app
-- ---------------------------------------------------------------------
create or replace function private.trava_pessoas()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.chamada_do_app() then return new; end if;
  if tg_op = 'INSERT' then
    new.criado_por := auth.uid();
    if new.foto_public_id is not null and not private.e_admin() then
      raise exception 'A foto é enviada pelo app, depois do cadastro';
    end if;
  elsif not private.e_admin() and (
       new.igreja_id is distinct from old.igreja_id or
       new.criado_por is distinct from old.criado_por) then
    raise exception 'Sem permissão para alterar estes campos da pessoa';
  elsif not private.e_admin() and new.foto_public_id is distinct from old.foto_public_id then
    raise exception 'A foto só pode ser trocada pelo envio de foto do app';
  elsif new.telefone is distinct from old.telefone
        and exists (select 1 from public.perfis f where f.pessoa_id = old.id)
        and not (private.e_admin() or private.e_lider_algum()) then
    raise exception 'O telefone de quem tem login só pode ser trocado pela liderança';
  end if;
  return new;
end $$;

create or replace function private.trava_dados_crianca()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if not private.chamada_do_app() or private.e_recepcao(private.dept_familia(old.familia_id)) then
    return new;
  end if;
  if new.sala_fixa_id is distinct from old.sala_fixa_id
     or new.ativo is distinct from old.ativo
     or new.perfil is distinct from old.perfil
     or new.familia_id is distinct from old.familia_id then
    raise exception 'Sem permissão para alterar estes campos da criança';
  end if;
  return new;
end $$;

drop trigger if exists criancas_trava_dados on public.criancas;
create trigger criancas_trava_dados before update on public.criancas
  for each row execute function private.trava_dados_crianca();
