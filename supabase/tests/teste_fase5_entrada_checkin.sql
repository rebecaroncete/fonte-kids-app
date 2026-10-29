-- =====================================================================
-- Teste da Fase 5 · Etapa 5B (entrada do check-in) com DADOS 100% FICTÍCIOS.
-- Tudo roda dentro de um bloco que é DESFEITO no final (nada fica salvo):
-- o resultado aparece na mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- =====================================================================
do $teste$
declare
  u_lider uuid := gen_random_uuid(); u_vol uuid := gen_random_uuid(); u_pai uuid := gen_random_uuid();
  p_lider uuid; p_vol uuid; p_pai uuid; p_outro uuid; p_a uuid; p_b uuid; p_c uuid; p_d uuid;
  v_kids uuid; v_igreja uuid; s3 uuid; s7 uuid; s10 uuid;
  v_fam uuid; v_fam2 uuid; c_a uuid; c_b uuid; c_c uuid; c_d uuid;
  culto uuid; k_a uuid;
  j jsonb; f jsonb; n bigint; txt text;
  r text := ''; falhas int := 0; total int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s3  from public.salas where departamento_id = v_kids and idade_min = 3;
  select id into s7  from public.salas where departamento_id = v_kids and idade_min = 7;
  select id into s10 from public.salas where departamento_id = v_kids and idade_min = 10;

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Lider') returning id into p_lider;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Voluntaria') returning id into p_vol;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Responsavel Um', '5599900007318') returning id into p_pai;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Responsavel Dois') returning id into p_outro;
  insert into public.pessoas (igreja_id, nome, data_nascimento)  -- 5 anos → 3 a 6
    values (v_igreja, 'Qwzteste Crianca Alfa', private.hoje() - interval '5 years' - interval '40 days') returning id into p_a;
  insert into public.pessoas (igreja_id, nome, data_nascimento)  -- 10 anos → 10 a 12 (junto com 7 a 9 no culto de teste)
    values (v_igreja, 'Qwzteste Crianca Beta', private.hoje() - interval '10 years' - interval '40 days') returning id into p_b;
  insert into public.pessoas (igreja_id, nome)                   -- sem data → sem sala
    values (v_igreja, 'Qwzteste Crianca Gama') returning id into p_c;
  insert into public.pessoas (igreja_id, nome, data_nascimento)  -- aniversário daqui a 3 dias
    values (v_igreja, 'Qwzteste Crianca Delta', private.hoje() - interval '6 years' + interval '3 days') returning id into p_d;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lider, 'f5b.lider@exemplo.invalid', jsonb_build_object('pessoa_id', p_lider)),
    (u_vol,   'f5b.vol@exemplo.invalid',   jsonb_build_object('pessoa_id', p_vol)),
    (u_pai,   'f5b.pai@exemplo.invalid',   jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lider, u_vol, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lider, v_kids, 'lider'), (u_vol, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.familias (departamento_id) values (v_kids) returning id into v_fam;
  insert into public.familias (departamento_id) values (v_kids) returning id into v_fam2;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (v_fam, p_pai, true), (v_fam2, p_outro, true);
  insert into public.criancas (familia_id, pessoa_id) values (v_fam, p_a) returning id into c_a;
  insert into public.criancas (familia_id, pessoa_id) values (v_fam, p_b) returning id into c_b;
  insert into public.criancas (familia_id, pessoa_id) values (v_fam, p_c) returning id into c_c;
  insert into public.criancas (familia_id, pessoa_id) values (v_fam2, p_d) returning id into c_d;

  -- ================= TESTES =================
  -- Visitante sem login
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    j := public.cultos_de_hoje();
    r := r || E'\n❌ visitante sem login viu os cultos de hoje'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê o check-in';
  end;
  perform set_config('role', 'authenticated', true);

  -- Líder cria um culto extra hoje com 10–12 junto com 7–9
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  culto := public.criar_culto_extra(private.hoje(), '03:17', 'Culto Teste 5B',
    jsonb_build_array(jsonb_build_object('sala_id', s10, 'cancelada', false, 'junto_com', s7)));

  -- Responsável (sem papel de equipe)
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));
  begin
    j := public.buscar_para_checkin(culto, 'qwzteste');
    r := r || E'\n❌ responsável usou a busca do check-in'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não usa a busca do check-in';
  end;
  begin
    j := public.fazer_checkin(culto, array[c_a]);
    r := r || E'\n❌ responsável fez check-in'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não faz check-in';
  end;

  -- Voluntária (recepção)
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  select count(*) into n from jsonb_array_elements(public.cultos_de_hoje()) x where (x->>'id')::uuid = culto;
  r := r || format(E'\n%s voluntária vê o culto de hoje: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  j := public.buscar_para_checkin(culto, 'QWZTÉSTE crianca');
  n := jsonb_array_length(j);
  r := r || format(E'\n%s busca pelo nome (sem acento, maiúsculas): %s famílias (esperado 2)', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  select x into f from jsonb_array_elements(j) x where (x->>'familia_id')::uuid = v_fam;
  select c->>'sala_nome' into txt from jsonb_array_elements(f->'criancas') c where (c->>'id')::uuid = c_a;
  r := r || format(E'\n%s sala pela idade (5 anos): %s (esperado 3 a 6 anos)', case when txt='3 a 6 anos' then '✅' else '❌' end, txt); falhas := falhas + (txt is distinct from '3 a 6 anos')::int;
  select c->>'sala_nome' into txt from jsonb_array_elements(f->'criancas') c where (c->>'id')::uuid = c_b;
  r := r || format(E'\n%s salas juntas (10 anos): %s (esperado 7 a 12 anos)', case when txt='7 a 12 anos' then '✅' else '❌' end, txt); falhas := falhas + (txt is distinct from '7 a 12 anos')::int;
  select c->>'sem_sala' into txt from jsonb_array_elements(f->'criancas') c where (c->>'id')::uuid = c_c;
  r := r || format(E'\n%s sem data → sem sala: %s (esperado sem_data)', case when txt='sem_data' then '✅' else '❌' end, txt); falhas := falhas + (txt is distinct from 'sem_data')::int;
  select count(*) into n from jsonb_array_elements(j) x, jsonb_array_elements(x->'criancas') c
   where (c->>'id')::uuid = c_d and (c->>'aniversario')::boolean;
  r := r || format(E'\n%s 🎂 aniversário daqui a 3 dias: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from jsonb_array_elements(j) x, jsonb_array_elements(x->'criancas') c
   where c ? 'data_nascimento' or c ? 'nascimento';
  r := r || format(E'\n%s a busca não devolve a data de nascimento: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  select count(*) into n from jsonb_array_elements(public.buscar_para_checkin(culto, '7318')) x where (x->>'familia_id')::uuid = v_fam;
  r := r || format(E'\n%s busca pelos 4 últimos números do telefone: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  begin
    insert into public.checkins (culto_id, crianca_id, sala_id, codigo_seguranca) values (culto, c_a, s3, '');
    r := r || E'\n❌ check-in gravado direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ ninguém grava check-in direto na tabela (só pelas funções)';
  end;
  begin
    j := public.fazer_checkin(culto, array[c_c]);
    r := r || E'\n❌ check-in de criança sem sala'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ criança sem sala não faz check-in (pede para corrigir)';
  end;

  j := public.fazer_checkin(culto, array[c_a, c_b]);
  select count(*) into n from jsonb_array_elements(j) x where char_length(x->>'codigo') = 4;
  r := r || format(E'\n%s check-in de 2 crianças, cada uma com código de 4 caracteres: %s (esperado 2)', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  select count(*) into n from public.checkins where culto_id = culto and crianca_id = c_b and sala_id = s7;
  r := r || format(E'\n%s criança de 10 anos foi para a sala que recebe (7 a 9 → "7 a 12"): %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  j := public.fazer_checkin(culto, array[c_a]);
  select count(*) into n from public.checkins where culto_id = culto and crianca_id = c_a;
  r := r || format(E'\n%s check-in repetido não duplica (devolve o mesmo código): %s (esperado 1) %s', case when n=1 and (j->0->>'ja_tinha')::boolean then '✅' else '❌' end, n, j->0->>'ja_tinha');
  falhas := falhas + (n<>1 or not (j->0->>'ja_tinha')::boolean)::int;

  begin
    update public.checkins set codigo_seguranca = 'ZZZZ' where culto_id = culto;
    r := r || E'\n❌ check-in alterado direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ ninguém altera check-in direto na tabela';
  end;

  -- Corrigir os dados na hora (recepção) → sala aparece; sem aviso no sino
  txt := public.editar_crianca(c_c, 'Qwzteste Crianca Gama', (private.hoje() - interval '4 years')::date, null);
  r := r || format(E'\n%s recepção corrige a data de nascimento na hora: %s', case when txt='ok' then '✅' else '❌' end, txt); falhas := falhas + (txt<>'ok')::int;
  select count(*) into n from public.notificacoes where link like '%' || c_c::text;
  r := r || format(E'\n%s correção pela equipe não gera aviso no sino: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  j := public.fazer_checkin(culto, array[c_c, c_d]);
  r := r || format(E'\n%s depois de corrigir, a criança faz check-in: %s', case when jsonb_array_length(j)=2 then '✅' else '❌' end, jsonb_array_length(j)); falhas := falhas + (jsonb_array_length(j)<>2)::int;

  -- Desfazer
  select id into k_a from public.checkins where culto_id = culto and crianca_id = c_a;
  txt := public.desfazer_checkin(k_a);
  select count(*) into n from public.checkins where id = k_a;
  r := r || format(E'\n%s recepção desfaz dentro de 30 minutos: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  j := public.fazer_checkin(culto, array[c_a]);
  select id into k_a from public.checkins where culto_id = culto and crianca_id = c_a;
  perform set_config('role', 'postgres', true);
  update public.checkins set entrada_em = now() - interval '1 hour' where id = k_a;
  perform set_config('role', 'authenticated', true);
  begin
    txt := public.desfazer_checkin(k_a);
    r := r || E'\n❌ recepção desfez depois de 30 minutos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recepção não desfaz depois de 30 minutos';
  end;

  -- Responsável vê só o check-in dos próprios filhos (sala e código)
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  j := public.meus_checkins_hoje();
  n := jsonb_array_length(j);
  r := r || format(E'\n%s responsável vê o check-in dos próprios filhos: %s (esperado 3, sem a criança da outra família)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from jsonb_array_elements(j) x where char_length(x->>'codigo') = 4 and x->>'sala_nome' is not null;
  r := r || format(E'\n%s cada um com sala e código: %s (esperado 3)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  begin
    txt := public.desfazer_checkin(k_a);
    r := r || E'\n❌ responsável desfez check-in'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não desfaz check-in';
  end;

  -- Líder desfaz a qualquer hora
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  txt := public.desfazer_checkin(k_a);
  select count(*) into n from public.checkins where id = k_a;
  r := r || format(E'\n%s liderança desfaz depois de 30 minutos: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.auditoria where tabela = 'checkins';
  r := r || format(E'\n%s auditoria registrou os check-ins: %s (esperado > 0)', case when n>0 then '✅' else '❌' end, n); falhas := falhas + (n=0)::int;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
