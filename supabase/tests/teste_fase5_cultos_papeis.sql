-- =====================================================================
-- Teste da Fase 5 · Etapa 5A (agenda de cultos, salas por culto, papéis)
-- com DADOS 100% FICTÍCIOS. Tudo roda dentro de um bloco que é DESFEITO
-- no final (nada fica salvo): o resultado aparece na mensagem de erro
-- "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- =====================================================================
do $teste$
declare
  u_admin uuid := gen_random_uuid(); u_pastor uuid := gen_random_uuid();
  u_lider uuid := gen_random_uuid(); u_vol uuid := gen_random_uuid();
  u_pai uuid := gen_random_uuid();
  p_admin uuid; p_pastor uuid; p_lider uuid; p_vol uuid; p_pai uuid; p_cri uuid;
  v_kids uuid; v_igreja uuid; s0 uuid; s3 uuid; s7 uuid; s10 uuid;
  v_fam uuid; v_cri uuid;
  rec uuid; c1 uuid; c2 uuid; extra uuid;
  j jsonb; n bigint; txt text;
  r text := ''; falhas int := 0; total int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s0  from public.salas where departamento_id = v_kids and idade_min = 0;
  select id into s3  from public.salas where departamento_id = v_kids and idade_min = 3;
  select id into s7  from public.salas where departamento_id = v_kids and idade_min = 7;
  select id into s10 from public.salas where departamento_id = v_kids and idade_min = 10;

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Admin Teste F5')  returning id into p_admin;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Pastor Teste F5') returning id into p_pastor;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Líder Teste F5')  returning id into p_lider;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Voluntária Teste F5') returning id into p_vol;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Responsável Teste F5') returning id into p_pai;
  insert into public.pessoas (igreja_id, nome, data_nascimento)
    values (v_igreja, 'Criança Teste F5', private.hoje() - interval '10 years') returning id into p_cri;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_admin, 'f5.admin@exemplo.invalid',  jsonb_build_object('pessoa_id', p_admin)),
    (u_pastor,'f5.pastor@exemplo.invalid', jsonb_build_object('pessoa_id', p_pastor)),
    (u_lider, 'f5.lider@exemplo.invalid',  jsonb_build_object('pessoa_id', p_lider)),
    (u_vol,   'f5.vol@exemplo.invalid',    jsonb_build_object('pessoa_id', p_vol)),
    (u_pai,   'f5.pai@exemplo.invalid',    jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_admin, u_pastor, u_lider, u_vol, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_admin, null, 'admin'), (u_pastor, null, 'pastor'), (u_lider, v_kids, 'lider'),
    (u_vol, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.familias (departamento_id) values (v_kids) returning id into v_fam;
  insert into public.criancas (familia_id, pessoa_id) values (v_fam, p_cri) returning id into v_cri;

  -- ================= TESTES =================
  -- Visitante sem login
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    j := public.cultos_proximos(14);
    r := r || E'\n❌ visitante sem login leu os cultos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não lê os cultos';
  end;

  perform set_config('role', 'authenticated', true);

  -- Responsável (sem papel de equipe)
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  begin
    j := public.cultos_proximos(14);
    r := r || E'\n❌ responsável leu a lista de cultos da equipe'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não lê a lista de cultos da equipe';
  end;

  -- Voluntária
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  select count(*) into n from public.papeis_usuario where perfil_id = u_vol and papel = 'recepcao';
  r := r || format(E'\n%s voluntária ganhou recepção automaticamente: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  j := public.cultos_proximos(14);
  n := jsonb_array_length(j);
  r := r || format(E'\n%s voluntária vê os cultos dos próximos 14 dias: %s (esperado 4 ou mais)', case when n>=4 then '✅' else '❌' end, n); falhas := falhas + (n<4)::int;
  select count(*) into n from jsonb_array_elements(public.agenda_cultos()) a
   where a->>'dia_semana' = '2' and exists (select 1 from jsonb_array_elements(a->'salas') s where s->>'nome' = '7 a 12 anos');
  r := r || format(E'\n%s agenda: terça com a sala "7 a 12 anos": %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    perform public.salvar_culto_agenda(null, 'Culto Teste Vol', 3, '03:11');
    r := r || E'\n❌ voluntária mudou a agenda'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não muda a agenda';
  end;
  begin
    insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, private.hoje(), '03:12', 'Direto');
    r := r || E'\n❌ voluntária criou culto direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ ninguém grava culto direto na tabela (só pelas funções)';
  end;
  begin
    perform public.definir_papel(u_vol, 'lider', true);
    r := r || E'\n❌ voluntária se deu acesso de líder'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não dá acesso de líder';
  end;
  begin
    perform * from public.papeis_voluntarias();
    r := r || E'\n❌ voluntária viu a lista de acessos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não vê a lista de acessos';
  end;

  -- Líder: agenda
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  rec := public.salvar_culto_agenda(null, 'Culto Teste F5', 3, '03:17');
  select count(*) into n from public.cultos where culto_recorrente_id = rec;
  r := r || format(E'\n%s líder cria culto na agenda e os dias aparecem sozinhos: %s (esperado 2 ou mais)', case when n>=2 then '✅' else '❌' end, n); falhas := falhas + (n<2)::int;
  select id into c1 from public.cultos where culto_recorrente_id = rec order by data limit 1;
  select id into c2 from public.cultos where culto_recorrente_id = rec order by data offset 1 limit 1;

  txt := public.definir_salas_agenda(rec, jsonb_build_array(jsonb_build_object('sala_id', s10, 'junto_com', s7)));
  select count(*) into n from public.culto_salas where culto_id in (c1, c2) and sala_id = s10 and combinada_com_sala_id = s7;
  r := r || format(E'\n%s juntar salas na agenda vale para os próximos cultos: %s (esperado 2)', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;

  begin
    perform public.definir_salas_agenda(rec, jsonb_build_array(
      jsonb_build_object('sala_id', s10, 'junto_com', s7), jsonb_build_object('sala_id', s7, 'junto_com', s3)));
    r := r || E'\n❌ aceitou juntar numa sala que já está junto com outra'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recusa juntar numa sala que já está junto com outra';
  end;
  begin
    perform public.definir_salas_agenda(rec, jsonb_build_array(jsonb_build_object('sala_id', s10, 'junto_com', s7, 'cancelada', true)));
    r := r || E'\n❌ aceitou sala fechada e junto ao mesmo tempo'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recusa sala fechada e junto ao mesmo tempo';
  end;

  -- Líder: ajuste de um dia só
  txt := public.definir_salas_dia(c1, jsonb_build_array(jsonb_build_object('sala_id', s0, 'cancelada', true)));
  txt := public.definir_salas_agenda(rec, '[]'::jsonb);  -- agenda volta a ter todas separadas
  select count(*) into n from public.culto_salas where culto_id = c1 and sala_id = s0 and cancelada;
  r := r || format(E'\n%s ajuste de um dia não é desfeito por mudança na agenda: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.culto_salas where culto_id = c2;
  r := r || format(E'\n%s os outros dias seguem a agenda nova: %s exceções (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  txt := public.definir_salas_dia(c1, null);
  select count(*) into n from public.cultos where id = c1 and not salas_personalizadas;
  r := r || format(E'\n%s "voltar ao padrão da agenda" num dia: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- check-in fictício (como o servidor) na sala 10 a 12 do 2º dia
  perform set_config('role', 'postgres', true);
  insert into public.checkins (culto_id, crianca_id, sala_id) values (c2, v_cri, s10);
  perform set_config('role', 'authenticated', true);
  txt := public.definir_salas_dia(c2, jsonb_build_array(jsonb_build_object('sala_id', s10, 'junto_com', s7)));
  select count(*) into n from public.checkins where culto_id = c2 and sala_id = s7;
  r := r || format(E'\n%s juntar salas no dia leva quem já fez check-in para a sala que recebe: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    perform public.definir_salas_dia(c2, jsonb_build_array(jsonb_build_object('sala_id', s7, 'cancelada', true)));
    r := r || E'\n❌ fechou sala com criança no check-in'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não fecha sala com criança no check-in';
  end;
  begin
    perform public.cancelar_culto(c2, true);
    r := r || E'\n❌ cancelou culto com check-in'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não cancela culto que já tem check-in';
  end;
  txt := public.cancelar_culto(c1, true);
  select count(*) into n from public.cultos where id = c1 and cancelado;
  r := r || format(E'\n%s líder cancela culto sem check-in: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- desativar da agenda: some dos próximos dias, menos o que tem check-in
  perform public.salvar_culto_agenda(rec, 'Culto Teste F5', 3, '03:17', false);
  select count(*) into n from public.cultos where culto_recorrente_id = rec and data >= private.hoje();
  r := r || format(E'\n%s desativar culto da agenda tira os próximos dias (fica só o que tem check-in): %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- culto extra
  extra := public.criar_culto_extra(private.hoje() + 3, '03:19', 'Culto Extra Teste',
             jsonb_build_array(jsonb_build_object('sala_id', s10, 'junto_com', s7)));
  select count(*) into n from jsonb_array_elements(public.cultos_proximos(14)) c
   where c->>'id' = extra::text and (c->>'extra')::boolean
     and exists (select 1 from jsonb_array_elements(c->'salas') s where s->>'nome' = '7 a 12 anos');
  r := r || format(E'\n%s culto extra aparece na lista, com as salas juntas: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    perform public.criar_culto_extra(private.hoje() - 1, '03:20', 'Culto Passado');
    r := r || E'\n❌ criou culto extra no passado'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não cria culto extra no passado';
  end;

  -- Líder: papéis
  txt := public.definir_papel(u_vol, 'lider', true);
  select count(*) into n from public.papeis_usuario where perfil_id = u_vol and papel = 'lider';
  r := r || format(E'\n%s líder dá acesso de líder a uma voluntária: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.papeis_voluntarias() where perfil_id = u_vol and lider and recepcao;
  r := r || format(E'\n%s lista de acessos mostra a voluntária como líder e recepção: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  txt := public.definir_papel(u_vol, 'lider', false);
  txt := public.definir_papel(u_vol, 'recepcao', false);
  select count(*) into n from public.papeis_usuario where perfil_id = u_vol and papel in ('lider', 'recepcao');
  r := r || format(E'\n%s líder tira líder e recepção da voluntária: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  begin
    perform public.definir_papel(u_pai, 'recepcao', true);
    r := r || E'\n❌ deu recepção a quem não é voluntária'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ acessos só para voluntárias';
  end;
  begin
    perform public.definir_papel(u_vol, 'pastor', true);
    r := r || E'\n❌ líder deu papel de pastor'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ líder não dá papel de pastor';
  end;
  delete from public.papeis_usuario where perfil_id = u_lider and papel = 'lider'; get diagnostics n = row_count;
  r := r || format(E'\n%s líder não consegue tirar o próprio acesso (direto na tabela): %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Pastor: não cria outro pastor (só admin)
  perform set_config('request.jwt.claims', json_build_object('sub', u_pastor, 'role', 'authenticated')::text, true);
  begin
    insert into public.papeis_usuario (perfil_id, departamento_id, papel) values (u_vol, null, 'pastor');
    r := r || E'\n❌ pastor criou outro pastor'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ pastor não cria pastor (só admin)';
  end;
  txt := public.definir_papel(u_vol, 'recepcao', true);
  select count(*) into n from public.papeis_usuario where perfil_id = u_vol and papel = 'recepcao';
  r := r || format(E'\n%s pastor dá acesso de recepção: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- Admin
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
  begin
    insert into public.papeis_usuario (perfil_id, departamento_id, papel) values (u_vol, null, 'pastor');
    r := r || E'\n✅ admin cria pastor';
  exception when others then r := r || E'\n❌ admin não criou pastor: ' || sqlerrm; falhas := falhas + 1;
  end;
  select count(*) into n from public.auditoria where tabela in ('culto_recorrente_salas', 'cultos_recorrentes', 'culto_salas');
  r := r || format(E'\n%s auditoria registrou as mudanças da agenda e das salas: %s (esperado > 0)', case when n>0 then '✅' else '❌' end, n); falhas := falhas + (n=0)::int;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
