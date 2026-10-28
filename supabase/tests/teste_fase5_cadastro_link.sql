-- =====================================================================
-- Teste da Fase 5 · Etapa 5D (cadastro pelo link, "Adicionar criança",
-- grupos de WhatsApp) com DADOS 100% FICTÍCIOS.
-- Tudo roda dentro de um bloco que é DESFEITO no final (nada fica salvo):
-- o resultado aparece na mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- Obs.: a Edge Function (captcha, ticket, logins, fotos) é conferida no
-- roteiro pelo celular; aqui se testa o banco.
-- =====================================================================
do $teste$
declare
  u_lider uuid := gen_random_uuid(); u_vol uuid := gen_random_uuid(); u_outro uuid := gen_random_uuid(); u_novo uuid := gen_random_uuid();
  p_lider uuid; p_vol uuid; p_outro uuid; p_kid_outro uuid;
  v_kids uuid; v_igreja uuid; v_termo text;
  f_outra uuid; v_fam uuid; v_principal uuid; v_cri uuid; v_id uuid;
  tel1 text := '5519' || '9' || lpad((floor(random() * 1e8))::bigint::text, 8, '0');
  tel2 text := '5518' || '9' || lpad((floor(random() * 1e8))::bigint::text, 8, '0');
  tel3 text := '5517' || '9' || lpad((floor(random() * 1e8))::bigint::text, 8, '0');
  dados jsonb; j jsonb; x jsonb; n bigint; txt text; ok boolean; d13 text;
  r text := ''; falhas int := 0; total int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select versao into v_termo from public.termos_lgpd_versoes where vigente;
  d13 := (private.hoje() - interval '13 years')::date::text;

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Lider') returning id into p_lider;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Voluntaria') returning id into p_vol;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Outro Responsavel', tel3) returning id into p_outro;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Outra', private.hoje() - interval '4 years') returning id into p_kid_outro;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lider, 'f5d.lider@exemplo.invalid', jsonb_build_object('pessoa_id', p_lider)),
    (u_vol,   'f5d.vol@exemplo.invalid',   jsonb_build_object('pessoa_id', p_vol)),
    (u_outro, 'f5d.outro@exemplo.invalid', jsonb_build_object('pessoa_id', p_outro));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lider, u_vol, u_outro);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lider, v_kids, 'lider'), (u_vol, v_kids, 'voluntaria'), (u_vol, v_kids, 'recepcao'), (u_outro, null, 'responsavel');
  insert into public.familias (departamento_id) values (v_kids) returning id into f_outra;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (f_outra, p_outro, true);
  insert into public.criancas (familia_id, pessoa_id) values (f_outra, p_kid_outro);
  insert into public.termos_lgpd (familia_id, versao, aceito_por_nome, aceito_por_perfil) values (f_outra, v_termo, 'Qwzteste', u_outro);

  dados := jsonb_build_object('termo_versao', v_termo,
    'responsaveis', jsonb_build_array(
      jsonb_build_object('nome', 'Qwzteste Mae Nova', 'telefone', tel1),
      jsonb_build_object('nome', 'Qwzteste Pai Novo', 'telefone', tel2)),
    'criancas', jsonb_build_array(
      jsonb_build_object('nome', 'Qwzteste Kid Pequeno', 'nascimento', (private.hoje() - interval '5 years')::date, 'perfil', 'visitante',
                         'relacao', 'mae', 'relacao2', 'pai'),
      jsonb_build_object('nome', 'Qwzteste Kid Grande', 'nascimento', (private.hoje() - interval '11 years')::date,
                         'relacao', 'outro', 'relacao_detalhe', 'madrinha')),
    'autorizados', jsonb_build_array(jsonb_build_object('nome', 'Qwzteste Avo', 'telefone', '5519900000000', 'observacao', 'avó')));

  -- ================= Sem login (anon) =================
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.cadastrar_familia_link(dados);
    r := r || E'\n❌ visitante sem login cadastrou direto no banco'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não cadastra direto no banco (só pela Edge Function)';
  end;
  begin j := public.cadastro_link_verificar(tel1);
    r := r || E'\n❌ visitante sem login consultou telefone direto no banco'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não consulta telefone direto no banco';
  end;
  begin perform public.cadastro_link_gravar_foto(f_outra, p_kid_outro, 'pessoas/criancas/x');
    r := r || E'\n❌ visitante sem login gravou foto'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não grava foto';
  end;
  begin select count(*) into n from private.cadastros_link;
    r := r || E'\n❌ visitante sem login leu o registro de cadastros'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não lê o registro de cadastros';
  end;
  begin v_id := public.incluir_crianca(f_outra, 'Qwzteste Intrusa', private.hoje() - interval '3 years', null);
    r := r || E'\n❌ visitante sem login incluiu criança'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não inclui criança';
  end;
  begin j := public.grupos_whatsapp();
    r := r || E'\n❌ visitante sem login viu os grupos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê os grupos';
  end;

  -- ================= Com login de responsável (não pode usar as funções do cadastro público) =================
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_outro, 'role', 'authenticated')::text, true);
  begin j := public.cadastrar_familia_link(dados);
    r := r || E'\n❌ login comum chamou o cadastro público direto'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ login comum não chama o cadastro público direto';
  end;
  begin perform public.cadastro_link_ligar_login(f_outra, p_outro, u_outro);
    r := r || E'\n❌ login comum chamou ligar_login'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ login comum não chama ligar_login';
  end;

  -- ================= Edge Function (service_role) =================
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  j := public.cadastro_link_verificar(tel1);
  ok := (j ->> 'existe') = 'false' and (j -> 'termo' ->> 'versao') = v_termo;
  r := r || format(E'\n%s telefone novo: não existe e devolve o termo vigente', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  j := public.cadastro_link_verificar(tel3);
  ok := (j ->> 'existe') = 'true' and j -> 'termo' is null;
  r := r || format(E'\n%s telefone de responsável já cadastrado: existe (sem termo)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- erros de validação (nada gravado)
  begin j := public.cadastrar_familia_link(jsonb_set(dados, '{termo_versao}', '"v0"'));
    r := r || E'\n❌ aceitou termo desatualizado'; falhas := falhas + 1;
  exception when others then
    r := r || format(E'\n%s recusa termo desatualizado', case when sqlerrm = 'termo_desatualizado' then '✅' else '❌ (' || sqlerrm || ')' end);
    falhas := falhas + (sqlerrm <> 'termo_desatualizado')::int;
  end;
  begin j := public.cadastrar_familia_link(jsonb_set(dados, '{criancas,0,nascimento}', to_jsonb(d13)));
    r := r || E'\n❌ aceitou criança de 13 anos'; falhas := falhas + 1;
  exception when others then
    r := r || format(E'\n%s recusa criança acima de 12 anos', case when sqlerrm = 'nascimento_crianca_1' then '✅' else '❌ (' || sqlerrm || ')' end);
    falhas := falhas + (sqlerrm <> 'nascimento_crianca_1')::int;
  end;
  begin j := public.cadastrar_familia_link(jsonb_set(dados, '{criancas,0,relacao}', '"conjuge"'));
    r := r || E'\n❌ aceitou relação "cônjuge" com criança'; falhas := falhas + 1;
  exception when others then
    r := r || format(E'\n%s recusa relação inválida', case when sqlerrm = 'relacao_crianca_1' then '✅' else '❌ (' || sqlerrm || ')' end);
    falhas := falhas + (sqlerrm <> 'relacao_crianca_1')::int;
  end;
  begin j := public.cadastrar_familia_link(jsonb_set(dados, '{responsaveis,1,telefone}', to_jsonb(tel3)));
    r := r || E'\n❌ aceitou 2º responsável com telefone já cadastrado'; falhas := falhas + 1;
  exception when others then
    r := r || format(E'\n%s recusa 2º responsável com telefone já cadastrado', case when sqlerrm = 'telefone2_ja_cadastrado' then '✅' else '❌ (' || sqlerrm || ')' end);
    falhas := falhas + (sqlerrm <> 'telefone2_ja_cadastrado')::int;
  end;
  begin j := public.cadastrar_familia_link(jsonb_set(dados, '{responsaveis}',
      (dados -> 'responsaveis') || jsonb_build_array(jsonb_build_object('nome', 'Qwzteste Terceiro', 'telefone', null))));
    r := r || E'\n❌ aceitou 3 responsáveis'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recusa mais de 2 responsáveis';
  end;
  begin j := public.cadastrar_familia_link(jsonb_set(dados, '{responsaveis,0,telefone}', '"123"'));
    r := r || E'\n❌ aceitou telefone inválido'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recusa telefone inválido';
  end;
  select count(*) into n from public.pessoas where nome like 'Qwzteste Kid%';
  r := r || format(E'\n%s cadastro recusado não deixa nada gravado: %s pessoas', case when n = 0 then '✅' else '❌' end, n); falhas := falhas + (n <> 0)::int;

  -- cadastro válido
  j := public.cadastrar_familia_link(dados);
  v_fam := (j ->> 'familia_id')::uuid;
  ok := jsonb_array_length(j -> 'logins') = 2 and jsonb_array_length(j -> 'criancas') = 2
        and j -> 'grupos' @> '["0_9","10_12"]'::jsonb;
  r := r || format(E'\n%s cadastro válido: 2 logins a criar, 2 crianças, grupos 0–9 e 10–12', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  select count(*) into n from public.responsaveis_criancas rc join public.criancas c on c.id = rc.crianca_id where c.familia_id = v_fam;
  r := r || format(E'\n%s cada criança ligada aos 2 responsáveis: %s vínculos (esperado 4)', case when n = 4 then '✅' else '❌' end, n); falhas := falhas + (n <> 4)::int;
  select count(*) into n from public.relacoes_pessoas x join public.criancas c on c.pessoa_id = x.relacionada_id where c.familia_id = v_fam;
  r := r || format(E'\n%s relações registradas: %s (esperado 3)', case when n = 3 then '✅' else '❌' end, n); falhas := falhas + (n <> 3)::int;
  select count(*) into n from public.pessoas_autorizadas where familia_id = v_fam;
  r := r || format(E'\n%s autorizado gravado: %s', case when n = 1 then '✅' else '❌' end, n); falhas := falhas + (n <> 1)::int;
  select count(*) into n from public.termos_lgpd where familia_id = v_fam and versao = v_termo and aceito_por_perfil is null;
  r := r || format(E'\n%s aceite do termo registrado (ainda sem login): %s', case when n = 1 then '✅' else '❌' end, n); falhas := falhas + (n <> 1)::int;
  select count(*) into n from public.notificacoes where tipo = 'familia_nova' and link like '%' || v_fam || '%';
  r := r || format(E'\n%s liderança avisada (família nova): %s avisos', case when n > 0 then '✅' else '❌' end, n); falhas := falhas + (n = 0)::int;
  perform set_config('role', 'postgres', true);
  select count(*) into n from private.cadastros_link where familia_id = v_fam;
  perform set_config('role', 'service_role', true);
  r := r || format(E'\n%s cadastro contado para o limite diário', case when n = 1 then '✅' else '❌' end); falhas := falhas + (n <> 1)::int;

  -- mesmo telefone de novo
  begin j := public.cadastrar_familia_link(dados);
    r := r || E'\n❌ cadastrou duas vezes o mesmo telefone'; falhas := falhas + 1;
  exception when others then
    r := r || format(E'\n%s telefone já cadastrado é recusado', case when sqlerrm = 'telefone_ja_cadastrado' then '✅' else '❌ (' || sqlerrm || ')' end);
    falhas := falhas + (sqlerrm <> 'telefone_ja_cadastrado')::int;
  end;
  j := public.cadastro_link_verificar(tel2);
  r := r || format(E'\n%s telefone do 2º responsável passa a contar como cadastrado', case when (j ->> 'existe') = 'true' then '✅' else '❌' end);
  falhas := falhas + ((j ->> 'existe') <> 'true')::int;

  -- telefone compartilhado entre os 2 responsáveis: 1 login só
  begin
    x := jsonb_set(jsonb_set(jsonb_set(dados, '{responsaveis,0,telefone}', '"5519911110000"'), '{responsaveis,1,telefone}', '"5519911110000"'),
                   '{autorizados}', '[]');
    if public.cadastro_link_verificar('5519911110000') ->> 'existe' = 'true' then
      r := r || E'\nℹ️ telefone compartilhado não testado (número de teste já existe)';
    else
      j := public.cadastrar_familia_link(x);
      r := r || format(E'\n%s telefone compartilhado entre responsáveis: 1 login', case when jsonb_array_length(j -> 'logins') = 1 then '✅' else '❌' end);
      falhas := falhas + (jsonb_array_length(j -> 'logins') <> 1)::int;
    end if;
  end;

  -- login do principal + ligar termo e relações
  select pessoa_id into v_principal from public.responsaveis where familia_id = v_fam and principal;
  perform set_config('role', 'postgres', true);
  insert into auth.users (id, email, raw_app_meta_data) values (u_novo, 'f5d.novo@exemplo.invalid', jsonb_build_object('pessoa_id', v_principal, 'telefone', tel1));
  update public.perfis set troca_senha_obrigatoria = false where id = u_novo;
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values (u_novo, null, 'responsavel');
  perform set_config('role', 'service_role', true);
  perform public.cadastro_link_ligar_login(v_fam, v_principal, u_novo);
  perform set_config('role', 'postgres', true);
  ok := private.termo_em_dia(u_novo);
  r := r || format(E'\n%s 1º acesso não pede o termo de novo (aceite ligado ao login)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  select count(*) into n from public.relacoes_pessoas where pessoa_id = v_principal and informado_por = u_novo;
  r := r || format(E'\n%s relações do principal ligadas ao login dele: %s', case when n = 2 then '✅' else '❌' end, n); falhas := falhas + (n <> 2)::int;

  -- foto: só pessoa da família, só public_id válido
  perform set_config('role', 'service_role', true);
  begin perform public.cadastro_link_gravar_foto(v_fam, p_kid_outro, 'pessoas/criancas/' || p_kid_outro || '_1');
    r := r || E'\n❌ gravou foto de criança de outra família'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não grava foto de criança de outra família';
  end;
  begin perform public.cadastro_link_gravar_foto(v_fam, v_principal, 'qualquer/coisa');
    r := r || E'\n❌ gravou foto com endereço inválido'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não grava foto com endereço inválido';
  end;
  perform public.cadastro_link_gravar_foto(v_fam, v_principal, 'pessoas/adultos/' || v_principal || '_123');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.pessoas where id = v_principal and foto_public_id is not null;
  r := r || format(E'\n%s foto do cadastro gravada', case when n = 1 then '✅' else '❌' end); falhas := falhas + (n <> 1)::int;

  -- limite diário
  insert into private.cadastros_link (familia_id) select v_fam from generate_series(1, 100);
  perform set_config('role', 'service_role', true);
  begin j := public.cadastrar_familia_link(jsonb_set(jsonb_set(dados, '{responsaveis,0,telefone}', '"5519922220000"'), '{responsaveis}', jsonb_build_array(jsonb_build_object('nome', 'Qwzteste X', 'telefone', '5519922220000'))));
    r := r || E'\n❌ passou do limite de 100 cadastros por dia'; falhas := falhas + 1;
  exception when others then
    r := r || format(E'\n%s limite de 100 cadastros por dia', case when sqlerrm = 'limite_diario' then '✅' else '❌ (' || sqlerrm || ')' end);
    falhas := falhas + (sqlerrm <> 'limite_diario')::int;
  end;
  perform set_config('role', 'postgres', true);
  delete from private.cadastros_link where id not in (select min(id) from private.cadastros_link group by familia_id) and familia_id = v_fam;

  -- ================= Adicionar criança (app) =================
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_novo, 'role', 'authenticated')::text, true);
  v_cri := public.incluir_crianca(v_fam, 'Qwzteste Kid Caçula', (private.hoje() - interval '1 year')::date, null, 'membro', 'mae', null);
  select count(*) into n from public.responsaveis_criancas where crianca_id = v_cri;
  r := r || format(E'\n%s responsável adiciona criança (ligada aos 2 responsáveis): %s', case when n = 2 then '✅' else '❌' end, n); falhas := falhas + (n <> 2)::int;
  begin v_id := public.incluir_crianca(f_outra, 'Qwzteste Intrusa', (private.hoje() - interval '3 years')::date, null);
    r := r || E'\n❌ responsável incluiu criança em outra família'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não inclui criança em outra família';
  end;
  begin v_id := public.incluir_crianca(v_fam, 'Qwzteste Velha', (private.hoje() - interval '20 years')::date, null);
    r := r || E'\n❌ aceitou "criança" de 20 anos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recusa data de nascimento inválida ao adicionar';
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  v_id := public.incluir_crianca(f_outra, 'Qwzteste Kid Balcao', (private.hoje() - interval '6 years')::date, 'Alergia fictícia');
  r := r || format(E'\n%s recepção adiciona criança no balcão', case when v_id is not null then '✅' else '❌' end); falhas := falhas + (v_id is null)::int;

  -- ================= Grupos de WhatsApp =================
  perform set_config('request.jwt.claims', json_build_object('sub', u_outro, 'role', 'authenticated')::text, true);
  begin j := public.grupos_whatsapp();
    r := r || E'\n❌ responsável viu a lista dos grupos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê a lista dos grupos';
  end;
  begin perform public.marcar_grupo_whatsapp(p_outro, '0_9', true);
    r := r || E'\n❌ responsável marcou grupo'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não marca grupo';
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  begin j := public.grupos_whatsapp();
    r := r || E'\n❌ recepção viu a lista dos grupos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recepção (voluntária) não vê a lista dos grupos';
  end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  j := public.grupos_whatsapp();
  select count(*) into n from jsonb_array_elements(j -> 'responsaveis') e
   where (e ->> 'pessoa_id')::uuid = v_principal and (e ->> 'faixa_0_9')::boolean and (e ->> 'faixa_10_12')::boolean;
  r := r || format(E'\n%s liderança vê a família nova nos dois grupos (falta convite)', case when n = 1 then '✅' else '❌' end); falhas := falhas + (n <> 1)::int;
  perform public.marcar_grupo_whatsapp(v_principal, '10_12', true);
  j := public.grupos_whatsapp();
  select count(*) into n from jsonb_array_elements(j -> 'responsaveis') e
   where (e ->> 'pessoa_id')::uuid = v_principal and (e ->> 'no_10_12')::boolean and not (e ->> 'no_0_9')::boolean;
  r := r || format(E'\n%s liderança marca quem está no grupo 10–12', case when n = 1 then '✅' else '❌' end); falhas := falhas + (n <> 1)::int;
  perform public.marcar_grupo_whatsapp(v_principal, '10_12', false);
  select count(*) into n from public.membros_grupo_whatsapp where pessoa_id = v_principal;
  r := r || format(E'\n%s liderança desmarca', case when n = 0 then '✅' else '❌' end); falhas := falhas + (n <> 0)::int;
  begin perform public.marcar_grupo_whatsapp(v_principal, '13_18', true);
    r := r || E'\n❌ aceitou grupo inexistente'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recusa grupo inexistente';
  end;
  begin perform public.marcar_grupo_whatsapp(p_lider, '0_9', true);
    r := r || E'\n❌ marcou no grupo quem não é responsável'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ só marca responsáveis de crianças do Fonte Kids';
  end;
  begin
    insert into public.membros_grupo_whatsapp (pessoa_id, grupo) values (v_principal, '0_9');
    r := r || E'\n❌ líder gravou direto na tabela dos grupos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ ninguém grava direto na tabela dos grupos';
  end;

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.auditoria where tabela = 'membros_grupo_whatsapp' and registro_id is not null and em > now() - interval '1 minute';
  r := r || format(E'\n%s auditoria registrou a marcação dos grupos: %s', case when n > 0 then '✅' else '❌' end, n); falhas := falhas + (n = 0)::int;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
