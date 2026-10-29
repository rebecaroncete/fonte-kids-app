-- =====================================================================
-- Migração 0007: SEGURANÇA
--   1. Funções auxiliares (schema private, fora da API)
--   2. Gatilhos: perfil automático, código de check-in, travas, auditoria
--   3. RLS em TODAS as tabelas
--   4. Permissões (anon não lê nada) + funções RPC
--   5. Realtime
-- Resumo das regras:
--   pai/mãe .......... só a própria família
--   voluntária ....... crianças/check-ins das salas em que é (ou foi) escalada;
--                      contatos dos pais só no dia, da sala dela
--   recepção ......... cadastro e check-in do departamento
--   líder ............ tudo do departamento
--   pastor / admin ... tudo
-- =====================================================================

-- ---------------------------------------------------------------
-- 1. Funções auxiliares (SECURITY DEFINER: leem sem cair no RLS,
--    evitando recursão; search_path vazio contra sequestro)
-- ---------------------------------------------------------------
create function private.hoje() returns date
language sql stable set search_path = '' as $$
  select (now() at time zone 'America/Sao_Paulo')::date
$$;

create function private.tem_papel_global(p_papeis public.papel_tipo[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.papeis_usuario pu
    join public.perfis p on p.id = pu.perfil_id
    where pu.perfil_id = (select auth.uid()) and p.ativo and pu.papel = any (p_papeis)
  )
$$;

create function private.e_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.tem_papel_global(array['admin']::public.papel_tipo[])
$$;

create function private.e_pastor_ou_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.tem_papel_global(array['admin','pastor']::public.papel_tipo[])
$$;

create function private.tem_papel_dept(p_papeis public.papel_tipo[], p_dept uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.papeis_usuario pu
    join public.perfis p on p.id = pu.perfil_id
    where pu.perfil_id = (select auth.uid()) and p.ativo
      and pu.departamento_id = p_dept and pu.papel = any (p_papeis)
  )
$$;

create function private.e_lider(p_dept uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_pastor_ou_admin()
      or private.tem_papel_dept(array['lider']::public.papel_tipo[], p_dept)
$$;

create function private.e_lider_algum() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_pastor_ou_admin() or exists (
    select 1 from public.papeis_usuario pu join public.perfis p on p.id = pu.perfil_id
    where pu.perfil_id = (select auth.uid()) and p.ativo and pu.papel = 'lider')
$$;

create function private.e_recepcao(p_dept uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_lider(p_dept)
      or private.tem_papel_dept(array['recepcao']::public.papel_tipo[], p_dept)
$$;

create function private.e_equipe(p_dept uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_recepcao(p_dept)
      or private.tem_papel_dept(array['voluntaria']::public.papel_tipo[], p_dept)
$$;

-- "De qual departamento é este registro?"
create function private.dept_familia(p uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select departamento_id from public.familias where id = p $$;
create function private.dept_sala(p uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select departamento_id from public.salas where id = p $$;
create function private.dept_escala(p uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select departamento_id from public.escalas where id = p $$;
create function private.dept_voluntaria(p uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select departamento_id from public.voluntarias where id = p $$;
create function private.dept_evento(p uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select departamento_id from public.eventos where id = p $$;
create function private.dept_enquete(p uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select departamento_id from public.enquetes where id = p $$;

-- Vínculos do usuário logado
create function private.minhas_familias() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select familia_id from public.responsaveis where perfil_id = (select auth.uid()) $$;

create function private.minhas_criancas() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select c.id from public.criancas c
  where c.familia_id in (select private.minhas_familias()) $$;

create function private.minhas_voluntarias() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select id from public.voluntarias
  where perfil_id = (select auth.uid()) and status = 'ativa' $$;

-- Salas em que a voluntária já foi escalada (escala publicada)
create function private.salas_que_atuo() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select distinct ei.sala_id
  from public.escala_itens ei join public.escalas e on e.id = ei.escala_id
  where e.status <> 'rascunho' and ei.sala_id is not null
    and ei.voluntaria_id in (select private.minhas_voluntarias()) $$;

-- Está escalada HOJE neste culto/sala (ou é Líder do Culto)?
create function private.atuo_hoje(p_culto uuid, p_sala uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.escala_itens ei
    join public.escalas e on e.id = ei.escala_id
    join public.cultos c  on c.id = ei.culto_id
    where e.status <> 'rascunho'
      and ei.culto_id = p_culto
      and (ei.sala_id = p_sala or ei.funcao = 'lider_culto')
      and c.data = private.hoje()
      and ei.voluntaria_id in (select private.minhas_voluntarias())
  ) $$;

create function private.criancas_das_minhas_salas() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select distinct k.crianca_id from public.checkins k
  where k.sala_id in (select private.salas_que_atuo()) $$;

-- Famílias das crianças que estão HOJE na sala da voluntária
create function private.familias_visiveis_hoje() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select distinct c.familia_id
  from public.checkins k
  join public.criancas c on c.id = k.crianca_id
  join public.cultos cu on cu.id = k.culto_id
  where cu.data = private.hoje() and private.atuo_hoje(k.culto_id, k.sala_id) $$;

create function private.pode_ver_escala(p_escala uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.escalas e where e.id = p_escala and (
      private.e_lider(e.departamento_id) or
      (e.status <> 'rascunho' and private.e_equipe(e.departamento_id)))) $$;

create function private.pode_ver_enquete(p_enquete uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.enquetes q where q.id = p_enquete and (
      private.e_lider(q.departamento_id) or (q.publicada and (
        q.publico = 'todos' or
        (q.publico = 'equipe'   and private.e_equipe(q.departamento_id)) or
        (q.publico = 'familias' and (exists (select private.minhas_familias()) or private.e_equipe(q.departamento_id)))
      )))) $$;

create function private.enquete_aberta(p_enquete uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.pode_ver_enquete(p_enquete) and exists (
    select 1 from public.enquetes q where q.id = p_enquete and q.publicada
      and (q.encerra_em is null or q.encerra_em > now())) $$;

create function private.evento_aberto(p_evento uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.eventos e
    where e.id = p_evento and e.publicado and e.inscricoes_abertas) $$;

-- Quem pode dar/tirar cada papel
create function private.pode_gerir_papel(p_papel public.papel_tipo, p_dept uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select case
    when p_papel = 'admin'       then private.e_admin()
    when p_papel = 'pastor'      then private.e_pastor_ou_admin()
    when p_papel = 'responsavel' then private.e_lider_algum()
    else private.e_lider(p_dept)
  end $$;

-- "A chamada vem do app (usuário comum)?" — RPCs e servidor rodam com outro papel
create function private.chamada_do_app() returns boolean
language sql stable set search_path = '' as $$
  select current_user in ('authenticated','anon') $$;

-- ---------------------------------------------------------------
-- 2. Gatilhos
-- ---------------------------------------------------------------

-- 2a. Cria o perfil quando um usuário é criado no Auth
create function private.criar_perfil_novo_usuario()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.perfis (id, nome, telefone)
  values (new.id,
          coalesce(new.raw_user_meta_data ->> 'nome', ''),
          nullif(new.raw_user_meta_data ->> 'telefone', ''))
  on conflict (id) do nothing;
  return new;
end $$;
create trigger ao_criar_usuario after insert on auth.users
  for each row execute function private.criar_perfil_novo_usuario();

-- 2b. Código de segurança do check-in: 4 caracteres sem ambiguidade
--     (sem 0/O, 1/I/L, 2/Z, 5/S, 8/B), único por culto
create function private.gerar_codigo_checkin()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  alfabeto constant text := 'ACDEFGHJKMNPQRTUVWXY34679';
  bytes bytea;
  codigo text;
  tentativas int := 0;
begin
  if new.codigo_seguranca is not null and new.codigo_seguranca <> '' then
    new.codigo_seguranca := upper(new.codigo_seguranca);
    return new;
  end if;
  loop
    bytes := uuid_send(gen_random_uuid());
    codigo := '';
    for i in 0..3 loop
      codigo := codigo || substr(alfabeto, 1 + (get_byte(bytes, i) % length(alfabeto)), 1);
    end loop;
    exit when not exists (select 1 from public.checkins
                          where culto_id = new.culto_id and codigo_seguranca = codigo);
    tentativas := tentativas + 1;
    if tentativas > 50 then
      raise exception 'Não foi possível gerar um código de segurança único';
    end if;
  end loop;
  new.codigo_seguranca := codigo;
  return new;
end $$;
create trigger checkins_codigo before insert on public.checkins
  for each row execute function private.gerar_codigo_checkin();

-- 2c. Travas de campos sensíveis (o RLS decide a LINHA; isto protege COLUNAS)
create function private.trava_perfis()
returns trigger language plpgsql set search_path = '' as $$
begin
  if private.chamada_do_app() and not private.e_pastor_ou_admin() and (
       new.id is distinct from old.id or
       new.ativo is distinct from old.ativo or
       new.troca_senha_obrigatoria is distinct from old.troca_senha_obrigatoria or
       new.igreja_id is distinct from old.igreja_id) then
    raise exception 'Sem permissão para alterar estes campos do perfil';
  end if;
  return new;
end $$;
create trigger perfis_trava before update on public.perfis
  for each row execute function private.trava_perfis();

create function private.trava_voluntarias()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not private.chamada_do_app() then return new; end if;
  if tg_op = 'INSERT' then
    if not private.e_lider(new.departamento_id) then
      new.status := 'pendente';          -- auto-cadastro sempre aguarda aprovação
      new.aprovada_por := null;
      new.aprovada_em := null;
    end if;
  elsif not private.e_lider(old.departamento_id) and (
       new.status is distinct from old.status or
       new.funcao is distinct from old.funcao or
       new.departamento_id is distinct from old.departamento_id or
       new.perfil_id is distinct from old.perfil_id or
       new.aprovada_por is distinct from old.aprovada_por or
       new.aprovada_em is distinct from old.aprovada_em) then
    raise exception 'Só líderes podem aprovar ou mudar a função da voluntária';
  end if;
  return new;
end $$;
create trigger voluntarias_trava before insert or update on public.voluntarias
  for each row execute function private.trava_voluntarias();

-- Ligar um responsável a um login só pelo servidor ou por líder
create function private.trava_responsaveis()
returns trigger language plpgsql set search_path = '' as $$
begin
  if private.chamada_do_app()
     and not private.e_lider(private.dept_familia(new.familia_id))
     and new.perfil_id is distinct from (case when tg_op = 'UPDATE' then old.perfil_id else null end) then
    raise exception 'Sem permissão para vincular login a este responsável';
  end if;
  return new;
end $$;
create trigger responsaveis_trava before insert or update on public.responsaveis
  for each row execute function private.trava_responsaveis();

-- Check-in: dados de entrada não mudam; quem faz a saída é registrado
create function private.trava_checkins()
returns trigger language plpgsql set search_path = '' as $$
begin
  if private.chamada_do_app() and not private.e_lider(private.dept_sala(old.sala_id)) and (
       new.culto_id is distinct from old.culto_id or
       new.crianca_id is distinct from old.crianca_id or
       new.codigo_seguranca is distinct from old.codigo_seguranca or
       new.entrada_em is distinct from old.entrada_em or
       new.entrada_por is distinct from old.entrada_por) then
    raise exception 'Dados de entrada do check-in não podem ser alterados';
  end if;
  if new.saida_em is not null and old.saida_em is null then
    new.saida_por := coalesce(new.saida_por, auth.uid());
  end if;
  return new;
end $$;
create trigger checkins_trava before update on public.checkins
  for each row execute function private.trava_checkins();

-- 2d. Auditoria (quem, o quê, quando — sem copiar dados pessoais)
create function private.auditar()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_campos text[];
begin
  if tg_op = 'DELETE' then v_id := old.id; else v_id := new.id; end if;
  if tg_op = 'UPDATE' then
    select array_agg(n.key order by n.key) into v_campos
    from jsonb_each(to_jsonb(new)) n
    where n.value is distinct from (to_jsonb(old) -> n.key)
      and n.key <> 'atualizado_em';
    if v_campos is null then return new; end if;
  end if;
  insert into public.auditoria (perfil_id, tabela, registro_id, acao, campos_alterados)
  values (auth.uid(), tg_table_name, v_id, tg_op, v_campos);
  return coalesce(new, old);
end $$;

do $$
declare t text;
begin
  foreach t in array array['familias','responsaveis','pessoas_autorizadas','criancas',
                           'termos_lgpd','voluntarias','papeis_usuario','checkins','perfis']
  loop
    execute format('create trigger %I after insert or update or delete on public.%I
                    for each row execute function private.auditar()', t || '_auditoria', t);
  end loop;
end $$;

-- ---------------------------------------------------------------
-- 3. RLS: ligado em todas as tabelas públicas
-- ---------------------------------------------------------------
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;

-- Estrutura (todos logados leem; só gestão altera)
create policy igrejas_ler    on public.igrejas for select to authenticated using (true);
create policy igrejas_gerir  on public.igrejas for insert to authenticated with check ((select private.e_admin()));
create policy igrejas_editar on public.igrejas for update to authenticated using ((select private.e_admin())) with check ((select private.e_admin()));
create policy igrejas_apagar on public.igrejas for delete to authenticated using ((select private.e_admin()));

create policy dept_ler    on public.departamentos for select to authenticated using (true);
create policy dept_criar  on public.departamentos for insert to authenticated with check ((select private.e_pastor_ou_admin()));
create policy dept_editar on public.departamentos for update to authenticated using ((select private.e_pastor_ou_admin())) with check ((select private.e_pastor_ou_admin()));
create policy dept_apagar on public.departamentos for delete to authenticated using ((select private.e_pastor_ou_admin()));

-- Perfis
create policy perfis_ler on public.perfis for select to authenticated
  using (id = (select auth.uid()) or (select private.e_lider_algum()));
create policy perfis_editar on public.perfis for update to authenticated
  using (id = (select auth.uid()) or (select private.e_pastor_ou_admin()))
  with check (id = (select auth.uid()) or (select private.e_pastor_ou_admin()));
create policy perfis_apagar on public.perfis for delete to authenticated
  using ((select private.e_admin()));

-- Papéis (promover/rebaixar)
create policy papeis_ler on public.papeis_usuario for select to authenticated
  using (perfil_id = (select auth.uid()) or (select private.e_lider_algum()));
create policy papeis_dar on public.papeis_usuario for insert to authenticated
  with check (private.pode_gerir_papel(papel, departamento_id));
create policy papeis_tirar on public.papeis_usuario for delete to authenticated
  using (private.pode_gerir_papel(papel, departamento_id));

-- Salas
create policy salas_ler    on public.salas for select to authenticated using (true);
create policy salas_criar  on public.salas for insert to authenticated with check (private.e_lider(departamento_id));
create policy salas_editar on public.salas for update to authenticated using (private.e_lider(departamento_id)) with check (private.e_lider(departamento_id));
create policy salas_apagar on public.salas for delete to authenticated using (private.e_lider(departamento_id));

-- Famílias
create policy familias_ler on public.familias for select to authenticated using (
  id in (select private.minhas_familias())
  or private.e_recepcao(departamento_id)
  or id in (select private.familias_visiveis_hoje()));
create policy familias_criar on public.familias for insert to authenticated
  with check (private.e_recepcao(departamento_id));
create policy familias_editar on public.familias for update to authenticated
  using (id in (select private.minhas_familias()) or private.e_recepcao(departamento_id))
  with check (id in (select private.minhas_familias()) or private.e_recepcao(departamento_id));
create policy familias_apagar on public.familias for delete to authenticated
  using (private.e_lider(departamento_id));

-- Responsáveis e pessoas autorizadas (mesma regra)
create policy responsaveis_ler on public.responsaveis for select to authenticated using (
  familia_id in (select private.minhas_familias())
  or private.e_recepcao(private.dept_familia(familia_id))
  or familia_id in (select private.familias_visiveis_hoje()));
create policy responsaveis_criar on public.responsaveis for insert to authenticated with check (
  familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));
create policy responsaveis_editar on public.responsaveis for update to authenticated
  using (familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)))
  with check (familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));
create policy responsaveis_apagar on public.responsaveis for delete to authenticated using (
  familia_id in (select private.minhas_familias()) or private.e_lider(private.dept_familia(familia_id)));

create policy autorizadas_ler on public.pessoas_autorizadas for select to authenticated using (
  familia_id in (select private.minhas_familias())
  or private.e_recepcao(private.dept_familia(familia_id))
  or familia_id in (select private.familias_visiveis_hoje()));
create policy autorizadas_criar on public.pessoas_autorizadas for insert to authenticated with check (
  familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));
create policy autorizadas_editar on public.pessoas_autorizadas for update to authenticated
  using (familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)))
  with check (familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));
create policy autorizadas_apagar on public.pessoas_autorizadas for delete to authenticated using (
  familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));

-- Crianças
create policy criancas_ler on public.criancas for select to authenticated using (
  familia_id in (select private.minhas_familias())
  or private.e_recepcao(private.dept_familia(familia_id))
  or id in (select private.criancas_das_minhas_salas()));
create policy criancas_criar on public.criancas for insert to authenticated with check (
  familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));
create policy criancas_editar on public.criancas for update to authenticated
  using (familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)))
  with check (familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));
