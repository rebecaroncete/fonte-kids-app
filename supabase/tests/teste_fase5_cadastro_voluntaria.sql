-- =====================================================================
-- Teste da Fase 5 · Etapa 5F (cadastro de voluntária pelo link e aprovação)
-- com DADOS 100% FICTÍCIOS. Tudo roda dentro de um bloco que é DESFEITO no
-- final (nada fica salvo, nem os avisos): o resultado aparece na mensagem
-- de erro "RESULTADO DOS TESTES".
-- Como rodar: cole no SQL Editor do Supabase e execute.
-- =====================================================================
do $teste$
declare
  u_lider uuid := gen_random_uuid(); u_vol uuid := gen_random_uuid(); u_pai uuid := gen_random_uuid();
  p_lider uuid; p_vol uuid; p_pai uuid;
  v_kids uuid; v_igreja uuid; s0 uuid; s3 uuid; rec1 uuid;
  tel_a text := '5511900007301'; tel_b text := '5511900007302'; tel_c text := '5511900007303';
  base jsonb; j jsonb; n bigint; txt text; ped1 uuid; ped2 uuid; ped3 uuid; v_pessoa uuid; v_familia uuid;
  -- datas calculadas no início (o papel de serviço não usa funções internas)
  d11 date := private.hoje() - interval '11 years'; d15 date := private.hoje() - interval '15 years';
  d25 date := private.hoje() - interval '25 years';
  r text := ''; falhas int := 0; total int := 0;
