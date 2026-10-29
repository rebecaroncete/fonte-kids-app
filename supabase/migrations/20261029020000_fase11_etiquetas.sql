-- =====================================================================
-- Fase 11 · Etiquetas na Brother QL-800 (29/10/2026)
--   1. A fila (fila_impressao) passa a ser gravada SÓ por funções:
--        pedir_etiquetas(checkins, tipo, reimpressao)  recepção (celulares)
--        situacao_pedidos(pedidos)                      "Impressa"/"Na fila" no celular
--        situacao_etiquetas()                           ligadas? estação no ar? link?
--        ligar_etiquetas(sim/não)                       só a liderança
--        gerar_link_estacao() / desligar_link_estacao() só a liderança
--      e, SEM LOGIN, só com o código secreto do link da estação:
--        estacao_buscar(codigo)                         a estação pega os pedidos
--        estacao_concluir(codigo, pedidos, ok, erro)    devolve o resultado
--        estacao_lista(codigo)                          etiquetas de hoje
--        estacao_reimprimir(codigo, pedido)             "Imprimir de novo"
--   2. Dois tipos de etiqueta:
--        crianca      uma por check-in: nome curto ("Maria S."), sala,
--                     código, data/culto, só o AVISO de alergia (sem dizer qual)
--                     e, para urgência, primeiro nome e telefone do
--                     responsável principal (decisão da Rebeca, 29/10/2026)
--        responsavel  uma por família e culto: nome curto, sala e código de
--                     cada criança com check-in no culto, data/culto
--      A do responsável não leva telefone. O conteúdo é montado na hora de
--      imprimir (a fila guarda só ids), então nada pessoal fica na fila.
--   3. "Estação de etiquetas": link sem senha (como o telão) aberto no
--      computador da recepção. O banco guarda só o hash do código; a
--      liderança troca o link quando quiser (o antigo para na hora). O link
--      só alcança as etiquetas de hoje. A estação dá sinal de "no ar" a
--      cada busca (estacoes_impressao).
--      Pedido pendente há mais de 10 min (estação fechada) vira "erro"
--      ("Não impressa") e não sai sozinho depois; dá para imprimir na lista.
--   4. Interruptor "etiquetas_ligadas" em configuracoes (começa desligado):
--      desligado, pedir_etiquetas não grava nada e o check-in fica como hoje.
--   5. Pedidos com mais de 7 dias são apagados pela própria estação.
-- Escrita só por funções security definer; RLS em tudo; auditoria.
-- Toda alteração com WHERE (a API usa pg_safeupdate).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Estrutura
-- ---------------------------------------------------------------------
alter table public.fila_impressao
  add column if not exists culto_id    uuid references public.cultos(id) on delete cascade,
  add column if not exists familia_id  uuid references public.familias(id) on delete cascade,
  add column if not exists reimpressao boolean not null default false,
  add column if not exists pegou_em    timestamptz;

-- pedidos antigos do modelo inicial (tipo 'etiqueta') não valem mais
delete from public.fila_impressao where tipo not in ('crianca', 'responsavel');
alter table public.fila_impressao alter column tipo set default 'crianca';
alter table public.fila_impressao drop constraint if exists fila_impressao_tipo_check;
alter table public.fila_impressao add constraint fila_impressao_tipo_check
  check (tipo in ('crianca', 'responsavel'));

create index if not exists fila_impressao_culto_idx on public.fila_impressao (culto_id);
create index if not exists fila_impressao_familia_idx on public.fila_impressao (familia_id);

-- Gravação só pelas funções (antes a recepção podia inserir/alterar direto)
drop policy if exists fila_criar on public.fila_impressao;
drop policy if exists fila_editar on public.fila_impressao;
drop policy if exists fila_apagar on public.fila_impressao;
revoke insert, update, delete, truncate on public.fila_impressao from anon, authenticated;
-- leitura (fila_ler, recepção do departamento) continua: é o que o Realtime usa

drop trigger if exists fila_impressao_auditoria on public.fila_impressao;
create trigger fila_impressao_auditoria after insert or update or delete
  on public.fila_impressao for each row execute function private.auditar();