create policy criancas_apagar on public.criancas for delete to authenticated using (
  private.e_lider(private.dept_familia(familia_id)));

-- Termo LGPD (não se edita; só se registra novo aceite)
create policy termos_ler on public.termos_lgpd for select to authenticated using (
  familia_id in (select private.minhas_familias()) or private.e_lider(private.dept_familia(familia_id)));
create policy termos_criar on public.termos_lgpd for insert to authenticated with check (
  familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(familia_id)));
create policy termos_apagar on public.termos_lgpd for delete to authenticated using ((select private.e_admin()));

-- Voluntárias (dados completos: a própria e líderes; lista da equipe via RPC)
create policy voluntarias_ler on public.voluntarias for select to authenticated using (
  perfil_id = (select auth.uid()) or private.e_lider(departamento_id));
create policy voluntarias_criar on public.voluntarias for insert to authenticated with check (
  perfil_id = (select auth.uid()) or private.e_lider(departamento_id));
create policy voluntarias_editar on public.voluntarias for update to authenticated
  using (perfil_id = (select auth.uid()) or private.e_lider(departamento_id))
  with check (perfil_id = (select auth.uid()) or private.e_lider(departamento_id));
create policy voluntarias_apagar on public.voluntarias for delete to authenticated using (
  private.e_lider(departamento_id));

