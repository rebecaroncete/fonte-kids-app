-- =====================================================================
-- Fase 4 · Etapa 2 (parte 3/3) – Colunas antigas, regras de acesso e fotos
-- Resumo das regras novas:
--   pessoas ............. cada um vê a PESSOA de quem já via o papel
--                          (família, recepção, voluntária da sala/dia,
--                          líder das voluntárias, pastor/admin) + a si mesmo.
--                          Data de nascimento NÃO é lida direto da tabela:
--                          vem pela função nascimentos() (adultos: só a
--                          própria pessoa, a família e a liderança).
--   relacoes_pessoas .... lê: a própria pessoa, a família da criança,
--                          recepção/voluntária do dia (crianças), líderes de
--                          qualquer departamento e pastores (consulta entre
--                          departamentos, conforme o termo LGPD v1).
--                          Grava: liderança/recepção; o responsável grava
--                          pela função do 1º acesso (Etapa 4).
--   possiveis_duplicidades  só líderes (dos departamentos envolvidos) e pastor/admin.
-- =====================================================================

-- ---------------------------------------------------------------
-- 1. Pessoa obrigatória nos papéis + unicidade
-- ---------------------------------------------------------------
alter table public.responsaveis        alter column pessoa_id set not null;
alter table public.criancas            alter column pessoa_id set not null;
alter table public.voluntarias         alter column pessoa_id set not null;
alter table public.pessoas_autorizadas alter column pessoa_id set not null;

alter table public.responsaveis        add constraint responsaveis_familia_pessoa_uk unique (familia_id, pessoa_id);
alter table public.criancas            add constraint criancas_pessoa_uk unique (pessoa_id);
alter table public.pessoas_autorizadas add constraint autorizadas_familia_pessoa_uk unique (familia_id, pessoa_id);
create index responsaveis_pessoa_idx on public.responsaveis (pessoa_id);
create index autorizadas_pessoa_idx  on public.pessoas_autorizadas (pessoa_id);

-- ---------------------------------------------------------------
-- 2. Regras que dependem de colunas que vão sair (recriadas abaixo)
-- ---------------------------------------------------------------
drop policy voluntarias_ler    on public.voluntarias;
drop policy voluntarias_criar  on public.voluntarias;
drop policy voluntarias_editar on public.voluntarias;
drop policy indisp_ler    on public.indisponibilidades;
drop policy indisp_criar  on public.indisponibilidades;
drop policy indisp_editar on public.indisponibilidades;
drop policy indisp_apagar on public.indisponibilidades;
drop trigger responsaveis_trava on public.responsaveis;
drop function private.trava_responsaveis();

-- ---------------------------------------------------------------
-- 3. Dados pessoais saem dos papéis (agora ficam só em "pessoas")
-- ---------------------------------------------------------------
alter table public.responsaveis        drop column nome, drop column telefone, drop column parentesco, drop column perfil_id;
alter table public.criancas            drop column nome, drop column data_nascimento, drop column sexo, drop column foto_public_id;
alter table public.voluntarias         drop column nome, drop column telefone, drop column data_nascimento,
                                       drop column sexo, drop column foto_public_id, drop column perfil_id;
alter table public.pessoas_autorizadas drop column nome, drop column telefone, drop column parentesco;
-- parentesco agora só em relacoes_pessoas; responsaveis_criancas = vínculo de responsabilidade no Fonte Kids
alter table public.responsaveis_criancas drop column parentesco, drop column parentesco_detalhe, drop column confirmado_em;
drop type public.parentesco_tipo;
alter table public.perfis drop column nome, drop column foto_public_id;   -- vêm da pessoa

alter table public.voluntarias add constraint voluntarias_dept_pessoa_uk unique (departamento_id, pessoa_id);
create index voluntarias_pessoa_idx on public.voluntarias (pessoa_id);