-- Estação no ar: último sinal por departamento (sem auditoria: é só um relógio)
create table if not exists public.estacoes_impressao (
  departamento_id uuid primary key references public.departamentos(id) on delete cascade,
  visto_em        timestamptz not null default now(),
  perfil_id       uuid references public.perfis(id) on delete set null
);
alter table public.estacoes_impressao enable row level security;
revoke all on public.estacoes_impressao from anon, authenticated;

-- Acesso da estação (só o hash do código; fora da API)
create table if not exists private.estacao_acesso (
  id              uuid primary key default gen_random_uuid(),
  departamento_id uuid not null unique references public.departamentos(id),
  codigo_hash     text not null,
  criado_em       timestamptz not null default now(),
  criado_por      uuid
);
revoke all on private.estacao_acesso from public, anon, authenticated;
drop trigger if exists estacao_acesso_auditoria on private.estacao_acesso;
create trigger estacao_acesso_auditoria after insert or update or delete
  on private.estacao_acesso for each row execute function private.auditar();

-- Interruptor (começa desligado)
insert into public.configuracoes (departamento_id, chave, valor, descricao)
select d.id, 'etiquetas_ligadas', 'nao',
       'Etiquetas na impressora da recepção (sim/nao). Desligado: o check-in só mostra o código.'
  from public.departamentos d
 where d.slug = 'kids'
on conflict (departamento_id, chave) do nothing;

-- ---------------------------------------------------------------------
-- 2. Ajudantes (privados)
-- ---------------------------------------------------------------------
create or replace function private.etiquetas_ligadas(p_dept uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select c.valor = 'sim' from public.configuracoes c
                    where c.departamento_id = p_dept and c.chave = 'etiquetas_ligadas'), false) $$;

-- Estação no ar = deu sinal no último minuto e meio
create or replace function private.estacao_ativa(p_dept uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.estacoes_impressao e
                  where e.departamento_id = p_dept and e.visto_em > now() - interval '90 seconds') $$;

-- Departamento do código da estação (null se inválido)
create or replace function private.estacao_dept(p_codigo text) returns uuid
language sql stable security definer set search_path = '' as $$
  select a.departamento_id from private.estacao_acesso a
   where p_codigo ~ '^[0-9a-f]{32}$'
     and a.codigo_hash = encode(sha256(convert_to(p_codigo, 'UTF8')), 'hex') $$;

-- "5511912345678" -> "(11) 91234-5678"
create or replace function private.telefone_etiqueta(p_tel text) returns text
language sql immutable set search_path = '' as $$
  select case
    when length(d) in (12, 13) and left(d, 2) = '55' then
      '(' || substr(d, 3, 2) || ') ' || substr(d, 5, length(d) - 8) || '-' || right(d, 4)
    when length(d) in (10, 11) then
      '(' || left(d, 2) || ') ' || substr(d, 3, length(d) - 6) || '-' || right(d, 4)
    else nullif(d, '') end
    from (select regexp_replace(coalesce(p_tel, ''), '\D', '', 'g') d) x $$;

-- "Maria Clara da Silva" -> "Maria S."
create or replace function private.nome_etiqueta(p_nome text) returns text
language sql immutable set search_path = '' as $$
  select case when cardinality(a) > 1 then a[1] || ' ' || upper(left(a[cardinality(a)], 1)) || '.'
              else a[1] end
    from (select regexp_split_to_array(btrim(coalesce(p_nome, '')), '\s+') a) x $$;

-- Dados de uma criança com check-in, só o que vai no papel
create or replace function private.etiqueta_crianca_json(p_checkin uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'nome', private.nome_etiqueta(p.nome),
    'sala', private.nome_sala_culto(private.salas_do_culto_json(cu.id, cu.culto_recorrente_id, false), k.sala_id),
    'codigo', k.codigo_seguranca,
    'alergia', nullif(btrim(coalesce(c.alergias_observacoes, '')), '') is not null,
    'responsavel', r.primeiro, 'telefone', private.telefone_etiqueta(r.telefone))
    from public.checkins k
    join public.cultos cu on cu.id = k.culto_id
    join public.criancas c on c.id = k.crianca_id
    join public.pessoas p on p.id = c.pessoa_id
    left join lateral (
      select split_part(btrim(pr.nome), ' ', 1) as primeiro, pr.telefone
        from public.responsaveis rr join public.pessoas pr on pr.id = rr.pessoa_id
       where rr.familia_id = c.familia_id
       order by rr.principal desc, (pr.telefone is null), pr.nome limit 1) r on true
   where k.id = p_checkin $$;