create policy indisp_ler on public.indisponibilidades for select to authenticated using (
  voluntaria_id in (select id from public.voluntarias where perfil_id = (select auth.uid()))
  or private.e_lider(private.dept_voluntaria(voluntaria_id)));
create policy indisp_criar on public.indisponibilidades for insert to authenticated with check (
  voluntaria_id in (select id from public.voluntarias where perfil_id = (select auth.uid()))
  or private.e_lider(private.dept_voluntaria(voluntaria_id)));
create policy indisp_editar on public.indisponibilidades for update to authenticated
  using (voluntaria_id in (select id from public.voluntarias where perfil_id = (select auth.uid()))
         or private.e_lider(private.dept_voluntaria(voluntaria_id)))
  with check (voluntaria_id in (select id from public.voluntarias where perfil_id = (select auth.uid()))
         or private.e_lider(private.dept_voluntaria(voluntaria_id)));
create policy indisp_apagar on public.indisponibilidades for delete to authenticated using (
  voluntaria_id in (select id from public.voluntarias where perfil_id = (select auth.uid()))
  or private.e_lider(private.dept_voluntaria(voluntaria_id)));

-- Cultos
create policy recorrentes_ler    on public.cultos_recorrentes for select to authenticated using (true);
create policy recorrentes_criar  on public.cultos_recorrentes for insert to authenticated with check ((select private.e_pastor_ou_admin()));
create policy recorrentes_editar on public.cultos_recorrentes for update to authenticated using ((select private.e_pastor_ou_admin())) with check ((select private.e_pastor_ou_admin()));
create policy recorrentes_apagar on public.cultos_recorrentes for delete to authenticated using ((select private.e_pastor_ou_admin()));

