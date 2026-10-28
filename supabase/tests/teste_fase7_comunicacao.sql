-- =====================================================================
-- Teste da Fase 7 (comunicação: avisos, push e enquetes) com DADOS 100%
-- FICTÍCIOS. Tudo roda dentro de um bloco que é DESFEITO no final (nada
-- fica salvo, nenhum push sai): o resultado aparece na mensagem de erro
-- "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- (Os avisos de teste para "todos" também alcançam os logins reais dentro
--  do bloco, mas tudo é desfeito: ninguém recebe nada e nada é mostrado.)
-- =====================================================================
do $teste$
declare
  u_lid uuid := gen_random_uuid(); u_lid2 uuid := gen_random_uuid(); u_rec uuid := gen_random_uuid();
  u_v1 uuid := gen_random_uuid(); u_pai uuid := gen_random_uuid();
  p_lid uuid; p_lid2 uuid; p_rec uuid; p_v1 uuid; p_pai uuid;
  v_kids uuid; v_igreja uuid; v_fam uuid;
  ep1 text := 'https://push.exemplo.invalid/teste-' || gen_random_uuid();
  ch_p256 text := repeat('B', 87); ch_auth text := repeat('a', 22);
  enq uuid; op1 uuid; op2 uuid; n_id uuid;
  j jsonb; n bigint; n2 bigint; ok boolean;
  r text := ''; falhas int := 0; total int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Lider') returning id into p_lid;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Lider Dois') returning id into p_lid2;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Recepcao') returning id into p_rec;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Voluntaria') returning id into p_v1;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Responsavel') returning id into p_pai;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lid,  'f7.lid@exemplo.invalid',  jsonb_build_object('pessoa_id', p_lid)),
    (u_lid2, 'f7.lid2@exemplo.invalid', jsonb_build_object('pessoa_id', p_lid2)),
    (u_rec,  'f7.rec@exemplo.invalid',  jsonb_build_object('pessoa_id', p_rec)),
    (u_v1,   'f7.v1@exemplo.invalid',   jsonb_build_object('pessoa_id', p_v1)),
    (u_pai,  'f7.pai@exemplo.invalid',  jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lid, u_lid2, u_rec, u_v1, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lid, v_kids, 'lider'), (u_lid2, v_kids, 'lider'), (u_rec, v_kids, 'recepcao'),
    (u_v1, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.familias (departamento_id) values (v_kids) returning id into v_fam;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (v_fam, p_pai, true);
  -- ================= TESTES =================
  -- Visitante sem login
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin perform public.enviar_aviso('todos', 'Teste', 'Texto');
    r := r || E'\n❌ visitante sem login enviou aviso'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não envia aviso'; end;
  perform set_config('role', 'authenticated', true);

  -- Voluntária e responsável não enviam aviso
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  begin perform public.enviar_aviso('todos', 'Teste', 'Texto');
    r := r || E'\n❌ voluntária enviou aviso'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não envia aviso'; end;
  begin j := public.avisos_enviados(10);
    r := r || E'\n❌ voluntária viu os avisos enviados'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não vê os avisos enviados'; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  begin perform public.enviar_aviso('responsaveis', 'Teste', 'Texto');
    r := r || E'\n❌ responsável enviou aviso'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não envia aviso'; end;
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));

  -- Fim da inserção direta em notificações (nem a liderança)
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  begin insert into public.notificacoes (destinatario_id, titulo) values (u_v1, 'Direto');
    r := r || E'\n❌ líder gravou notificação direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ notificação só pelas funções (nem a liderança grava direto)'; end;
  begin perform public.enviar_aviso('pais', 'Teste', 'Texto');
    r := r || E'\n❌ aceitou público inválido'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ público inválido é recusado'; end;
  begin perform public.enviar_aviso('todos', 'Oi', 'Texto');
    r := r || E'\n❌ aceitou título curto demais'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ título curto demais é recusado'; end;

  -- Públicos
  perform public.enviar_aviso('lideres', 'Teste lideres', 'Só líderes');
  perform public.enviar_aviso('equipe', 'Teste equipe', 'Equipe');
  perform public.enviar_aviso('responsaveis', 'Teste responsaveis', 'Responsáveis');
  perform public.enviar_aviso('todos', 'Teste todos', 'Todos');
  perform set_config('role', 'postgres', true);
  -- [quem, título] que deve receber
  ok := (select count(*) from public.notificacoes where destinatario_id = u_lid2 and tipo = 'aviso'
           and titulo in ('Teste lideres', 'Teste equipe', 'Teste todos')) = 3
    and not exists (select 1 from public.notificacoes where destinatario_id = u_lid2 and titulo = 'Teste responsaveis');
  r := r || format(E'\n%s outra líder recebe: líderes, equipe e todos (não responsáveis)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  ok := (select count(*) from public.notificacoes where destinatario_id in (u_v1, u_rec)
           and titulo in ('Teste equipe', 'Teste todos')) = 4
    and not exists (select 1 from public.notificacoes where destinatario_id in (u_v1, u_rec)
                      and titulo in ('Teste lideres', 'Teste responsaveis'));
  r := r || format(E'\n%s voluntária e recepção recebem: equipe e todos', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  ok := (select count(*) from public.notificacoes where destinatario_id = u_pai
           and titulo in ('Teste responsaveis', 'Teste todos')) = 2
    and not exists (select 1 from public.notificacoes where destinatario_id = u_pai
                      and titulo in ('Teste lideres', 'Teste equipe'));
  r := r || format(E'\n%s responsável recebe: responsáveis e todos', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  ok := not exists (select 1 from public.notificacoes where destinatario_id = u_lid and tipo = 'aviso');
  r := r || format(E'\n%s quem envia não recebe o próprio aviso', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- Leitura e "Enviados"
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  update public.notificacoes set lida_em = now() where titulo = 'Teste todos' and lida_em is null;
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  j := public.avisos_enviados(10);
  select x into j from jsonb_array_elements(j) x where x->>'titulo' = 'Teste todos';
  ok := (j->>'destinatarios')::int >= 4 and (j->>'lidas')::int = 1;
  r := r || format(E'\n%s "Enviados": %s destinatários, %s leitura', case when ok then '✅' else '❌' end, j->>'destinatarios', j->>'lidas'); falhas := falhas + (not ok)::int;

  -- ---------- Push ----------
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  begin insert into public.push_subscriptions (perfil_id, endpoint, p256dh, auth) values (u_v1, ep1 || 'x', ch_p256, ch_auth);
    r := r || E'\n❌ gravou aparelho direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ aparelho só pela função'; end;
  begin perform public.salvar_push('http://inseguro.invalid/x', ch_p256, ch_auth, null);
    r := r || E'\n❌ aceitou endereço de push sem https'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ endereço de push sem https é recusado'; end;
  perform public.salvar_push(ep1, ch_p256, ch_auth, 'Android');
  ok := (select count(*) from public.push_subscriptions where endpoint = ep1) = 1;
  r := r || format(E'\n%s voluntária liga o push no aparelho', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform set_config('request.jwt.claims', json_build_object('sub', u_rec, 'role', 'authenticated')::text, true);
  ok := (select count(*) from public.push_subscriptions) = 0;
  r := r || format(E'\n%s ninguém vê o aparelho de outra pessoa', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- Notificação nova de quem tem aparelho → 1 chamada para a Edge Function
  perform set_config('role', 'postgres', true);
  select count(*) into n from net.http_request_queue where url like '%/functions/v1/enviar-push';
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  perform public.enviar_aviso('equipe', 'Teste push', 'Texto do push');
  perform set_config('role', 'postgres', true);
  select count(*) into n2 from net.http_request_queue where url like '%/functions/v1/enviar-push';
  r := r || format(E'\n%s aviso com aparelho inscrito chama o envio do push (1 chamada)', case when n2 = n + 1 then '✅' else '❌' end); falhas := falhas + (n2 <> n + 1)::int;
  perform set_config('role', 'authenticated', true);
  perform public.enviar_aviso('lideres', 'Teste sem push', 'Ninguém da liderança de teste tem aparelho');
  perform set_config('role', 'postgres', true);
  select count(*) into n from net.http_request_queue where url like '%/functions/v1/enviar-push';
  -- (pode haver líder real com aparelho; então só conta se nenhum líder real tiver)
  ok := n = n2 or exists (select 1 from public.push_subscriptions s join public.papeis_usuario pu on pu.perfil_id = s.perfil_id
                           where pu.papel in ('lider', 'pastor', 'admin') and s.perfil_id <> u_lid);
  r := r || format(E'\n%s sem aparelho inscrito, não chama o push', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- push_preparar: só a chave de serviço
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  begin j := public.push_preparar(array[gen_random_uuid()]);
    r := r || E'\n❌ login comum chamou o preparo do push'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ preparo do push só pela Edge Function'; end;
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  select id into n_id from public.notificacoes where destinatario_id = u_v1 and titulo = 'Teste push';
  j := public.push_preparar(array[n_id]);
  ok := jsonb_array_length(j) = 1 and j->0->>'corpo' = 'Texto do push'
        and j->0->'inscricoes'->0->>'endpoint' = ep1;
  r := r || format(E'\n%s aviso da liderança vai com o texto para o aparelho certo', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  j := public.push_preparar(array[n_id]);
  r := r || format(E'\n%s cada notificação vai uma única vez', case when jsonb_array_length(j) = 0 then '✅' else '❌' end); falhas := falhas + (jsonb_array_length(j) <> 0)::int;
  -- notificação automática (com nome de criança no texto) → só o título
  perform set_config('role', 'postgres', true);
  insert into public.notificacoes (destinatario_id, titulo, corpo, tipo)
    values (u_v1, 'Dados de criança atualizados', 'Qwzteste alterou o nome de Qwzteste Criança.', 'cadastro_editado')
    returning id into n_id;
  perform set_config('role', 'service_role', true);
  j := public.push_preparar(array[n_id]);
  ok := j->0->>'corpo' = 'Abra o app para ver.' and j->0->>'titulo' = 'Dados de criança atualizados';
  r := r || format(E'\n%s automática mostra só o título (sem nomes) na tela bloqueada', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- mesmo aparelho, outro login → passa para quem está conectado; remover
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_rec, 'role', 'authenticated')::text, true);
  perform public.salvar_push(ep1, ch_p256, ch_auth, null);
  perform set_config('role', 'postgres', true);
  ok := (select perfil_id from public.push_subscriptions where endpoint = ep1) = u_rec
        and (select count(*) from public.push_subscriptions where endpoint = ep1) = 1;
  r := r || format(E'\n%s aparelho usado por outro login passa para quem entrou', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  perform public.remover_push(ep1); -- não é mais dela: não apaga
  perform set_config('request.jwt.claims', json_build_object('sub', u_rec, 'role', 'authenticated')::text, true);
  ok := (select count(*) from public.push_subscriptions where endpoint = ep1) = 1;
  perform public.remover_push(ep1);
  ok := ok and (select count(*) from public.push_subscriptions where endpoint = ep1) = 0;
  r := r || format(E'\n%s só o dono desliga o push do aparelho', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform public.salvar_push(ep1, ch_p256, ch_auth, null);
  perform set_config('role', 'service_role', true);
  perform public.push_remover_inscricoes(array[ep1]);
  perform set_config('role', 'postgres', true);
  ok := not exists (select 1 from public.push_subscriptions where endpoint = ep1);
  r := r || format(E'\n%s aparelho recusado pelo serviço de push é apagado', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- ---------- Enquetes ----------
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  begin perform public.criar_enquete('Qual horário?', 'equipe', array['A', 'B']);
    r := r || E'\n❌ voluntária criou enquete'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não cria enquete'; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  begin perform public.criar_enquete('Qual horário?', 'equipe', array['Sim', ' sim ']);
    r := r || E'\n❌ aceitou enquete com opções repetidas'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ enquete precisa de 2 opções diferentes'; end;
  begin insert into public.enquetes (departamento_id, pergunta) values (v_kids, 'Direto');
    r := r || E'\n❌ líder gravou enquete direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ enquete só pelas funções'; end;
  j := public.criar_enquete('Qwzteste: melhor dia para o encontro?', 'equipe', array['Sábado', 'Domingo', 'Sábado'], false, private.hoje() + 7);
  enq := (j->>'id')::uuid;
  select id into op1 from public.enquete_opcoes where enquete_id = enq and texto = 'Sábado';
  select id into op2 from public.enquete_opcoes where enquete_id = enq and texto = 'Domingo';
  perform set_config('role', 'postgres', true);
  ok := (select count(*) from public.enquete_opcoes where enquete_id = enq) = 2
        and exists (select 1 from public.notificacoes where destinatario_id = u_v1 and tipo = 'enquete' and link = '#/enquetes')
        and not exists (select 1 from public.notificacoes where destinatario_id = u_pai and tipo = 'enquete');
  r := r || format(E'\n%s liderança cria enquete da equipe (equipe avisada, responsável não)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  j := public.enquetes_lista();
  ok := not exists (select 1 from jsonb_array_elements(j) x where (x->>'id')::uuid = enq);
  r := r || format(E'\n%s responsável não vê enquete da equipe', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin perform public.votar_enquete(enq, array[op1]);
    r := r || E'\n❌ responsável votou em enquete da equipe'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vota em enquete da equipe'; end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  ok := public.enquetes_pendentes() >= 1;
  select x into j from jsonb_array_elements(public.enquetes_lista()) x where (x->>'id')::uuid = enq;
  ok := ok and (j->>'pode_votar')::boolean and not (j->>'ve_totais')::boolean and j->'opcoes'->0->'votos' = 'null'::jsonb;
  r := r || format(E'\n%s voluntária vê a enquete sem os totais antes de votar', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin perform public.votar_enquete(enq, array[op1, op2]);
    r := r || E'\n❌ votou em duas opções numa enquete de uma escolha'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ enquete de uma escolha aceita só uma opção'; end;
  begin insert into public.votos (enquete_id, opcao_id, perfil_id) values (enq, op1, u_v1);
    r := r || E'\n❌ voto gravado direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voto só pela função'; end;
  perform public.votar_enquete(enq, array[op1]);
  perform public.votar_enquete(enq, array[op2]);
  select x into j from jsonb_array_elements(public.enquetes_lista()) x where (x->>'id')::uuid = enq;
  ok := (j->>'ve_totais')::boolean and (j->>'votantes')::int = 1 and j->'meus_votos' = jsonb_build_array(op2)
        and j->'quem_votou' = 'null'::jsonb;
  r := r || format(E'\n%s voluntária muda o voto e vê só os totais (sem nomes)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  select x into j from jsonb_array_elements(public.enquetes_lista()) x where (x->>'id')::uuid = enq;
  ok := jsonb_array_length(j->'quem_votou') = 1 and j->'quem_votou'->0->>'nome' = 'Qwzteste Voluntaria'
        and (j->>'destinatarios')::int >= 3;
  r := r || format(E'\n%s liderança vê quem votou e em quê', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  begin perform public.encerrar_enquete(enq);
    r := r || E'\n❌ voluntária encerrou a enquete'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não encerra enquete'; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  perform public.encerrar_enquete(enq);
  perform set_config('request.jwt.claims', json_build_object('sub', u_rec, 'role', 'authenticated')::text, true);
  select x into j from jsonb_array_elements(public.enquetes_lista()) x where (x->>'id')::uuid = enq;
  ok := not (j->>'aberta')::boolean and (j->>'ve_totais')::boolean;
  r := r || format(E'\n%s enquete encerrada mostra os totais para toda a equipe', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin perform public.votar_enquete(enq, array[op1]);
    r := r || E'\n❌ votou em enquete encerrada'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ enquete encerrada não recebe voto'; end;

  -- Enquete para responsáveis
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  j := public.criar_enquete('Qwzteste: festa no sábado?', 'familias', array['Sim', 'Não']);
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  select id into op1 from public.enquete_opcoes where enquete_id = (j->>'id')::uuid and texto = 'Sim';
  perform public.votar_enquete((j->>'id')::uuid, array[op1]);
  ok := exists (select 1 from public.votos where enquete_id = (j->>'id')::uuid and perfil_id = u_pai);
  r := r || format(E'\n%s responsável vota na enquete das famílias', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  perform public.apagar_enquete(enq);
  ok := not exists (select 1 from public.enquetes where id = enq);
  r := r || format(E'\n%s liderança apaga a enquete', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- Funções internas fechadas
  begin perform private.destinatarios('todos');
    r := r || E'\n❌ função interna liberada para o app'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ funções internas fechadas para o app'; end;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
