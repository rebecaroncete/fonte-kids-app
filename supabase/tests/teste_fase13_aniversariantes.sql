-- =====================================================================
-- Teste dos aniversariantes do mês (Fase 13) com DADOS 100% FICTÍCIOS
-- (pessoas "Qwzteste", aniversário hoje). Tudo é DESFEITO no final: o
-- resultado aparece na mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor depois da migração
-- 20261029170000_fase13_aniversariantes.
-- =====================================================================
do $teste$
declare
  u_lid uuid := gen_random_uuid(); u_rec uuid := gen_random_uuid(); u_vol uuid := gen_random_uuid();
  u_aniv uuid := gen_random_uuid(); u_pai uuid := gen_random_uuid();
  p_lid uuid; p_rec uuid; p_vol uuid; p_aniv uuid; p_vinat uuid; p_pai uuid; p_mae uuid; p_avo uuid; p_tia uuid;
  p_c1 uuid; p_c2 uuid; p_cinat uuid; p_bebe uuid;
  fam1 uuid; fam2 uuid; v_kids uuid; v_igreja uuid;
  v_hoje date := private.hoje();
  j jsonb; c jsonb; v jsonb; t text; n int; r text := ''; falhas int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';

  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Lider Um', '5500000000021') returning id into p_lid;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Recepcao Um', '5500000000022') returning id into p_rec;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Voluntaria Um', '5500000000023') returning id into p_vol;
  insert into public.pessoas (igreja_id, nome, telefone, data_nascimento)
    values (v_igreja, 'Qwzteste Voluntaria Aniversario', '5571999990024', v_hoje - interval '30 years') returning id into p_aniv;
  insert into public.pessoas (igreja_id, nome, telefone, data_nascimento)
    values (v_igreja, 'Qwzteste Voluntaria Inativa', '5571999990025', v_hoje - interval '25 years') returning id into p_vinat;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Pai Ficticio', '5571999990001') returning id into p_pai;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Mae Ficticia', '5571999990002') returning id into p_mae;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Avo Semtelefone') returning id into p_avo;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Tia Ficticia', '5571999990003') returning id into p_tia;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Abc', v_hoje - interval '6 years') returning id into p_c1;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Def', v_hoje - interval '1 year') returning id into p_c2;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Inativa', v_hoje - interval '4 years') returning id into p_cinat;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Bebe', v_hoje) returning id into p_bebe;

  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lid,  'f13.lid@exemplo.invalid',  jsonb_build_object('pessoa_id', p_lid)),
    (u_rec,  'f13.rec@exemplo.invalid',  jsonb_build_object('pessoa_id', p_rec)),
    (u_vol,  'f13.vol@exemplo.invalid',  jsonb_build_object('pessoa_id', p_vol)),
    (u_aniv, 'f13.aniv@exemplo.invalid', jsonb_build_object('pessoa_id', p_aniv)),
    (u_pai,  'f13.pai@exemplo.invalid',  jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lid, u_rec, u_vol, u_aniv, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lid, v_kids, 'lider'), (u_rec, v_kids, 'recepcao'), (u_vol, v_kids, 'voluntaria'),
    (u_aniv, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.voluntarias (departamento_id, pessoa_id, funcao, status) values
    (v_kids, p_vol, 'auxiliar', 'ativa'), (v_kids, p_aniv, 'auxiliar', 'ativa'), (v_kids, p_vinat, 'auxiliar', 'inativa');
  insert into public.familias (departamento_id) values (v_kids) returning id into fam1;
  insert into public.familias (departamento_id) values (v_kids) returning id into fam2;
  -- família 1: principal com telefone; família 2: principal SEM telefone (vai para a tia)
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (fam1, p_pai, false), (fam1, p_mae, true);
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (fam2, p_avo, true), (fam2, p_tia, false);
  insert into public.criancas (familia_id, pessoa_id) values (fam1, p_c1), (fam2, p_c2), (fam1, p_bebe);
  insert into public.criancas (familia_id, pessoa_id, ativo) values (fam1, p_cinat, false);

  -- 29/02 vira 28/02 em ano comum
  if private.aniversario_no_ano(date '2020-02-29', 2027) = date '2027-02-28'
     and private.aniversario_no_ano(date '2020-02-29', 2028) = date '2028-02-29' then
    r := r || E'\n✅ 29/02 vira 28/02 em ano comum';
  else r := r || E'\n❌ 29/02 em ano comum'; falhas := falhas + 1; end if;

  -- ---------- Aviso do dia (fora do RLS) ----------
  delete from public.aniversarios_avisados where dia = v_hoje;
  n := private.avisar_aniversariantes_dia(v_hoje);
  if exists (select 1 from public.notificacoes where destinatario_id = u_lid and tipo = 'aniversario' and link = '#/aniversariantes')
     and exists (select 1 from public.notificacoes where destinatario_id = u_rec and tipo = 'aniversario')
     and exists (select 1 from public.notificacoes where destinatario_id = u_vol and tipo = 'aniversario') then
    r := r || E'\n✅ aviso do dia chegou para liderança, recepção e voluntária';
  else r := r || E'\n❌ aviso do dia não chegou para a equipe'; falhas := falhas + 1; end if;
  if not exists (select 1 from public.notificacoes where destinatario_id = u_aniv and tipo = 'aniversario') then
    r := r || E'\n✅ a aniversariante não recebe o aviso sobre ela mesma';
  else r := r || E'\n❌ a aniversariante recebeu o aviso'; falhas := falhas + 1; end if;
  if not exists (select 1 from public.notificacoes where destinatario_id = u_pai and tipo = 'aniversario') then
    r := r || E'\n✅ responsável não recebe o aviso';
  else r := r || E'\n❌ responsável recebeu o aviso'; falhas := falhas + 1; end if;
  select n2.corpo into t from public.notificacoes n2 where n2.destinatario_id = u_lid and n2.tipo = 'aniversario' limit 1;
  if t like '%Qwzteste Abc (6 anos)%' and t like '%Qwzteste Def (1 ano)%'
     and t like '%Qwzteste Aniversario%' and t not like '%Inativa%' and t not like '%Bebe%' then
    r := r || E'\n✅ texto do aviso com crianças (idade) e voluntária; inativos e recém-nascido fora';
  else r := r || E'\n❌ texto do aviso: ' || coalesce(t, 'nulo'); falhas := falhas + 1; end if;
  if (select titulo from public.notificacoes where destinatario_id = u_lid and tipo = 'aniversario' limit 1) not like '%Qwzteste%' then
    r := r || E'\n✅ título sem nomes (é o que aparece na tela bloqueada)';
  else r := r || E'\n❌ título com nome'; falhas := falhas + 1; end if;
  n := private.avisar_aniversariantes_dia(v_hoje);
  if n = 0 and (select count(*) from public.notificacoes where destinatario_id = u_lid and tipo = 'aniversario') = 1 then
    r := r || E'\n✅ uma vez só por dia';
  else r := r || E'\n❌ avisou de novo no mesmo dia'; falhas := falhas + 1; end if;

  -- ---------- Tela (com RLS) ----------
  perform set_config('role', 'authenticated', true);

  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.aniversariantes_mes(v_hoje);
    r := r || E'\n❌ visitante sem login viu aniversariantes'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê'; end;
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));
  begin j := public.aniversariantes_mes(v_hoje);
    r := r || E'\n❌ responsável viu a lista'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê a lista'; end;

  -- voluntária SEM o papel de recepção (caso raro: hoje toda voluntária ganha
  -- a recepção junto, decisão de 27/10/2026): vê a lista, sem telefones
  perform set_config('role', 'postgres', true);
  delete from public.papeis_usuario where perfil_id = u_vol and papel = 'recepcao';
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  j := public.aniversariantes_mes(v_hoje);
  select x into c from jsonb_array_elements(j->'criancas') x where x->>'nome' = 'Qwzteste Abc';
  if c is not null and (c->>'idade')::int = 6 and c->>'dia' = v_hoje::text then
    r := r || E'\n✅ voluntária vê a criança com o dia e a idade';
  else r := r || E'\n❌ criança na lista da voluntária: ' || coalesce(c::text, 'não veio'); falhas := falhas + 1; end if;
  if not (j->>'pode_whatsapp')::boolean and c->'responsavel' = 'null'::jsonb and j->'mensagem_crianca' = 'null'::jsonb
     and not exists (select 1 from jsonb_array_elements(j->'voluntarias') x where x->>'nome' like 'Qwzteste%' and x->'telefone' <> 'null'::jsonb) then
    r := r || E'\n✅ voluntária sem recepção não vê telefones nem botão de WhatsApp';
  else r := r || E'\n❌ voluntária viu telefone: ' || j::text; falhas := falhas + 1; end if;
  if not exists (select 1 from jsonb_array_elements(j->'criancas') x where x->>'nome' in ('Qwzteste Inativa', 'Qwzteste Bebe'))
     and not exists (select 1 from jsonb_array_elements(j->'voluntarias') x where x->>'nome' = 'Qwzteste Inativa')
     and exists (select 1 from jsonb_array_elements(j->'voluntarias') x where x->>'nome' = 'Qwzteste Aniversario') then
    r := r || E'\n✅ só crianças e voluntárias ativas (e recém-nascido fora)';
  else r := r || E'\n❌ inativos na lista'; falhas := falhas + 1; end if;

  -- recepção: telefone do responsável principal (ou de outro, se o principal não tiver)
  perform set_config('request.jwt.claims', json_build_object('sub', u_rec, 'role', 'authenticated')::text, true);
  j := public.aniversariantes_mes(v_hoje);
  select x into c from jsonb_array_elements(j->'criancas') x where x->>'nome' = 'Qwzteste Abc';
  if (j->>'pode_whatsapp')::boolean and c->'responsavel'->>'nome' = 'Qwzteste Ficticia'
     and c->'responsavel'->>'telefone' = '5571999990002' and j->>'mensagem_crianca' like '%{nome_crianca}%' then
    r := r || E'\n✅ recepção: responsável principal com telefone e mensagem pronta';
  else r := r || E'\n❌ recepção, criança 1: ' || coalesce(c::text, 'não veio'); falhas := falhas + 1; end if;
  select x into c from jsonb_array_elements(j->'criancas') x where x->>'nome' = 'Qwzteste Def';
  if c->'responsavel'->>'telefone' = '5571999990003' then
    r := r || E'\n✅ principal sem telefone: vai para outro responsável que tenha';
  else r := r || E'\n❌ recepção, criança 2: ' || coalesce(c::text, 'não veio'); falhas := falhas + 1; end if;
  select x into v from jsonb_array_elements(j->'voluntarias') x where x->>'nome' = 'Qwzteste Aniversario';
  if v->>'telefone' = '5571999990024' then
    r := r || E'\n✅ recepção vê o WhatsApp da voluntária aniversariante';
  else r := r || E'\n❌ voluntária na recepção: ' || coalesce(v::text, 'não veio'); falhas := falhas + 1; end if;

  -- liderança
  perform set_config('request.jwt.claims', json_build_object('sub', u_lid, 'role', 'authenticated')::text, true);
  j := public.aniversariantes_mes(v_hoje);
  if (j->>'pode_whatsapp')::boolean and exists (select 1 from jsonb_array_elements(j->'criancas') x where x->>'nome' = 'Qwzteste Abc') then
    r := r || E'\n✅ liderança vê a lista com WhatsApp';
  else r := r || E'\n❌ liderança: ' || j::text; falhas := falhas + 1; end if;
  j := public.aniversariantes_mes((v_hoje + interval '1 month')::date);
  if not exists (select 1 from jsonb_array_elements(j->'criancas') x where x->>'nome' like 'Qwzteste%') then
    r := r || E'\n✅ outro mês não mostra os aniversariantes de hoje';
  else r := r || E'\n❌ mês seguinte com os de hoje'; falhas := falhas + 1; end if;

  raise exception E'RESULTADO DOS TESTES (Fase 13 · Aniversariantes): % falha(s)%', falhas, r;
end $teste$;
