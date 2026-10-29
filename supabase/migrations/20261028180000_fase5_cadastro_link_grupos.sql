-- =====================================================================
-- Fase 5 · Etapa 5D – Cadastro pelo link público + convites + grupos de
-- WhatsApp + "Adicionar criança" (decisões 77, 81, 87, 91, 92 e as de
-- 28/10/2026: todos os responsáveis com telefone ganham login; até 100
-- cadastros por dia; família nova aparece na hora para a recepção;
-- telefone já cadastrado é avisado e a família adiciona criança pelo app).
--
-- SEGURANÇA DO CADASTRO SEM LOGIN
--  * Quem não tem login NÃO chama nada daqui. As funções do cadastro
--    público só podem ser executadas pela chave de serviço (service_role),
--    usada apenas pela Edge Function "cadastro-publico", que confere o
--    captcha (Turnstile) no servidor antes.
--  * O banco valida tudo de novo (nomes, telefones, datas, quantidades,
--    versão do termo) e grava tudo de uma vez (ou nada).
--  * Limite: 100 cadastros pelo link a cada 24 h (private.cadastros_link
--    guarda só a família e a hora).
--  * Telefone já cadastrado (de um responsável ou de um login) → recusado
--    com a mensagem "telefone_ja_cadastrado" (a família entra no app e usa
--    "Adicionar criança").
--  * Crianças de 0 a 12 anos (o Fonte Kids atende até 12).
-- =====================================================================

-- ---------- Registro dos cadastros pelo link (para o limite diário) ----------
create table if not exists private.cadastros_link (
  id bigint generated always as identity primary key,
  familia_id uuid not null references public.familias(id) on delete cascade,
  criado_em timestamptz not null default now()
);
create index if not exists cadastros_link_criado_em on private.cadastros_link (criado_em);
alter table private.cadastros_link enable row level security;
revoke all on private.cadastros_link from public, anon, authenticated;

-- ---------- Telefone já cadastrado? ----------
-- Conta: telefone de um responsável já cadastrado ou de um login existente.
create or replace function private.telefone_ja_cadastrado(p_tel text)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.pessoas p join public.responsaveis r on r.pessoa_id = p.id
                 where p.telefone = p_tel)
      or exists (select 1 from public.perfis f where f.telefone = p_tel)
$$;

create or replace function private.normalizar_telefone(p text)
returns text language plpgsql immutable set search_path = '' as $$
declare d text := regexp_replace(coalesce(p, ''), '\D', '', 'g');
begin
  if d = '' then return null; end if;
  if char_length(d) in (12, 13) and left(d, 2) = '55' then d := substr(d, 3); end if;
  if char_length(d) not in (10, 11) or left(d, 1) = '0' then return 'invalido'; end if;
  d := '55' || d;
  if d !~ '^55[1-9][0-9]9?[0-9]{8}$' then return 'invalido'; end if;
  return d;
end $$;

create or replace function private.nome_limpo(p text)
returns text language sql immutable set search_path = '' as $$
  select regexp_replace(btrim(coalesce(p, '')), '\s+', ' ', 'g')
$$;

