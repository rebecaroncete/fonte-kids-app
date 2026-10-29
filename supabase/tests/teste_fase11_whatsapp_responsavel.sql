-- =====================================================================
-- Teste do "WhatsApp" do responsável (Fase 11) com DADOS 100% FICTÍCIOS
-- (culto fictício hoje às 23h56). Tudo é DESFEITO no final: o resultado
-- aparece na mensagem de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor depois da migração
-- 20261029030000_fase11_whatsapp_responsavel.
-- =====================================================================
do $teste$
declare
  u_v1 uuid := gen_random_uuid(); u_pai uuid := gen_random_uuid();
  p_v1 uuid; p_pai uuid; p_mae uuid; p_sem uuid; p_a uuid;
  ca uuid; fam uuid; v_kids uuid; v_igreja uuid; s0 uuid; cul uuid; cul_velho uuid; ka uuid; k_velho uuid;
  v_hoje date := private.hoje();
  j jsonb; r text := ''; falhas int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s0 from public.salas where departamento_id = v_kids and idade_min = 0;

  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Voluntaria Um', '5500000000011') returning id into p_v1;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Pai Ficticio', '5500000000001') returning id into p_pai;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Mae Ficticia', '5500000000002') returning id into p_mae;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Sem Telefone') returning id into p_sem;
  insert into public.pessoas (igreja_id, nome, data_nascimento) values (v_igreja, 'Qwzteste Crianca Abc', v_hoje - interval '2 years') returning id into p_a;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_v1,  'f11w.v1@exemplo.invalid',  jsonb_build_object('pessoa_id', p_v1)),
    (u_pai, 'f11w.pai@exemplo.invalid', jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_v1, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values (u_v1, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.voluntarias (departamento_id, pessoa_id, funcao, status) values (v_kids, p_v1, 'auxiliar', 'ativa');
  insert into public.familias (departamento_id) values (v_kids) returning id into fam;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (fam, p_pai, false), (fam, p_mae, true), (fam, p_sem, false);
  insert into public.criancas (familia_id, pessoa_id) values (fam, p_a) returning id into ca;
  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, v_hoje, '23:56', 'Qwzteste') returning id into cul;
  insert into public.cultos (igreja_id, data, horario, nome) values (v_igreja, v_hoje - 3, '06:06', 'Qwzteste') returning id into cul_velho;
  insert into public.checkins (culto_id, crianca_id, sala_id) values (cul, ca, s0) returning id into ka;
  insert into public.checkins (culto_id, crianca_id, sala_id, entrada_em, saida_em)
    values (cul_velho, ca, s0, now() - interval '3 days', now() - interval '3 days') returning id into k_velho;

  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));
  begin j := public.whatsapp_responsaveis(ka);
    r := r || E'\n❌ responsável abriu o WhatsApp da recepção'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não usa o WhatsApp da recepção'; end;

  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.whatsapp_responsaveis(ka);
    r := r || E'\n❌ visitante sem login viu telefones'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante sem login não vê telefones'; end;
  perform set_config('role', 'authenticated', true);

  perform set_config('request.jwt.claims', json_build_object('sub', u_v1, 'role', 'authenticated')::text, true);
  j := public.whatsapp_responsaveis(ka);
  if jsonb_array_length(j->'responsaveis') = 2 then r := r || E'\n✅ mostra os 2 responsáveis com telefone (quem não tem fica de fora)';
  else r := r || E'\n❌ responsáveis: ' || j::text; falhas := falhas + 1; end if;
  if j->'responsaveis'->0->>'nome' = 'Qwzteste Ficticia' and (j->'responsaveis'->0->>'principal')::boolean then
    r := r || E'\n✅ o responsável principal vem primeiro';
  else r := r || E'\n❌ ordem: ' || j::text; falhas := falhas + 1; end if;
  if j->>'mensagem' like '%Qwzteste Abc%' and j->>'mensagem' not like '%{nome_crianca}%' then
    r := r || E'\n✅ mensagem pronta do modelo "choro" com o nome da criança';
  else r := r || E'\n❌ mensagem: ' || coalesce(j->>'mensagem', 'nula'); falhas := falhas + 1; end if;
  begin j := public.whatsapp_responsaveis(k_velho);
    r := r || E'\n❌ abriu WhatsApp de check-in de outro dia'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ só check-in de hoje'; end;

  raise exception E'RESULTADO DOS TESTES (Fase 11 · WhatsApp): % falha(s)%', falhas, r;
end $teste$;