-- Conteúdo de um pedido (montado na hora; null se o check-in sumiu)
create or replace function private.etiqueta_do_pedido(p public.fila_impressao) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_cu public.cultos%rowtype; v_lista jsonb;
begin
  select * into v_cu from public.cultos where id = p.culto_id;
  if not found then return null; end if;
  if p.tipo = 'crianca' then
    if p.checkin_id is null then return null; end if;
    v_lista := jsonb_build_array(private.etiqueta_crianca_json(p.checkin_id));
  else
    -- na etiqueta do responsável não vai telefone
    select jsonb_agg(private.etiqueta_crianca_json(k.id) - 'responsavel' - 'telefone' order by pe.nome) into v_lista
      from public.checkins k
      join public.criancas c on c.id = k.crianca_id
      join public.pessoas pe on pe.id = c.pessoa_id
     where k.culto_id = p.culto_id and c.familia_id = p.familia_id;
  end if;
  if v_lista is null or jsonb_array_length(v_lista) = 0 or v_lista->0 = 'null'::jsonb then
    return null;
  end if;
  return jsonb_build_object(
    'tipo', p.tipo,
    'data', to_char(v_cu.data, 'DD/MM/YYYY'),
    'culto', coalesce(v_cu.nome, 'Culto'),
    'horario', to_char(v_cu.horario, 'HH24:MI'),
    'criancas', v_lista);
end $$;

-- Linha da lista/da busca da estação
create or replace function private.pedido_json(p public.fila_impressao) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', p.id, 'tipo', p.tipo, 'status', p.status, 'erro', p.erro,
    'reimpressao', p.reimpressao, 'criado_em', p.criado_em, 'impresso_em', p.impresso_em,
    'etiqueta', private.etiqueta_do_pedido(p)) $$;

-- ---------------------------------------------------------------------
-- 3. Situação e interruptor
-- ---------------------------------------------------------------------
create or replace function public.situacao_etiquetas() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids();
begin
  if not private.e_recepcao(v_dept) then raise exception 'Sem permissão'; end if;
  return jsonb_build_object(
    'ligadas', private.etiquetas_ligadas(v_dept),
    'estacao_ativa', private.estacao_ativa(v_dept),
    'estacao_visto_em', (select e.visto_em from public.estacoes_impressao e where e.departamento_id = v_dept),
    'pode_ligar', private.e_lider(v_dept),
    'link', case when private.e_lider(v_dept) then coalesce((
              select jsonb_build_object('ativo', true, 'criado_em', a.criado_em,
                       'criado_por', (select private.primeiro_ultimo(p.nome) from public.perfis pf
                                        join public.pessoas p on p.id = pf.pessoa_id where pf.id = a.criado_por))
                from private.estacao_acesso a where a.departamento_id = v_dept),
              jsonb_build_object('ativo', false)) end);
end $$;

-- Link da estação: gera (ou troca) o código; ele só aparece esta vez
create or replace function public.gerar_link_estacao() returns text
language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids(); v_cod text;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  v_cod := replace(gen_random_uuid()::text, '-', '');   -- 32 caracteres, 122 bits aleatórios
  insert into private.estacao_acesso (departamento_id, codigo_hash, criado_por)
  values (v_dept, encode(sha256(convert_to(v_cod, 'UTF8')), 'hex'), auth.uid())
  on conflict (departamento_id) do update
    set codigo_hash = excluded.codigo_hash, criado_em = now(), criado_por = excluded.criado_por;
  return v_cod;
end $$;

create or replace function public.desligar_link_estacao() returns text
language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids();
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  delete from private.estacao_acesso where departamento_id = v_dept;
  delete from public.estacoes_impressao where departamento_id = v_dept;
  return 'ok';