comment on table public.responsaveis_criancas is
  'Quem responde por cada criança no Fonte Kids. O parentesco fica em relacoes_pessoas.';
comment on column public.perfis.telefone is 'Telefone de LOGIN (único). Contato fica em pessoas.telefone.';

-- ---------------------------------------------------------------
-- 4. Funções auxiliares
-- ---------------------------------------------------------------
create function private.minha_pessoa() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.pessoa_id from public.perfis p where p.id = (select auth.uid()) and p.ativo $$;

create function private.minha_igreja() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.igreja_id from public.perfis p where p.id = (select auth.uid()) and p.ativo $$;

create function private.tem_algum_papel() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.papeis_usuario pu join public.perfis p on p.id = pu.perfil_id
                 where pu.perfil_id = (select auth.uid()) and p.ativo) $$;

create or replace function private.minhas_familias() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select familia_id from public.responsaveis where pessoa_id = (select private.minha_pessoa()) $$;

create or replace function private.minhas_voluntarias() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select id from public.voluntarias
  where pessoa_id = (select private.minha_pessoa()) and status = 'ativa' $$;

-- Departamentos em que a pessoa tem algum papel
create function private.depts_da_pessoa(p uuid) returns setof uuid
language sql stable security definer set search_path = '' as $$
  select f.departamento_id from public.criancas c join public.familias f on f.id = c.familia_id where c.pessoa_id = p
  union select f.departamento_id from public.responsaveis r join public.familias f on f.id = r.familia_id where r.pessoa_id = p
  union select f.departamento_id from public.pessoas_autorizadas a join public.familias f on f.id = a.familia_id where a.pessoa_id = p
  union select v.departamento_id from public.voluntarias v where v.pessoa_id = p $$;

-- Quem pode ver a PESSOA = quem já podia ver algum papel dela
create function private.pode_ver_pessoa(p uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_pastor_ou_admin()
    or p = (select private.minha_pessoa())
    or exists (select 1 from public.pessoas x where x.id = p and x.criado_por = (select auth.uid()))
    or exists (select 1 from public.criancas c where c.pessoa_id = p and (
         c.familia_id in (select private.minhas_familias())
         or private.e_recepcao(private.dept_familia(c.familia_id))
         or c.id in (select private.criancas_das_minhas_salas())))
    or exists (select 1 from public.responsaveis r where r.pessoa_id = p and (
         r.familia_id in (select private.minhas_familias())
         or private.e_recepcao(private.dept_familia(r.familia_id))
         or r.familia_id in (select private.familias_visiveis_hoje())))
    or exists (select 1 from public.pessoas_autorizadas a where a.pessoa_id = p and (
         a.familia_id in (select private.minhas_familias())
         or private.e_recepcao(private.dept_familia(a.familia_id))
         or a.familia_id in (select private.familias_visiveis_hoje())))
    or exists (select 1 from public.voluntarias v where v.pessoa_id = p and private.e_lider(v.departamento_id)) $$;

-- Quem pode EDITAR a pessoa
create function private.pode_editar_pessoa(p uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_pastor_ou_admin()
    or p = (select private.minha_pessoa())
    or exists (select 1 from public.pessoas x where x.id = p and x.criado_por = (select auth.uid())
               and not exists (select private.depts_da_pessoa(p)))
    or exists (select 1 from public.criancas c where c.pessoa_id = p and (
         c.familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(c.familia_id))))
    or exists (select 1 from public.responsaveis r where r.pessoa_id = p and (
         r.familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(r.familia_id))))
    or exists (select 1 from public.pessoas_autorizadas a where a.pessoa_id = p and (
         a.familia_id in (select private.minhas_familias()) or private.e_recepcao(private.dept_familia(a.familia_id))))
    or exists (select 1 from public.voluntarias v where v.pessoa_id = p and private.e_lider(v.departamento_id)) $$;