create policy cultos_ler    on public.cultos for select to authenticated using (true);
create policy cultos_criar  on public.cultos for insert to authenticated with check ((select private.e_lider_algum()));
create policy cultos_editar on public.cultos for update to authenticated using ((select private.e_lider_algum())) with check ((select private.e_lider_algum()));
create policy cultos_apagar on public.cultos for delete to authenticated using ((select private.e_lider_algum()));

create policy culto_salas_ler    on public.culto_salas for select to authenticated using (true);
create policy culto_salas_criar  on public.culto_salas for insert to authenticated with check (private.e_lider(private.dept_sala(sala_id)));
create policy culto_salas_editar on public.culto_salas for update to authenticated using (private.e_lider(private.dept_sala(sala_id))) with check (private.e_lider(private.dept_sala(sala_id)));
create policy culto_salas_apagar on public.culto_salas for delete to authenticated using (private.e_lider(private.dept_sala(sala_id)));

-- Check-in / check-out
create policy checkins_ler on public.checkins for select to authenticated using (
  private.e_recepcao(private.dept_sala(sala_id))
  or crianca_id in (select private.minhas_criancas())
  or sala_id in (select private.salas_que_atuo()));
create policy checkins_criar on public.checkins for insert to authenticated with check (
  private.e_recepcao(private.dept_sala(sala_id)) or private.atuo_hoje(culto_id, sala_id));
