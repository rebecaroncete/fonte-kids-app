-- =====================================================================
-- Teste da Fase 8 (eventos, inscrições, "Quero ajudar" e voluntariado)
-- com DADOS 100% FICTÍCIOS. Tudo roda dentro de um bloco que é DESFEITO no
-- final (nada fica salvo, nenhum push sai): o resultado aparece na
-- mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute (depois da
-- migração 20261029000000_fase8_eventos_voluntariado).
-- (Os avisos de teste também alcançam os logins reais dentro do bloco,
--  mas tudo é desfeito: ninguém recebe nada e nenhum push sai.)
-- =====================================================================
do $teste$
declare
  u_lid uuid := gen_random_uuid(); u_v1 uuid := gen_random_uuid(); u_v2 uuid := gen_random_uuid();
  u_pai uuid := gen_random_uuid(); u_pai2 uuid := gen_random_uuid();
  p_lid uuid; p_v1 uuid; p_v2 uuid; p_pai uuid; p_pai2 uuid;
  p_c5 uuid; p_c11 uuid; p_d6 uuid; p_d7 uuid;
  c5 uuid; c11 uuid; d6 uuid; d7 uuid;
  v1 uuid; v2 uuid; v_kids uuid; v_igreja uuid; fam uuid; fam2 uuid;
  s0 uuid; s3 uuid; s7 uuid; rec10 uuid;
  ev uuid; ev2 uuid; ev3 uuid; ins uuid; ins2 uuid;
  esc_r uuid; esc_p uuid; cul_r uuid; cul_p uuid; it_r uuid; it_p uuid;
  v_inicio timestamptz := date_trunc('minute', now()) + interval '10 days';
  j jsonb; x jsonb; n bigint; ok boolean;
  r text := ''; falhas int := 0; total int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s0 from public.salas where departamento_id = v_kids and idade_min = 0;
  select id into s3 from public.salas where departamento_id = v_kids and idade_min = 3;
  select id into s7 from public.salas where departamento_id = v_kids and idade_min = 7;
  select id into rec10 from public.cultos_recorrentes where ativo order by dia_semana, horario limit 1;

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Lider') returning id into p_lid;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Voluntaria Um', private.hoje() - interval '30 years') returning id into p_v1;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Voluntaria Dois', private.hoje() - interval '25 years') returning id into p_v2;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Responsavel Um', '5500000000001') returning id into p_pai;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Responsavel Dois', '5500000000002') returning id into p_pai2;
  -- idades no dia do evento: 5, 11, 6 e 7 anos
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Cinco', (v_inicio::date - interval '5 years 2 months')::date) returning id into p_c5;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Onze', (v_inicio::date - interval '11 years 2 months')::date) returning id into p_c11;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Seis', (v_inicio::date - interval '6 years 2 months')::date) returning id into p_d6;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Sete', (v_inicio::date - interval '7 years 2 months')::date) returning id into p_d7;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lid,  'f8.lid@exemplo.invalid',  jsonb_build_object('pessoa_id', p_lid)),
    (u_v1,   'f8.v1@exemplo.invalid',   jsonb_build_object('pessoa_id', p_v1)),
    (u_v2,   'f8.v2@exemplo.invalid',   jsonb_build_object('pessoa_id', p_v2)),
    (u_pai,  'f8.pai@exemplo.invalid',  jsonb_build_object('pessoa_id', p_pai)),
    (u_pai2, 'f8.pai2@exemplo.invalid', jsonb_build_object('pessoa_id', p_pai2));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lid, u_v1, u_v2, u_pai, u_pai2);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lid, v_kids, 'lider'), (u_v1, v_kids, 'voluntaria'), (u_v2, v_kids, 'voluntaria'),
    (u_pai, null, 'responsavel'), (u_pai2, null, 'responsavel');
  insert into public.voluntarias (departamento_id, pessoa_id, funcao, status, salas_preferidas, cultos_preferidos)
    values (v_kids, p_v1, 'professora', 'ativa', array[s0], array[rec10]) returning id into v1;
  insert into public.voluntarias (departamento_id, pessoa_id, funcao, status, salas_preferidas, cultos_preferidos)
    values (v_kids, p_v2, 'auxiliar', 'ativa', array[s3], array[rec10]) returning id into v2;
  insert into public.familias (departamento_id) values (v_kids) returning id into fam;
  insert into public.familias (departamento_id) values (v_kids) returning id into fam2;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (fam, p_pai, true), (fam2, p_pai2, true);
  insert into public.criancas (familia_id, pessoa_id) values (fam, p_c5) returning id into c5;
  insert into public.criancas (familia_id, pessoa_id) values (fam, p_c11) returning id into c11;
  insert into public.criancas (familia_id, pessoa_id) values (fam2, p_d6) returning id into d6;
  insert into public.criancas (familia_id, pessoa_id) values (fam2, p_d7) returning id into d7;
  -- escala em rascunho e escala publicada (meses bem à frente), V2 escalada nas duas
  insert into public.cultos (igreja_id, data, horario, nome)
    values (v_igreja, (date_trunc('month', private.hoje()) + interval '9 months')::date + 2, '07:13', 'Qwzteste culto') returning id into cul_r;
  insert into public.cultos (igreja_id, data, horario, nome)
    values (v_igreja, (date_trunc('month', private.hoje()) + interval '10 months')::date + 2, '07:13', 'Qwzteste culto') returning id into cul_p;
  insert into public.escalas (departamento_id, mes_referencia, status)
    values (v_kids, (date_trunc('month', private.hoje()) + interval '9 months')::date, 'rascunho') returning id into esc_r;
  insert into public.escalas (departamento_id, mes_referencia, status)
    values (v_kids, (date_trunc('month', private.hoje()) + interval '10 months')::date, 'publicada') returning id into esc_p;
  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao, voluntaria_id) values (esc_r, cul_r, s3, 'auxiliar', v2) returning id into it_r;
  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao, voluntaria_id) values (esc_p, cul_p, s3, 'auxiliar', v2) returning id into it_p;

  -- Responsáveis aceitam o termo (sem isso o login não libera nada)
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai2, 'role', 'authenticated')::text, true);
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));

  -- ================= TESTES: eventos =================
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.eventos_lista();
    r := r || E'\n❌ visitante sem login viu os eventos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê eventos'; end;
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  begin perform public.salvar_evento(null, jsonb_build_object('titulo', 'Qwzteste evento', 'inicio', v_inicio));
    r := r || E'\n❌ responsável criou evento'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não cria evento'; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  begin perform public.salvar_evento(null, jsonb_build_object('titulo', 'Qwzteste evento', 'inicio', v_inicio));
    r := r || E'\n❌ voluntária criou evento'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não cria evento'; end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  begin insert into public.eventos (departamento_id, titulo) values (v_kids, 'Direto');
    r := r || E'\n❌ líder gravou evento direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ evento só pelas funções (nem a liderança grava direto)'; end;
  begin perform public.salvar_evento(null, jsonb_build_object('titulo', 'Oi', 'inicio', v_inicio));
    r := r || E'\n❌ aceitou nome curto demais'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ nome curto demais é recusado'; end;
  begin perform public.salvar_evento(null, jsonb_build_object('titulo', 'Qwzteste evento', 'inicio', v_inicio, 'fim', v_inicio - interval '1 hour'));
    r := r || E'\n❌ aceitou fim antes do início'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ fim antes do início é recusado'; end;
  begin perform public.salvar_evento(null, jsonb_build_object('titulo', 'Qwzteste evento', 'inicio', v_inicio, 'inscricoes_ate', (v_inicio::date + 1)));
    r := r || E'\n❌ aceitou prazo depois do evento'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ prazo de inscrição depois do evento é recusado'; end;
  begin perform public.salvar_evento(null, jsonb_build_object('titulo', 'Qwzteste evento', 'inicio', now() - interval '1 day'));
    r := r || E'\n❌ aceitou evento no passado'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ evento no passado é recusado'; end;

  ev := public.salvar_evento(null, jsonb_build_object(
    'titulo', 'Qwzteste Festa', 'descricao', 'Teste', 'inicio', v_inicio, 'fim', v_inicio + interval '3 hours',
    'local', 'Salão', 'idade_min', 3, 'idade_max', 9, 'vagas', 2, 'autorizacao', true,
    'inscricoes_abertas', true, 'aceita_ajuda', true, 'vagas_ajuda', 1));
  ok := exists (select 1 from public.eventos where id = ev and not publicado and limite_inscricoes = 2 and precisa_autorizacao);
  r := r || format(E'\n%s liderança cria o evento em rascunho', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  j := public.eventos_lista();
  ok := not exists (select 1 from jsonb_array_elements(j) e where (e->>'id')::uuid = ev);
  r := r || format(E'\n%s responsável não vê o rascunho', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin perform public.inscrever_crianca(ev, c5, true);
    r := r || E'\n❌ inscreveu em evento em rascunho'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ rascunho não recebe inscrição'; end;

  -- Publicar avisa o público escolhido
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  begin perform public.publicar_evento(ev, 'pais');
    r := r || E'\n❌ aceitou público inválido'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ público inválido é recusado'; end;
  j := public.publicar_evento(ev, 'responsaveis');
  perform set_config('role', 'postgres', true); -- conferir as notificações de todos (o RLS só mostra as próprias)
  ok := exists (select 1 from public.notificacoes where destinatario_id = u_pai and tipo = 'evento' and link = '#/eventos?id=' || ev)
    and exists (select 1 from public.notificacoes where destinatario_id = u_pai2 and tipo = 'evento')
    and not exists (select 1 from public.notificacoes where destinatario_id in (u_v1, u_lid) and tipo = 'evento')
    and (j->>'destinatarios')::int >= 2;
  r := r || format(E'\n%s publicar avisa só o público escolhido (responsáveis)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  ok := not exists (select 1 from public.notificacoes where tipo = 'evento' and link = '#/eventos?id=' || ev and corpo ilike '%Qwzteste Crianca%');
  r := r || format(E'\n%s aviso do evento sem nome de criança', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform set_config('role', 'authenticated', true);
  begin perform public.publicar_evento(ev, 'todos');
    r := r || E'\n❌ publicou duas vezes'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não publica duas vezes'; end;

  -- Responsável vê as próprias crianças e se cabem na faixa
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  select e into x from jsonb_array_elements(public.eventos_lista()) e where (e->>'id')::uuid = ev;
  ok := x is not null and jsonb_array_length(x->'minhas_criancas') = 2
    and exists (select 1 from jsonb_array_elements(x->'minhas_criancas') c where (c->>'id')::uuid = c5 and (c->>'cabe')::boolean and (c->>'idade')::int = 5)
    and exists (select 1 from jsonb_array_elements(x->'minhas_criancas') c where (c->>'id')::uuid = c11 and not (c->>'cabe')::boolean)
    and not exists (select 1 from jsonb_array_elements(x->'minhas_criancas') c where (c->>'id')::uuid in (d6, d7));
  r := r || format(E'\n%s responsável vê só as próprias crianças, com idade e faixa', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  begin perform public.inscrever_crianca(ev, c5, false);
    r := r || E'\n❌ inscreveu sem a autorização'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ sem "Autorizo" a inscrição é recusada'; end;
  ins := public.inscrever_crianca(ev, c5, true, 'Leva lanche');
  ok := exists (select 1 from public.inscricoes_evento where id = ins and autorizado_em is not null and autorizado_por = u_pai and inscrito_por = u_pai);
  r := r || format(E'\n%s responsável inscreve e autoriza (com data e quem marcou)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  ok := public.inscrever_crianca(ev, c5, true, 'Outra obs') = ins
    and (select count(*) from public.inscricoes_evento where evento_id = ev and crianca_id = c5) = 1;
  r := r || format(E'\n%s inscrever de novo só atualiza (sem duplicar)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin perform public.inscrever_crianca(ev, c11, true);
    r := r || E'\n❌ inscreveu criança fora da faixa de idade'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ criança fora da faixa de idade é recusada'; end;
  begin perform public.inscrever_crianca(ev, d6, true);
    r := r || E'\n❌ inscreveu criança de outra família'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não inscreve criança de outra família'; end;
  begin insert into public.inscricoes_evento (evento_id, crianca_id) values (ev, c11);
    r := r || E'\n❌ gravou inscrição direto na tabela'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ inscrição só pelas funções'; end;
  begin j := public.evento_inscritos(ev);
    r := r || E'\n❌ responsável viu a lista de inscritos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê a lista de inscritos'; end;

  -- Vagas esgotadas (limite 2)
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai2, 'role', 'authenticated')::text, true);
  ins2 := public.inscrever_crianca(ev, d6, true);
  begin perform public.inscrever_crianca(ev, d7, true);
    r := r || E'\n❌ passou do limite de vagas'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ vagas esgotadas: inscrição recusada'; end;
  begin perform public.cancelar_inscricao(ins);
    r := r || E'\n❌ tirou a inscrição de outra família'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não tira a inscrição de outra família'; end;

  -- Liderança inscreve passando do limite, vê a lista e marca presença
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  perform public.inscrever_crianca(ev, d7);
  ok := (select count(*) from public.inscricoes_evento where evento_id = ev) = 3
    and exists (select 1 from public.inscricoes_evento where evento_id = ev and crianca_id = d7 and autorizado_em is null);
  r := r || format(E'\n%s liderança inscreve mesmo passando do limite (sem autorizar pelos pais)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  j := public.evento_inscritos(ev);
  ok := jsonb_array_length(j->'inscritos') = 3
    and exists (select 1 from jsonb_array_elements(j->'inscritos') i where (i->>'crianca_id')::uuid = c5
                and jsonb_array_length(i->'responsaveis') = 1 and i->'responsaveis'->0->>'telefone' = '5500000000001')
    and exists (select 1 from jsonb_array_elements(j->'inscritos') i where (i->>'crianca_id')::uuid = d7 and (i->>'pela_lideranca')::boolean);
  r := r || format(E'\n%s liderança vê os inscritos com o WhatsApp do responsável', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform public.marcar_presenca_evento(ins, true);
  ok := (select presente from public.inscricoes_evento where id = ins);
  r := r || format(E'\n%s liderança marca "Presente"', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  begin perform public.marcar_presenca_evento(ins, false);
    r := r || E'\n❌ responsável marcou presença'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não marca presença'; end;

  -- Quero ajudar (1 vaga)
  begin perform public.ajudar_evento(ev, true);
    r := r || E'\n❌ responsável se ofereceu para ajudar'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ só voluntária ativa se oferece para ajudar'; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_v2, 'role', 'authenticated')::text, true);
  perform public.ajudar_evento(ev, true);
  select e into x from jsonb_array_elements(public.eventos_lista()) e where (e->>'id')::uuid = ev;
  ok := (x->>'eu_ajudo')::boolean and (x->>'ajudantes')::int = 1 and x->'minhas_criancas' = 'null'::jsonb;
  r := r || format(E'\n%s voluntária se oferece e vê "Vou ajudar"', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  begin perform public.ajudar_evento(ev, true);
    r := r || E'\n❌ passou das vagas de ajuda'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ vagas de ajuda preenchidas: recusado'; end;

  -- Avisar inscritos (1 por hora)
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  n := public.avisar_inscritos(ev, null);
  perform set_config('role', 'postgres', true);
  ok := n = 2 and exists (select 1 from public.notificacoes where destinatario_id = u_pai and titulo like 'Lembrete:%')
    and not exists (select 1 from public.notificacoes where destinatario_id = u_v2 and titulo like 'Lembrete:%');
  r := r || format(E'\n%s "Avisar inscritos" vai só para os responsáveis dos inscritos', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform set_config('role', 'authenticated', true);
  begin perform public.avisar_inscritos(ev, 'De novo');
    r := r || E'\n❌ mandou dois lembretes seguidos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ lembrete: no máximo 1 por hora'; end;

  -- Responsável tira a própria inscrição; prazo vencido fecha
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai2, 'role', 'authenticated')::text, true);
  perform public.cancelar_inscricao(ins2);
  ok := not exists (select 1 from public.inscricoes_evento where id = ins2);
  r := r || format(E'\n%s responsável tira a própria inscrição', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform set_config('role', 'postgres', true);
  update public.eventos set inscricoes_ate = private.hoje() - 1 where id = ev;
  perform set_config('role', 'authenticated', true);
  begin perform public.inscrever_crianca(ev, d6, true);
    r := r || E'\n❌ inscreveu depois do prazo'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ depois do prazo a inscrição é recusada'; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  begin perform public.cancelar_inscricao(ins);
    r := r || E'\n❌ tirou a inscrição depois do prazo'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ depois do prazo só a liderança tira a inscrição'; end;

  -- Apagar x cancelar
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  begin perform public.apagar_evento(ev);
    r := r || E'\n❌ apagou evento com inscrições'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ evento com inscrições não é apagado'; end;
  n := public.cancelar_evento(ev);
  perform set_config('role', 'postgres', true);
  ok := n = 3 and exists (select 1 from public.notificacoes where destinatario_id = u_v2 and titulo like 'Evento cancelado:%')
    and exists (select 1 from public.notificacoes where destinatario_id = u_pai2 and titulo like 'Evento cancelado:%');
  r := r || format(E'\n%s cancelar avisa os responsáveis dos inscritos e quem ia ajudar', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform set_config('role', 'authenticated', true);
  begin perform public.inscrever_crianca(ev, d6);
    r := r || E'\n❌ inscreveu em evento cancelado'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ evento cancelado não recebe inscrição'; end;
  ev2 := public.salvar_evento(null, jsonb_build_object('titulo', 'Qwzteste Rascunho', 'inicio', v_inicio));
  perform public.apagar_evento(ev2);
  ok := not exists (select 1 from public.eventos where id = ev2);
  r := r || format(E'\n%s liderança apaga evento sem inscrições', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- ================= TESTES: voluntariado =================
  ev3 := public.salvar_evento(null, jsonb_build_object('titulo', 'Qwzteste Ajuda', 'inicio', v_inicio, 'aceita_ajuda', true));
  perform public.publicar_evento(ev3, 'lideres');
  perform set_config('request.jwt.claims', json_build_object('sub', u_v2, 'role', 'authenticated')::text, true);
  perform public.ajudar_evento(ev3, true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  j := public.voluntaria_preferencias();
  ok := (j->>'id')::uuid = v1 and jsonb_array_length(j->'opcoes_salas') >= 4 and not (j->>'pode_tudo')::boolean;
  r := r || format(E'\n%s voluntária abre as próprias preferências', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform public.salvar_voluntaria(v1, jsonb_build_object('salas', jsonb_build_array(s3, s0), 'cultos', jsonb_build_array(rec10), 'funcao', 'auxiliar', 'email', 'x@exemplo.invalid'));
  ok := exists (select 1 from public.voluntarias where id = v1 and salas_preferidas = array[s3, s0] and funcao = 'professora' and email is null);
  r := r || format(E'\n%s voluntária muda só salas e cultos (função continua com a liderança)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin perform public.salvar_voluntaria(v2, jsonb_build_object('salas', jsonb_build_array(s0), 'cultos', jsonb_build_array(rec10)));
    r := r || E'\n❌ voluntária mudou o cadastro de outra'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não muda o cadastro de outra'; end;
  begin update public.voluntarias set teto_mensal = 9 where id = v1;
    get diagnostics n = row_count;
    if n > 0 then r := r || E'\n❌ voluntária gravou direto na tabela'; falhas := falhas + 1;
    else r := r || E'\n✅ voluntária não grava direto na tabela'; end if;
  exception when others then r := r || E'\n✅ voluntária não grava direto na tabela'; end;
  begin perform public.salvar_voluntaria(v1, jsonb_build_object('salas', jsonb_build_array(s0, s3, s7, s0, s3), 'cultos', jsonb_build_array(rec10)));
    r := r || E'\n❌ aceitou 5 salas'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ mais de 4 salas é recusado'; end;
  begin perform public.definir_status_voluntaria(v2, false);
    r := r || E'\n❌ voluntária desativou outra'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não desativa ninguém'; end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  perform public.salvar_voluntaria(v1, jsonb_build_object('salas', jsonb_build_array(s7), 'cultos', jsonb_build_array(rec10),
                                                          'funcao', 'auxiliar', 'email', 'Teste@Exemplo.invalid', 'profissao', 'Teste'));
  ok := exists (select 1 from public.voluntarias where id = v1 and funcao = 'auxiliar' and email = 'teste@exemplo.invalid' and salas_preferidas = array[s7]);
  r := r || format(E'\n%s liderança edita função, e-mail, salas e cultos', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  j := public.definir_status_voluntaria(v2, false);
  ok := exists (select 1 from public.voluntarias where id = v2 and status = 'inativa')
    and exists (select 1 from public.escala_itens where id = it_r and voluntaria_id is null)
    and exists (select 1 from public.escala_itens where id = it_p and voluntaria_id = v2)
    and not exists (select 1 from public.ajudas_evento where voluntaria_id = v2 and evento_id = ev3)
    and not exists (select 1 from public.papeis_usuario where perfil_id = u_v2 and papel in ('voluntaria', 'recepcao'))
    and exists (select 1 from public.perfis where id = u_v2 and ativo)
    and (j->>'vagas')::int = 1;
  r := r || format(E'\n%s desativar: sai do rascunho e das ajudas, perde os papéis; publicada e login continuam', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin perform public.trocar_vaga(it_r, v2);
    r := r || E'\n❌ voluntária inativa entrou na escala'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária inativa não entra na escala'; end;
  perform public.definir_status_voluntaria(v2, true);
  ok := exists (select 1 from public.voluntarias where id = v2 and status = 'ativa')
    and exists (select 1 from public.papeis_usuario where perfil_id = u_v2 and papel = 'voluntaria')
    and exists (select 1 from public.papeis_usuario where perfil_id = u_v2 and papel = 'recepcao');
  r := r || format(E'\n%s reativar devolve os papéis de voluntária e recepção', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- Início: próximos eventos
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  j := public.proximos_eventos();
  ok := exists (select 1 from jsonb_array_elements(j) e where (e->>'id')::uuid = ev3)
    and not exists (select 1 from jsonb_array_elements(j) e where (e->>'id')::uuid = ev);
  r := r || format(E'\n%s Início mostra os próximos eventos (sem os cancelados)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- Funções internas fechadas
  begin perform private.responsaveis_inscritos(ev);
    r := r || E'\n❌ função interna liberada para o app'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ funções internas fechadas para o app'; end;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
