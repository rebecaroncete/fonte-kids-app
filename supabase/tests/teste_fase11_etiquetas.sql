-- =====================================================================
-- Teste da Fase 11 (etiquetas: fila só por funções, interruptor,
-- pedir/reimprimir, estação de etiquetas, conteúdo das etiquetas)
-- com DADOS 100% FICTÍCIOS (culto fictício hoje às 23h57). Tudo roda
-- dentro de um bloco que é DESFEITO no final (nada fica salvo, nada
-- imprime): o resultado aparece na mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute (depois da
-- migração 20261029020000_fase11_etiquetas).
-- =====================================================================
do $teste$
declare
  u_lid uuid := gen_random_uuid(); u_v1 uuid := gen_random_uuid(); u_pai uuid := gen_random_uuid();
  p_lid uuid; p_v1 uuid; p_pai uuid; p_a uuid; p_b uuid;
  ca uuid; cb uuid; fam uuid; v_kids uuid; v_igreja uuid;
  s0 uuid; s3 uuid; cul uuid; cul_velho uuid;
  ka uuid; kb uuid; k_velho uuid;
  ped_resp uuid; ped_a uuid; ped_novo uuid; ped_velho uuid;
  v_hoje date := private.hoje();
  j jsonb; x jsonb; n bigint; t text; cod text;
  r text := ''; falhas int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s0 from public.salas where departamento_id = v_kids and idade_min = 0;
  select id into s3 from public.salas where departamento_id = v_kids and idade_min = 3;
  -- começa do zero: nenhuma estação "no ar" e etiquetas desligadas
  delete from public.estacoes_impressao where departamento_id = v_kids;
  delete from private.estacao_acesso where departamento_id = v_kids;
  update public.configuracoes set valor = 'nao' where departamento_id = v_kids and chave = 'etiquetas_ligadas';

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Lider') returning id into p_lid;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Voluntaria Um', '5500000000011') returning id into p_v1;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Responsavel', '5500000000001') returning id into p_pai;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Abc', v_hoje - interval '2 years') returning id into p_a;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Bcd', v_hoje - interval '5 years') returning id into p_b;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lid, 'f11.lid@exemplo.invalid', jsonb_build_object('pessoa_id', p_lid)),
    (u_v1,  'f11.v1@exemplo.invalid',  jsonb_build_object('pessoa_id', p_v1)),
    (u_pai, 'f11.pai@exemplo.invalid', jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lid, u_v1, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lid, v_kids, 'lider'), (u_v1, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.voluntarias (departamento_id, pessoa_id, funcao, status) values (v_kids, p_v1, 'auxiliar', 'ativa');
  insert into public.familias (departamento_id) values (v_kids) returning id into fam;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (fam, p_pai, true);
  insert into public.criancas (familia_id, pessoa_id, alergias_observacoes) values (fam, p_a, 'Alergia fictícia de teste') returning id into ca;
  insert into public.criancas (familia_id, pessoa_id) values (fam, p_b) returning id into cb;

  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, v_hoje, '23:57', 'Qwzteste') returning id into cul;
  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, v_hoje - 3, '06:07', 'Qwzteste') returning id into cul_velho;
  insert into public.checkins (culto_id, crianca_id, sala_id) values (cul, ca, s0) returning id into ka;
  insert into public.checkins (culto_id, crianca_id, sala_id) values (cul, cb, s3) returning id into kb;
  insert into public.checkins (culto_id, crianca_id, sala_id, entrada_em, saida_em)
    values (cul_velho, ca, s0, now() - interval '3 days', now() - interval '3 days') returning id into k_velho;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));

  -- ================= Permissões =================
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.situacao_etiquetas();
    r := r || E'\n❌ visitante sem login viu a situação das etiquetas'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não usa as etiquetas'; end;
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  begin j := public.pedir_etiquetas(array[ka], 'ambas', false);
    r := r || E'\n❌ responsável pediu etiqueta'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não pede etiqueta'; end;
  begin j := public.gerar_link_estacao();
    r := r || E'\n❌ responsável gerou o link da estação'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não gera o link da estação'; end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  begin
    insert into public.fila_impressao (departamento_id, checkin_id, culto_id, tipo) values (v_kids, ka, cul, 'crianca');
    r := r || E'\n❌ voluntária gravou direto na fila'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ fila só pelas funções (gravação direta bloqueada)'; end;
  begin j := public.ligar_etiquetas(true);
    r := r || E'\n❌ voluntária ligou as etiquetas'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ só a liderança liga as etiquetas'; end;
  begin t := public.gerar_link_estacao();
    r := r || E'\n❌ voluntária gerou o link da estação'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ só a liderança gera o link da estação'; end;

  -- ================= Desligadas =================
  j := public.situacao_etiquetas();
  if not (j->>'ligadas')::boolean and not (j->>'estacao_ativa')::boolean and not (j->>'pode_ligar')::boolean then
    r := r || E'\n✅ começa desligado, sem estação, e a voluntária não vê o interruptor';
  else r := r || E'\n❌ situação inicial: ' || j::text; falhas := falhas + 1; end if;
  j := public.pedir_etiquetas(array[ka, kb], 'ambas', false);
  select count(*) into n from public.fila_impressao where culto_id = cul;
  if not (j->>'ligadas')::boolean and jsonb_array_length(j->'pedidos') = 0 and n = 0 then
    r := r || E'\n✅ desligado: o check-in não gera etiqueta';
  else r := r || E'\n❌ desligado gerou pedido: ' || j::text; falhas := falhas + 1; end if;
  begin j := public.pedir_etiquetas(array[ka], 'crianca', true);
    r := r || E'\n❌ reimprimiu com as etiquetas desligadas'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ reimprimir desligado avisa'; end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  j := public.ligar_etiquetas(true);
  if (j->>'ligadas')::boolean and (j->>'pode_ligar')::boolean and not (j->'link'->>'ativo')::boolean then r := r || E'\n✅ líder liga as etiquetas';
  else r := r || E'\n❌ ligar: ' || j::text; falhas := falhas + 1; end if;
  cod := public.gerar_link_estacao();
  if length(cod) = 32 and (public.situacao_etiquetas()->'link'->>'ativo')::boolean
     and not exists (select 1 from private.estacao_acesso where codigo_hash = cod) then
    r := r || E'\n✅ link da estação gerado (o banco guarda só o hash)';
  else r := r || E'\n❌ link da estação'; falhas := falhas + 1; end if;

  -- ================= Pedir (celular da voluntária) =================
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  j := public.pedir_etiquetas(array[ka, kb], 'ambas', false);
  if jsonb_array_length(j->'pedidos') = 3 and not (j->>'estacao_ativa')::boolean then
    r := r || E'\n✅ 2 crianças da mesma família: 2 etiquetas de criança + 1 do responsável (estação ainda fora)';
  else r := r || E'\n❌ pedidos: ' || j::text; falhas := falhas + 1; end if;
  select (p->>'id')::uuid into ped_resp from jsonb_array_elements(j->'pedidos') p where p->>'tipo' = 'responsavel';
  select (p->>'id')::uuid into ped_a from jsonb_array_elements(j->'pedidos') p where p->>'checkin_id' = ka::text;
  j := public.pedir_etiquetas(array[ka, kb], 'ambas', false);
  if jsonb_array_length(j->'pedidos') = 0 then r := r || E'\n✅ repetir o pedido não duplica etiqueta';
  else r := r || E'\n❌ duplicou: ' || j::text; falhas := falhas + 1; end if;
  begin j := public.pedir_etiquetas(array[k_velho], 'crianca', true);
    r := r || E'\n❌ pediu etiqueta de check-in de outro dia'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ só check-in de hoje vira etiqueta'; end;

  -- ================= Estação (sem login, pelo link) =================
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.estacao_buscar(repeat('0', 32));
    r := r || E'\n❌ estação abriu com código errado'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ link da estação com código errado não abre'; end;
  begin perform 1 from public.fila_impressao limit 1;
    select count(*) into n from public.fila_impressao;
    if n = 0 then r := r || E'\n✅ sem login não se lê a fila direto';
    else r := r || E'\n❌ sem login leu a fila'; falhas := falhas + 1; end if;
  exception when others then r := r || E'\n✅ sem login não se lê a fila direto'; end;
  j := public.estacao_buscar(cod);
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  if jsonb_array_length(j->'pedidos') = 3 then r := r || E'\n✅ estação pega os 3 pedidos';
  else r := r || E'\n❌ estação pegou: ' || jsonb_array_length(j->'pedidos'); falhas := falhas + 1; end if;
  select count(*) into n from public.fila_impressao where culto_id = cul and status = 'imprimindo';
  if n = 3 then r := r || E'\n✅ pedidos ficam "imprimindo"';
  else r := r || E'\n❌ imprimindo: ' || n; falhas := falhas + 1; end if;
  if (public.situacao_etiquetas()->>'estacao_ativa')::boolean then r := r || E'\n✅ celulares veem a estação no ar';
  else r := r || E'\n❌ estação não aparece no ar'; falhas := falhas + 1; end if;
  if jsonb_array_length(public.estacao_buscar(cod)->'pedidos') = 0 then r := r || E'\n✅ cada pedido sai uma vez só';
  else r := r || E'\n❌ estação pegou o mesmo pedido de novo'; falhas := falhas + 1; end if;

  -- Conteúdo
  select p->'etiqueta' into x from jsonb_array_elements(j->'pedidos') p where (p->>'id')::uuid = ped_a;
  if x->'criancas'->0->>'nome' = 'Qwzteste A.' and x->'criancas'->0->>'codigo' = (select codigo_seguranca from public.checkins where id = ka)
     and (x->'criancas'->0->>'alergia')::boolean and x->>'horario' = '23:57' and x->>'data' = to_char(v_hoje, 'DD/MM/YYYY')
     and x->'criancas'->0->>'responsavel' = 'Qwzteste' and x->'criancas'->0->>'telefone' = '(00) 00000-0001' then
    r := r || E'\n✅ etiqueta da criança: nome curto, código, aviso de alergia, data, horário e responsável com telefone';
  else r := r || E'\n❌ etiqueta da criança: ' || coalesce(x::text, 'nula'); falhas := falhas + 1; end if;
  t := (j->'pedidos')::text;
  if t not like '%Alergia fictícia%' and t not like '%Crianca Abc%' and t not like '%Responsavel%' then
    r := r || E'\n✅ nenhuma etiqueta leva nome completo nem qual é a alergia';
  else r := r || E'\n❌ etiqueta com dado a mais: ' || t; falhas := falhas + 1; end if;
  select p->'etiqueta' into x from jsonb_array_elements(j->'pedidos') p where (p->>'id')::uuid = ped_resp;
  if jsonb_array_length(x->'criancas') = 2 and x->>'tipo' = 'responsavel'
     and not exists (select 1 from jsonb_array_elements(x->'criancas') c where c->>'codigo' is null) then
    r := r || E'\n✅ etiqueta do responsável traz as 2 crianças com o código de cada uma';
  else r := r || E'\n❌ etiqueta do responsável: ' || coalesce(x::text, 'nula'); falhas := falhas + 1; end if;
  if (x->'criancas')::text not like '%00000-0001%' then r := r || E'\n✅ etiqueta do responsável não leva telefone';
  else r := r || E'\n❌ telefone na etiqueta do responsável'; falhas := falhas + 1; end if;
  if (x->'criancas'->1->>'alergia') = 'false' then r := r || E'\n✅ criança sem alergia sai sem o aviso';
  else r := r || E'\n❌ aviso de alergia indevido: ' || x::text; falhas := falhas + 1; end if;

  -- Concluir
  n := public.estacao_concluir(cod, array[ped_a, ped_resp], true, null);
  if n = 2 and (select status from public.fila_impressao where id = ped_a) = 'impresso'
     and (select impresso_em from public.fila_impressao where id = ped_a) is not null then
    r := r || E'\n✅ estação marca "impresso"';
  else r := r || E'\n❌ concluir: ' || n; falhas := falhas + 1; end if;
  j := public.situacao_pedidos(array[ped_a, ped_resp]);
  if jsonb_array_length(j->'pedidos') = 2 and not exists (select 1 from jsonb_array_elements(j->'pedidos') p where p->>'status' <> 'impresso') then
    r := r || E'\n✅ celular vê "Impressa"';
  else r := r || E'\n❌ situação dos pedidos: ' || j::text; falhas := falhas + 1; end if;
  n := public.estacao_concluir(cod, (select array_agg(id) from public.fila_impressao where culto_id = cul and status = 'imprimindo'), false, 'Teste fictício');
  if n = 1 and exists (select 1 from public.fila_impressao where culto_id = cul and status = 'erro' and erro = 'Teste fictício') then
    r := r || E'\n✅ falha na impressão fica como "erro" com o motivo';
  else r := r || E'\n❌ falha: ' || n; falhas := falhas + 1; end if;

  -- Reimprimir
  ped_novo := public.estacao_reimprimir(cod, ped_a);
  if (select reimpressao and status = 'pendente' from public.fila_impressao where id = ped_novo) then
    r := r || E'\n✅ "Imprimir de novo" na estação cria um pedido novo';
  else r := r || E'\n❌ reimprimir pedido'; falhas := falhas + 1; end if;
  j := public.pedir_etiquetas(array[kb], 'responsavel', true);
  if jsonb_array_length(j->'pedidos') = 1 and j->'pedidos'->0->>'tipo' = 'responsavel' then
    r := r || E'\n✅ "Reimprimir" no celular (só a do responsável)';
  else r := r || E'\n❌ reimprimir no celular: ' || j::text; falhas := falhas + 1; end if;
  j := public.estacao_lista(cod)->'pedidos';
  if jsonb_array_length(j) >= 5 then r := r || E'\n✅ lista da estação mostra as etiquetas de hoje';
  else r := r || E'\n❌ lista da estação: ' || jsonb_array_length(j); falhas := falhas + 1; end if;

  -- Estação fechada: pedido antigo não sai sozinho; pedido de 8 dias é apagado (fora do RLS)
  perform set_config('role', 'postgres', true);
  update public.fila_impressao set criado_em = now() - interval '11 minutes' where id = ped_novo;
  insert into public.fila_impressao (departamento_id, checkin_id, culto_id, familia_id, tipo, criado_em)
    values (v_kids, k_velho, cul_velho, fam, 'crianca', now() - interval '8 days') returning id into ped_velho;
  perform set_config('role', 'authenticated', true);
  j := public.estacao_buscar(cod);
  if not exists (select 1 from jsonb_array_elements(j->'pedidos') p where (p->>'id')::uuid = ped_novo)
     and (select status from public.fila_impressao where id = ped_novo) = 'erro' then
    r := r || E'\n✅ pedido com mais de 10 min (estação fechada) vira "Não impressa" e não sai sozinho';
  else r := r || E'\n❌ pedido antigo: ' || j::text; falhas := falhas + 1; end if;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.fila_impressao where id = ped_velho;
  perform set_config('role', 'authenticated', true);
  if n = 0 then r := r || E'\n✅ pedidos com mais de 7 dias são apagados';
  else r := r || E'\n❌ pedido de 8 dias ficou'; falhas := falhas + 1; end if;

  -- Desfazer o check-in: a etiqueta da criança some; a do responsável fica só com a outra
  perform public.desfazer_checkin(ka);
  select count(*) into n from public.fila_impressao where checkin_id = ka;
  if n = 0 then r := r || E'\n✅ desfazer o check-in tira as etiquetas da criança da fila';
  else r := r || E'\n❌ ficaram ' || n || ' etiqueta(s) do check-in desfeito'; falhas := falhas + 1; end if;
  select p->'etiqueta' into x from jsonb_array_elements(public.estacao_lista(cod)->'pedidos') p where (p->>'id')::uuid = ped_resp;
  if jsonb_array_length(x->'criancas') = 1 then r := r || E'\n✅ etiqueta do responsável passa a ter só quem ficou';
  else r := r || E'\n❌ responsável depois do desfazer: ' || coalesce(x::text, 'nula'); falhas := falhas + 1; end if;

  -- Responsável não lê a fila; líder desliga
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  select count(*) into n from public.fila_impressao;
  if n = 0 then r := r || E'\n✅ responsável não lê a fila';
  else r := r || E'\n❌ responsável leu ' || n || ' pedido(s)'; falhas := falhas + 1; end if;
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  j := public.ligar_etiquetas(false);
  if not (j->>'ligadas')::boolean and jsonb_array_length(public.estacao_buscar(cod)->'pedidos') = 0 then
    r := r || E'\n✅ líder desliga as etiquetas (a estação para de imprimir)';
  else r := r || E'\n❌ desligar: ' || j::text; falhas := falhas + 1; end if;
  perform public.desligar_link_estacao();
  begin j := public.estacao_lista(cod);
    r := r || E'\n❌ link antigo da estação continuou valendo'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ desligar o link: o antigo para na hora'; end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.auditoria where tabela = 'configuracoes' and perfil_id = u_lid;
  if n = 2 then r := r || E'\n✅ ligar/desligar fica na auditoria';
  else r := r || E'\n❌ auditoria do interruptor: ' || n; falhas := falhas + 1; end if;
  select count(*) into n from public.auditoria where tabela = 'fila_impressao' and perfil_id = u_v1;
  if n > 0 then r := r || E'\n✅ pedidos de etiqueta ficam na auditoria';
  else r := r || E'\n❌ fila sem auditoria'; falhas := falhas + 1; end if;

  raise exception E'RESULTADO DOS TESTES (Fase 11): % falha(s)%', falhas, r;
end $teste$;