create policy checkins_editar on public.checkins for update to authenticated
  using (private.e_recepcao(private.dept_sala(sala_id)) or private.atuo_hoje(culto_id, sala_id))
  with check (private.e_recepcao(private.dept_sala(sala_id)) or private.atuo_hoje(culto_id, sala_id));
create policy checkins_apagar on public.checkins for delete to authenticated using (
  private.e_lider(private.dept_sala(sala_id)));

-- Escala
create policy escalas_ler on public.escalas for select to authenticated using (
  private.e_lider(departamento_id) or (status <> 'rascunho' and private.e_equipe(departamento_id)));
create policy escalas_criar  on public.escalas for insert to authenticated with check (private.e_lider(departamento_id));
create policy escalas_editar on public.escalas for update to authenticated using (private.e_lider(departamento_id)) with check (private.e_lider(departamento_id));
create policy escalas_apagar on public.escalas for delete to authenticated using (private.e_lider(departamento_id));

create policy esc_config_ler    on public.escala_config_salas for select to authenticated using (private.pode_ver_escala(escala_id));
create policy esc_config_criar  on public.escala_config_salas for insert to authenticated with check (private.e_lider(private.dept_escala(escala_id)));
create policy esc_config_editar on public.escala_config_salas for update to authenticated using (private.e_lider(private.dept_escala(escala_id))) with check (private.e_lider(private.dept_escala(escala_id)));
create policy esc_config_apagar on public.escala_config_salas for delete to authenticated using (private.e_lider(private.dept_escala(escala_id)));

