-- =====================================================================
-- Teste da Fase 5 · Etapa 5C (Presentes, "Saiu", chamar responsável,
-- telão e fechamento automático) com DADOS 100% FICTÍCIOS.
-- Tudo roda dentro de um bloco que é DESFEITO no final (nada fica salvo,
-- nem o link do telão): o resultado aparece na mensagem de erro
-- "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- Obs.: a parte do fechamento automático só roda depois das 04:00.
-- =====================================================================
do $teste$
declare
  u_lider uuid := gen_random_uuid(); u_vol uuid := gen_random_uuid(); u_pai uuid := gen_random_uuid();
  p_lider uuid; p_vol uuid; p_pai uuid; p_outro uuid; p_a uuid; p_b uuid; p_d uuid;
  v_kids uuid; v_igreja uuid; s7 uuid; s10 uuid;
  v_fam uuid; v_fam2 uuid; c_a uuid; c_b uuid; c_d uuid;
  culto uuid; k_a uuid; k_b uuid; k_d uuid; ch_a uuid; ch_b uuid; ch_d uuid; v_id uuid;
  cod1 text; cod2 text;
  v_agora timestamp := now() at time zone 'America/Sao_Paulo';
  j jsonb; x jsonb; n bigint; txt text;
  r text := ''; falhas int := 0; total int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s7  from public.salas where departamento_id = v_kids and idade_min = 7;
  select id into s10 from public.salas where departamento_id = v_kids and idade_min = 10;

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Lider') returning id into p_lider;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Voluntaria') returning id into p_vol;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Responsavel Um') returning id into p_pai;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Responsavel Dois') returning id into p_outro;
  insert into public.pessoas (igreja_id, nome, data_nascimento)
    values (v_igreja, 'Qwzteste Crianca Alfa', private.hoje() - interval '5 years' - interval '40 days') returning id into p_a;
  insert into public.pessoas (igreja_id, nome, data_nascimento)
    values (v_igreja, 'Qwzteste Crianca Beta', private.hoje() - interval '10 years' - interval '40 days') returning id into p_b;
  insert into public.pessoas (igreja_id, nome, data_nascimento)
    values (v_igreja, 'Qwzteste Crianca Delta', private.hoje() - interval '6 years' + interval '3 days') returning id into p_d;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lider, 'f5c.lider@exemplo.invalid', jsonb_build_object('pessoa_id', p_lider)),
    (u_vol,   'f5c.vol@exemplo.invalid',   jsonb_build_object('pessoa_id', p_vol)),
    (u_pai,   'f5c.pai@exemplo.invalid',   jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lider, u_vol, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lider, v_kids, 'lider'), (u_vol, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.familias (departamento_id) values (v_kids) returning id into v_fam;
  insert into public.familias (departamento_id) values (v_kids) returning id into v_fam2;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (v_fam, p_pai, true), (v_fam2, p_outro, true);
  insert into public.criancas (familia_id, pessoa_id, alergias_observacoes) values (v_fam, p_a, 'Alergia fictícia') returning id into c_a;
  insert into public.criancas (familia_id, pessoa_id) values (v_fam, p_b) returning id into c_b;
  insert into public.criancas (familia_id, pessoa_id) values (v_fam2, p_d) returning id into c_d;

  -- ================= TESTES =================
  -- Visitante sem login
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  txt := public.keep_alive();
  r := r || format(E'\n%s keep-alive continua respondendo: %s', case when txt='ok' then '✅' else '❌' end, txt); falhas := falhas + (txt<>'ok')::int;
  begin
    j := public.presentes_do_culto(gen_random_uuid());
    r := r || E'\n❌ visitante sem login viu Presentes'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê Presentes';
  end;
  begin
    v_id := public.chamar_responsavel(gen_random_uuid());
    r := r || E'\n❌ visitante sem login chamou responsável'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não chama responsável';
  end;
  begin
    txt := public.gerar_link_telao();
    r := r || E'\n❌ visitante sem login gerou link do telão'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não gera link do telão';
  end;
  begin
    select count(*) into n from public.chamadas_responsavel;
    r := r || E'\n❌ visitante sem login leu a tabela de chamadas'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não lê a tabela de chamadas';
  end;
  begin
    select count(*) into n from private.telao_acesso;
    r := r || E'\n❌ visitante sem login leu o acesso do telão'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não lê o acesso do telão';
  end;
  perform set_config('role', 'authenticated', true);

  -- Líder cria um culto extra que começou há 7 minutos (10–12 junto com 7–9)
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  culto := public.criar_culto_extra(private.hoje(), to_char(v_agora - interval '7 minutes', 'HH24:MI')::time, 'Culto Teste 5C',
    jsonb_build_array(jsonb_build_object('sala_id', s10, 'cancelada', false, 'junto_com', s7)));

  -- Voluntária faz o check-in de 3 crianças (2 famílias)
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  j := public.fazer_checkin(culto, array[c_a, c_b, c_d]);
  select id into k_a from public.checkins where culto_id = culto and crianca_id = c_a;
  select id into k_b from public.checkins where culto_id = culto and crianca_id = c_b;
  select id into k_d from public.checkins where culto_id = culto and crianca_id = c_d;

  -- Presentes
  j := public.presentes_do_culto(culto);
  select count(*) into n from jsonb_array_elements(j->'salas') s, jsonb_array_elements(s->'criancas') c;
  r := r || format(E'\n%s Presentes lista as 3 crianças: %s', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from jsonb_array_elements(j->'salas') s, jsonb_array_elements(s->'criancas') c
   where s->>'nome' = '7 a 12 anos' and (c->>'crianca_id')::uuid = c_b;
  r := r || format(E'\n%s salas juntas respeitadas (10 anos em "7 a 12 anos"): %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from jsonb_array_elements(j->'salas') s, jsonb_array_elements(s->'criancas') c
   where (c->>'crianca_id')::uuid = c_d and (c->>'aniversario')::boolean;
  r := r || format(E'\n%s 🎂 em Presentes: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from jsonb_array_elements(j->'salas') s, jsonb_array_elements(s->'criancas') c
   where (c->>'crianca_id')::uuid = c_a and c->>'alergias' is not null and char_length(c->>'codigo') = 4;
  r := r || format(E'\n%s alergia e código em Presentes: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from jsonb_array_elements(j->'salas') s, jsonb_array_elements(s->'criancas') c
   where c ? 'data_nascimento' or c ? 'nascimento' or c ? 'telefone';
  r := r || format(E'\n%s Presentes não devolve data de nascimento nem telefone: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Responsável não vê Presentes nem as chamadas
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));
  begin
    j := public.presentes_do_culto(culto);
    r := r || E'\n❌ responsável viu Presentes'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê Presentes';
  end;
  begin
    v_id := public.chamar_responsavel(k_a);
    r := r || E'\n❌ responsável chamou no telão'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não chama no telão';
  end;
  begin
    txt := public.marcar_saida(k_a);
    r := r || E'\n❌ responsável marcou "Saiu"'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não marca "Saiu"';
  end;

  -- Voluntária chama o responsável
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  ch_a := public.chamar_responsavel(k_a);
  v_id := public.chamar_responsavel(k_a);
  select count(*) into n from public.chamadas_responsavel where checkin_id = k_a and situacao = 'aguardando';
  r := r || format(E'\n%s chamar de novo não duplica (uma chamada aberta por criança): %s', case when n=1 and v_id=ch_a then '✅' else '❌' end, n); falhas := falhas + (n<>1 or v_id<>ch_a)::int;
  begin
    insert into public.chamadas_responsavel (checkin_id, culto_id, departamento_id) values (k_b, culto, v_kids);
    r := r || E'\n❌ chamada gravada direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ ninguém grava chamada direto na tabela';
  end;
  begin
    txt := public.gerar_link_telao();
    r := r || E'\n❌ voluntária (sem papel de líder) gerou link do telão'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ só a liderança gera o link do telão';
  end;

  -- Líder gera o link do telão
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  cod1 := public.gerar_link_telao();
  r := r || format(E'\n%s código do telão com 32 caracteres: %s', case when cod1 ~ '^[0-9a-f]{32}$' then '✅' else '❌' end, char_length(cod1)); falhas := falhas + (cod1 !~ '^[0-9a-f]{32}$')::int;
  perform set_config('role', 'postgres', true);
  select count(*) into n from private.telao_acesso where codigo_hash = cod1 or codigo_hash like '%' || cod1 || '%';
  r := r || format(E'\n%s o banco não guarda o código, só o hash: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Telão (sem login)
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    j := public.telao_chamadas('00000000000000000000000000000000');
    r := r || E'\n❌ telão abriu com código errado'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ telão não abre com código errado';
  end;
  j := public.telao_chamadas(cod1);
  select e into x from jsonb_array_elements(j) e where (e->>'id')::uuid = ch_a;
  r := r || format(E'\n%s telão mostra a chamada: %s', case when x is not null then '✅' else '❌' end, (x is not null)); falhas := falhas + (x is null)::int;
  r := r || format(E'\n%s telão mostra primeiro e último nome (criança e responsável): %s / %s',
    case when x->>'crianca' = 'Qwzteste Alfa' and x->>'responsavel' = 'Qwzteste Um' then '✅' else '❌' end, x->>'crianca', x->>'responsavel');
  falhas := falhas + (x->>'crianca' is distinct from 'Qwzteste Alfa' or x->>'responsavel' is distinct from 'Qwzteste Um')::int;
  r := r || format(E'\n%s telão mostra código e sala: %s', case when char_length(x->>'codigo') = 4 and x->>'sala' = '3 a 6 anos' then '✅' else '❌' end, x->>'sala');
  falhas := falhas + (char_length(x->>'codigo') <> 4 or x->>'sala' is distinct from '3 a 6 anos')::int;
  select count(*) into n from jsonb_object_keys(x) k where k not in ('id', 'crianca', 'responsavel', 'codigo', 'sala', 'chamada_em');
  r := r || format(E'\n%s telão não recebe outros dados (alergia, telefone, foto…): %s campos a mais (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Líder troca o link: o antigo para na hora
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  cod2 := public.gerar_link_telao();
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    j := public.telao_chamadas(cod1);
    r := r || E'\n❌ link antigo continuou funcionando depois da troca'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ link antigo para de funcionar ao gerar um novo';
  end;
  j := public.telao_chamadas(cod2);
  r := r || format(E'\n%s link novo funciona: %s chamada(s)', case when jsonb_array_length(j) >= 1 then '✅' else '❌' end, jsonb_array_length(j)); falhas := falhas + (jsonb_array_length(j) < 1)::int;

  begin
    txt := public.telao_anunciar(cod1, ch_a);
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);  -- conferência (o telão não lê a tabela)
  select count(*) into n from public.chamadas_responsavel where id = ch_a and situacao = 'aguardando';
  perform set_config('role', 'anon', true);
  r := r || format(E'\n%s "Anunciado" com link antigo não vale: %s (esperado 1 aguardando)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  txt := public.telao_anunciar(cod2, ch_a);
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.chamadas_responsavel where id = ch_a and situacao = 'anunciada' and anunciada_em is not null;
  perform set_config('role', 'anon', true);
  r := r || format(E'\n%s telão marca "Anunciado": %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    update public.chamadas_responsavel set situacao = 'aguardando' where id = ch_a;
    get diagnostics n = row_count;
    if n > 0 then r := r || E'\n❌ telão alterou a tabela de chamadas direto'; falhas := falhas + 1;
    else r := r || E'\n✅ telão não altera a tabela de chamadas direto'; end if;
  exception when others then r := r || E'\n✅ telão não altera a tabela de chamadas direto';
  end;

  -- Voluntária vê "Anunciado" em Presentes; cancela outra chamada; "Saiu"
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  j := public.presentes_do_culto(culto);
  select count(*) into n from jsonb_array_elements(j->'salas') s, jsonb_array_elements(s->'criancas') c
   where (c->>'crianca_id')::uuid = c_a and c->'chamada'->>'situacao' = 'anunciada';
  r := r || format(E'\n%s voluntária vê "Anunciado" em Presentes: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  ch_b := public.chamar_responsavel(k_b);
  txt := public.cancelar_chamada(ch_b);
  select count(*) into n from public.chamadas_responsavel where id = ch_b and situacao = 'cancelada';
  r := r || format(E'\n%s voluntária cancela uma chamada: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  begin
    update public.checkins set saida_em = now() where id = k_a;
    r := r || E'\n❌ saída gravada direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ ninguém grava saída direto na tabela (só pelas funções)';
  end;
  txt := public.marcar_saida(k_a);
  select count(*) into n from public.checkins where id = k_a and saida_em is not null and saida_por = u_vol and not saida_automatica;
  r := r || format(E'\n%s "Saiu" registra hora e quem marcou: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    v_id := public.chamar_responsavel(k_a);
    r := r || E'\n❌ chamou responsável de criança que já saiu'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não chama responsável de criança que já saiu';
  end;
  txt := public.desfazer_saida(k_a);
  select count(*) into n from public.checkins where id = k_a and saida_em is null and saida_por is null;
  r := r || format(E'\n%s desfazer "Saiu": %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- Desfazer check-in apaga a chamada aberta junto
  ch_d := public.chamar_responsavel(k_d);
  txt := public.desfazer_checkin(k_d);
  select count(*) into n from public.chamadas_responsavel where id = ch_d;
  r := r || format(E'\n%s desfazer check-in tira a chamada do telão: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Fechamento automático (3 h depois do início do culto)
  if v_agora::time >= time '04:00' then
    ch_b := public.chamar_responsavel(k_b);
    perform set_config('role', 'postgres', true);
    update public.cultos set horario = (v_agora - interval '3 hours 30 minutes')::time where id = culto;
    perform set_config('role', 'anon', true);
    perform set_config('request.jwt.claims', '{"role":"anon"}', true);
    txt := public.keep_alive();            -- o keep-alive diário fecha os vencidos
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
    select count(*) into n from public.checkins where culto_id = culto and saida_em is null;
    r := r || format(E'\n%s check-ins fecham sozinhos 3 h depois do início: %s abertos (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
    select count(*) into n from public.checkins where id = k_b and saida_automatica and saida_por is null;
    r := r || format(E'\n%s saída automática sem "quem registrou": %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
    select count(*) into n from public.chamadas_responsavel where id = ch_b and situacao = 'cancelada';
    r := r || format(E'\n%s chamada parada é encerrada no fim do culto: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
    j := public.presentes_do_culto(culto);
    r := r || format(E'\n%s Presentes avisa que o culto terminou: %s', case when (j->'culto'->>'encerrado')::boolean then '✅' else '❌' end, j->'culto'->>'encerrado');
    falhas := falhas + (not (j->'culto'->>'encerrado')::boolean)::int;
    begin
      txt := public.desfazer_saida(k_b);
      r := r || E'\n❌ desfez saída automática'; falhas := falhas + 1;
    exception when others then r := r || E'\n✅ saída automática não pode ser desfeita';
    end;
    begin
      v_id := public.chamar_responsavel(k_a);
      r := r || E'\n❌ chamou responsável depois do fim do culto'; falhas := falhas + 1;
    exception when others then r := r || E'\n✅ não chama responsável depois do fim do culto';
    end;
  else
    r := r || E'\nℹ️ fechamento automático não testado (rode depois das 04:00)';
  end if;

  -- Desligar o telão
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  txt := public.desligar_telao();
  j := public.situacao_telao();
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    j := public.telao_chamadas(cod2);
    r := r || E'\n❌ telão continuou funcionando depois de desligado'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ telão desligado não abre';
  end;

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.auditoria where tabela in ('chamadas_responsavel', 'telao_acesso');
  r := r || format(E'\n%s auditoria registrou chamadas e link do telão: %s (esperado > 0)', case when n>0 then '✅' else '❌' end, n); falhas := falhas + (n=0)::int;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
