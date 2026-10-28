-- =====================================================================
-- Teste da Fase 6 · Etapa 6A (motor de escala) com DADOS 100% FICTÍCIOS.
-- Tudo roda dentro de um bloco que é DESFEITO no final (nada fica salvo):
-- o resultado aparece na mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- (O motor usa também as voluntárias reais do mês de teste, mas nada é
--  gravado nem mostrado: só contagens e ✅/❌.)
-- =====================================================================
do $teste$
declare
  u_lid uuid := gen_random_uuid(); u_v1 uuid := gen_random_uuid(); u_v2 uuid := gen_random_uuid();
  u_pai uuid := gen_random_uuid();
  p_lid uuid; p_v1 uuid; p_v2 uuid; p_pai uuid;
  v1 uuid; v2 uuid;
  v_kids uuid; v_igreja uuid; s0 uuid; s3 uuid; rec10 uuid;
  v_mes date := (date_trunc('month', private.hoje()) + interval '3 months')::date;
  v_dom date; culto_ind uuid; culto_x uuid; item uuid; item2 uuid;
  j jsonb; n bigint; n2 bigint; txt text; ok boolean;
  r text := ''; falhas int := 0; total int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s0 from public.salas where departamento_id = v_kids and idade_min = 0;
  select id into s3 from public.salas where departamento_id = v_kids and idade_min = 3;
  select id into rec10 from public.cultos_recorrentes where dia_semana = 0 and horario = '10:00';

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome, sexo) values (v_igreja, 'Qwzteste Lider', 'F') returning id into p_lid;
  insert into public.pessoas (igreja_id, nome, sexo, data_nascimento)
    values (v_igreja, 'Qwzteste Voluntaria Um', 'F', private.hoje() - interval '30 years') returning id into p_v1;
  insert into public.pessoas (igreja_id, nome, sexo, data_nascimento)
    values (v_igreja, 'Qwzteste Voluntaria Dois', 'F', private.hoje() - interval '15 years') returning id into p_v2;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Responsavel') returning id into p_pai;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lid, 'f6.lid@exemplo.invalid', jsonb_build_object('pessoa_id', p_lid)),
    (u_v1,  'f6.v1@exemplo.invalid',  jsonb_build_object('pessoa_id', p_v1)),
    (u_v2,  'f6.v2@exemplo.invalid',  jsonb_build_object('pessoa_id', p_v2)),
    (u_pai, 'f6.pai@exemplo.invalid', jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lid, u_v1, u_v2, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lid, v_kids, 'lider'), (u_v1, v_kids, 'voluntaria'), (u_v2, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  -- V1: professora adulta, só 0 a 2 anos, só domingo 10h, teto 2
  insert into public.voluntarias (departamento_id, pessoa_id, funcao, status, salas_preferidas, cultos_preferidos, teto_mensal)
    values (v_kids, p_v1, 'professora', 'ativa', array[s0], array[rec10], 2) returning id into v1;
  -- V2: "professora" de 15 anos (conta como auxiliar), 0 a 2 e 3 a 6, domingo 10h
  insert into public.voluntarias (departamento_id, pessoa_id, funcao, status, salas_preferidas, cultos_preferidos, teto_mensal)
    values (v_kids, p_v2, 'professora', 'ativa', array[s0, s3], array[rec10], 3) returning id into v2;

  -- ================= TESTES =================
  -- Visitante sem login
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.escala_do_mes(v_mes);
    r := r || E'\n❌ visitante sem login viu a escala'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê a escala'; end;
  begin j := public.minha_escala();
    r := r || E'\n❌ visitante sem login abriu "Minha escala"'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não abre "Minha escala"'; end;
  perform set_config('role', 'authenticated', true);

  -- Responsável (não é da equipe)
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  begin j := public.escala_do_mes(v_mes);
    r := r || E'\n❌ responsável viu a escala'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê a escala'; end;

  -- Voluntária não faz o que é da liderança
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  begin perform public.configurar_escala(v_mes, null);
    r := r || E'\n❌ voluntária configurou o mês'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não configura o mês'; end;
  begin j := public.lembretes_escala(private.hoje(), private.hoje() + 7);
    r := r || E'\n❌ voluntária viu os telefones dos lembretes'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não vê os lembretes (telefones)'; end;
  begin perform public.definir_regras_escala('{"teto_padrao": 9}');
    r := r || E'\n❌ voluntária mudou as regras'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não muda as regras'; end;
  -- indisponibilidade da V1 no 1º domingo 10h do mês de teste (pela função)
  j := public.minha_indisponibilidade(v_mes);
  select (c->>'id')::uuid, (c->>'data')::date into culto_ind, v_dom
    from jsonb_array_elements(j->'cultos') c where (c->>'horario') = '10:00' order by (c->>'data') limit 1;
  perform public.salvar_indisponibilidade(v_mes, array[culto_ind]);
  j := public.minha_indisponibilidade(v_mes);
  ok := (j->>'respondeu')::boolean and exists (select 1 from jsonb_array_elements(j->'cultos') c
          where (c->>'id')::uuid = culto_ind and (c->>'indisponivel')::boolean);
  r := r || format(E'\n%s voluntária marca a própria indisponibilidade', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin insert into public.indisponibilidades (voluntaria_id, data, horario) values (v1, v_dom, '19:00');
    r := r || E'\n❌ gravação direta na tabela de indisponibilidade'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ indisponibilidade só pela função'; end;

  -- Liderança configura e gera
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  perform public.configurar_escala(v_mes, null);
  j := public.gerar_rascunho(v_mes);
  n := (j->>'vagas')::bigint;
  r := r || format(E'\n%s liderança gera o rascunho: %s vagas, %s preenchidas', case when n > 0 then '✅' else '❌' end, n, j->>'preenchidas'); falhas := falhas + (n = 0)::int;
  begin insert into public.escala_itens (escala_id, culto_id, sala_id, funcao)
          select e.id, culto_ind, s0, 'auxiliar' from public.escalas e where e.mes_referencia = v_mes;
    r := r || E'\n❌ gravação direta na tabela da escala'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ escala só pelas funções (nem a liderança grava direto)'; end;
  j := public.simular_escala(v_mes, 'datas');
  r := r || format(E'\n%s simulação não grava nada', case when (j->>'vagas')::int = n then '✅' else '❌' end); falhas := falhas + ((j->>'vagas')::int <> n)::int;

  -- Voluntária não vê rascunho
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  j := public.escala_do_mes(v_mes);
  r := r || format(E'\n%s voluntária não vê o rascunho', case when j->'escala' = 'null'::jsonb then '✅' else '❌' end); falhas := falhas + (j->'escala' <> 'null'::jsonb)::int;

  -- Regras do motor (conferidas como administrador do banco)
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.escala_itens i join public.escalas e on e.id = i.escala_id and e.mes_referencia = v_mes
   join public.cultos c on c.id = i.culto_id
   where i.voluntaria_id is not null
   group by i.voluntaria_id, c.data having count(*) > 1 limit 1;
  r := r || format(E'\n%s ninguém fica com duas vagas no mesmo dia', case when coalesce(n, 0) = 0 then '✅' else '❌' end); falhas := falhas + (coalesce(n, 0) > 0)::int;
  n := null;
  select count(*) into n from (
    select i.voluntaria_id from public.escala_itens i join public.escalas e on e.id = i.escala_id and e.mes_referencia = v_mes
    join public.voluntarias v on v.id = i.voluntaria_id
    where i.funcao <> 'lider_culto'
    group by i.voluntaria_id, v.teto_mensal having count(*) > coalesce(v.teto_mensal, 3)) z;
  r := r || format(E'\n%s ninguém passa do teto do mês', case when n = 0 then '✅' else '❌' end); falhas := falhas + (n > 0)::int;
  select count(*) into n from public.escala_itens i join public.escalas e on e.id = i.escala_id and e.mes_referencia = v_mes
   join public.cultos c on c.id = i.culto_id
   join public.indisponibilidades d on d.voluntaria_id = i.voluntaria_id and d.data = c.data and d.horario = c.horario;
  r := r || format(E'\n%s ninguém é escalada num culto em que marcou indisponível', case when n = 0 then '✅' else '❌' end); falhas := falhas + (n > 0)::int;
  select count(*) into n from public.escala_itens i join public.escalas e on e.id = i.escala_id and e.mes_referencia = v_mes
   join public.cultos c on c.id = i.culto_id join public.voluntarias v on v.id = i.voluntaria_id
   where i.funcao <> 'lider_culto' and (
     not (coalesce(v.salas_preferidas, '{}') && (select g.salas from private.esc_grupos(c.id) g where g.sala_id = i.sala_id))
     or (c.culto_recorrente_id is not null and not c.culto_recorrente_id = any (coalesce(v.cultos_preferidos, '{}'))));
  r := r || format(E'\n%s todas as vagas respeitam faixas e cultos preferidos', case when n = 0 then '✅' else '❌' end); falhas := falhas + (n > 0)::int;
  select count(*) into n from public.escala_itens i join public.escalas e on e.id = i.escala_id and e.mes_referencia = v_mes
   where i.funcao = 'professora' and not i.cobrindo_lider and i.voluntaria_id is not null
     and not private.esc_pode_liderar(i.voluntaria_id);
  r := r || format(E'\n%s vaga de professora só com quem pode liderar (16+)', case when n = 0 then '✅' else '❌' end); falhas := falhas + (n > 0)::int;
  select count(*) into n from public.escala_itens i join public.escalas e on e.id = i.escala_id and e.mes_referencia = v_mes
   where i.voluntaria_id = v2 and i.funcao = 'professora' and not i.cobrindo_lider;
  r := r || format(E'\n%s voluntária de 15 anos não vira professora', case when n = 0 then '✅' else '❌' end); falhas := falhas + (n > 0)::int;
  select count(*) into n from public.escala_itens i join public.escalas e on e.id = i.escala_id and e.mes_referencia = v_mes
   where i.funcao = 'lider_culto' and i.voluntaria_id is null;
  select count(*) into n2 from public.cultos c where c.data between v_mes and (v_mes + interval '1 month' - interval '1 day')::date
   and not c.cancelado and c.igreja_id = v_igreja;
  r := r || format(E'\n%s uma vaga de líder do culto por culto, vazia', case when n = n2 then '✅' else '❌' end); falhas := falhas + (n <> n2)::int;

  -- Publicar
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  -- garante uma vaga da V1 e uma vaga aberta para os testes seguintes
  select i.id into item from public.escala_itens i join public.escalas e on e.id = i.escala_id and e.mes_referencia = v_mes
   join public.cultos c on c.id = i.culto_id
   where i.sala_id = s0 and i.funcao = 'auxiliar' and c.culto_recorrente_id = rec10 and c.id <> culto_ind
     and not exists (select 1 from public.escala_itens o join public.cultos oc on oc.id = o.culto_id
                     where o.voluntaria_id = v1 and oc.data = c.data)
   order by c.data limit 1;
  perform public.trocar_vaga(item, v1, null);
  j := public.candidatas_vaga(item);
  r := r || format(E'\n%s liderança vê as candidatas com avisos', case when jsonb_array_length(j) > 0 then '✅' else '❌' end); falhas := falhas + (jsonb_array_length(j) = 0)::int;
  select c.id into culto_x from public.cultos c where c.id = (select culto_id from public.escala_itens where id = item);
  item2 := public.adicionar_vaga(culto_x, s3, 'auxiliar');
  j := public.publicar_escala(v_mes);
  r := r || format(E'\n%s liderança publica (%s voluntárias avisadas)', case when (j->>'voluntarias')::int > 0 then '✅' else '❌' end, j->>'voluntarias');
  falhas := falhas + ((j->>'voluntarias')::int = 0)::int;
  begin j := public.gerar_rascunho(v_mes);
    r := r || E'\n❌ gerar de novo apagou a escala publicada'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ escala publicada não pode ser gerada de novo'; end;

  -- Voluntária depois de publicar
  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  j := public.escala_do_mes(v_mes);
  r := r || format(E'\n%s voluntária vê a escala publicada', case when j->'escala' <> 'null'::jsonb then '✅' else '❌' end); falhas := falhas + (j->'escala' = 'null'::jsonb)::int;
  ok := (select count(*) from public.notificacoes where destinatario_id = u_v1 and tipo = 'escala') > 0;
  r := r || format(E'\n%s voluntária recebe aviso da publicação', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  j := public.minha_escala();
  ok := exists (select 1 from jsonb_array_elements(j->'minhas') x where (x->>'id')::uuid = item);
  r := r || format(E'\n%s "Minha escala" mostra a vaga dela', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  ok := exists (select 1 from jsonb_array_elements(j->'abertas') x where (x->>'id')::uuid = item2);
  r := r || format(E'\n%s "Minha escala" mostra as vagas abertas', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform public.responder_escala(item, 'ciente');
  ok := (select resposta from public.escala_itens where id = item) = 'ciente';
  r := r || format(E'\n%s voluntária marca Ciente', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin perform public.pegar_vaga(item2);
    r := r || E'\n❌ pegou duas vagas no mesmo dia'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não pega vaga no dia em que já está escalada'; end;
  begin perform public.salvar_indisponibilidade(v_mes, '{}');
    r := r || E'\n❌ mudou a indisponibilidade de mês já publicado'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ indisponibilidade fecha quando a escala é publicada'; end;
  perform set_config('role', 'postgres', true);
  n := (select count(*) from public.notificacoes where destinatario_id = u_lid);
  perform set_config('role', 'authenticated', true);
  perform public.responder_escala(item, 'recusado');
  perform set_config('role', 'postgres', true);
  ok := (select voluntaria_id is null and resposta = 'pendente' from public.escala_itens where id = item)
        and (select count(*) from public.notificacoes where destinatario_id = u_lid) > n;
  perform set_config('role', 'authenticated', true);
  r := r || format(E'\n%s "Não poderei" libera a vaga e avisa a liderança', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  perform public.pegar_vaga(item2);
  ok := (select voluntaria_id = v1 and resposta = 'ciente' from public.escala_itens where id = item2);
  r := r || format(E'\n%s voluntária pega vaga aberta (entra como Ciente)', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;
  begin perform public.responder_escala(item2, 'ciente');
    perform set_config('request.jwt.claims', json_build_object('sub', u_v2, 'role', 'authenticated')::text, true);
    perform public.responder_escala(item2, 'recusado');
    r := r || E'\n❌ voluntária respondeu pela vaga de outra'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ ninguém responde pela vaga de outra pessoa'; end;
  perform set_config('request.jwt.claims', json_build_object('sub', u_v2, 'role', 'authenticated')::text, true);
  begin
    select i.id into item from public.escala_itens i join public.escalas e on e.id = i.escala_id and e.mes_referencia = v_mes
     where i.funcao = 'lider_culto' and i.voluntaria_id is null limit 1;
    perform public.pegar_vaga(item);
    r := r || E'\n❌ voluntária pegou a vaga de líder do culto'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ líder do culto só pela liderança'; end;

  -- Liderança: lembretes
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  j := public.lembretes_escala(v_mes, v_mes + 30);
  ok := jsonb_array_length(j->'itens') > 0 and (j->>'mensagem') is not null;
  r := r || format(E'\n%s liderança monta os lembretes do WhatsApp', case when ok then '✅' else '❌' end); falhas := falhas + (not ok)::int;

  -- Funções internas fechadas
  begin perform private.esc_motor('datas');
    r := r || E'\n❌ função interna liberada para o app'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ funções internas fechadas para o app'; end;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