begin
  select id, igreja_id into v_kids, v_igreja from public.departamentos where slug = 'kids';
  select id into s0 from public.salas where departamento_id = v_kids and idade_min = 0;
  select id into s3 from public.salas where departamento_id = v_kids and idade_min = 3;
  select id into rec1 from public.cultos_recorrentes where ativo order by dia_semana, horario limit 1;
  if exists (select 1 from public.pessoas where telefone in (tel_a, tel_b, tel_c))
     or exists (select 1 from public.pedidos_voluntaria where telefone in (tel_a, tel_b, tel_c)) then
    raise exception 'Telefones fictícios do teste já existem no banco – troque-os';
  end if;

  -- ---------- Montagem (fictícia) ----------
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Lider') returning id into p_lider;
  insert into public.pessoas (igreja_id, nome) values (v_igreja, 'Qwzteste Voluntaria') returning id into p_vol;
  insert into public.pessoas (igreja_id, nome, telefone) values (v_igreja, 'Qwzteste Responsavel Original', tel_b) returning id into p_pai;
  insert into auth.users (id, email, raw_app_meta_data) values
    (u_lider, 'f5f.lider@exemplo.invalid', jsonb_build_object('pessoa_id', p_lider)),
    (u_vol,   'f5f.vol@exemplo.invalid',   jsonb_build_object('pessoa_id', p_vol)),
    (u_pai,   'f5f.pai@exemplo.invalid',   jsonb_build_object('pessoa_id', p_pai));
  update public.perfis set troca_senha_obrigatoria = false where id in (u_lider, u_vol, u_pai);
  insert into public.papeis_usuario (perfil_id, departamento_id, papel) values
    (u_lider, v_kids, 'lider'), (u_vol, v_kids, 'voluntaria'), (u_pai, null, 'responsavel');
  insert into public.familias (departamento_id) values (v_kids) returning id into v_familia;
  insert into public.responsaveis (familia_id, pessoa_id, principal) values (v_familia, p_pai, true);

  base := jsonb_build_object('nome', 'Qwzteste Candidata Alfa', 'telefone', tel_a,
    'nascimento', d25, 'email', 'alfa@exemplo.invalid',
    'profissao', 'Fictícia', 'sexo', 'F', 'funcao', 'auxiliar',
    'salas', jsonb_build_array(s3, s0), 'cultos', jsonb_build_array(rec1),
    'termo_versao', (select versao from public.termos_voluntaria_versoes where vigente));

  -- ================= TESTES =================
  -- Visitante sem login: nada direto
  perform set_config('role', 'anon', true);
  perform set_config('request.jwt.claims', '{"role":"anon"}', true);
  begin j := public.voluntaria_link_opcoes();
    r := r || E'\n❌ visitante chamou as opções direto (sem a Edge Function)'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante não chama as funções do link direto'; end;
  begin j := public.pedido_voluntaria_criar(base);
    r := r || E'\n❌ visitante gravou pedido direto'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante não grava pedido direto'; end;
  begin select count(*) into n from public.pedidos_voluntaria;
    r := r || E'\n❌ visitante leu a tabela de pedidos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ visitante não lê a tabela de pedidos'; end;

  -- Login comum também não chama as funções do link
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  begin j := public.pedido_voluntaria_criar(base);
    r := r || E'\n❌ login comum gravou pedido direto'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ login comum não grava pedido direto'; end;

  -- Edge Function (service_role)
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  j := public.voluntaria_link_opcoes();
  txt := (j->'termo'->>'versao') || '/' || jsonb_array_length(j->'salas') || '/' || (jsonb_array_length(j->'cultos') > 0);
  r := r || format(E'\n%s opções do formulário (termo/salas/cultos): %s', case when j->'termo'->>'texto' is not null and jsonb_array_length(j->'salas') >= 4 then '✅' else '❌' end, txt);
  falhas := falhas + (not (j->'termo'->>'texto' is not null and jsonb_array_length(j->'salas') >= 4))::int;

  begin j := public.pedido_voluntaria_criar(base || jsonb_build_object('nascimento', d11));
    r := r || E'\n❌ aceitou menor de 12 anos'; falhas := falhas + 1;
  exception when others then r := r || format(E'\n%s recusa menor de 12 anos: %s', case when sqlerrm='nascimento' then '✅' else '❌' end, sqlerrm); falhas := falhas + (sqlerrm<>'nascimento')::int; end;
  begin j := public.pedido_voluntaria_criar(base || jsonb_build_object('salas', jsonb_build_array(gen_random_uuid())));
    r := r || E'\n❌ aceitou sala inexistente'; falhas := falhas + 1;
  exception when others then r := r || format(E'\n%s recusa sala inexistente: %s', case when sqlerrm='salas' then '✅' else '❌' end, sqlerrm); falhas := falhas + (sqlerrm<>'salas')::int; end;
  begin j := public.pedido_voluntaria_criar(base || jsonb_build_object('salas', jsonb_build_array(s3, s3)));
    r := r || E'\n❌ aceitou sala repetida'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recusa sala repetida'; end;
  begin j := public.pedido_voluntaria_criar(base || jsonb_build_object('termo_versao', 'v0'));
    r := r || E'\n❌ aceitou termo desatualizado'; falhas := falhas + 1;
  exception when others then r := r || format(E'\n%s recusa termo desatualizado: %s', case when sqlerrm='termo_desatualizado' then '✅' else '❌' end, sqlerrm); falhas := falhas + (sqlerrm<>'termo_desatualizado')::int; end;
  begin j := public.pedido_voluntaria_criar(base || jsonb_build_object('email', 'sem-arroba'));
    r := r || E'\n❌ aceitou e-mail inválido'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ recusa e-mail inválido'; end;

  j := public.pedido_voluntaria_criar(base);
  ped1 := (j->>'pedido_id')::uuid;
  j := public.pedido_voluntaria_criar(base || jsonb_build_object('nome', 'Qwzteste Candidata Alfa Corrigida'));
  select count(*) into n from public.pedidos_voluntaria where telefone = tel_a;
  r := r || format(E'\n%s mesmo telefone: o pedido novo substitui o antigo: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  ped1 := (j->>'pedido_id')::uuid;

  begin txt := public.pedido_voluntaria_gravar_foto(ped1, 'pessoas/criancas/qualquer');
    r := r || E'\n❌ foto em pasta errada foi aceita'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ foto só na pasta do pedido'; end;
  txt := public.pedido_voluntaria_gravar_foto(ped1, 'pessoas/adultos/pedido_' || ped1 || '_1');
  r := r || format(E'\n%s foto ligada ao pedido: %s', case when txt='ok' then '✅' else '❌' end, txt); falhas := falhas + (txt<>'ok')::int;

  j := public.pedido_voluntaria_criar(base || jsonb_build_object('nome', 'Qwzteste Responsavel Original', 'telefone', tel_b,
                                                                'nascimento', d15));
  ped2 := (j->>'pedido_id')::uuid;
  j := public.pedido_voluntaria_criar(base || jsonb_build_object('nome', 'Qwzteste Candidata Gama', 'telefone', tel_c));
  ped3 := (j->>'pedido_id')::uuid;
  txt := public.pedido_voluntaria_gravar_foto(ped3, 'pessoas/adultos/pedido_' || ped3 || '_9');

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.notificacoes where destinatario_id = u_lider and tipo = 'voluntaria_nova';
  r := r || format(E'\n%s líder recebeu aviso no sino: %s', case when n>=3 then '✅' else '❌' end, n); falhas := falhas + (n<3)::int;
  select count(*) into n from public.notificacoes where destinatario_id in (u_vol, u_pai) and tipo = 'voluntaria_nova';
  r := r || format(E'\n%s voluntária e responsável não recebem esse aviso: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;

  -- Voluntária (recepção) e responsável: nada
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', u_vol, 'role', 'authenticated')::text, true);
  begin j := public.pedidos_voluntaria_lista();
    r := r || E'\n❌ voluntária viu os pedidos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não vê os pedidos'; end;
  begin j := public.aprovar_pedido_voluntaria(ped1);
    r := r || E'\n❌ voluntária aprovou pedido'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não aprova'; end;
  begin txt := public.recusar_pedido_voluntaria(ped1);
    r := r || E'\n❌ voluntária recusou pedido'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ voluntária não recusa'; end;
  select count(*) into n from public.fotos_pedidos_voluntaria(array[ped1, ped3]);
  r := r || format(E'\n%s voluntária não vê foto do pedido: %s (esperado 0)', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  n := public.contar_pedidos_voluntaria();
  r := r || format(E'\n%s contagem para a voluntária é 0: %s', case when n=0 then '✅' else '❌' end, n); falhas := falhas + (n<>0)::int;
  perform set_config('request.jwt.claims', json_build_object('sub', u_pai, 'role', 'authenticated')::text, true);
  perform public.aceitar_termo_lgpd((select versao from public.termos_lgpd_versoes where vigente limit 1));
  begin j := public.pedidos_voluntaria_lista();
    r := r || E'\n❌ responsável viu os pedidos'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ responsável não vê os pedidos'; end;

  -- Líder
  perform set_config('request.jwt.claims', json_build_object('sub', u_lider, 'role', 'authenticated')::text, true);
  j := public.pedidos_voluntaria_lista();
  select count(*) into n from jsonb_array_elements(j) x where x->>'telefone' in (tel_a, tel_b, tel_c);
  r := r || format(E'\n%s líder vê os 3 pedidos: %s', case when n=3 then '✅' else '❌' end, n); falhas := falhas + (n<>3)::int;
  select count(*) into n from jsonb_array_elements(j) x
   where (x->>'id')::uuid = ped2 and (x->'mesmo_telefone'->0->>'tem_login')::boolean and x->>'idade' = '15';
  r := r || format(E'\n%s pedido mostra telefone já usado (com login) e a idade: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  select count(*) into n from public.fotos_pedidos_voluntaria(array[ped1, ped3]);
  r := r || format(E'\n%s líder vê a foto dos pedidos: %s', case when n=2 then '✅' else '❌' end, n); falhas := falhas + (n<>2)::int;

  -- aprovar pedido novo (sem cadastro anterior)
  j := public.aprovar_pedido_voluntaria(ped1);
  v_pessoa := (j->>'pessoa_id')::uuid;
  select count(*) into n from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id
   where v.pessoa_id = v_pessoa and v.status = 'ativa' and v.aprovada_por = u_lider and v.termo_versao is not null
     and p.foto_public_id like 'pessoas/adultos/pedido_%' and p.nome = 'Qwzteste Candidata Alfa Corrigida'
     and v.salas_preferidas[1] = s3;
  r := r || format(E'\n%s aprovar cria pessoa + voluntária ativa (foto, termo, preferências): %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;
  r := r || format(E'\n%s sem login ainda (o app cria pela gerenciar-login): %s', case when j->>'tem_login'='false' then '✅' else '❌' end, j->>'tem_login'); falhas := falhas + (j->>'tem_login'<>'false')::int;
  begin j := public.aprovar_pedido_voluntaria(ped1);
    r := r || E'\n❌ aprovou o mesmo pedido duas vezes'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ pedido aprovado some (não aprova duas vezes)'; end;

  -- telefone de quem já tem login: precisa usar o mesmo cadastro
  begin j := public.aprovar_pedido_voluntaria(ped2);
    r := r || E'\n❌ criou pessoa nova com telefone de login existente'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ não duplica pessoa com telefone de login existente'; end;
  begin j := public.aprovar_pedido_voluntaria(ped2, p_vol);
    r := r || E'\n❌ ligou o pedido a pessoa com outro telefone'; falhas := falhas + 1;
  exception when others then r := r || E'\n✅ só liga a quem tem o mesmo telefone'; end;
  j := public.aprovar_pedido_voluntaria(ped2, p_pai);
  select count(*) into n from public.papeis_usuario where perfil_id = u_pai and departamento_id = v_kids and papel in ('voluntaria', 'recepcao');
  r := r || format(E'\n%s cadastro existente com login ganha voluntária + recepção: %s', case when n=2 and j->>'tem_login'='true' then '✅' else '❌' end, n); falhas := falhas + (not (n=2 and j->>'tem_login'='true'))::int;
  select count(*) into n from public.pessoas where id = p_pai and nome = 'Qwzteste Responsavel Original';
  r := r || format(E'\n%s cadastro existente não é sobrescrito: %s', case when n=1 then '✅' else '❌' end, n); falhas := falhas + (n<>1)::int;

  -- recusar
  txt := public.recusar_pedido_voluntaria(ped3);
  perform set_config('role', 'postgres', true);   -- a tabela é fechada para o app; conferência como dono
  select count(*) into n from public.pedidos_voluntaria where id = ped3;
  r := r || format(E'\n%s recusar apaga o pedido e devolve a foto para apagar: %s', case when n=0 and txt like 'pessoas/adultos/pedido_%' then '✅' else '❌' end, n); falhas := falhas + (not (n=0 and txt like 'pessoas/adultos/pedido_%'))::int;

  -- limite diário
  perform set_config('role', 'postgres', true);
  insert into private.pedidos_voluntaria_link (criado_em) select now() from generate_series(1, 30);
  perform set_config('role', 'service_role', true);
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  begin j := public.pedido_voluntaria_criar(base || jsonb_build_object('telefone', tel_c));
    r := r || E'\n❌ passou do limite de 30 por dia'; falhas := falhas + 1;
  exception when others then r := r || format(E'\n%s limite de 30 pedidos a cada 24 h: %s', case when sqlerrm='limite_diario' then '✅' else '❌' end, sqlerrm); falhas := falhas + (sqlerrm<>'limite_diario')::int; end;

  perform set_config('role', 'postgres', true);
  select count(*) into n from public.auditoria where tabela = 'pedidos_voluntaria';
  r := r || format(E'\n%s auditoria registrou os pedidos: %s (esperado > 0)', case when n>0 then '✅' else '❌' end, n); falhas := falhas + (n=0)::int;

  total := array_length(regexp_split_to_array(btrim(r, E'\n'), E'\n'), 1);
  raise exception E'RESULTADO DOS TESTES — falhas: % de %\n%', falhas, total, r;
end
$teste$;
