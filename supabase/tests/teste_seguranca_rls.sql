-- =====================================================================
-- Teste das regras de segurança (RLS) com DADOS 100% FICTÍCIOS.
-- Roda tudo dentro de um bloco que é DESFEITO no final (nada fica salvo):
-- o resultado aparece na mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- Fase 4: cadastro único de pessoas (pessoas, relacoes_pessoas,
-- possiveis_duplicidades, nascimentos(), fotos_pessoas()).
-- =====================================================================
do $teste$
declare
  -- usuários fictícios
  u_admin uuid := gen_random_uuid();  u_pastor uuid := gen_random_uuid();
  u_lider uuid := gen_random_uuid();  u_recep  uuid := gen_random_uuid();
  u_vol1  uuid := gen_random_uuid();  u_vol2   uuid := gen_random_uuid();
  u_pai1  uuid := gen_random_uuid();  u_pai2   uuid := gen_random_uuid();
  u_estranho uuid := gen_random_uuid();
  -- pessoas fictícias
  p_admin uuid; p_pastor uuid; p_lider uuid; p_recep uuid; p_vol1 uuid; p_vol2 uuid;
  p_pai1 uuid; p_pai2 uuid; pc1 uuid; pc2 uuid; pc3 uuid; p_nova uuid; pvol3 uuid; pvol4 uuid; pdup uuid; p_c3 uuid;
  v_kids uuid; v_igreja uuid; s_36 uuid; s_79 uuid;
  f1 uuid; f2 uuid; c1 uuid; c2 uuid; c3 uuid; vol1 uuid; vol2 uuid;
  culto_hoje uuid; esc_pub uuid; esc_ras uuid; item_v1 uuid; dup_id uuid;
  n bigint; m bigint; vol3 uuid; vol4 uuid; txt text;
  r text := '';
  falhas int := 0;
  total int := 0;