create policy esc_itens_ler    on public.escala_itens for select to authenticated using (private.pode_ver_escala(escala_id));
create policy esc_itens_criar  on public.escala_itens for insert to authenticated with check (private.e_lider(private.dept_escala(escala_id)));
create policy esc_itens_editar on public.escala_itens for update to authenticated using (private.e_lider(private.dept_escala(escala_id))) with check (private.e_lider(private.dept_escala(escala_id)));
create policy esc_itens_apagar on public.escala_itens for delete to authenticated using (private.e_lider(private.dept_escala(escala_id)));

-- Tabelas de parâmetros do departamento (equipe lê, líder altera)
do $$
declare t text;
begin
  foreach t in array array['regras_escala','configuracoes','mensagens_whatsapp_modelos','licoes'] loop
    execute format('create policy %I on public.%I for select to authenticated using (private.e_equipe(departamento_id))', t||'_ler', t);
    execute format('create policy %I on public.%I for insert to authenticated with check (private.e_lider(departamento_id))', t||'_criar', t);
    execute format('create policy %I on public.%I for update to authenticated using (private.e_lider(departamento_id)) with check (private.e_lider(departamento_id))', t||'_editar', t);
    execute format('create policy %I on public.%I for delete to authenticated using (private.e_lider(departamento_id))', t||'_apagar', t);
  end loop;