-- ---------- 1) Verificar telefone (só a Edge Function) ----------
-- Devolve: { existe: true|false } e, se não existe, o termo vigente.
create or replace function public.cadastro_link_verificar(p_telefone text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_tel text := private.normalizar_telefone(p_telefone); v_termo record;
begin
  if v_tel is null or v_tel = 'invalido' then raise exception 'telefone_invalido'; end if;
  if private.telefone_ja_cadastrado(v_tel) then
    return jsonb_build_object('existe', true);
  end if;
  select versao, texto into v_termo from public.termos_lgpd_versoes where vigente limit 1;
  return jsonb_build_object('existe', false,
    'termo', case when v_termo.versao is null then null
                  else jsonb_build_object('versao', v_termo.versao, 'texto', v_termo.texto) end);
end $$;

-- ---------- 2) Cadastrar a família (só a Edge Function) ----------
-- p_dados = {
--   "responsaveis": [{ "nome", "telefone" }]   (1 ou 2; o 1º é o principal; telefone do 1º obrigatório)
--   "criancas": [{ "nome", "nascimento": "AAAA-MM-DD", "alergias", "perfil": "membro"|"visitante",
--                  "relacao", "relacao_detalhe", "relacao2", "relacao2_detalhe" }]   (1 a 10)
--   "autorizados": [{ "nome", "telefone", "observacao" }]   (0 a 10)
--   "termo_versao": "v1"
-- }
-- Devolve (só para a Edge Function): família, quem ganha login, pessoas das
-- crianças (na ordem enviada) e os links dos grupos certos pela idade.
create or replace function public.cadastrar_familia_link(p_dados jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids();
  v_igreja uuid;
  v_hoje date := private.hoje();
  v_resps jsonb := coalesce(p_dados -> 'responsaveis', '[]'::jsonb);
  v_cris  jsonb := coalesce(p_dados -> 'criancas', '[]'::jsonb);
  v_auts  jsonb := coalesce(p_dados -> 'autorizados', '[]'::jsonb);
  v_vigente text;
  v_fam uuid;
  r jsonb; c jsonb; a jsonb;
  i int;
  v_nome text; v_tel text; v_nasc date; v_alerg text; v_perfil text; v_tipo text; v_det text; v_obs text;
  v_resp_pessoas uuid[] := '{}';
  v_resp_ids uuid[] := '{}';
  v_resp_tels text[] := '{}';
  v_pessoa uuid; v_resp uuid; v_cri uuid;
  v_cri_pessoas uuid[] := '{}';
  v_logins jsonb := '[]'::jsonb;
  v_tels_login text[] := '{}';
  v_grupos text[] := '{}';
  v_idade int;
  v_links jsonb := '[]'::jsonb;
  v_principal_nome text;
begin
  if v_dept is null then raise exception 'configuracao'; end if;
  select igreja_id into v_igreja from public.departamentos where id = v_dept;

  -- Limite: 100 cadastros pelo link a cada 24 h
  if (select count(*) from private.cadastros_link where criado_em > now() - interval '24 hours') >= 100 then
    raise exception 'limite_diario';
  end if;

  -- Termo vigente
  select versao into v_vigente from public.termos_lgpd_versoes where vigente limit 1;
  if v_vigente is null or (p_dados ->> 'termo_versao') is distinct from v_vigente then
    raise exception 'termo_desatualizado';
  end if;

  -- Quantidades
  if jsonb_typeof(v_resps) <> 'array' or jsonb_array_length(v_resps) not between 1 and 2 then raise exception 'responsaveis_invalidos'; end if;
  if jsonb_typeof(v_cris) <> 'array' or jsonb_array_length(v_cris) not between 1 and 10 then raise exception 'criancas_invalidas'; end if;
  if jsonb_typeof(v_auts) <> 'array' or jsonb_array_length(v_auts) > 10 then raise exception 'autorizados_invalidos'; end if;

  -- Responsáveis: validação
  for i in 0 .. jsonb_array_length(v_resps) - 1 loop
    r := v_resps -> i;
    v_nome := private.nome_limpo(r ->> 'nome');
    if char_length(v_nome) < 3 or char_length(v_nome) > 120 then raise exception 'nome_responsavel_%', i + 1; end if;
    v_tel := private.normalizar_telefone(r ->> 'telefone');
    if v_tel = 'invalido' or (i = 0 and v_tel is null) then raise exception 'telefone_responsavel_%', i + 1; end if;
    if v_tel is not null then
      perform pg_advisory_xact_lock(hashtext('cadastro_link:' || v_tel));
      if private.telefone_ja_cadastrado(v_tel) then
        raise exception '%', case when i = 0 then 'telefone_ja_cadastrado' else 'telefone2_ja_cadastrado' end;
      end if;
    end if;
    v_resp_tels := v_resp_tels || coalesce(v_tel, '');
  end loop;

  -- Crianças: validação
  for i in 0 .. jsonb_array_length(v_cris) - 1 loop
    c := v_cris -> i;
    v_nome := private.nome_limpo(c ->> 'nome');
    if char_length(v_nome) < 3 or char_length(v_nome) > 120 then raise exception 'nome_crianca_%', i + 1; end if;
    begin v_nasc := (c ->> 'nascimento')::date; exception when others then v_nasc := null; end;
    if v_nasc is null or v_nasc > v_hoje or v_nasc <= (v_hoje - interval '13 years')::date then
      raise exception 'nascimento_crianca_%', i + 1;
    end if;
    if char_length(coalesce(c ->> 'alergias', '')) > 500 then raise exception 'alergias_crianca_%', i + 1; end if;
    if coalesce(c ->> 'perfil', 'membro') not in ('membro', 'visitante') then raise exception 'perfil_crianca_%', i + 1; end if;
    v_tipo := c ->> 'relacao';
    if v_tipo is null or v_tipo not in ('mae','pai','madrasta','padrasto','avo','tio','irmao','responsavel_legal','outro') then
      raise exception 'relacao_crianca_%', i + 1;
    end if;
    v_det := nullif(btrim(coalesce(c ->> 'relacao_detalhe', '')), '');
    if v_tipo = 'outro' and (v_det is null or char_length(v_det) > 60) then raise exception 'relacao_crianca_%', i + 1; end if;
    v_tipo := nullif(c ->> 'relacao2', '');
    if v_tipo is not null then
      if jsonb_array_length(v_resps) < 2
         or v_tipo not in ('mae','pai','madrasta','padrasto','avo','tio','irmao','responsavel_legal','outro') then
        raise exception 'relacao2_crianca_%', i + 1;
      end if;
      v_det := nullif(btrim(coalesce(c ->> 'relacao2_detalhe', '')), '');
      if v_tipo = 'outro' and (v_det is null or char_length(v_det) > 60) then raise exception 'relacao2_crianca_%', i + 1; end if;
    end if;
  end loop;

  -- Autorizados: validação
  for i in 0 .. jsonb_array_length(v_auts) - 1 loop
    a := v_auts -> i;
    v_nome := private.nome_limpo(a ->> 'nome');
    if char_length(v_nome) < 3 or char_length(v_nome) > 120 then raise exception 'nome_autorizado_%', i + 1; end if;
    v_tel := private.normalizar_telefone(a ->> 'telefone');
    if v_tel is null or v_tel = 'invalido' then raise exception 'telefone_autorizado_%', i + 1; end if;
    if char_length(btrim(coalesce(a ->> 'observacao', ''))) > 120 then raise exception 'observacao_autorizado_%', i + 1; end if;
  end loop;

  -- ===== Gravação (tudo ou nada) =====
  insert into public.familias (departamento_id, observacoes)
  values (v_dept, 'Cadastro feito pelo link público') returning id into v_fam;

  for i in 0 .. jsonb_array_length(v_resps) - 1 loop
    r := v_resps -> i;
    v_tel := nullif(v_resp_tels[i + 1], '');
    insert into public.pessoas (igreja_id, nome, telefone, criado_por)
    values (v_igreja, private.nome_limpo(r ->> 'nome'), v_tel, null) returning id into v_pessoa;
    insert into public.responsaveis (familia_id, pessoa_id, principal)
    values (v_fam, v_pessoa, i = 0) returning id into v_resp;
    v_resp_pessoas := v_resp_pessoas || v_pessoa;
    v_resp_ids := v_resp_ids || v_resp;
    if i = 0 then v_principal_nome := private.nome_limpo(r ->> 'nome'); end if;
    -- login para cada telefone diferente (telefone repetido: só o principal)
    if v_tel is not null and not (v_tel = any (v_tels_login)) then
      v_tels_login := v_tels_login || v_tel;
      v_logins := v_logins || jsonb_build_object('pessoa_id', v_pessoa, 'telefone', v_tel, 'principal', i = 0);
    end if;
  end loop;

  for i in 0 .. jsonb_array_length(v_cris) - 1 loop
    c := v_cris -> i;
    v_nasc := (c ->> 'nascimento')::date;
    insert into public.pessoas (igreja_id, nome, data_nascimento, criado_por)
    values (v_igreja, private.nome_limpo(c ->> 'nome'), v_nasc, null) returning id into v_pessoa;
    insert into public.criancas (familia_id, pessoa_id, alergias_observacoes, perfil)
    values (v_fam, v_pessoa, nullif(btrim(coalesce(c ->> 'alergias', '')), ''),
            coalesce(c ->> 'perfil', 'membro')::public.perfil_crianca)
    returning id into v_cri;
    v_cri_pessoas := v_cri_pessoas || v_pessoa;
    insert into public.responsaveis_criancas (responsavel_id, crianca_id)
    select unnest(v_resp_ids), v_cri;
    -- relação do principal (e do 2º, se informada)
    insert into public.relacoes_pessoas (pessoa_id, relacionada_id, tipo, detalhe, origem, informado_por)
    values (v_resp_pessoas[1], v_pessoa, (c ->> 'relacao')::public.relacao_tipo,
            case when c ->> 'relacao' = 'outro' then btrim(c ->> 'relacao_detalhe') end, 'responsavel', null);
    if nullif(c ->> 'relacao2', '') is not null then
      insert into public.relacoes_pessoas (pessoa_id, relacionada_id, tipo, detalhe, origem, informado_por)
      values (v_resp_pessoas[2], v_pessoa, (c ->> 'relacao2')::public.relacao_tipo,
              case when c ->> 'relacao2' = 'outro' then btrim(c ->> 'relacao2_detalhe') end, 'responsavel', null);
    end if;
    -- grupo de WhatsApp pela idade
    v_idade := extract(year from age(v_hoje, v_nasc))::int;
    if v_idade <= 9 and not ('0_9' = any (v_grupos)) then v_grupos := v_grupos || '0_9'::text; end if;
    if v_idade between 10 and 12 and not ('10_12' = any (v_grupos)) then v_grupos := v_grupos || '10_12'::text; end if;
  end loop;

  for i in 0 .. jsonb_array_length(v_auts) - 1 loop
    a := v_auts -> i;
    insert into public.pessoas (igreja_id, nome, telefone, criado_por)
    values (v_igreja, private.nome_limpo(a ->> 'nome'), private.normalizar_telefone(a ->> 'telefone'), null)
    returning id into v_pessoa;
    v_obs := nullif(btrim(coalesce(a ->> 'observacao', '')), '');
    insert into public.pessoas_autorizadas (familia_id, pessoa_id, observacao) values (v_fam, v_pessoa, v_obs);
  end loop;

  -- termo aceito por quem preencheu (o principal); o login é ligado depois
  insert into public.termos_lgpd (familia_id, versao, aceito_por_nome, aceito_por_perfil, aceito_em)
  values (v_fam, v_vigente, v_principal_nome, null, now());

  insert into private.cadastros_link (familia_id) values (v_fam);

  -- links dos grupos certos (só os configurados)
  select coalesce(jsonb_agg(jsonb_build_object('grupo', g.grupo, 'link', cf.valor) order by g.grupo), '[]'::jsonb)
    into v_links
  from unnest(v_grupos) as g(grupo)
  join public.configuracoes cf on cf.departamento_id = v_dept and cf.chave = 'link_grupo_whatsapp_' || g.grupo
  where cf.valor ~ '^https://chat\.whatsapp\.com/[A-Za-z0-9]+$';

  perform private.detectar_duplicidades();
  perform private.avisar_lideranca_kids('Família nova cadastrada',
    v_principal_nome || ' cadastrou ' || jsonb_array_length(v_cris)
      || case when jsonb_array_length(v_cris) = 1 then ' criança' else ' crianças' end || ' pelo link.',
    '#/ficha?tipo=familia&id=' || v_fam, 'familia_nova');

  return jsonb_build_object('familia_id', v_fam, 'logins', v_logins,
    'criancas', to_jsonb(v_cri_pessoas), 'grupos', to_jsonb(v_grupos), 'links', v_links);
end $$;

-- ---------- 3) Depois de criar o login (só a Edge Function) ----------
-- Liga o aceite do termo e as relações informadas ao login do principal.
create or replace function public.cadastro_link_ligar_login(p_familia uuid, p_pessoa uuid, p_perfil uuid)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.perfis f where f.id = p_perfil and f.pessoa_id = p_pessoa) then return; end if;
  if not exists (select 1 from public.responsaveis r where r.familia_id = p_familia and r.pessoa_id = p_pessoa and r.principal) then
    return;
  end if;
  update public.termos_lgpd set aceito_por_perfil = p_perfil
   where familia_id = p_familia and aceito_por_perfil is null;
  update public.relacoes_pessoas x set informado_por = p_perfil
   where x.pessoa_id = p_pessoa and x.informado_por is null
     and x.relacionada_id in (select c.pessoa_id from public.criancas c where c.familia_id = p_familia);