begin
  -- Departamento e salas FICTÍCIOS, separados dos dados reais
  select igreja_id into v_igreja from public.departamentos where slug = 'kids';
  insert into public.departamentos (igreja_id, nome, slug)
    values (v_igreja, 'Departamento Teste RLS', 'teste-rls-' || substr(gen_random_uuid()::text, 1, 8))
    returning id into v_kids;
  insert into public.salas (departamento_id, nome, idade_min, idade_max, capacidade, ordem)
    values (v_kids, '3 a 6 anos', 3, 6, 20, 1) returning id into s_36;
  insert into public.salas (departamento_id, nome, idade_min, idade_max, capacidade, ordem)
    values (v_kids, '7 a 9 anos', 7, 9, 25, 2) returning id into s_79;

  -- ---------- Montagem (como administrador do banco) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Admin Teste')       returning id into p_admin;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Pastor Teste')      returning id into p_pastor;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Líder Teste')       returning id into p_lider;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Recepção Teste')    returning id into p_recep;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Voluntária Um')     returning id into p_vol1;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Voluntária Dois')   returning id into p_vol2;
  insert into public.pessoas (igreja_id, nome, telefone, data_nascimento)
    values (v_igreja, 'Responsável Um', '5500000000001', '1980-02-02') returning id into p_pai1;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Responsável Dois', '5500000000002') returning id into p_pai2;
  insert into public.pessoas (igreja_id, nome, data_nascimento)
    values (v_igreja, 'Criança Teste A', private.hoje() - interval '5 years') returning id into pc1;
  insert into public.pessoas (igreja_id, nome, data_nascimento)
    values (v_igreja, 'Criança Teste B', private.hoje() - interval '8 years') returning id into pc2;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Criança Teste C') returning id into pc3;

  -- o login é ligado à pessoa pelo servidor (raw_app_meta_data)
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_admin,'teste.admin@exemplo.invalid',  jsonb_build_object('pessoa_id', p_admin)),
    (u_pastor,'teste.pastor@exemplo.invalid',jsonb_build_object('pessoa_id', p_pastor)),
    (u_lider,'teste.lider@exemplo.invalid',  jsonb_build_object('pessoa_id', p_lider)),
    (u_recep,'teste.recep@exemplo.invalid',  jsonb_build_object('pessoa_id', p_recep)),
    (u_vol1,'teste.vol1@exemplo.invalid',    jsonb_build_object('pessoa_id', p_vol1)),
    (u_vol2,'teste.vol2@exemplo.invalid',    jsonb_build_object('pessoa_id', p_vol2)),
    (u_pai1,'teste.pai1@exemplo.invalid',    jsonb_build_object('pessoa_id', p_pai1)),
    (u_pai2,'teste.pai2@exemplo.invalid',    jsonb_build_object('pessoa_id', p_pai2)),
    (u_estranho,'teste.x@exemplo.invalid',   '{}'::jsonb);

  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_admin, null, 'admin'), (u_pastor, null, 'pastor'),
    (u_lider, v_kids, 'lider'), (u_recep, v_kids, 'recepcao'),
    (u_vol1, v_kids, 'voluntaria'), (u_vol2, v_kids, 'voluntaria'),
    (u_pai1, null, 'responsavel'), (u_pai2, null, 'responsavel');

  insert into public.familias (departamento_id) values (v_kids) returning id into f1;
  insert into public.familias (departamento_id) values (v_kids) returning id into f2;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values
    (f1, p_pai1, true), (f2, p_pai2, true);
  insert into public.criancas (familia_id, pessoa_id) values (f1, pc1) returning id into c1;
  insert into public.criancas (familia_id, pessoa_id) values (f2, pc2) returning id into c2;
  insert into public.criancas (familia_id, pessoa_id) values (f2, pc3) returning id into c3; -- sem check-in
  insert into public.responsaveis_criancas (responsavel_id, crianca_id)
    select r.id, c.id from public.responsaveis r join public.criancas c using (familia_id) where c.id in (c1, c2, c3);
  insert into public.pendencias_cadastro (familia_id, tipo, mensagem)
    values (f1, 'teste', 'Pendência de teste 1'), (f2, 'teste', 'Pendência de teste 2');
  insert into public.relacoes_pessoas (pessoa_id, relacionada_id, tipo, origem) values
    (p_pai1, pc1, 'pai', 'legado'), (p_pai2, pc2, 'mae', 'legado');

  insert into public.voluntarias (departamento_id, pessoa_id, status, funcao)
    values (v_kids, p_vol1, 'ativa', 'professora') returning id into vol1;
  insert into public.voluntarias (departamento_id, pessoa_id, status)
    values (v_kids, p_vol2, 'pendente') returning id into vol2;

  insert into public.cultos (igreja_id, data, horario, nome)
    values (v_igreja, private.hoje(), '03:33', 'Culto teste') returning id into culto_hoje;
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
    select count(*) into n from public.pessoas;
    r := r || E'\n❌ anon conseguiu ler pessoas'; falhas := falhas + 1;
  exception when insufficient_privilege then
    r := r || E'\n✅ PESSOAS: anon NÃO lê pessoas';
  end;
  begin
    insert into public.log_erros (mensagem) values ('teste');
    r := r || E'\n✅ anon registra erro no log';
  exception when others then
    r := r || E'\n❌ anon não registrou erro: ' || sqlerrm; falhas := falhas + 1;
  end;

  -- Usuário logado SEM papel (e sem pessoa)
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_estranho, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s sem papel vê %s crianças (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.checkins;      r := r || format(E'\n%s sem papel vê %s check-ins (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.responsaveis;  r := r || format(E'\n%s sem papel vê %s responsáveis (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.responsaveis_criancas; r := r || format(E'\n%s sem papel vê %s vínculos responsável–criança (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.pendencias_cadastro;   r := r || format(E'\n%s sem papel vê %s pendências (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.perfis;        r := r || format(E'\n%s sem papel vê %s perfis (esperado 1 = ele mesmo)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.pessoas;       r := r || format(E'\n%s PESSOAS: sem papel vê %s pessoas (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.relacoes_pessoas; r := r || format(E'\n%s PESSOAS: sem papel vê %s relações familiares (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.possiveis_duplicidades; r := r || format(E'\n%s PESSOAS: sem papel vê %s possíveis duplicidades (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  begin
    insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Intrusa');
    r := r || E'\n❌ sem papel cadastrou pessoa'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ PESSOAS: sem papel NÃO cadastra pessoa';
  end;

  -- Pai/mãe da família 1
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s pai1 vê %s crianças (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.criancas where id = c2; r := r || format(E'\n%s pai1 vê criança de OUTRA família: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.responsaveis;  r := r || format(E'\n%s pai1 vê %s responsáveis (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.checkins;      r := r || format(E'\n%s pai1 vê %s check-ins (esperado 1, do filho)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.responsaveis_criancas; r := r || format(E'\n%s pai1 vê %s vínculos responsável–criança (esperado 1, o dele)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.pendencias_cadastro;   r := r || format(E'\n%s pai1 vê %s pendências (esperado 1, a da família)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  update public.criancas set alergias_observacoes = 'x' where id = c2; get diagnostics n = row_count;
  r := r || format(E'\n%s pai1 alterou criança de outra família: %s linhas (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  begin
    insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Pessoa Nova Teste') returning id into p_nova;
    r := r || E'\n✅ PESSOAS: pai1 cadastra uma pessoa nova';
  exception when others then r := r || E'\n❌ pai1 não cadastrou pessoa: ' || sqlerrm; falhas := falhas + 1;
  end;
  begin
    insert into public.criancas (familia_id, pessoa_id) values (f2, p_nova);
    r := r || E'\n❌ pai1 cadastrou criança em outra família'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ pai1 NÃO cadastra criança em outra família';
  end;
  begin
    insert into public.pessoas_autorizadas (familia_id, pessoa_id, observacao) values (f1, p_nova, 'teste');
    r := r || E'\n✅ PESSOAS: pai1 autoriza a pessoa que ele cadastrou a buscar o filho';
  exception when others then r := r || E'\n❌ pai1 não autorizou a pessoa: ' || sqlerrm; falhas := falhas + 1;
  end;
  begin
    insert into public.responsaveis (familia_id, pessoa_id) values (f1, p_pai2);
    r := r || E'\n❌ pai1 puxou a pessoa de OUTRA família para a dele'; falhas := falhas + 1;
  exception when raise_exception or insufficient_privilege then r := r || E'\n✅ PESSOAS: pai1 NÃO liga à família dele a pessoa de outra família';
  end;
  select count(*) into n from public.pessoas;       r := r || format(E'\n%s PESSOAS: pai1 vê %s pessoas (esperado 3: ele, o filho e a que cadastrou)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from public.pessoas where id in (pc2, p_pai2); r := r || format(E'\n%s PESSOAS: pai1 vê pessoas de OUTRA família: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  begin
    select count(data_nascimento) into n from public.pessoas;
    r := r || E'\n❌ pai1 leu data de nascimento direto da tabela'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ PESSOAS: data de nascimento NÃO é lida direto da tabela';
  end;
  select count(*) into n from public.nascimentos(array[pc1, pc2, p_pai2]);
  r := r || format(E'\n%s PESSOAS: pai1 recebe %s data(s) de nascimento (esperado 1, a do filho)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  update public.pessoas set sexo = 'F' where id = pc1; get diagnostics n = row_count;
  r := r || format(E'\n%s PESSOAS: pai1 corrige o cadastro do filho (esperado 1): %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  update public.pessoas set sexo = 'F' where id = pc2; get diagnostics n = row_count;
  r := r || format(E'\n%s PESSOAS: pai1 alterou pessoa de outra família: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.relacoes_pessoas; r := r || format(E'\n%s RELAÇÕES: pai1 vê %s relação(ões) (esperado 1, a dele com o filho)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    insert into public.relacoes_pessoas (pessoa_id, relacionada_id, tipo) values (p_pai1, pc2, 'tio');
    r := r || E'\n❌ pai1 gravou relação direto na tabela'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ RELAÇÕES: pai1 NÃO grava relação direto (só pela função do 1º acesso)';
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
  begin
    update public.perfis set pessoa_id = p_pai2 where id = u_pai1;
    r := r || E'\n❌ pai1 trocou a pessoa ligada ao próprio login'; falhas := falhas + 1;
  exception when raise_exception then r := r || E'\n✅ PESSOAS: pai1 NÃO troca a pessoa ligada ao login';
  end;

  -- Voluntária 1 (escalada HOJE na sala 3–6, escala publicada)
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s vol1 vê %s crianças (esperado 1, da sala dela)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.checkins;      r := r || format(E'\n%s vol1 vê %s check-ins (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.responsaveis;  r := r || format(E'\n%s vol1 vê %s responsáveis (esperado 1, só hoje e da sala)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.voluntarias;   r := r || format(E'\n%s vol1 vê %s fichas de voluntária (esperado 1 = a própria)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.escalas;       r := r || format(E'\n%s vol1 vê %s escalas (esperado 1, rascunho oculto)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.equipe_departamento(v_kids); r := r || format(E'\n%s vol1 vê lista da equipe (dados mínimos): %s ativa(s) (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.pessoas;       r := r || format(E'\n%s PESSOAS: vol1 vê %s pessoas (esperado 4: ela, a criança da sala, o responsável e o autorizado, só hoje)', case when n=4 then '✅' else '❌' end, n); falhas := falhas + (n<>4)::int;
  select count(*) into n from public.nascimentos(array[pc1, p_pai1]);
  r := r || format(E'\n%s PESSOAS: vol1 recebe %s nascimento(s) (esperado 1: da criança, não do adulto)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.relacoes_pessoas; r := r || format(E'\n%s RELAÇÕES: vol1 vê %s relação(ões) (esperado 1, da criança da sala hoje)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
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
  begin
    insert into public.voluntarias (departamento_id, pessoa_id) values (v_kids, p_pai2);
    r := r || E'\n❌ vol2 cadastrou outra pessoa como voluntária'; falhas := falhas + 1;
  exception when raise_exception or insufficient_privilege then r := r || E'\n✅ PESSOAS: vol2 NÃO cadastra outra pessoa como voluntária';
  end;

  -- Recepção
  perform set_config('request.jwt.claims', json_build_object('sub', u_recep, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas;      r := r || format(E'\n%s recepção vê %s crianças (esperado 3)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from public.voluntarias;   r := r || format(E'\n%s recepção vê %s fichas de voluntária (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.pessoas;       r := r || format(E'\n%s PESSOAS: recepção vê %s pessoas (esperado 7: ela, 3 crianças, 2 responsáveis, 1 autorizado)', case when n=7 then '✅' else '❌' end, n); falhas := falhas + (n<>7)::int;
  select count(*) into n from public.pessoas where id in (p_vol1, p_vol2); r := r || format(E'\n%s PESSOAS: recepção vê pessoas de voluntárias: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.nascimentos(array[pc1, p_pai1]);
  r := r || format(E'\n%s PESSOAS: recepção recebe %s nascimento(s) (esperado 1: da criança, não do adulto)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    insert into public.relacoes_pessoas (pessoa_id, relacionada_id, tipo) values (p_pai2, pc3, 'mae');
    r := r || E'\n✅ RELAÇÕES: recepção registra relação de família do departamento';
  exception when others then r := r || E'\n❌ recepção não registrou relação: ' || sqlerrm; falhas := falhas + 1;
  end;
  select count(*) into n from public.relacoes_pessoas; r := r || format(E'\n%s RELAÇÕES: recepção vê %s relações (esperado 3)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
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
  select count(*) into n from public.nascimentos(array[p_pai1]);
  r := r || format(E'\n%s PESSOAS: líder recebe nascimento de responsável adulto: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.relacoes_pessoas where pessoa_id in (p_pai1, p_pai2);
  r := r || format(E'\n%s RELAÇÕES: líder consulta relações (entre departamentos): %s (esperado 3)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
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
  delete from public.pessoas where id = p_pastor; get diagnostics n = row_count;
  r := r || format(E'\n%s PESSOAS: líder apagou pessoa fora do departamento dele: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Pastor
  perform set_config('request.jwt.claims', json_build_object('sub', u_pastor, 'role', 'authenticated')::text, true);
  select count(*) into n from public.criancas where id in (c1, c2, c3); r := r || format(E'\n%s pastor vê %s das 3 crianças de teste (esperado 3; vê também as reais)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from public.pessoas where id in (p_vol1, pc2, p_pai2); r := r || format(E'\n%s PESSOAS: pastor vê %s das 3 pessoas de teste (esperado 3)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from public.auditoria;     r := r || format(E'\n%s pastor vê auditoria: %s registros (esperado > 0)', case when n>0 then '✅' else '❌' end, n); falhas := falhas + (n=0)::int;
  select count(*) into n from public.auditoria where campos_alterados @> array['saida_em'];
  r := r || format(E'\n%s auditoria registrou o check-out (só nomes de campos, sem dados): %s', case when n>=1 then '✅' else '❌' end, n); falhas := falhas + (n=0)::int;

  -- Admin
  perform set_config('request.jwt.claims', json_build_object('sub', u_admin, 'role', 'authenticated')::text, true);
  select count(*) into n from public.log_erros;     r := r || format(E'\n%s admin lê log de erros: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- ================= FOTOS =================
  -- Fotos FICTÍCIAS (identificadores inventados, não existem no Cloudinary)
  -- e duas voluntárias ativas novas, uma maior e uma MENOR de idade.
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '{}', true);
  update public.pessoas set foto_public_id = 'teste/crianca-' || id where id in (pc1, pc2, pc3);
  update public.pessoas set foto_public_id = 'teste/vol1', data_nascimento = '1990-01-01' where id = p_vol1;
  insert into public.pessoas (igreja_id, nome, data_nascimento, foto_public_id)
    values (v_igreja, 'Voluntária Menor Teste', private.hoje() - interval '15 years', 'teste/vol3') returning id into pvol3;
  insert into public.pessoas (igreja_id, nome, data_nascimento, foto_public_id)
    values (v_igreja, 'Voluntária Maior Teste', '1985-05-05', 'teste/vol4') returning id into pvol4;
  insert into public.voluntarias (departamento_id, pessoa_id, status) values (v_kids, pvol3, 'ativa') returning id into vol3;
  insert into public.voluntarias (departamento_id, pessoa_id, status) values (v_kids, pvol4, 'ativa') returning id into vol4;

  -- Sem login: não pode nem chamar
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin
    select count(*) into n from public.fotos_criancas(array[c1, c2, c3]);
    r := r || E'\n❌ anon pediu fotos de crianças'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ FOTOS: anon NÃO pede fotos';
  end;
  begin
    select count(*) into n from public.fotos_pessoas(array[pc1]);
    r := r || E'\n❌ anon pediu fotos por pessoa'; falhas := falhas + 1;
  exception when insufficient_privilege then r := r || E'\n✅ FOTOS: anon NÃO pede fotos por pessoa';
  end;
  perform set_config('role', 'authenticated', true);

  -- Logado sem papel
  perform set_config('request.jwt.claims', json_build_object('sub', u_estranho, 'role', 'authenticated')::text, true);
  select count(*) into n from public.fotos_criancas(array[c1, c2, c3]);
  r := r || format(E'\n%s FOTOS: sem papel recebe %s fotos de crianças (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.fotos_voluntarias(array[vol1, vol3, vol4]);
  r := r || format(E'\n%s FOTOS: sem papel recebe %s fotos de voluntárias (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.fotos_pessoas(array[pc1, pc2, p_vol1, pvol4]);
  r := r || format(E'\n%s FOTOS: sem papel recebe %s fotos por pessoa (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Pai/mãe: só a foto do próprio filho
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.fotos_criancas(array[c1, c2, c3]);
  r := r || format(E'\n%s FOTOS: pai1 recebe %s foto(s) de crianças (esperado 1, a do filho)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.fotos_voluntarias(array[vol1, vol3, vol4]);
  r := r || format(E'\n%s FOTOS: pai1 recebe %s fotos de voluntárias (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.fotos_pessoas(array[pc1, pc2, p_vol1]);
  r := r || format(E'\n%s FOTOS: pai1 recebe %s foto(s) por pessoa (esperado 1, a do filho)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- Voluntária 1: fotos das crianças = exatamente as crianças que ela já pode ver
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.fotos_criancas(array[c1, c2, c3]);
  select count(*) into m from public.criancas where id in (c1, c2, c3);
  r := r || format(E'\n%s FOTOS: vol1 recebe %s fotos de crianças = %s crianças que ela vê', case when n=m and n>0 then '✅' else '❌' end, n, m); falhas := falhas + (n<>m or n=0)::int;
  select count(*) into n from public.fotos_criancas(array[c2]);
  r := r || format(E'\n%s FOTOS: vol1 recebe foto de criança de outra sala: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.fotos_voluntarias(array[vol1, vol3, vol4]);
  r := r || format(E'\n%s FOTOS: vol1 recebe %s fotos de voluntárias (esperado 2: a própria e a maior de idade)', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  select count(*) into n from public.fotos_voluntarias(array[vol3]);
  r := r || format(E'\n%s FOTOS: vol1 recebe foto da voluntária MENOR: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.fotos_pessoas(array[pvol3]);
  r := r || format(E'\n%s FOTOS: vol1 recebe foto da MENOR pela pessoa: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.equipe_departamento(v_kids) e where e.id = vol3 and e.foto_public_id is not null;
  r := r || format(E'\n%s FOTOS: lista da equipe esconde a foto da MENOR para a equipe: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Recepção: crianças do departamento; voluntárias só maiores
  perform set_config('request.jwt.claims', json_build_object('sub', u_recep, 'role', 'authenticated')::text, true);
  select count(*) into n from public.fotos_criancas(array[c1, c2, c3]);
  r := r || format(E'\n%s FOTOS: recepção recebe %s fotos de crianças (esperado 3)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from public.fotos_voluntarias(array[vol1, vol3, vol4]);
  r := r || format(E'\n%s FOTOS: recepção recebe %s fotos de voluntárias (esperado 2, sem a menor)', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;
  select count(*) into n from public.fotos_pessoas(array[pc1, pc2, pc3, p_vol1, pvol3, pvol4]);
  r := r || format(E'\n%s FOTOS: recepção recebe %s fotos por pessoa (esperado 5, sem a menor)', case when n=5 then '✅' else '❌' end, n); falhas := falhas + (n<>5)::int;

  -- Líder: todas, inclusive a da menor
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  select count(*) into n from public.fotos_voluntarias(array[vol1, vol3, vol4]);
  r := r || format(E'\n%s FOTOS: líder recebe %s fotos de voluntárias (esperado 3, inclui a menor)', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from public.fotos_pessoas(array[pvol3]);
  r := r || format(E'\n%s FOTOS: líder recebe a foto da MENOR pela pessoa: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.equipe_departamento(v_kids) e where e.id = vol3 and e.foto_public_id is not null;
  r := r || format(E'\n%s FOTOS: líder vê a foto da MENOR na lista da equipe: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- ================= DUPLICIDADES E EXCLUSÃO (Fase 4) =================
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '{}', true);
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Criança Teste C') returning id into pdup;
  insert into public.possiveis_duplicidades (pessoa_a, pessoa_b, motivo)
    values (least(pc3, pdup), greatest(pc3, pdup), 'mesmo_nome') returning id into dup_id;
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_pai1, 'role', 'authenticated')::text, true);
  select count(*) into n from public.possiveis_duplicidades;
  r := r || format(E'\n%s DUPLICIDADES: pai1 vê %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  begin
    perform public.resolver_duplicidade(dup_id, true);
    r := r || E'\n❌ pai1 resolveu duplicidade'; falhas := falhas + 1;
  exception when raise_exception then r := r || E'\n✅ DUPLICIDADES: pai1 NÃO resolve duplicidade';
  end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  select count(*) into n from public.possiveis_duplicidades;
  r := r || format(E'\n%s DUPLICIDADES: líder vê %s (esperado 1: só as do departamento dele)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  begin
    perform public.resolver_duplicidade(dup_id, true);
    r := r || E'\n✅ DUPLICIDADES: líder junta os dois cadastros da mesma pessoa';
  exception when others then r := r || E'\n❌ líder não juntou: ' || sqlerrm; falhas := falhas + 1;
  end;
  select pessoa_id into p_c3 from public.criancas where id = c3;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.pessoas where id in (pc3, pdup);
  r := r || format(E'\n%s DUPLICIDADES: depois de juntar sobra %s pessoa (esperado 1) e a criança continua ligada: %s', case when n=1 and p_c3 in (pc3, pdup) then '✅' else '❌' end, n, (p_c3 is not null)); falhas := falhas + (n<>1 or p_c3 is null or p_c3 not in (pc3, pdup))::int;
  select count(*) into n from public.relacoes_pessoas where relacionada_id = p_c3;
  r := r || format(E'\n%s DUPLICIDADES: a relação da criança foi mantida: %s (esperado 1)', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  delete from public.criancas where id = c3;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.pessoas where id = p_c3;
  r := r || format(E'\n%s EXCLUSÃO: apagar o cadastro da criança apaga a pessoa sem outro vínculo: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  select count(*) into n from public.relacoes_pessoas where relacionada_id = p_c3;
  r := r || format(E'\n%s EXCLUSÃO: e as relações dela: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