end $$;

create or replace function public.ligar_etiquetas(p_ligar boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids(); v_id uuid;
begin
  if not private.e_lider(v_dept) then raise exception 'Só a liderança liga ou desliga as etiquetas'; end if;
  insert into public.configuracoes (departamento_id, chave, valor, descricao)
  values (v_dept, 'etiquetas_ligadas', 'nao', 'Etiquetas na impressora da recepção (sim/nao)')
  on conflict (departamento_id, chave) do nothing;
  update public.configuracoes
     set valor = case when coalesce(p_ligar, false) then 'sim' else 'nao' end
   where departamento_id = v_dept and chave = 'etiquetas_ligadas'
  returning id into v_id;
  insert into public.auditoria (perfil_id, tabela, registro_id, acao, campos_alterados)
  values (auth.uid(), 'configuracoes', v_id, 'UPDATE',
          array['etiquetas_ligadas=' || case when coalesce(p_ligar, false) then 'sim' else 'nao' end]);
  return public.situacao_etiquetas();
end $$;

-- ---------------------------------------------------------------------
-- 4. Pedir etiquetas (celulares da recepção)
-- p_tipo: 'ambas' | 'crianca' | 'responsavel'
-- Sem reimpressão: cada check-in ganha UMA etiqueta de criança (repetir a
-- chamada não duplica) e cada família uma do responsável quando entrou
-- alguém novo. Com reimpressão: sempre cria pedidos novos.
-- Etiquetas desligadas: não grava nada (devolve ligadas = false), exceto
-- na reimpressão, que avisa com erro.
-- ---------------------------------------------------------------------
create or replace function public.pedir_etiquetas(p_checkins uuid[], p_tipo text default 'ambas',
  p_reimpressao boolean default false) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids();
  v_k record;
  v_id uuid;
  v_pedidos jsonb := '[]'::jsonb;
  v_familias jsonb := '{}'::jsonb;   -- familia_id -> culto_id
  v_f record;
begin
  if not private.e_recepcao(v_dept) then raise exception 'Sem permissão'; end if;
  if coalesce(p_tipo, '') not in ('ambas', 'crianca', 'responsavel') then
    raise exception 'Tipo de etiqueta inválido';
  end if;
  if coalesce(cardinality(p_checkins), 0) = 0 then raise exception 'Escolha ao menos uma criança'; end if;
  if cardinality(p_checkins) > 30 then raise exception 'No máximo 30 crianças de cada vez'; end if;
  if not private.etiquetas_ligadas(v_dept) then
    if p_reimpressao then raise exception 'As etiquetas estão desligadas (Mais → Etiquetas)'; end if;
    return jsonb_build_object('ligadas', false, 'estacao_ativa', private.estacao_ativa(v_dept), 'pedidos', '[]'::jsonb);
  end if;

  for v_k in
    select k.id, k.culto_id, c.familia_id
      from public.checkins k
      join public.cultos cu on cu.id = k.culto_id
      join public.criancas c on c.id = k.crianca_id
     where k.id = any (p_checkins)
       and cu.data = private.hoje()
       and private.dept_sala(k.sala_id) = v_dept
  loop
    if p_tipo in ('ambas', 'crianca') then
      if p_reimpressao or not exists (select 1 from public.fila_impressao f
                                       where f.checkin_id = v_k.id and f.tipo = 'crianca' and not f.reimpressao) then
        insert into public.fila_impressao (departamento_id, checkin_id, culto_id, familia_id, tipo, reimpressao)
        values (v_dept, v_k.id, v_k.culto_id, v_k.familia_id, 'crianca', coalesce(p_reimpressao, false))
        returning id into v_id;
        v_pedidos := v_pedidos || jsonb_build_object('id', v_id, 'tipo', 'crianca', 'checkin_id', v_k.id);
        v_familias := v_familias || jsonb_build_object(v_k.familia_id::text, v_k.culto_id);
      end if;
    end if;
    if p_tipo = 'responsavel' then
      v_familias := v_familias || jsonb_build_object(v_k.familia_id::text, v_k.culto_id);
    end if;
  end loop;

  if p_tipo in ('ambas', 'responsavel') then
    for v_f in select key::uuid as familia_id, (value #>> '{}')::uuid as culto_id from jsonb_each(v_familias) loop
      insert into public.fila_impressao (departamento_id, checkin_id, culto_id, familia_id, tipo, reimpressao)
      values (v_dept, null, v_f.culto_id, v_f.familia_id, 'responsavel', coalesce(p_reimpressao, false))
      returning id into v_id;
      v_pedidos := v_pedidos || jsonb_build_object('id', v_id, 'tipo', 'responsavel', 'familia_id', v_f.familia_id);
    end loop;
  end if;

  if p_reimpressao and jsonb_array_length(v_pedidos) = 0 then
    raise exception 'Check-in de hoje não encontrado';
  end if;
  return jsonb_build_object('ligadas', true, 'estacao_ativa', private.estacao_ativa(v_dept), 'pedidos', v_pedidos);
end $$;

-- Situação de pedidos (tela "Check-in feito" nos celulares)
create or replace function public.situacao_pedidos(p_pedidos uuid[]) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_dept uuid := private.dept_kids();
begin
  if not private.e_recepcao(v_dept) then raise exception 'Sem permissão'; end if;
  return jsonb_build_object(
    'estacao_ativa', private.estacao_ativa(v_dept),
    'pedidos', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'tipo', f.tipo, 'status', f.status,
                                                              'checkin_id', f.checkin_id, 'erro', f.erro))
                           from public.fila_impressao f
                          where f.id = any (coalesce(p_pedidos, '{}')) and f.departamento_id = v_dept), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- 5. Estação de etiquetas (link sem login, só com o código secreto)