end $$;

-- Eventos e inscrições
create policy eventos_ler    on public.eventos for select to authenticated using (publicado or private.e_lider(departamento_id));
create policy eventos_criar  on public.eventos for insert to authenticated with check (private.e_lider(departamento_id));
create policy eventos_editar on public.eventos for update to authenticated using (private.e_lider(departamento_id)) with check (private.e_lider(departamento_id));
create policy eventos_apagar on public.eventos for delete to authenticated using (private.e_lider(departamento_id));

create policy inscricoes_ler on public.inscricoes_evento for select to authenticated using (
  inscrito_por = (select auth.uid()) or private.e_lider(private.dept_evento(evento_id)));
create policy inscricoes_criar on public.inscricoes_evento for insert to authenticated with check (
  (inscrito_por = (select auth.uid()) and private.evento_aberto(evento_id))
  or private.e_lider(private.dept_evento(evento_id)));
create policy inscricoes_editar on public.inscricoes_evento for update to authenticated
  using (private.e_lider(private.dept_evento(evento_id)))
  with check (private.e_lider(private.dept_evento(evento_id)));
create policy inscricoes_apagar on public.inscricoes_evento for delete to authenticated using (
  inscrito_por = (select auth.uid()) or private.e_lider(private.dept_evento(evento_id)));

-- Enquetes
create policy enquetes_ler    on public.enquetes for select to authenticated using (private.pode_ver_enquete(id));
create policy enquetes_criar  on public.enquetes for insert to authenticated with check (private.e_lider(departamento_id));
create policy enquetes_editar on public.enquetes for update to authenticated using (private.e_lider(departamento_id)) with check (private.e_lider(departamento_id));
create policy enquetes_apagar on public.enquetes for delete to authenticated using (private.e_lider(departamento_id));

create policy opcoes_ler    on public.enquete_opcoes for select to authenticated using (private.pode_ver_enquete(enquete_id));
create policy opcoes_criar  on public.enquete_opcoes for insert to authenticated with check (private.e_lider(private.dept_enquete(enquete_id)));
create policy opcoes_editar on public.enquete_opcoes for update to authenticated using (private.e_lider(private.dept_enquete(enquete_id))) with check (private.e_lider(private.dept_enquete(enquete_id)));
create policy opcoes_apagar on public.enquete_opcoes for delete to authenticated using (private.e_lider(private.dept_enquete(enquete_id)));

create policy votos_ler on public.votos for select to authenticated using (
  perfil_id = (select auth.uid()) or private.e_lider(private.dept_enquete(enquete_id)));
create policy votos_criar on public.votos for insert to authenticated with check (
  perfil_id = (select auth.uid()) and private.enquete_aberta(enquete_id));
create policy votos_apagar on public.votos for delete to authenticated using (
  perfil_id = (select auth.uid()) and private.enquete_aberta(enquete_id));

-- Notificações (sino) e push
create policy notif_ler    on public.notificacoes for select to authenticated using (destinatario_id = (select auth.uid()));
create policy notif_criar  on public.notificacoes for insert to authenticated with check (
  criado_por = (select auth.uid()) and (select private.e_lider_algum()));
create policy notif_marcar on public.notificacoes for update to authenticated
  using (destinatario_id = (select auth.uid())) with check (destinatario_id = (select auth.uid()));
create policy notif_apagar on public.notificacoes for delete to authenticated using (destinatario_id = (select auth.uid()));

create policy push_ler    on public.push_subscriptions for select to authenticated using (perfil_id = (select auth.uid()));
create policy push_criar  on public.push_subscriptions for insert to authenticated with check (perfil_id = (select auth.uid()));
create policy push_editar on public.push_subscriptions for update to authenticated using (perfil_id = (select auth.uid())) with check (perfil_id = (select auth.uid()));
create policy push_apagar on public.push_subscriptions for delete to authenticated using (perfil_id = (select auth.uid()));

