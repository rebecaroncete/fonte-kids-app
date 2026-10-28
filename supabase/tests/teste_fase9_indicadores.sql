-- =====================================================================
-- Teste da Fase 9 (indicadores, relatório do mês, "Sentimos falta",
-- voluntárias sem escala, "Não poderei" registrado e aviso do dia 1)
-- com DADOS 100% FICTÍCIOS (cultos em fevereiro/março de 2025 e em
-- horários que não existem). Tudo roda dentro de um bloco que é DESFEITO
-- no final (nada fica salvo, nenhum push sai): o resultado aparece na
-- mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute (depois da
-- migração 20261029010000_fase9_indicadores).
-- =====================================================================
do $teste$
declare
  u_lid uuid := gen_random_uuid(); u_v1 uuid := gen_random_uuid(); u_v2 uuid := gen_random_uuid();
  u_pai uuid := gen_random_uuid();
  p_lid uuid; p_v1 uuid; p_v2 uuid; p_pai uuid;
  p_a uuid; p_b uuid; p_c uuid; p_d uuid; p_e uuid; p_f uuid;
  ca uuid; cb uuid; cc uuid; cd uuid; ce uuid; cf uuid;
  v1 uuid; v2 uuid; v_kids uuid; v_igreja uuid; fam uuid;
  s0 uuid; s3 uuid; rec10 uuid;
  k0 uuid; k1 uuid; k2 uuid; k3 uuid; k4 uuid; r0 uuid; r49 uuid; r42 uuid; r35 uuid; r7 uuid;
  esc uuid; esc_p uuid; cul_p uuid; it_p uuid; ev uuid;
  v_hoje date := private.hoje();
  j jsonb; x jsonb; n bigint; ok boolean;
  r text := ''; falhas int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s0 from public.salas where departamento_id = v_kids and idade_min = 0;
  select id into s3 from public.salas where departamento_id = v_kids and idade_min = 3;
  select id into rec10 from public.cultos_recorrentes where ativo order by dia_semana, horario limit 1;

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Lider') returning id into p_lid;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Voluntaria Um', '5500000000011') returning id into p_v1;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Voluntaria Dois', '5500000000012') returning id into p_v2;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Responsavel', '5500000000001') returning id into p_pai;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca A', v_hoje - interval '5 years') returning id into p_a;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca B', v_hoje - interval '4 years') returning id into p_b;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca C', v_hoje - interval '6 years') returning id into p_c;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca D', v_hoje - interval '7 years') returning id into p_d;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca E', v_hoje - interval '8 years') returning id into p_e;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca F', v_hoje - interval '9 years') returning id into p_f;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lid, 'f9.lid@exemplo.invalid', jsonb_build_object('pessoa_id', p_lid)),
    (u_v1,  'f9.v1@exemplo.invalid',  jsonb_build_object('pessoa_id', p_v1)),
    (u_v2,  'f9.v2@exemplo.invalid',  jsonb_build_object('pessoa_id', p_v2)),
    (u_pai, 'f9.pai@exemplo.invalid', jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lid, u_v1, u_v2, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lid, v_kids, 'lider'), (u_v1, v_kids, 'voluntaria'), (u_v2, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.voluntarias (departamento_id, pessoa_id, funcao, status) values (v_kids, p_v1, 'professora', 'ativa') returning id into v1;
  insert into public.voluntarias (departamento_id, pessoa_id, funcao, status) values (v_kids, p_v2, 'auxiliar', 'ativa') returning id into v2;
  insert into public.familias (departamento_id, criado_em) values (v_kids, '2025-03-05 12:00-03') returning id into fam;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (fam, p_pai, true);
  insert into public.criancas (familia_id, pessoa_id) values (fam, p_a) returning id into ca;
  insert into public.criancas (familia_id, pessoa_id, perfil) values (fam, p_b, 'visitante') returning id into cb;
  insert into public.criancas (familia_id, pessoa_id) values (fam, p_c) returning id into cc;
  insert into public.criancas (familia_id, pessoa_id) values (fam, p_d) returning id into cd;
  insert into public.criancas (familia_id, pessoa_id, perfil) values (fam, p_e, 'visitante') returning id into ce;
  insert into public.criancas (familia_id, pessoa_id, ativo) values (fam, p_f, false) returning id into cf;

  -- Cultos fictícios: 23/02/2025, 02/03/2025 (10h07 e 19h13 extra), 04/03 cancelado, 09/03
  insert into public.cultos (igreja_id, culto_recorrente_id, data, horario, nome) values (v_igreja, rec10, '2025-02-23', '10:07', 'Qwzteste') returning id into k0;
  insert into public.cultos (igreja_id, culto_recorrente_id, data, horario, nome) values (v_igreja, rec10, '2025-03-02', '10:07', 'Qwzteste') returning id into k1;
  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, '2025-03-02', '19:13', 'Qwzteste extra') returning id into k2;
  insert into public.cultos (igreja_id, data, horario, nome, cancelado) values (v_igreja, '2025-03-04', '20:13', 'Qwzteste', true) returning id into k3;
  insert into public.cultos (igreja_id, culto_recorrente_id, data, horario, nome) values (v_igreja, rec10, '2025-03-09', '10:07', 'Qwzteste') returning id into k4;
  -- A vem desde 23/02; B (visitante) e C chegam em 02/03; B volta em 09/03
  insert into public.checkins (culto_id, crianca_id, sala_id, entrada_em) values
    (k0, ca, s0, '2025-02-23 10:10-03'),
    (k1, ca, s0, '2025-03-02 10:10-03'), (k1, cb, s3, '2025-03-02 10:10-03'), (k1, cc, s3, '2025-03-02 10:10-03'),
    (k2, cc, s3, '2025-03-02 19:15-03'),
    (k4, cb, s3, '2025-03-09 10:10-03');
  -- "Sentimos falta": D e F (inativa) vieram 3 vezes há 5 a 7 semanas; E também, mas voltou há 1 semana
  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, v_hoje - 49, '06:07', 'Qwzteste') returning id into r49;
  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, v_hoje - 42, '06:07', 'Qwzteste') returning id into r42;
  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, v_hoje - 35, '06:07', 'Qwzteste') returning id into r35;
  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, v_hoje - 7, '06:07', 'Qwzteste') returning id into r7;
  -- Culto fictício hoje às 23h58 (o mais recente de todos) para o "Último culto"
  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, v_hoje, '23:58', 'Qwzteste') returning id into r0;
  insert into public.checkins (culto_id, crianca_id, sala_id, entrada_em, saida_em) values
    (r49, cd, s3, now() - interval '49 days', now() - interval '49 days'), (r42, cd, s3, now() - interval '42 days', now() - interval '42 days'),
    (r35, cd, s3, now() - interval '35 days', now() - interval '35 days'),
    (r49, ce, s3, now() - interval '49 days', now() - interval '49 days'), (r42, ce, s3, now() - interval '42 days', now() - interval '42 days'),
    (r7,  ce, s3, now() - interval '7 days', now() - interval '7 days'),
    (r49, cf, s3, now() - interval '49 days', now() - interval '49 days'), (r42, cf, s3, now() - interval '42 days', now() - interval '42 days'),
    (r35, cf, s3, now() - interval '35 days', now() - interval '35 days'),
    (r0,  ca, s0, now(), now());

  -- Escala publicada de março/2025: V1 professora (Ciente) em 02/03; auxiliar vazia; sem líder do culto; 1 "Não poderei"
  insert into public.escalas (departamento_id, mes_referencia, status) values (v_kids, '2025-03-01', 'publicada') returning id into esc;
  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao, voluntaria_id, resposta) values
    (esc, k1, s0, 'professora', v1, 'ciente'), (esc, k1, s3, 'auxiliar', null, 'pendente');
  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao) values (esc, k1, null, 'lider_culto');
  insert into public.escala_recusas (escala_id, culto_id, voluntaria_id) values (esc, k1, v2);
  -- Escala publicada bem à frente: V2 auxiliar (para "Não poderei" de verdade)
  insert into public.cultos (igreja_id, data, horario, nome)
    values (v_igreja, (date_trunc('month', v_hoje) + interval '10 months')::date + 2, '07:13', 'Qwzteste') returning id into cul_p;
  insert into public.escalas (departamento_id, mes_referencia, status)
    values (v_kids, (date_trunc('month', v_hoje) + interval '10 months')::date, 'publicada') returning id into esc_p;
  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao, voluntaria_id) values (esc_p, cul_p, s3, 'auxiliar', v2) returning id into it_p;

  -- Evento publicado em março/2025: 2 inscritos (1 presente) e 1 ajudante
  insert into public.eventos (departamento_id, titulo, inicio, publicado) values (v_kids, 'Festa ficticia', '2025-03-15 15:00-03', true) returning id into ev;
  insert into public.inscricoes_evento (evento_id, crianca_id, presente) values (ev, ca, true), (ev, cb, null);
  insert into public.ajudas_evento (evento_id, voluntaria_id) values (ev, v1);

  -- Responsável aceita o termo (sem isso o login não libera nada)
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));

  -- ================= Permissões =================
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.indicadores_mes('2025-03-01');
    r := r || E'\n❌ visitante sem login viu os indicadores'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê indicadores'; end;
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  begin j := public.indicadores_semana('2025-03-02');
    r := r || E'\n❌ responsável viu os indicadores'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê indicadores'; end;
  begin j := public.sentimos_falta();
    r := r || E'\n❌ responsável viu "Sentimos falta"'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê "Sentimos falta"'; end;

  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  begin j := public.indicadores_mes('2025-03-01');
    r := r || E'\n❌ voluntária viu os indicadores'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não vê indicadores'; end;
  begin j := public.voluntarias_sem_escala();
    r := r || E'\n❌ voluntária viu "voluntárias sem escala"'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não vê "voluntárias sem escala"'; end;
  j := public.ultimo_culto();
  if j is null then r := r || E'\n✅ "Último culto" fica vazio para a voluntária';
  else r := r || E'\n❌ voluntária viu o "Último culto"'; falhas := falhas + 1; end if;

  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  begin perform 1 from public.escala_recusas limit 1;
    r := r || E'\n❌ líder leu "escala_recusas" direto'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ "escala_recusas" só pelas funções'; end;
  begin perform 1 from public.relatorios_avisados limit 1;
    r := r || E'\n❌ líder leu "relatorios_avisados" direto'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ "relatorios_avisados" só pelas funções'; end;
  begin perform private.avisar_relatorio_mes('2025-04-01');
    r := r || E'\n❌ líder disparou o aviso do relatório'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ aviso do relatório não pode ser chamado pelo app'; end;

  -- ================= Semana (02/03 a 08/03/2025) =================
  j := public.indicadores_semana('2025-03-05');
  if j->>'inicio' = '2025-03-02' and j->>'fim' = '2025-03-08' then r := r || E'\n✅ semana vai de domingo a sábado';
  else r := r || E'\n❌ semana errada: ' || coalesce(j->>'inicio', '–') || ' a ' || coalesce(j->>'fim', '–'); falhas := falhas + 1; end if;
  x := j->'atual';
  if (x->>'presencas')::int = 4 and (x->>'criancas')::int = 3 and (x->>'visitantes')::int = 1 and (x->>'membros')::int = 2
     and (x->>'cultos')::int = 2 then r := r || E'\n✅ semana: 4 presenças, 3 crianças, 1 visitante, 2 cultos';
  else r := r || E'\n❌ totais da semana: ' || x::text; falhas := falhas + 1; end if;
  if (x->>'primeira_vez')::int = 2 then r := r || E'\n✅ semana: 2 crianças pela primeira vez';
  else r := r || E'\n❌ primeira vez na semana: ' || coalesce(x->>'primeira_vez', 'nulo'); falhas := falhas + 1; end if;
  x := j->'anterior';
  if (x->>'presencas')::int = 1 and x->'primeira_vez' = 'null'::jsonb then
    r := r || E'\n✅ semana anterior: 1 presença; "primeira vez" vazio na semana em que o histórico começa';
  else r := r || E'\n❌ semana anterior: ' || x::text; falhas := falhas + 1; end if;
  if jsonb_array_length(j->'cultos') = 2 then r := r || E'\n✅ culto cancelado sem check-in fica fora da semana';
  else r := r || E'\n❌ cultos da semana: ' || jsonb_array_length(j->'cultos'); falhas := falhas + 1; end if;
  x := j->'cultos'->0;
  if (x->>'presencas')::int = 3 and (x->>'visitantes')::int = 1 and (x->>'primeira_vez')::int = 2 then
    r := r || E'\n✅ culto de 02/03 10h: 3 crianças, 1 visitante, 2 primeira vez';
  else r := r || E'\n❌ culto de 02/03: ' || x::text; falhas := falhas + 1; end if;
  if (j->'cultos'->1->>'primeira_vez')::int = 0 then r := r || E'\n✅ quem veio a 2 cultos no mesmo dia conta "primeira vez" só no primeiro';
  else r := r || E'\n❌ primeira vez no 2º culto do dia: ' || coalesce(j->'cultos'->1->>'primeira_vez', 'nulo'); falhas := falhas + 1; end if;
  select (s->>'presencas')::int into n from jsonb_array_elements(x->'salas') s where s->>'nome' = (select nome from public.salas where id = s3);
  if n = 2 then r := r || E'\n✅ presença por sala no culto';
  else r := r || E'\n❌ sala 3 a 6 no culto: ' || coalesce(n::text, 'nulo'); falhas := falhas + 1; end if;
  x := j->'escala';
  if (x->>'vagas')::int = 2 and (x->>'preenchidas')::int = 1 and (x->>'cientes')::int = 1
     and (x->>'cultos_sem_lider')::int = 1 and (x->>'nao_poderei')::int = 1 then
    r := r || E'\n✅ escala da semana: 2 vagas, 1 preenchida, 1 ciente, 1 sem líder, 1 "Não poderei"';
  else r := r || E'\n❌ escala da semana: ' || x::text; falhas := falhas + 1; end if;

  -- ================= Mês (março/2025) =================
  j := public.indicadores_mes('2025-03-20');
  x := j->'atual';
  if (x->>'presencas')::int = 5 and (x->>'criancas')::int = 3 and (x->>'cultos')::int = 3 and (x->>'primeira_vez')::int = 2
     and (x->>'familias_novas')::int = 1 then r := r || E'\n✅ mês: 5 presenças em 3 cultos, 2 primeira vez, 1 família nova';
  else r := r || E'\n❌ totais do mês: ' || x::text; falhas := falhas + 1; end if;
  if (j->'anterior'->>'presencas')::int = 1 then r := r || E'\n✅ mês anterior para comparar';
  else r := r || E'\n❌ mês anterior: ' || (j->'anterior')::text; falhas := falhas + 1; end if;
  select s into x from jsonb_array_elements(j->'por_tipo') s where s->>'nome' = (select nome from public.cultos_recorrentes where id = rec10);
  if (x->>'cultos')::int = 2 and (x->>'media')::numeric = 2 and (x->>'maximo')::int = 3
     and exists (select 1 from jsonb_array_elements(j->'por_tipo') s where s->>'nome' = 'Cultos extras' and (s->>'cultos')::int = 1) then
    r := r || E'\n✅ média por tipo de culto (e cultos extras à parte)';
  else r := r || E'\n❌ por tipo: ' || (j->'por_tipo')::text; falhas := falhas + 1; end if;
  select s into x from jsonb_array_elements(j->'por_sala') s where s->>'nome' = (select nome from public.salas where id = s3);
  if (x->>'cultos')::int = 3 and (x->>'maximo')::int = 2 and (x->>'lotou')::int = 0 then r := r || E'\n✅ por sala: média, máximo e lotação';
  else r := r || E'\n❌ por sala: ' || coalesce(x::text, 'nulo'); falhas := falhas + 1; end if;
  if jsonb_array_length(j->'semanas') = 2 and (j->'semanas'->0->>'presencas')::int = 4 then r := r || E'\n✅ presença por semana do mês';
  else r := r || E'\n❌ semanas: ' || (j->'semanas')::text; falhas := falhas + 1; end if;
  if (j->'retorno'->>'visitantes_novos')::int = 1 and (j->'retorno'->>'voltaram')::int = 1 then r := r || E'\n✅ visitante novo que voltou';
  else r := r || E'\n❌ retorno: ' || coalesce((j->'retorno')::text, 'nulo'); falhas := falhas + 1; end if;
  x := j->'voluntarias';
  if (x->>'escaladas')::int = 1 and (x->>'vagas')::int = 2 and (x->>'ativas')::int >= 2 and x->>'escala_status' = 'publicada' then
    r := r || E'\n✅ voluntárias e cobertura da escala no mês';
  else r := r || E'\n❌ voluntárias do mês: ' || x::text; falhas := falhas + 1; end if;
  x := j->'eventos'->0;
  if jsonb_array_length(j->'eventos') = 1 and (x->>'inscritos')::int = 2 and (x->>'presentes')::int = 1 and (x->>'ajudantes')::int = 1 then
    r := r || E'\n✅ evento do mês: inscritos, presentes e ajudantes';
  else r := r || E'\n❌ eventos: ' || (j->'eventos')::text; falhas := falhas + 1; end if;
  if position('Qwzteste' in j::text) = 0 and position('5500000' in j::text) = 0 then
    r := r || E'\n✅ indicadores do mês (base do relatório) sem nomes nem telefones';
  else r := r || E'\n❌ indicadores do mês trazem nome ou telefone'; falhas := falhas + 1; end if;
  if (public.indicadores_mes('2025-09-01')->'atual'->>'presencas')::int = 0 then r := r || E'\n✅ mês sem culto volta zerado';
  else r := r || E'\n❌ mês sem culto não veio zerado'; falhas := falhas + 1; end if;

  -- ================= Último culto =================
  j := public.ultimo_culto();
  if j->>'id' = r0::text and (j->>'presencas')::int = 1 then r := r || E'\n✅ "Último culto" para o Início da liderança';
  else r := r || E'\n❌ último culto: ' || coalesce(j::text, 'nulo'); falhas := falhas + 1; end if;

  -- ================= Cuidado =================
  j := public.sentimos_falta();
  select s into x from jsonb_array_elements(j) s where s->>'crianca_id' = cd::text;
  if (x->>'vezes')::int = 3 and x->'responsaveis'->0->>'telefone' = '5500000000001' then
    r := r || E'\n✅ "Sentimos falta": criança que vinha e sumiu há 5 semanas, com WhatsApp do responsável';
  else r := r || E'\n❌ "Sentimos falta" sem a criança D: ' || coalesce(x::text, 'nulo'); falhas := falhas + 1; end if;
  if not exists (select 1 from jsonb_array_elements(j) s where s->>'crianca_id' in (ce::text, cf::text, ca::text)) then
    r := r || E'\n✅ fora da lista: quem voltou há 1 semana, cadastro inativo e quem veio pouco';
  else r := r || E'\n❌ "Sentimos falta" com criança que não devia'; falhas := falhas + 1; end if;

  j := public.voluntarias_sem_escala();
  if exists (select 1 from jsonb_array_elements(j) s where s->>'voluntaria_id' = v1::text and s->>'ultima_vez' = '2025-03-02')
     and not exists (select 1 from jsonb_array_elements(j) s where s->>'voluntaria_id' = v2::text) then
    r := r || E'\n✅ voluntárias sem escala há 2 meses (quem tem vaga adiante fica fora)';
  else r := r || E'\n❌ voluntárias sem escala: V1/V2 erradas'; falhas := falhas + 1; end if;

  -- ================= "Não poderei" fica registrado =================
  perform set_config('request.jwt.claims', json_build_object('sub', u_v2, 'role', 'authenticated')::text, true);
  perform public.responder_escala(it_p, 'recusado');
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.escala_recusas where item_id = it_p and voluntaria_id = v2;
  ok := (select voluntaria_id is null from public.escala_itens where id = it_p);
  if n = 1 and ok then r := r || E'\n✅ "Não poderei" libera a vaga e fica registrado';
  else r := r || E'\n❌ "Não poderei": registros=' || n || ' vaga liberada=' || coalesce(ok::text, 'nulo'); falhas := falhas + 1; end if;
  select count(*) into n from public.notificacoes where destinatario_id = u_lid and titulo = 'Vaga liberada na escala';
  if n = 1 then r := r || E'\n✅ liderança continua avisada da vaga liberada';
  else r := r || E'\n❌ aviso da vaga liberada ao líder: ' || n; falhas := falhas + 1; end if;

  -- ================= Relatório automático (fora do RLS) =================
  perform set_config('request.jwt.claims', '{}', true);
  delete from public.relatorios_avisados where mes in ('2025-01-01', '2025-03-01');
  if private.avisar_relatorio_mes('2025-04-10') = 0 then r := r || E'\n✅ depois do dia 7 não avisa';
  else r := r || E'\n❌ avisou no dia 10'; falhas := falhas + 1; end if;
  if private.avisar_relatorio_mes('2025-02-01') = 0 then r := r || E'\n✅ mês sem check-in não avisa';
  else r := r || E'\n❌ avisou de mês sem check-in'; falhas := falhas + 1; end if;
  n := private.avisar_relatorio_mes('2025-04-01');
  if n >= 1 then r := r || E'\n✅ dia 1: relatório avisado a ' || n || ' login(s) da liderança';
  else r := r || E'\n❌ dia 1 não avisou'; falhas := falhas + 1; end if;
  select count(*) into n from public.notificacoes
   where destinatario_id = u_lid and titulo = 'Relatório de março de 2025 pronto'
     and link = '#/indicadores?aba=mes&mes=2025-03&ver=relatorio' and tipo = 'relatorio';
  if n = 1 then r := r || E'\n✅ líder recebe "Relatório de março de 2025 pronto" com o link do relatório';
  else r := r || E'\n❌ líder recebeu ' || n || ' aviso(s) do relatório'; falhas := falhas + 1; end if;
  select count(*) into n from public.notificacoes where destinatario_id in (u_v1, u_v2, u_pai) and tipo = 'relatorio';
  if n = 0 then r := r || E'\n✅ voluntárias e responsáveis não recebem o relatório';
  else r := r || E'\n❌ relatório foi para quem não é liderança'; falhas := falhas + 1; end if;
  if private.avisar_relatorio_mes('2025-04-03') = 0 then r := r || E'\n✅ o aviso do mês sai uma vez só';
  else r := r || E'\n❌ avisou duas vezes o mesmo mês'; falhas := falhas + 1; end if;
  if public.keep_alive() = 'ok' then r := r || E'\n✅ keep_alive continua respondendo "ok"';
  else r := r || E'\n❌ keep_alive mudou a resposta'; falhas := falhas + 1; end if;

  raise exception E'RESULTADO DOS TESTES (Fase 9): % falha(s)%', falhas, r;
end $teste$;