-- Apagar a pessoa (LGPD): pastor/admin, ou líder de TODOS os departamentos em que ela está
create function private.pode_apagar_pessoa(p uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_pastor_ou_admin()
    or (exists (select private.depts_da_pessoa(p))
        and not exists (select 1 from private.depts_da_pessoa(p) d(id) where not private.e_lider(d.id))) $$;

-- Relações: quem lê
create function private.pode_ver_relacao(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_lider_algum()   -- líderes de qualquer departamento e pastores/admin
    or (select private.minha_pessoa()) in (a, b)
    or exists (select 1 from public.criancas c where c.pessoa_id in (a, b) and (
         c.familia_id in (select private.minhas_familias())
         or private.e_recepcao(private.dept_familia(c.familia_id))
         or c.familia_id in (select private.familias_visiveis_hoje()))) $$;

-- Relações: quem grava direto (o responsável usa a função do 1º acesso)
create function private.pode_gravar_relacao(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_pastor_ou_admin()
    or exists (select 1 from private.depts_da_pessoa(a) d(id) where private.e_recepcao(d.id))
    or exists (select 1 from private.depts_da_pessoa(b) d(id) where private.e_recepcao(d.id)) $$;

-- Duplicidades: liderança dos departamentos envolvidos
create function private.pode_ver_duplicidade(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_pastor_ou_admin()
    or exists (select 1 from private.depts_da_pessoa(a) d(id) where private.e_lider(d.id))
    or exists (select 1 from private.depts_da_pessoa(b) d(id) where private.e_lider(d.id)) $$;

-- ---------------------------------------------------------------
-- 5. Gatilhos
-- ---------------------------------------------------------------
-- 5a. Perfil novo: a pessoa e o telefone de login vêm de raw_app_meta_data,
--     que SÓ o servidor consegue gravar (o usuário não consegue se ligar a
--     outra pessoa pelo cadastro).
create or replace function private.criar_perfil_novo_usuario()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_pessoa uuid; v_igreja uuid;
begin
  begin
    v_pessoa := nullif(new.raw_app_meta_data ->> 'pessoa_id', '')::uuid;
  exception when invalid_text_representation then v_pessoa := null;
  end;
  select igreja_id into v_igreja from public.pessoas where id = v_pessoa;
  if v_igreja is null then v_pessoa := null; end if;
  insert into public.perfis (id, telefone, pessoa_id, igreja_id)
  values (new.id, nullif(new.raw_app_meta_data ->> 'telefone', ''), v_pessoa, v_igreja)
  on conflict (id) do nothing;
  return new;
end $$;

-- 5b. Perfil: pessoa, telefone de login e situação só pelo servidor/pastor/admin
create or replace function private.trava_perfis()
returns trigger language plpgsql set search_path = '' as $$
begin
  if private.chamada_do_app() and not private.e_pastor_ou_admin() and (
       new.id is distinct from old.id or
       new.ativo is distinct from old.ativo or
       new.troca_senha_obrigatoria is distinct from old.troca_senha_obrigatoria or
       new.igreja_id is distinct from old.igreja_id or
       new.pessoa_id is distinct from old.pessoa_id or
       new.telefone is distinct from old.telefone) then
    raise exception 'Sem permissão para alterar estes campos do perfil';
  end if;
  return new;
end $$;

-- 5c. Pessoa: quem cadastrou e a igreja não mudam pelo app
create function private.trava_pessoas()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not private.chamada_do_app() then return new; end if;
  if tg_op = 'INSERT' then
    new.criado_por := auth.uid();
  elsif not private.e_admin() and (
       new.igreja_id is distinct from old.igreja_id or
       new.criado_por is distinct from old.criado_por) then
    raise exception 'Sem permissão para alterar estes campos da pessoa';
  end if;
  return new;
end $$;
create trigger pessoas_trava before insert or update on public.pessoas
  for each row execute function private.trava_pessoas();

-- 5d. Ligar uma pessoa a uma família: quem não é recepção/liderança só liga
--     a si mesmo ou pessoas que ele mesmo cadastrou (impede "puxar" o
--     cadastro de outra pessoa para a própria família e ver os dados dela).
create function private.trava_vinculo_familia()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not private.chamada_do_app() or private.e_recepcao(private.dept_familia(new.familia_id)) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.pessoa_id is distinct from old.pessoa_id then
      raise exception 'Sem permissão para trocar a pessoa deste cadastro';
    end if;
    return new;
  end if;
  if new.pessoa_id is distinct from private.minha_pessoa()
     and not exists (select 1 from public.pessoas p
                     where p.id = new.pessoa_id and p.criado_por = auth.uid()) then
    raise exception 'Só é possível vincular pessoas cadastradas por você';
  end if;
  return new;
end $$;
create trigger responsaveis_trava before insert or update on public.responsaveis
  for each row execute function private.trava_vinculo_familia();
create trigger criancas_trava before insert or update on public.criancas
  for each row execute function private.trava_vinculo_familia();
create trigger autorizadas_trava before insert or update on public.pessoas_autorizadas
  for each row execute function private.trava_vinculo_familia();

-- 5e. Voluntária: auto-cadastro só da própria pessoa; aprovação só por líder
create or replace function private.trava_voluntarias()
returns trigger language plpgsql set search_path = '' as $$
begin
  if not private.chamada_do_app() then return new; end if;
  if tg_op = 'INSERT' then
    if not private.e_lider(new.departamento_id) then
      if new.pessoa_id is distinct from private.minha_pessoa() then
        raise exception 'O auto-cadastro de voluntária só pode ser da própria pessoa';
      end if;
      new.status := 'pendente';          -- auto-cadastro sempre aguarda aprovação
      new.aprovada_por := null;
      new.aprovada_em := null;
    end if;
  elsif not private.e_lider(old.departamento_id) and (
       new.status is distinct from old.status or
       new.funcao is distinct from old.funcao or
       new.departamento_id is distinct from old.departamento_id or
       new.pessoa_id is distinct from old.pessoa_id or
       new.aprovada_por is distinct from old.aprovada_por or
       new.aprovada_em is distinct from old.aprovada_em) then
    raise exception 'Só líderes podem aprovar ou mudar a função da voluntária';
  end if;
  return new;
end $$;

-- 5f. Relação: quem informou é sempre quem está logado
create or replace function private.normalizar_relacao()
returns trigger language plpgsql set search_path = '' as $$
declare tmp uuid;
begin
  if new.tipo in ('conjuge','irmao') and new.pessoa_id > new.relacionada_id then
    tmp := new.pessoa_id; new.pessoa_id := new.relacionada_id; new.relacionada_id := tmp;
  end if;
  if new.tipo <> 'outro' then new.detalhe := null; end if;
  if private.chamada_do_app() then new.informado_por := auth.uid(); end if;
  return new;
end $$;

-- 5g. Pessoa sem nenhum papel e sem login é apagada (LGPD: apagar a família
--     apaga as pessoas dela que não participam de mais nada na igreja).
create function private.apagar_pessoa_sem_vinculo()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  delete from public.pessoas p
  where p.id = old.pessoa_id
    and not exists (select private.depts_da_pessoa(p.id))
    and not exists (select 1 from public.perfis x where x.pessoa_id = p.id);
  return null;
end $$;
create trigger criancas_pessoa_orfa after delete on public.criancas
  for each row execute function private.apagar_pessoa_sem_vinculo();
create trigger responsaveis_pessoa_orfa after delete on public.responsaveis
  for each row execute function private.apagar_pessoa_sem_vinculo();
create trigger autorizadas_pessoa_orfa after delete on public.pessoas_autorizadas
  for each row execute function private.apagar_pessoa_sem_vinculo();
create trigger voluntarias_pessoa_orfa after delete on public.voluntarias
  for each row execute function private.apagar_pessoa_sem_vinculo();

-- 5h. Auditoria (só nomes de campos)
create trigger pessoas_auditoria after insert or update or delete on public.pessoas
  for each row execute function private.auditar();
create trigger relacoes_pessoas_auditoria after insert or update or delete on public.relacoes_pessoas
  for each row execute function private.auditar();
create trigger duplicidades_auditoria after insert or update or delete on public.possiveis_duplicidades
  for each row execute function private.auditar();

-- ---------------------------------------------------------------
-- 6. RLS
-- ---------------------------------------------------------------
alter table public.pessoas                enable row level security;
alter table public.relacoes_pessoas       enable row level security;
alter table public.possiveis_duplicidades enable row level security;

create policy pessoas_ler on public.pessoas for select to authenticated
  using (private.pode_ver_pessoa(id));
create policy pessoas_criar on public.pessoas for insert to authenticated
  with check ((select private.e_admin())
              or (igreja_id = (select private.minha_igreja()) and (select private.tem_algum_papel())));
create policy pessoas_editar on public.pessoas for update to authenticated
  using (private.pode_editar_pessoa(id)) with check (private.pode_editar_pessoa(id));
create policy pessoas_apagar on public.pessoas for delete to authenticated
  using (private.pode_apagar_pessoa(id));

create policy relacoes_ler on public.relacoes_pessoas for select to authenticated
  using (private.pode_ver_relacao(pessoa_id, relacionada_id));
create policy relacoes_criar on public.relacoes_pessoas for insert to authenticated
  with check (private.pode_gravar_relacao(pessoa_id, relacionada_id));
create policy relacoes_editar on public.relacoes_pessoas for update to authenticated
  using (private.pode_gravar_relacao(pessoa_id, relacionada_id))
  with check (private.pode_gravar_relacao(pessoa_id, relacionada_id));
create policy relacoes_apagar on public.relacoes_pessoas for delete to authenticated
  using (private.pode_gravar_relacao(pessoa_id, relacionada_id));

create policy duplicidades_ler on public.possiveis_duplicidades for select to authenticated
  using (private.pode_ver_duplicidade(pessoa_a, pessoa_b));
create policy duplicidades_criar on public.possiveis_duplicidades for insert to authenticated
  with check (private.pode_ver_duplicidade(pessoa_a, pessoa_b));
create policy duplicidades_apagar on public.possiveis_duplicidades for delete to authenticated
  using ((select private.e_admin()));
-- (a resolução é feita pela função resolver_duplicidade)

-- Voluntárias e indisponibilidades (mesma regra de antes, agora pela pessoa)
create policy voluntarias_ler on public.voluntarias for select to authenticated using (
  pessoa_id = (select private.minha_pessoa()) or private.e_lider(departamento_id));
create policy voluntarias_criar on public.voluntarias for insert to authenticated with check (
  pessoa_id = (select private.minha_pessoa()) or private.e_lider(departamento_id));
create policy voluntarias_editar on public.voluntarias for update to authenticated
  using (pessoa_id = (select private.minha_pessoa()) or private.e_lider(departamento_id))
  with check (pessoa_id = (select private.minha_pessoa()) or private.e_lider(departamento_id));

create policy indisp_ler on public.indisponibilidades for select to authenticated using (
  voluntaria_id in (select id from public.voluntarias where pessoa_id = (select private.minha_pessoa()))
  or private.e_lider(private.dept_voluntaria(voluntaria_id)));
create policy indisp_criar on public.indisponibilidades for insert to authenticated with check (
  voluntaria_id in (select id from public.voluntarias where pessoa_id = (select private.minha_pessoa()))
  or private.e_lider(private.dept_voluntaria(voluntaria_id)));
create policy indisp_editar on public.indisponibilidades for update to authenticated
  using (voluntaria_id in (select id from public.voluntarias where pessoa_id = (select private.minha_pessoa()))
         or private.e_lider(private.dept_voluntaria(voluntaria_id)))
  with check (voluntaria_id in (select id from public.voluntarias where pessoa_id = (select private.minha_pessoa()))
         or private.e_lider(private.dept_voluntaria(voluntaria_id)));
create policy indisp_apagar on public.indisponibilidades for delete to authenticated using (
  voluntaria_id in (select id from public.voluntarias where pessoa_id = (select private.minha_pessoa()))
  or private.e_lider(private.dept_voluntaria(voluntaria_id)));

-- ---------------------------------------------------------------
-- 7. Permissões
-- ---------------------------------------------------------------
revoke all on public.pessoas, public.relacoes_pessoas, public.possiveis_duplicidades from anon;
grant insert, update, delete on public.pessoas to authenticated;
-- Leitura por coluna: a data de nascimento NÃO é lida direto (ver nascimentos())
revoke select on public.pessoas from authenticated;
grant select (id, igreja_id, nome, nome_busca, sexo, telefone, foto_public_id, criado_por, criado_em, atualizado_em)
  on public.pessoas to authenticated;
grant select, insert, update, delete on public.relacoes_pessoas to authenticated;
grant select, insert, delete on public.possiveis_duplicidades to authenticated;
revoke update on public.possiveis_duplicidades from authenticated;   -- só pela função resolver_duplicidade

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;
revoke all on function private.detectar_duplicidades() from authenticated;

-- ---------------------------------------------------------------
-- 8. Funções para o app
-- ---------------------------------------------------------------
-- Data de nascimento: crianças para quem já vê a criança; adultos só para a
-- própria pessoa, a família e a liderança. (A equipe vê dia/mês na lista da equipe.)
create function public.nascimentos(p_ids uuid[])
returns table (id uuid, data_nascimento date)
language sql stable security definer set search_path = '' as $$
  select p.id, p.data_nascimento
  from public.pessoas p
  where p.id = any (p_ids) and p.data_nascimento is not null
    and (p.id = (select private.minha_pessoa())
      or private.e_pastor_ou_admin()
      or exists (select 1 from public.criancas c where c.pessoa_id = p.id and (
           c.familia_id in (select private.minhas_familias())
           or private.e_recepcao(private.dept_familia(c.familia_id))
           or c.id in (select private.criancas_das_minhas_salas())))
      or exists (select 1 from public.responsaveis r where r.pessoa_id = p.id and (
           r.familia_id in (select private.minhas_familias())
           or private.e_lider(private.dept_familia(r.familia_id))))
      or exists (select 1 from public.voluntarias v where v.pessoa_id = p.id and private.e_lider(v.departamento_id)))
$$;

-- Fotos por CRIANÇA (mesma regra da tabela criancas)
create or replace function public.fotos_criancas(p_ids uuid[])
returns table (id uuid, foto_public_id text)
language sql stable security invoker set search_path = '' as $$
  select c.id, p.foto_public_id
  from public.criancas c join public.pessoas p on p.id = c.pessoa_id
  where c.id = any (p_ids) and p.foto_public_id is not null
$$;

-- Fotos por VOLUNTÁRIA (menor de idade: só ela e a liderança)
create or replace function public.fotos_voluntarias(p_ids uuid[])
returns table (id uuid, foto_public_id text)
language sql stable security definer set search_path = '' as $$
  select v.id, p.foto_public_id
  from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id
  where v.id = any (p_ids) and p.foto_public_id is not null
    and (v.pessoa_id = (select private.minha_pessoa())
      or private.e_lider(v.departamento_id)
      or (private.e_equipe(v.departamento_id) and v.status = 'ativa'
          and not private.e_menor(p.data_nascimento)))
$$;

-- Fotos por PESSOA (para os próximos departamentos): soma das regras acima.
-- Ser responsável não dá acesso a foto (como antes).
create function public.fotos_pessoas(p_ids uuid[])
returns table (id uuid, foto_public_id text)
language sql stable security definer set search_path = '' as $$
  select p.id, p.foto_public_id
  from public.pessoas p
  where p.id = any (p_ids) and p.foto_public_id is not null
    and (p.id = (select private.minha_pessoa())
      or private.e_pastor_ou_admin()
      or exists (select 1 from public.criancas c where c.pessoa_id = p.id and (
           c.familia_id in (select private.minhas_familias())
           or private.e_recepcao(private.dept_familia(c.familia_id))
           or c.id in (select private.criancas_das_minhas_salas())))
      or exists (select 1 from public.voluntarias v where v.pessoa_id = p.id and (
           private.e_lider(v.departamento_id)
           or (private.e_equipe(v.departamento_id) and v.status = 'ativa'
               and not private.e_menor(p.data_nascimento)))))
$$;

-- Lista da equipe (dados mínimos; foto de menor só para a liderança)
drop function if exists public.equipe_departamento(uuid);
create function public.equipe_departamento(p_departamento uuid)
returns table (id uuid, nome text, funcao public.funcao_voluntaria, foto_public_id text,
               aniversario_dia int, aniversario_mes int)
language sql stable security definer set search_path = '' as $$
  select v.id, p.nome, v.funcao,
         case when private.e_menor(p.data_nascimento)
                   and not private.e_lider(p_departamento)
                   and v.pessoa_id is distinct from (select private.minha_pessoa())
              then null else p.foto_public_id end,
         extract(day from p.data_nascimento)::int, extract(month from p.data_nascimento)::int
  from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id
  where v.departamento_id = p_departamento and v.status = 'ativa'
    and private.e_equipe(p_departamento)
  order by p.nome
$$;

-- Juntar duas pessoas que são a mesma (usada por resolver_duplicidade)
create function private.mesclar_pessoas(p_manter uuid, p_remover uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_manter = p_remover then raise exception 'Mesma pessoa'; end if;
  if exists (select 1 from public.perfis where pessoa_id = p_remover)
     and exists (select 1 from public.perfis where pessoa_id = p_manter) then
    raise exception 'As duas pessoas têm login: resolver manualmente';
  end if;
  if exists (select 1 from public.criancas where pessoa_id = p_remover)
     and exists (select 1 from public.criancas where pessoa_id = p_manter) then
    raise exception 'As duas são crianças cadastradas: juntar os cadastros de criança manualmente (check-ins)';
  end if;
  if exists (select 1 from public.voluntarias a join public.voluntarias b using (departamento_id)
             where a.pessoa_id = p_remover and b.pessoa_id = p_manter) then
    raise exception 'As duas são voluntárias no mesmo departamento: resolver manualmente';
  end if;
  -- completa o que estiver vazio
  update public.pessoas m set
    data_nascimento = coalesce(m.data_nascimento, r.data_nascimento),
    sexo            = coalesce(m.sexo, r.sexo),
    telefone        = coalesce(m.telefone, r.telefone),
    foto_public_id  = coalesce(m.foto_public_id, r.foto_public_id)
  from public.pessoas r where m.id = p_manter and r.id = p_remover;
  -- login e relações primeiro (apagar um papel pode apagar a pessoa sem vínculo)
  update public.perfis set pessoa_id = p_manter where pessoa_id = p_remover;
  -- relações (sem repetir nem criar relação consigo mesma)
  delete from public.relacoes_pessoas x
   where (x.pessoa_id = p_remover and x.relacionada_id = p_manter)
      or (x.pessoa_id = p_manter and x.relacionada_id = p_remover);
  delete from public.relacoes_pessoas x where x.pessoa_id = p_remover and exists (
    select 1 from public.relacoes_pessoas y where y.pessoa_id = p_manter and y.relacionada_id = x.relacionada_id and y.tipo = x.tipo);
  delete from public.relacoes_pessoas x where x.relacionada_id = p_remover and exists (
    select 1 from public.relacoes_pessoas y where y.relacionada_id = p_manter and y.pessoa_id = x.pessoa_id and y.tipo = x.tipo);
  update public.relacoes_pessoas set pessoa_id = p_manter where pessoa_id = p_remover;
  update public.relacoes_pessoas set relacionada_id = p_manter where relacionada_id = p_remover;
  -- papéis (no mesmo vínculo de família, o repetido é descartado)
  delete from public.responsaveis_criancas rc using public.responsaveis r
   where rc.responsavel_id = r.id and r.pessoa_id = p_remover
     and exists (select 1 from public.responsaveis k where k.pessoa_id = p_manter and k.familia_id = r.familia_id);
  delete from public.responsaveis r
   where r.pessoa_id = p_remover
     and exists (select 1 from public.responsaveis k where k.pessoa_id = p_manter and k.familia_id = r.familia_id);
  update public.responsaveis set pessoa_id = p_manter where pessoa_id = p_remover;
  delete from public.pessoas_autorizadas a
   where a.pessoa_id = p_remover
     and exists (select 1 from public.pessoas_autorizadas k where k.pessoa_id = p_manter and k.familia_id = a.familia_id);
  update public.pessoas_autorizadas set pessoa_id = p_manter where pessoa_id = p_remover;
  update public.criancas    set pessoa_id = p_manter where pessoa_id = p_remover;
  update public.voluntarias set pessoa_id = p_manter where pessoa_id = p_remover;
  -- outras duplicidades da pessoa removida passam para a mantida
  delete from public.possiveis_duplicidades where pessoa_a = p_remover or pessoa_b = p_remover;
  delete from public.pessoas where id = p_remover;
  perform private.detectar_duplicidades();
end $$;
revoke all on function private.mesclar_pessoas(uuid, uuid) from public, anon, authenticated;

-- Liderança decide um par duvidoso. Mesma pessoa: mantém quem tem login;
-- senão quem tem papel de voluntária; senão o cadastro mais antigo.
-- Devolve só o status (sem dados pessoais).
create function public.resolver_duplicidade(p_duplicidade uuid, p_mesma_pessoa boolean)
returns text language plpgsql security definer set search_path = '' as $$
declare d record; v_manter uuid; v_remover uuid;
begin
  select * into d from public.possiveis_duplicidades where id = p_duplicidade and situacao = 'pendente';
  if not found or not private.pode_ver_duplicidade(d.pessoa_a, d.pessoa_b) then
    raise exception 'Par não encontrado ou sem permissão';
  end if;
  if not p_mesma_pessoa then
    update public.possiveis_duplicidades
       set situacao = 'pessoas_diferentes', resolvido_por = auth.uid(), resolvido_em = now()
     where id = p_duplicidade;
    return 'marcadas como pessoas diferentes';
  end if;
  select p.id into v_manter from public.pessoas p where p.id in (d.pessoa_a, d.pessoa_b)
   order by exists (select 1 from public.perfis x where x.pessoa_id = p.id) desc,
            exists (select 1 from public.voluntarias v where v.pessoa_id = p.id) desc,
            p.criado_em, p.id
   limit 1;
  v_remover := case when v_manter = d.pessoa_a then d.pessoa_b else d.pessoa_a end;
  perform private.mesclar_pessoas(v_manter, v_remover);
  return 'cadastros juntados';
end $$;

revoke all on function public.nascimentos(uuid[]), public.fotos_pessoas(uuid[]),
                       public.resolver_duplicidade(uuid, boolean), public.equipe_departamento(uuid) from public, anon;
grant execute on function public.nascimentos(uuid[]), public.fotos_pessoas(uuid[]),
                          public.resolver_duplicidade(uuid, boolean), public.equipe_departamento(uuid) to authenticated;