-- Fila de impressão
create policy fila_ler    on public.fila_impressao for select to authenticated using (private.e_recepcao(departamento_id));
create policy fila_criar  on public.fila_impressao for insert to authenticated with check (private.e_recepcao(departamento_id));
create policy fila_editar on public.fila_impressao for update to authenticated using (private.e_recepcao(departamento_id)) with check (private.e_recepcao(departamento_id));
create policy fila_apagar on public.fila_impressao for delete to authenticated using (private.e_lider(departamento_id));

-- Log de erros: qualquer um registra, só admin lê
create policy log_registrar on public.log_erros for insert to anon, authenticated
  with check (perfil_id is null or perfil_id = (select auth.uid()));
create policy log_ler on public.log_erros for select to authenticated using ((select private.e_admin()));

-- Auditoria: só leitura para pastor/admin (gravada pelos gatilhos)
create policy auditoria_ler on public.auditoria for select to authenticated using ((select private.e_pastor_ou_admin()));

-- ---------------------------------------------------------------
-- 4. Permissões
-- ---------------------------------------------------------------
-- Visitante sem login (anon) não acessa nenhuma tabela, exceto registrar erro.
revoke all on all tables in schema public from anon;
grant insert on public.log_erros to anon;

grant select, insert, update, delete on all tables in schema public to authenticated;
revoke insert, update, delete on public.auditoria from authenticated;
revoke update on public.notificacoes from authenticated;
grant update (lida_em) on public.notificacoes to authenticated;

-- Tabelas futuras: nada para anon por padrão
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;

-- Funções privadas: só usuários logados (dentro das regras)
revoke all on all functions in schema private from public, anon;
grant usage on schema private to authenticated;
grant execute on all functions in schema private to authenticated;
grant usage on schema private to supabase_auth_admin;

-- ---------- Funções RPC (chamadas pelo app) ----------

-- Voluntária responde à própria escala (Ciente / Recusado)
create function public.responder_escala(p_item uuid, p_resposta public.resposta_escala)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_resposta = 'pendente' then
    raise exception 'Resposta inválida';
  end if;
  update public.escala_itens ei
     set resposta = p_resposta, respondido_em = now()
   where ei.id = p_item
     and ei.voluntaria_id in (select private.minhas_voluntarias())
     and exists (select 1 from public.escalas e where e.id = ei.escala_id and e.status = 'publicada');
  if not found then
    raise exception 'Item de escala não encontrado ou não pertence a você';
  end if;
end $$;

-- Lista da equipe com dados mínimos (sem telefone/ano de nascimento)
create function public.equipe_departamento(p_departamento uuid)
returns table (id uuid, nome text, funcao public.funcao_voluntaria, foto_public_id text,
               aniversario_dia int, aniversario_mes int)
language sql stable security definer set search_path = '' as $$
  select v.id, v.nome, v.funcao, v.foto_public_id,
         extract(day from v.data_nascimento)::int, extract(month from v.data_nascimento)::int
  from public.voluntarias v
  where v.departamento_id = p_departamento and v.status = 'ativa'
    and private.e_equipe(p_departamento)
  order by v.nome
$$;

-- Marca que a senha inicial já foi trocada (chamada logo após trocar a senha)
create function public.concluir_troca_senha()
returns void language sql security definer set search_path = '' as $$
  update public.perfis set troca_senha_obrigatoria = false where id = auth.uid()
$$;

revoke all on function public.responder_escala(uuid, public.resposta_escala) from public, anon;
revoke all on function public.equipe_departamento(uuid) from public, anon;
revoke all on function public.concluir_troca_senha() from public, anon;
grant execute on function public.responder_escala(uuid, public.resposta_escala) to authenticated;
grant execute on function public.equipe_departamento(uuid) to authenticated;
grant execute on function public.concluir_troca_senha() to authenticated;

-- ---------------------------------------------------------------
-- 5. Realtime (monitor do culto, sino, impressora) — respeita o RLS
-- ---------------------------------------------------------------
alter publication supabase_realtime add table public.checkins, public.notificacoes, public.fila_impressao;
