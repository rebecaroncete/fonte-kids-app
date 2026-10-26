-- =====================================================================
-- Teste das regras de segurança (RLS) com DADOS 100% FICTÍCIOS.
-- Roda tudo dentro de um bloco que é DESFEITO no final (nada fica salvo):
-- o resultado aparece na mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- =====================================================================
do $teste$
declare
  -- usuários fictícios
  u_admin uuid := gen_random_uuid();  u_pastor uuid := gen_random_uuid();
  u_lider uuid := gen_random_uuid();  u_recep  uuid := gen_random_uuid();
  u_vol1  uuid := gen_random_uuid();  u_vol2   uuid := gen_random_uuid();
  u_pai1  uuid := gen_random_uuid();  u_pai2   uuid := gen_random_uuid();
  u_estranho uuid := gen_random_uuid();
  v_kids uuid; v_igreja uuid; s_36 uuid; s_79 uuid;
  f1 uuid; f2 uuid; c1 uuid; c2 uuid; c3 uuid; vol1 uuid; vol2 uuid;
  culto_hoje uuid; esc_pub uuid; esc_ras uuid; item_v1 uuid; k_novo uuid;
  n bigint; txt text; ok_erro boolean;
  r text := '';
  falhas int := 0;
begin
  select id into v_kids from public.departamentos where slug = 'kids';
  select igreja_id into v_igreja from public.departamentos where id = v_kids;
  select id into s_36 from public.salas where departamento_id = v_kids and nome = '3 a 6 anos';
  select id into s_79 from public.salas where departamento_id = v_kids and nome = '7 a 9 anos';

  -- ---------- Montagem (como administrador do banco) ----------
  insert into auth.users (id, email, raw_user_meta_data) values
    (u_admin,'teste.admin@exemplo.invalid','{"nome":"Admin Teste"}'),
    (u_pastor,'teste.pastor@exemplo.invalid','{"nome":"Pastor Teste"}'),
    (u_lider,'teste.lider@exemplo.invalid','{"nome":"Líder Teste"}'),
    (u_recep,'teste.recep@exemplo.invalid','{"nome":"Recepção Teste"}'),
    (u_vol1,'teste.vol1@exemplo.invalid','{"nome":"Voluntária Um"}'),
    (u_vol2,'teste.vol2@exemplo.invalid','{"nome":"Voluntária Dois"}'),
    (u_pai1,'teste.pai1@exemplo.invalid','{"nome":"Responsável Um"}'),
    (u_pai2,'teste.pai2@exemplo.invalid','{"nome":"Responsável Dois"}'),
    (u_estranho,'teste.x@exemplo.invalid','{"nome":"Sem Papel"}');

  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_admin, null, 'admin'), (u_pastor, null, 'pastor'),
    (u_lider, v_kids, 'lider'), (u_recep, v_kids, 'recepcao'),
    (u_vol1, v_kids, 'voluntaria'), (u_vol2, v_kids, 'voluntaria'),
    (u_pai1, null, 'responsavel'), (u_pai2, null, 'responsavel');

  insert into public.familias (departamento_id) values (v_kids) returning id into f1;
  insert into public.familias (departamento_id) values (v_kids) returning id into f2;
  insert into public.responsaveis (familia_id, perfil_id, nome, telefone, principal) values
    (f1, u_pai1, 'Responsável Um', '5500000000001', true),
    (f2, u_pai2, 'Responsável Dois', '5500000000002', true);
  insert into public.criancas (familia_id, nome) values (f1, 'Criança Teste A') returning id into c1;
  insert into public.criancas (familia_id, nome) values (f2, 'Criança Teste B') returning id into c2;
  insert into public.criancas (familia_id, nome) values (f2, 'Criança Teste C') returning id into c3; -- sem check-in

  insert into public.voluntarias (departamento_id, perfil_id, nome, status, funcao)
    values (v_kids, u_vol1, 'Voluntária Um', 'ativa', 'professora') returning id into vol1;
  insert into public.voluntarias (departamento_id, perfil_id, nome, status)
    values (v_kids, u_vol2, 'Voluntária Dois', 'pendente') returning id into vol2;

  insert into public.cultos (igreja_id, data, horario, nome)
    values (v_igreja, private.hoje(), '10:00', 'Culto teste') returning id into culto_hoje;
  insert into public.checkins (culto_id, crianca_id, sala_id) values (culto_hoje, c1, s_36);
  insert into public.checkins (culto_id, crianca_id, sala_id) values (culto_hoje, c2, s_79);

  insert into public.escalas (departamento_id, mes_referencia, status)
    values (v_kids, date_trunc('month', private.hoje())::date, 'publicada') returning id into esc_pub;
  insert into public.escalas (departamento_id, mes_referencia, status)
    values (v_kids, (date_trunc('month', private.hoje()) + interval '1 month')::date, 'rascunho') returning id into esc_ras;
  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao, voluntaria_id)
    values (esc_pub, culto_hoje, s_36, 'professora', vol1) returning id into item_v1;
  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao, voluntaria_id)
    values (esc_ras, culto_hoje, s_79, 'auxiliar', vol2);

  -- ================= TESTES =================
  -- Visitante sem login (anon)
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    select count(*) into n from public.criancas;
    r := r || E'\n❌ anon conseguiu ler crianças'; falhas := falhas + 1;
  exception when insufficient_privilege then
    r := r || E'\n✅ anon NÃO lê crianças';
  end;
  begin
    insert into public.log_erros (mensagem) values ('teste');
    r := r || E'\n✅ anon registra erro no log';
  exception when others then
    r := r || E'\n❌ anon não registrou erro: ' || sqlerrm; falhas := falhas + 1;
  end;

  -- Usuário logado SEM papel
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_estranho, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s sem papel vê %s crianças (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.checkins;      r := r || format(E'\n%s sem papel vê %s check-ins (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.responsaveis;  r := r || format(E'\n%s sem papel vê %s responsáveis (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.perfis;        r := r || format(E'\n%s sem papel vê %s perfis (esperado 1 = ele mesmo)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- Pai/mãe da família 1
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s pai1 vê %s crianças (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.criancas where id = c2; r := r || format(E'\n%s pai1 vê criança de OUTRA família: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.responsaveis;  r := r || format(E'\n%s pai1 vê %s responsáveis (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.checkins;      r := r || format(E'\n%s pai1 vê %s check-ins (esperado 1, do filho)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  update public.criancas set alergias_observacoes = 'x' where id = c2; get diagnostics n = row_count;
  r := r || format(E'\n%s pai1 alterou criança de outra família: %s linhas (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  begin
    insert into public.criancas (familia_id, nome) values (f2, 'Intrusa');
    r := r || E'\n❌ pai1 cadastrou criança em outra família'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ pai1 NÃO cadastra criança em outra família';
  end;
  begin
    insert into public.papeis_usuario (perfil_id, departamento_id, papel) values (u_pai1, v_kids, 'lider');
    r := r || E'\n❌ pai1 se promoveu a líder'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ pai1 NÃO se promove a líder';
  end;
  begin
    update public.perfis set ativo = false, troca_senha_obrigatoria = false where id = u_pai1;
    r := r || E'\n❌ pai1 alterou campos protegidos do perfil'; falhas := falhas + 1;
  exception when raise_exception then r := r || E'\n✅ pai1 NÃO altera campos protegidos do perfil';
  end;

  -- Voluntária 1 (escalada HOJE na sala 3–6, escala publicada)
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s vol1 vê %s crianças (esperado 1, da sala dela)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.checkins;      r := r || format(E'\n%s vol1 vê %s check-ins (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.responsaveis;  r := r || format(E'\n%s vol1 vê %s responsáveis (esperado 1, só hoje e da sala)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.voluntarias;   r := r || format(E'\n%s vol1 vê %s fichas de voluntária (esperado 1 = a própria)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.escalas;       r := r || format(E'\n%s vol1 vê %s escalas (esperado 1, rascunho oculto)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.equipe_departamento(v_kids); r := r || format(E'\n%s vol1 vê lista da equipe (dados mínimos): %s ativa(s) (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    perform public.responder_escala(item_v1, 'ciente');
    r := r || E'\n✅ vol1 marca "Ciente" na própria escala';
  exception when others then r := r || E'\n❌ vol1 não conseguiu marcar Ciente: ' || sqlerrm; falhas := falhas + 1;
  end;
  begin
    insert into public.checkins (culto_id, crianca_id, sala_id) values (culto_hoje, c3, s_36);
    r := r || E'\n✅ vol1 faz check-in na sala em que está escalada hoje (permitido)';
  exception when others then r := r || E'\n❌ vol1 não fez check-in na própria sala: ' || sqlerrm; falhas := falhas + 1;
  end;
  begin
    insert into public.notificacoes (destinatario_id, titulo) values (u_vol2, 'oi');
    r := r || E'\n❌ vol1 enviou notificação sem ser líder'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ vol1 NÃO envia notificação (só líderes)';
  end;

  -- Voluntária 2 (cadastro pendente, não escalada)
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol2, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s vol2 vê %s crianças (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  begin
    update public.voluntarias set status = 'ativa' where id = vol2;
    r := r || E'\n❌ vol2 se auto-aprovou'; falhas := falhas + 1;
  exception when raise_exception then r := r || E'\n✅ vol2 NÃO se auto-aprova';
  end;
  begin
    perform public.responder_escala(item_v1, 'recusado');
    r := r || E'\n❌ vol2 respondeu escala de outra pessoa'; falhas := falhas + 1;
  exception when raise_exception then r := r || E'\n✅ vol2 NÃO responde escala de outra pessoa';
  end;

  -- Recepção
  perform set_config('request.jwt.claims', json_build_object('sub', u_recep, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s recepção vê %s crianças (esperado 3)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from public.voluntarias;   r := r || format(E'\n%s recepção vê %s fichas de voluntária (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select codigo_seguranca into txt from public.checkins where crianca_id = c1;
  r := r || format(E'\n%s código de segurança gerado: %s caracteres (esperado 4)', case when length(txt)=4 then '✅' else '❌' end, length(txt)); falhas := falhas + (length(txt)<>4)::int;
  update public.checkins set saida_em = now(), retirado_por_nome = 'Responsável Um', retirado_por_autorizado = true where crianca_id = c1 and culto_id = culto_hoje;
  select count(*) into n from public.checkins where crianca_id = c1 and saida_por = u_recep;
  r := r || format(E'\n%s check-out registra quem liberou (esperado 1): %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    update public.checkins set codigo_seguranca = 'ZZZZ' where crianca_id = c1;
    r := r || E'\n❌ recepção alterou o código de segurança'; falhas := falhas + 1;
  exception when raise_exception then r := r || E'\n✅ código de segurança não pode ser alterado';
  end;

  -- Líder
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  select count(*) into n from public.voluntarias;   r := r || format(E'\n%s líder vê %s voluntárias (esperado 2)', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  select count(*) into n from public.escalas;       r := r || format(E'\n%s líder vê %s escalas (esperado 2, inclui rascunho)', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  update public.voluntarias set status = 'ativa' where id = vol2; get diagnostics n = row_count;
  r := r || format(E'\n%s líder aprova voluntária (esperado 1): %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    insert into public.papeis_usuario (perfil_id, departamento_id, papel) values (u_vol2, v_kids, 'lider');
    r := r || E'\n✅ líder promove voluntária a líder';
  exception when others then r := r || E'\n❌ líder não promoveu: ' || sqlerrm; falhas := falhas + 1;
  end;
  begin
    insert into public.papeis_usuario (perfil_id, departamento_id, papel) values (u_vol1, null, 'pastor');
    r := r || E'\n❌ líder criou um pastor'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ líder NÃO cria pastor/admin';
  end;
  select count(*) into n from public.auditoria;     r := r || format(E'\n%s líder vê %s registros de auditoria (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Pastor
  perform set_config('request.jwt.claims', json_build_object('sub', u_pastor, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s pastor vê %s crianças (esperado 3)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from public.auditoria;     r := r || format(E'\n%s pastor vê auditoria: %s registros (esperado > 0)', case when n>0 then '✅' else '❌' end, n); falhas := falhas + (n=0)::int;
  select count(*) into n from public.auditoria where campos_alterados @> array['saida_em'];
  r := r || format(E'\n%s auditoria registrou o check-out (só nomes de campos, sem dados): %s', case when n>=1 then '✅' else '❌' end, n); falhas := falhas + (n=0)::int;

  -- Admin
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
  select count(*) into n from public.log_erros;     r := r || format(E'\n%s admin lê log de erros: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  raise exception E'RESULTADO DOS TESTES — falhas: %\n%', falhas, r;
end
$teste$;