end $$;

-- ---------- 4) Foto enviada no cadastro (só a Edge Function) ----------
create or replace function public.cadastro_link_gravar_foto(p_familia uuid, p_pessoa uuid, p_public_id text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_public_id !~ '^pessoas/(criancas|adultos)/[0-9a-f-]{36}_[0-9]+$' then raise exception 'foto_invalida'; end if;
  if not exists (select 1 from public.criancas c where c.familia_id = p_familia and c.pessoa_id = p_pessoa)
     and not exists (select 1 from public.responsaveis r where r.familia_id = p_familia and r.pessoa_id = p_pessoa) then
    raise exception 'pessoa_fora_da_familia';
  end if;
  -- só cadastros recentes (a foto vai logo depois do cadastro)
  if not exists (select 1 from private.cadastros_link l where l.familia_id = p_familia and l.criado_em > now() - interval '30 minutes') then
    raise exception 'cadastro_antigo';
  end if;
  update public.pessoas set foto_public_id = p_public_id where id = p_pessoa and foto_public_id is null;
end $$;

revoke all on function public.cadastro_link_verificar(text) from public, anon, authenticated;
revoke all on function public.cadastrar_familia_link(jsonb) from public, anon, authenticated;
revoke all on function public.cadastro_link_ligar_login(uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function public.cadastro_link_gravar_foto(uuid, uuid, text) from public, anon, authenticated;
grant execute on function public.cadastro_link_verificar(text) to service_role;
grant execute on function public.cadastrar_familia_link(jsonb) to service_role;
grant execute on function public.cadastro_link_ligar_login(uuid, uuid, uuid) to service_role;
grant execute on function public.cadastro_link_gravar_foto(uuid, uuid, text) to service_role;
revoke all on function private.telefone_ja_cadastrado(text) from public, anon, authenticated;
revoke all on function private.normalizar_telefone(text) from public, anon, authenticated;
revoke all on function private.nome_limpo(text) from public, anon, authenticated;

-- ---------- 5) Adicionar criança (app, com login) ----------
-- Responsável da família ou recepção/liderança do departamento.
-- A criança fica ligada a todos os responsáveis da família. Se quem inclui é
-- responsável da família, a relação dele(a) já é registrada.
-- Aviso no sino da liderança só quando quem inclui é o responsável.
create or replace function public.incluir_crianca(
  p_familia uuid, p_nome text, p_nascimento date, p_alergias text,
  p_perfil text default 'membro', p_relacao public.relacao_tipo default null, p_detalhe text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_eu uuid := private.minha_pessoa();
  v_nome text := private.nome_limpo(p_nome);
  v_alerg text := nullif(btrim(coalesce(p_alergias, '')), '');
  v_det text := nullif(btrim(coalesce(p_detalhe, '')), '');
  v_dept uuid; v_igreja uuid;
  v_equipe boolean; v_resp boolean;
  v_pessoa uuid; v_cri uuid; v_quem text;
begin
  if v_eu is null then raise exception 'Conclua o primeiro acesso antes de continuar'; end if;
  select f.departamento_id, d.igreja_id into v_dept, v_igreja
  from public.familias f join public.departamentos d on d.id = f.departamento_id where f.id = p_familia;
  if v_dept is null then raise exception 'Família não encontrada ou sem permissão'; end if;
  v_resp := p_familia in (select private.minhas_familias());
  v_equipe := private.e_recepcao(v_dept);
  if not v_resp and not v_equipe then raise exception 'Família não encontrada ou sem permissão'; end if;
  if char_length(v_nome) < 3 or char_length(v_nome) > 120 then
    raise exception 'Informe o nome completo (de 3 a 120 letras)';
  end if;
  if p_nascimento is null or p_nascimento > private.hoje() or p_nascimento <= private.hoje() - interval '18 years' then
    raise exception 'Data de nascimento inválida para uma criança';
  end if;
  if char_length(coalesce(v_alerg, '')) > 500 then raise exception 'Alergias e cuidados: use no máximo 500 caracteres'; end if;
  if coalesce(p_perfil, 'membro') not in ('membro', 'visitante') then raise exception 'Perfil inválido'; end if;
  if p_relacao = 'conjuge' then raise exception 'Tipo de relação inválido para uma criança'; end if;
  if p_relacao = 'outro' and (v_det is null or char_length(v_det) > 60) then
    raise exception 'Descreva a relação (ex.: madrinha)';
  end if;
  if (select count(*) from public.criancas where familia_id = p_familia and ativo) >= 10 then
    raise exception 'Limite de 10 crianças por família. Fale com a liderança.';
  end if;

  insert into public.pessoas (igreja_id, nome, data_nascimento, criado_por)
  values (v_igreja, v_nome, p_nascimento, auth.uid()) returning id into v_pessoa;
  insert into public.criancas (familia_id, pessoa_id, alergias_observacoes, perfil)
  values (p_familia, v_pessoa, v_alerg, coalesce(p_perfil, 'membro')::public.perfil_crianca) returning id into v_cri;
  insert into public.responsaveis_criancas (responsavel_id, crianca_id)
  select r.id, v_cri from public.responsaveis r where r.familia_id = p_familia;
  if v_resp and p_relacao is not null then
    insert into public.relacoes_pessoas (pessoa_id, relacionada_id, tipo, detalhe, origem, informado_por)
    values (v_eu, v_pessoa, p_relacao, case when p_relacao = 'outro' then v_det end, 'responsavel', auth.uid());
  end if;

  if not v_equipe then
    select nome into v_quem from public.pessoas where id = v_eu;
    perform private.avisar_lideranca_kids('Criança incluída',
      coalesce(v_quem, 'Um responsável') || ' incluiu ' || v_nome || ' na família.',
      '#/ficha?tipo=crianca&id=' || v_cri, 'cadastro_editado');
  end if;
  return v_cri;
end $$;
revoke all on function public.incluir_crianca(uuid, text, date, text, text, public.relacao_tipo, text) from public, anon;
grant execute on function public.incluir_crianca(uuid, text, date, text, text, public.relacao_tipo, text) to authenticated;

-- ---------- 6) Grupos de WhatsApp (liderança) ----------
-- Lista os responsáveis (com telefone) de crianças ativas de até 12 anos e
-- quem já está marcado em cada grupo. Também traz os links (para o convite).
create or replace function public.grupos_whatsapp()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids(); v_hoje date := private.hoje(); v_lista jsonb; v_links jsonb;
begin
  if not private.e_lider(v_dept) then raise exception 'Só a liderança do Fonte Kids vê os grupos'; end if;

  with faixas as (
    select r.pessoa_id,
      bool_or(extract(year from age(v_hoje, pc.data_nascimento)) <= 9) as f09,
      bool_or(extract(year from age(v_hoje, pc.data_nascimento)) between 10 and 12) as f1012,
      min(r.familia_id::text)::uuid as familia_id
    from public.responsaveis r
    join public.familias fa on fa.id = r.familia_id and fa.departamento_id = v_dept
    join public.responsaveis_criancas rc on rc.responsavel_id = r.id
    join public.criancas c on c.id = rc.crianca_id and c.ativo
    join public.pessoas pc on pc.id = c.pessoa_id and pc.data_nascimento is not null
    group by r.pessoa_id
  ), marcados as (
    select pessoa_id, bool_or(grupo = '0_9') as m09, bool_or(grupo = '10_12') as m1012
    from public.membros_grupo_whatsapp group by pessoa_id
  ), todos as (
    select coalesce(f.pessoa_id, m.pessoa_id) as pessoa_id,
      coalesce(f.f09, false) f09, coalesce(f.f1012, false) f1012,
      coalesce(m.m09, false) m09, coalesce(m.m1012, false) m1012,
      coalesce(f.familia_id, (select r2.familia_id from public.responsaveis r2 where r2.pessoa_id = m.pessoa_id limit 1)) familia_id
    from faixas f full join marcados m on m.pessoa_id = f.pessoa_id
  )
  select coalesce(jsonb_agg(jsonb_build_object(
      'pessoa_id', t.pessoa_id, 'nome', p.nome, 'telefone', p.telefone, 'familia_id', t.familia_id,
      'faixa_0_9', t.f09, 'faixa_10_12', t.f1012, 'no_0_9', t.m09, 'no_10_12', t.m1012,
      'tem_login', exists (select 1 from public.perfis x where x.pessoa_id = t.pessoa_id))
    order by p.nome_busca), '[]'::jsonb)
  into v_lista
  from todos t join public.pessoas p on p.id = t.pessoa_id
  where t.f09 or t.f1012 or t.m09 or t.m1012;

  select jsonb_build_object(
      '0_9',   (select valor from public.configuracoes where departamento_id = v_dept and chave = 'link_grupo_whatsapp_0_9'),
      '10_12', (select valor from public.configuracoes where departamento_id = v_dept and chave = 'link_grupo_whatsapp_10_12'))
    into v_links;
  return jsonb_build_object('responsaveis', v_lista, 'links', v_links);
end $$;

create or replace function public.marcar_grupo_whatsapp(p_pessoa uuid, p_grupo text, p_no_grupo boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids();
begin
  if not private.e_lider(v_dept) then raise exception 'Só a liderança do Fonte Kids marca os grupos'; end if;
  if p_grupo not in ('0_9', '10_12') then raise exception 'Grupo inválido'; end if;
  if not exists (select 1 from public.responsaveis r join public.familias f on f.id = r.familia_id
                 where r.pessoa_id = p_pessoa and f.departamento_id = v_dept) then
    raise exception 'Responsável não encontrado';
  end if;
  if p_no_grupo then
    insert into public.membros_grupo_whatsapp (pessoa_id, grupo, marcado_por)
    values (p_pessoa, p_grupo, auth.uid()) on conflict (pessoa_id, grupo) do nothing;
  else
    delete from public.membros_grupo_whatsapp where pessoa_id = p_pessoa and grupo = p_grupo;
  end if;
  return 'ok';
end $$;

revoke all on function public.grupos_whatsapp() from public, anon;
revoke all on function public.marcar_grupo_whatsapp(uuid, text, boolean) from public, anon;
grant execute on function public.grupos_whatsapp() to authenticated;
grant execute on function public.marcar_grupo_whatsapp(uuid, text, boolean) to authenticated;
