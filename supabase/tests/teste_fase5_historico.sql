-- =====================================================================
-- Teste da Fase 5 · Etapa 5E (Histórico) com DADOS 100% FICTÍCIOS.
-- Tudo roda dentro de um bloco que é DESFEITO no final (nada fica salvo):
-- o resultado aparece na mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- =====================================================================
do $teste$
declare
  u_vol uuid := gen_random_uuid(); u_pai uuid := gen_random_uuid(); u_sem uuid := gen_random_uuid();
  p_vol uuid; p_pai uuid; p_sem uuid; p_outro uuid; p_a uuid; p_d uuid;
  v_kids uuid; v_igreja uuid; s3 uuid;
  v_fam uuid; v_fam2 uuid; c_a uuid; c_d uuid;
  culto1 uuid; culto2 uuid; k_a1 uuid;
  j jsonb; n bigint; txt text;
  r text := ''; falhas int := 0; total int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s3 from public.salas where departamento_id = v_kids and idade_min = 3;

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Voluntaria') returning id into p_vol;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Responsavel Um') returning id into p_pai;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Sem Papel') returning id into p_sem;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Responsavel Dois') returning id into p_outro;
  insert into public.pessoas (igreja_id, nome, data_nascimento)
    values (v_igreja, 'Qwzteste Crianca Alfa', private.hoje() - interval '5 years') returning id into p_a;
  insert into public.pessoas (igreja_id, nome, data_nascimento)
    values (v_igreja, 'Qwzteste Crianca Delta', private.hoje() - interval '4 years') returning id into p_d;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_vol, 'f5e.vol@exemplo.invalid', jsonb_build_object('pessoa_id', p_vol)),
    (u_pai, 'f5e.pai@exemplo.invalid', jsonb_build_object('pessoa_id', p_pai)),
    (u_sem, 'f5e.sem@exemplo.invalid', jsonb_build_object('pessoa_id', p_sem));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_vol, u_pai, u_sem);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_vol, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.familias (departamento_id) values (v_kids) returning id into v_fam;
  insert into public.familias (departamento_id) values (v_kids) returning id into v_fam2;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (v_fam, p_pai, true), (v_fam2, p_outro, true);
  insert into public.criancas (familia_id, pessoa_id, alergias_observacoes)
    values (v_fam, p_a, 'Alergia fictícia') returning id into c_a;
  insert into public.criancas (familia_id, pessoa_id) values (v_fam2, p_d) returning id into c_d;

  -- dois cultos passados (horários improváveis para não colidir com os reais)
  insert into public.cultos (igreja_id, data, horario, nome)
    values (v_igreja, private.hoje() - 7, '06:11', 'Culto Teste 5E A') returning id into culto1;
  insert into public.cultos (igreja_id, data, horario, nome)
    values (v_igreja, private.hoje() - 14, '06:11', 'Culto Teste 5E B') returning id into culto2;
  insert into public.checkins (culto_id, crianca_id, sala_id, entrada_em, saida_em, saida_automatica)
    values (culto1, c_a, s3, (private.hoje() - 7 + time '06:15') at time zone 'America/Sao_Paulo',
            (private.hoje() - 7 + time '09:11') at time zone 'America/Sao_Paulo', true)
    returning id into k_a1;
  insert into public.checkins (culto_id, crianca_id, sala_id, entrada_em)
    values (culto1, c_d, s3, (private.hoje() - 7 + time '06:20') at time zone 'America/Sao_Paulo');
  insert into public.checkins (culto_id, crianca_id, sala_id, entrada_em)
    values (culto2, c_a, s3, (private.hoje() - 14 + time '06:15') at time zone 'America/Sao_Paulo');
  insert into public.chamadas_responsavel (checkin_id, culto_id, departamento_id, situacao, anunciada_em)
    values (k_a1, culto1, v_kids, 'anunciada', now());

  -- ================= TESTES =================
  -- Visitante sem login
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.historico_crianca(c_a);
    r := r || E'\n❌ visitante sem login viu o histórico da criança'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê histórico da criança'; end;
  begin j := public.historico_cultos(30);
    r := r || E'\n❌ visitante sem login viu a lista de cultos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê a lista de cultos'; end;
  begin j := public.historico_culto(culto1);
    r := r || E'\n❌ visitante sem login viu quem veio no culto'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê quem veio no culto'; end;
  perform set_config('role', 'authenticated', true);

  -- Login sem papel
  perform set_config('request.jwt.claims', json_build_object('sub', u_sem, 'role', 'authenticated')::text, true);
  begin j := public.historico_crianca(c_a);
    r := r || E'\n❌ login sem papel viu o histórico'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ login sem papel não vê histórico'; end;
  begin j := public.historico_cultos(30);
    r := r || E'\n❌ login sem papel viu a lista de cultos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ login sem papel não vê a lista de cultos'; end;

  -- Voluntária (= recepção)
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  j := public.historico_crianca(c_a);
  n := jsonb_array_length(j->'itens');
  r := r || format(E'\n%s recepção vê os 2 check-ins da criança: %s', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  n := (j->'resumo'->>'ultimos_30')::int;
  r := r || format(E'\n%s resumo conta 2 nos últimos 30 dias: %s', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  n := jsonb_array_length(j->'itens'->0->'chamadas');
  r := r || format(E'\n%s chamada do responsável aparece no histórico: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  txt := (j->'itens'->0->>'culto') || '/' || coalesce(j->'itens'->0->>'sala', '') || '/' || (j->'itens'->0->>'saida_automatica');
  r := r || format(E'\n%s mais recente primeiro, com sala e saída automática: %s', case when txt like 'Culto Teste 5E A/_%/true' then '✅' else '❌' end, txt); falhas := falhas + (txt not like 'Culto Teste 5E A/_%/true')::int;
  select count(*) into n from jsonb_array_elements(j->'itens') i
   where i ? 'data_nascimento' or i ? 'nascimento' or i ? 'telefone' or i ? 'alergias' or i ? 'retirado_por_nome';
  r := r || format(E'\n%s histórico da criança sem nascimento, telefone, alergias ou "retirado por": %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- paginação
  j := public.historico_crianca(c_a, null, 1);
  txt := jsonb_array_length(j->'itens') || '/' || (j->>'tem_mais');
  r := r || format(E'\n%s página 1 (limite 1) avisa que tem mais: %s', case when txt='1/true' then '✅' else '❌' end, txt); falhas := falhas + (txt<>'1/true')::int;
  j := public.historico_crianca(c_a, (j->'itens'->0->>'entrada_em')::timestamptz, 1);
  txt := jsonb_array_length(j->'itens') || '/' || (j->>'tem_mais') || '/' || (j->'itens'->0->>'culto');
  r := r || format(E'\n%s página 2 traz o culto mais antigo e termina: %s', case when txt='1/false/Culto Teste 5E B' then '✅' else '❌' end, txt); falhas := falhas + (txt<>'1/false/Culto Teste 5E B')::int;

  -- lista de cultos
  j := public.historico_cultos(30);
  select count(*) into n from jsonb_array_elements(j->'itens') i
   where (i->>'id')::uuid = culto1 and (i->>'total')::int = 2 and (i->>'chamadas')::int = 1
     and jsonb_array_length(i->'salas') = 1;
  r := r || format(E'\n%s lista de cultos com total, chamadas e total por sala: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  j := public.historico_cultos(10);
  select count(*) into n from jsonb_array_elements(j->'itens') i where (i->>'id')::uuid = culto2;
  r := r || format(E'\n%s filtro de 10 dias deixa de fora o culto de 14 dias atrás: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- quem veio no culto
  j := public.historico_culto(culto1);
  select count(*) into n from jsonb_array_elements(j->'salas') s, jsonb_array_elements(s->'criancas') c;
  r := r || format(E'\n%s culto mostra as 2 crianças: %s', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  select count(*) into n from jsonb_array_elements(j->'salas') s, jsonb_array_elements(s->'criancas') c
   where c ? 'data_nascimento' or c ? 'nascimento' or c ? 'telefone' or c ? 'alergias' or c ? 'retirado_por_nome';
  r := r || format(E'\n%s culto sem nascimento, telefone, alergias ou "retirado por": %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Responsável antes de aceitar o termo
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  begin j := public.historico_crianca(c_a);
    r := r || E'\n❌ responsável viu histórico antes de aceitar o termo'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável sem aceite do termo não vê histórico'; end;
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));

  -- Responsável depois do termo
  j := public.historico_crianca(c_a);
  n := jsonb_array_length(j->'itens');
  r := r || format(E'\n%s responsável vê o histórico do próprio filho: %s', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  begin j := public.historico_crianca(c_d);
    r := r || E'\n❌ responsável viu o histórico de criança de outra família'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê criança de outra família'; end;
  begin j := public.historico_cultos(30);
    r := r || E'\n❌ responsável viu a lista de cultos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê a lista de cultos'; end;
  begin j := public.historico_culto(culto1);
    r := r || E'\n❌ responsável viu quem veio no culto'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê quem veio no culto'; end;
  begin j := public.historico_crianca(gen_random_uuid());
    r := r || E'\n❌ criança inexistente não deu erro'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ criança inexistente dá erro (sem revelar nada)'; end;

  -- Funções internas fechadas para o app
  begin j := private.chamadas_json(k_a1);
    r := r || E'\n❌ função interna liberada para o app'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ funções internas fechadas para o app'; end;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