-- ---------------------------------------------------------------------
-- Dá o sinal de "no ar", vence o que passou do tempo e pega os pendentes.
-- Devolve só os pedidos que esta chamada pegou (cada um sai uma vez só,
-- mesmo com duas estações abertas).
create or replace function public.estacao_buscar(p_codigo text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.estacao_dept(p_codigo); v_saida jsonb := '[]'::jsonb; v_p public.fila_impressao%rowtype;
begin
  if v_dept is null then raise exception 'Link da estação inválido'; end if;

  insert into public.estacoes_impressao (departamento_id, visto_em, perfil_id)
  values (v_dept, now(), auth.uid())
  on conflict (departamento_id) do update set visto_em = excluded.visto_em, perfil_id = excluded.perfil_id;

  -- limpeza: pedidos com mais de 7 dias
  delete from public.fila_impressao where departamento_id = v_dept and criado_em < now() - interval '7 days';

  -- pendente há mais de 10 min (estação fechada) ou de outro dia: não sai sozinho
  update public.fila_impressao f
     set status = 'erro', erro = 'Não impressa: a estação estava fechada'
   where f.departamento_id = v_dept and f.status = 'pendente'
     and (f.criado_em < now() - interval '10 minutes'
          or not exists (select 1 from public.cultos c where c.id = f.culto_id and c.data = private.hoje()));
  -- "imprimindo" há mais de 2 min: a estação caiu no meio
  update public.fila_impressao f
     set status = 'erro', erro = 'A estação não confirmou a impressão'
   where f.departamento_id = v_dept and f.status = 'imprimindo' and f.pegou_em < now() - interval '2 minutes';

  if not private.etiquetas_ligadas(v_dept) then
    return jsonb_build_object('ligadas', false, 'pedidos', '[]'::jsonb);
  end if;

  for v_p in
    update public.fila_impressao f
       set status = 'imprimindo', pegou_em = now(), tentativas = f.tentativas + 1
     where f.id in (select x.id from public.fila_impressao x
                     where x.departamento_id = v_dept and x.status = 'pendente'
                     order by x.criado_em
                     limit 20
                     for update skip locked)
    returning f.*
  loop
    if private.etiqueta_do_pedido(v_p) is null then
      update public.fila_impressao set status = 'erro', erro = 'O check-in foi desfeito' where id = v_p.id;
    else
      v_saida := v_saida || private.pedido_json(v_p);
    end if;
  end loop;

  return jsonb_build_object('ligadas', true, 'pedidos', v_saida);
end $$;

create or replace function public.estacao_concluir(p_codigo text, p_pedidos uuid[], p_ok boolean, p_erro text default null)
returns integer
language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.estacao_dept(p_codigo); v_n integer;
begin
  if v_dept is null then raise exception 'Link da estação inválido'; end if;
  update public.fila_impressao
     set status = case when p_ok then 'impresso'::public.status_impressao else 'erro'::public.status_impressao end,
         impresso_em = case when p_ok then now() else null end,
         erro = case when p_ok then null else left(coalesce(nullif(btrim(p_erro), ''), 'Falha ao imprimir'), 200) end
   where id = any (coalesce(p_pedidos, '{}')) and departamento_id = v_dept
     and status in ('imprimindo', 'erro');
  get diagnostics v_n = row_count;
  return v_n;
end $$;

-- Pedidos de hoje (lista da estação), os mais novos primeiro
create or replace function public.estacao_lista(p_codigo text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v_dept uuid := private.estacao_dept(p_codigo);
begin
  if v_dept is null then raise exception 'Link da estação inválido'; end if;
  return jsonb_build_object(
    'ligadas', private.etiquetas_ligadas(v_dept),
    'pedidos', coalesce((
      select jsonb_agg(private.pedido_json(f) order by f.criado_em desc)
        from (select f.* from public.fila_impressao f
                join public.cultos c on c.id = f.culto_id
               where f.departamento_id = v_dept and c.data = private.hoje()
               order by f.criado_em desc limit 200) f
    ), '[]'::jsonb));
end $$;

-- "Imprimir de novo" na lista da estação (cria um pedido novo)
create or replace function public.estacao_reimprimir(p_codigo text, p_pedido uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare v_dept uuid := private.estacao_dept(p_codigo); v_p public.fila_impressao%rowtype; v_id uuid;
begin
  if v_dept is null then raise exception 'Link da estação inválido'; end if;
  if not private.etiquetas_ligadas(v_dept) then raise exception 'As etiquetas estão desligadas'; end if;
  select * into v_p from public.fila_impressao where id = p_pedido and departamento_id = v_dept;
  if not found then raise exception 'Etiqueta não encontrada'; end if;
  if not exists (select 1 from public.cultos c where c.id = v_p.culto_id and c.data = private.hoje()) then
    raise exception 'Só dá para imprimir etiquetas de hoje';
  end if;
  if private.etiqueta_do_pedido(v_p) is null then
    raise exception 'O check-in desta etiqueta foi desfeito';
  end if;
  insert into public.fila_impressao (departamento_id, checkin_id, culto_id, familia_id, tipo, reimpressao, criado_por)
  values (v_dept, v_p.checkin_id, v_p.culto_id, v_p.familia_id, v_p.tipo, true, null)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 6. Permissões
-- ---------------------------------------------------------------------
do $$
declare f text;
begin
  foreach f in array array[
    'private.etiquetas_ligadas(uuid)', 'private.estacao_ativa(uuid)', 'private.estacao_dept(text)',
    'private.telefone_etiqueta(text)', 'private.nome_etiqueta(text)',
    'private.etiqueta_crianca_json(uuid)', 'private.etiqueta_do_pedido(public.fila_impressao)',
    'private.pedido_json(public.fila_impressao)']
  loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
  end loop;
  -- equipe (com login)
  foreach f in array array[
    'public.situacao_etiquetas()', 'public.ligar_etiquetas(boolean)',
    'public.gerar_link_estacao()', 'public.desligar_link_estacao()',
    'public.pedir_etiquetas(uuid[], text, boolean)', 'public.situacao_pedidos(uuid[])']
  loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
  -- estação (sem login; o código secreto é conferido dentro)
  foreach f in array array[
    'public.estacao_buscar(text)', 'public.estacao_concluir(text, uuid[], boolean, text)',
    'public.estacao_lista(text)', 'public.estacao_reimprimir(text, uuid)']
  loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to anon, authenticated', f);
  end loop;
end $$;
