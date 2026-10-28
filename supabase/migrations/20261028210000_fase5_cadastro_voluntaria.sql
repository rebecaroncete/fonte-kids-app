-- Fase 5 · Etapa 5F – Cadastro de voluntária pelo link, com aprovação da liderança
-- * O link público (Edge Function cadastro-publico, ações "voluntaria_opcoes" e
--   "voluntaria") grava SÓ em pedidos_voluntaria – nunca em pessoas/voluntarias.
--   As funções do link só rodam com a chave de serviço (service_role).
-- * Termo próprio da voluntária (termos_voluntaria_versoes); o aceite vai para
--   a voluntária na aprovação (voluntarias.termo_versao / termo_aceito_em).
-- * Liderança (líder do Fonte Kids, pastor, admin): pedidos_voluntaria_lista(),
--   aprovar_pedido_voluntaria(), recusar_pedido_voluntaria() e
--   fotos_pedidos_voluntaria() (foto pela foto-assinada).
-- * Aprovar: cria (ou reaproveita, pelo telefone) a pessoa, cria a voluntária
--   ativa e, se a pessoa já tem login, dá o papel de voluntária (o gatilho dá
--   recepção junto). Sem login, o app chama a gerenciar-login ("criar").
-- * Recusar: apaga o pedido (a foto é apagada no Cloudinary pela enviar-foto).
-- * Idade mínima 12 anos; foto obrigatória (conferida na tela e na Edge Function);
--   limite de 30 pedidos a cada 24 h; mesmo telefone com pedido pendente =
--   o pedido novo substitui o antigo.

-- 1) Termo da voluntária ------------------------------------------------------------
create table if not exists public.termos_voluntaria_versoes (
  id           uuid primary key default gen_random_uuid(),
  versao       text not null unique,
  texto        text not null,
  vigente      boolean not null default false,
  publicado_em timestamptz not null default now()
);
create unique index if not exists termos_voluntaria_um_vigente on public.termos_voluntaria_versoes (vigente) where vigente;
alter table public.termos_voluntaria_versoes enable row level security;
revoke all on public.termos_voluntaria_versoes from anon, authenticated;
grant select on public.termos_voluntaria_versoes to authenticated;
create policy termos_voluntaria_ler on public.termos_voluntaria_versoes for select to authenticated using (true);
create trigger termos_voluntaria_auditoria after insert or update or delete
  on public.termos_voluntaria_versoes for each row execute function private.auditar();

insert into public.termos_voluntaria_versoes (versao, vigente, texto) values ('v1', true,
$termo$TERMO DE CONSENTIMENTO – VOLUNTÁRIAS E VOLUNTÁRIOS DO FONTE KIDS (versão 1)

Este termo segue a Lei Geral de Proteção de Dados (Lei 13.709/2018).

1. Quem trata os dados
A igreja, por meio do ministério infantil Fonte Kids, é responsável pelos dados enviados neste cadastro.

2. Quais dados
Nome, WhatsApp, data de nascimento, e-mail, profissão, sexo, foto, função desejada (professora ou auxiliar), faixas de idade e cultos em que prefere servir e, depois da aprovação, as escalas e a participação nos cultos.

3. Para que usamos
- Avaliar o seu cadastro e falar com você sobre o voluntariado.
- Montar a escala mensal, enviar lembretes e avisos (inclusive por WhatsApp e e-mail) e criar o seu acesso ao aplicativo.
- Identificar quem está servindo em cada sala, para a segurança das crianças.
Não vendemos nem compartilhamos os dados com empresas para fins comerciais.

4. Quem pode ver
- Enquanto o cadastro aguarda aprovação: só a liderança do Fonte Kids e os pastores.
- Depois de aprovado: você, a liderança e os pastores veem o cadastro completo; as outras voluntárias podem ver o seu nome e a sua foto na escala.
- A foto fica guardada de forma privada e só aparece, por poucos minutos, para quem tem permissão.

5. Onde ficam guardados
Em serviços de computação em nuvem contratados pela igreja, com acesso protegido por senha, cópias de segurança criptografadas e registro de alterações.

6. Por quanto tempo
Enquanto você servir no Fonte Kids. Se o cadastro não for aprovado, os dados e a foto são apagados. Se você deixar o voluntariado e pedir, o cadastro e a foto são apagados, exceto o que a lei exigir guardar.

7. Seus direitos
Você pode, a qualquer momento: ver os seus dados, corrigir o que estiver errado, pedir uma cópia, retirar este consentimento e pedir a exclusão do cadastro. Para isso, fale com a liderança do Fonte Kids.

8. Menores de 18 anos
Se você tem entre 12 e 17 anos, mostre este termo ao seu pai, mãe ou responsável antes de enviar. A liderança vai confirmar com ele(a) antes de aprovar o cadastro.

Ao marcar "Li e aceito", declaro que as informações são verdadeiras, que li este termo e que concordo com o tratamento dos dados descrito acima.$termo$)
on conflict (versao) do nothing;

-- 2) Aceite guardado na voluntária ----------------------------------------------------
alter table public.voluntarias add column if not exists termo_versao text;
alter table public.voluntarias add column if not exists termo_aceito_em timestamptz;

-- 3) Pedidos (o link público grava só aqui) ---------------------------------------
create table if not exists public.pedidos_voluntaria (
  id                uuid primary key default gen_random_uuid(),
  departamento_id   uuid not null references public.departamentos(id),
  nome              text not null check (char_length(nome) between 3 and 120),
  telefone          text not null check (telefone ~ '^55[1-9][0-9]9?[0-9]{8}$'),
  data_nascimento   date not null,
  email             text check (email is null or char_length(email) <= 120),
  profissao         text check (profissao is null or char_length(profissao) <= 80),
  sexo              public.sexo_tipo,
  funcao            public.funcao_voluntaria not null,
  salas_preferidas  uuid[] not null default '{}',
  cultos_preferidos uuid[] not null default '{}',
  foto_public_id    text,
  termo_versao      text not null,
  aceito_em         timestamptz not null default now(),
  criado_em         timestamptz not null default now()
);
create index if not exists pedidos_voluntaria_tel_idx on public.pedidos_voluntaria (telefone);
alter table public.pedidos_voluntaria enable row level security;
revoke all on public.pedidos_voluntaria from anon, authenticated;   -- só pelas funções
create trigger pedidos_voluntaria_auditoria after insert or update or delete
  on public.pedidos_voluntaria for each row execute function private.auditar();

-- registro só de contagem (limite diário), sem dado pessoal
create table if not exists private.pedidos_voluntaria_link (
  criado_em timestamptz not null default now()
);
revoke all on private.pedidos_voluntaria_link from public, anon, authenticated;

-- 4) Avisos: líderes do Fonte Kids, pastores e admin --------------------------------
create or replace function private.avisar_aprovadores_kids(p_titulo text, p_corpo text, p_link text, p_tipo text)
returns void language sql security definer set search_path to '' as $$
  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por)
  select distinct pu.perfil_id, p_titulo, p_corpo, p_link, p_tipo, auth.uid()
    from public.papeis_usuario pu
    join public.perfis p on p.id = pu.perfil_id and p.ativo
   where pu.perfil_id is distinct from auth.uid()
     and (pu.papel in ('admin', 'pastor')
          or (pu.papel = 'lider' and pu.departamento_id = private.dept_kids())) $$;

-- 5) Link público (só service_role) ------------------------------------------------
-- Opções do formulário: termo vigente, salas e cultos da agenda
create or replace function public.voluntaria_link_opcoes() returns jsonb
language sql stable security definer set search_path to '' as $$
  select jsonb_build_object(
    'termo', (select jsonb_build_object('versao', t.versao, 'texto', t.texto)
                from public.termos_voluntaria_versoes t where t.vigente limit 1),
    'salas', coalesce((select jsonb_agg(jsonb_build_object('id', s.id, 'nome', s.nome) order by s.ordem)
                from public.salas s where s.departamento_id = private.dept_kids() and s.ativa), '[]'::jsonb),
    'cultos', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'nome', r.nome, 'dia_semana', r.dia_semana,
                                         'horario', to_char(r.horario, 'HH24:MI')) order by r.dia_semana, r.horario)
                from public.cultos_recorrentes r where r.ativo), '[]'::jsonb)) $$;

-- Grava o pedido. Devolve { pedido_id, foto_antiga } (foto do pedido substituído, para apagar).
create or replace function public.pedido_voluntaria_criar(p_dados jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v_dept uuid := private.dept_kids();
  v_nome text := private.nome_limpo(p_dados->>'nome');
  v_tel text := private.normalizar_telefone(p_dados->>'telefone');
  v_nasc date;
  v_email text := nullif(lower(btrim(coalesce(p_dados->>'email', ''))), '');
  v_prof text := nullif(btrim(coalesce(p_dados->>'profissao', '')), '');
  v_sexo text := nullif(p_dados->>'sexo', '');
  v_funcao text := p_dados->>'funcao';
  v_salas uuid[];
  v_cultos uuid[];
  v_termo text;
  v_id uuid;
  v_antiga text;
begin
  -- validações (mensagens curtas: a Edge Function traduz para a tela)
  if v_nome is null or char_length(v_nome) not between 3 and 120 then raise exception 'nome'; end if;
  if v_tel is null then raise exception 'telefone'; end if;
  begin v_nasc := (p_dados->>'nascimento')::date; exception when others then raise exception 'nascimento'; end;
  if v_nasc is null or v_nasc > private.hoje() - interval '12 years' or v_nasc < date '1920-01-01' then
    raise exception 'nascimento';
  end if;
  if v_email is not null and (char_length(v_email) > 120 or v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$') then
    raise exception 'email';
  end if;
  if v_prof is not null and char_length(v_prof) > 80 then raise exception 'profissao'; end if;
  if v_sexo is not null and v_sexo not in ('F', 'M') then raise exception 'sexo'; end if;
  if v_funcao is null or v_funcao not in ('professora', 'auxiliar') then raise exception 'funcao'; end if;
  begin
    select array_agg(x::uuid order by o) into v_salas
      from jsonb_array_elements_text(coalesce(p_dados->'salas', '[]'::jsonb)) with ordinality t(x, o);
    select array_agg(x::uuid order by o) into v_cultos
      from jsonb_array_elements_text(coalesce(p_dados->'cultos', '[]'::jsonb)) with ordinality t(x, o);
  exception when others then raise exception 'preferencias';
  end;
  if coalesce(cardinality(v_salas), 0) not between 1 and 4
     or cardinality(v_salas) <> (select count(distinct s) from unnest(v_salas) s)
     or exists (select 1 from unnest(v_salas) s where not exists (
          select 1 from public.salas x where x.id = s and x.departamento_id = v_dept and x.ativa)) then
    raise exception 'salas';
  end if;
  if coalesce(cardinality(v_cultos), 0) not between 1 and 3
     or cardinality(v_cultos) <> (select count(distinct c) from unnest(v_cultos) c)
     or exists (select 1 from unnest(v_cultos) c where not exists (
          select 1 from public.cultos_recorrentes r where r.id = c and r.ativo)) then
    raise exception 'cultos';
  end if;
  select versao into v_termo from public.termos_voluntaria_versoes where vigente limit 1;
  if v_termo is null or v_termo is distinct from p_dados->>'termo_versao' then raise exception 'termo_desatualizado'; end if;

  -- limite: 30 pedidos a cada 24 h
  delete from private.pedidos_voluntaria_link where criado_em < now() - interval '24 hours';
  if (select count(*) from private.pedidos_voluntaria_link) >= 30 then raise exception 'limite_diario'; end if;
  insert into private.pedidos_voluntaria_link default values;

  -- mesmo telefone com pedido pendente: o novo substitui o antigo
  delete from public.pedidos_voluntaria where telefone = v_tel returning foto_public_id into v_antiga;

  insert into public.pedidos_voluntaria (departamento_id, nome, telefone, data_nascimento, email, profissao, sexo,
                                         funcao, salas_preferidas, cultos_preferidos, termo_versao)
  values (v_dept, v_nome, v_tel, v_nasc, v_email, v_prof, v_sexo::public.sexo_tipo,
          v_funcao::public.funcao_voluntaria, v_salas, v_cultos, v_termo)
  returning id into v_id;

  perform private.avisar_aprovadores_kids('Nova voluntária aguardando aprovação',
    'Um cadastro de voluntária chegou pelo link. Confira e aprove ou recuse.',
    '#/voluntarias-novas', 'voluntaria_nova');

  return jsonb_build_object('pedido_id', v_id, 'foto_antiga', v_antiga);
end $$;

-- Liga a foto ao pedido (só até 30 min depois; só na pasta certa)
create or replace function public.pedido_voluntaria_gravar_foto(p_pedido uuid, p_public_id text) returns text
language plpgsql security definer set search_path to '' as $$
begin
  if p_public_id !~ ('^pessoas/adultos/pedido_' || p_pedido::text || '_[0-9]+$') then raise exception 'foto'; end if;
  update public.pedidos_voluntaria set foto_public_id = p_public_id
   where id = p_pedido and criado_em > now() - interval '30 minutes';
  if not found then raise exception 'foto'; end if;
  return 'ok';
end $$;

-- 6) Liderança -------------------------------------------------------------------------
create or replace function private.pode_aprovar_voluntaria() returns boolean
language sql stable security definer set search_path to '' as $$
  select private.e_lider(private.dept_kids()) $$;

-- Lista de pedidos pendentes, com aviso de telefone já usado (sem telefone de terceiros)
create or replace function public.pedidos_voluntaria_lista() returns jsonb
language plpgsql stable security definer set search_path to '' as $$
begin
  if not private.pode_aprovar_voluntaria() then raise exception 'Sem permissão'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id, 'nome', p.nome, 'telefone', p.telefone, 'nascimento', p.data_nascimento,
      'idade', extract(year from age(private.hoje(), p.data_nascimento))::int,
      'email', p.email, 'profissao', p.profissao, 'sexo', p.sexo, 'funcao', p.funcao,
      'salas', (select coalesce(jsonb_agg(s.nome order by o), '[]'::jsonb)
                  from unnest(p.salas_preferidas) with ordinality u(sid, o) join public.salas s on s.id = u.sid),
      'cultos', (select coalesce(jsonb_agg(r.nome order by o), '[]'::jsonb)
                   from unnest(p.cultos_preferidos) with ordinality u(rid, o) join public.cultos_recorrentes r on r.id = u.rid),
      'tem_foto', p.foto_public_id is not null, 'termo_versao', p.termo_versao, 'criado_em', p.criado_em,
      'mesmo_telefone', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'pessoa_id', x.id, 'nome', x.nome,
                 'voluntaria', exists (select 1 from public.voluntarias v where v.pessoa_id = x.id),
                 'tem_login', exists (select 1 from public.perfis f where f.pessoa_id = x.id))), '[]'::jsonb)
          from public.pessoas x where x.telefone = p.telefone))
      order by p.criado_em)
    from public.pedidos_voluntaria p
    where p.departamento_id = private.dept_kids()
  ), '[]'::jsonb);
end $$;

create or replace function public.contar_pedidos_voluntaria() returns int
language sql stable security definer set search_path to '' as $$
  select case when private.pode_aprovar_voluntaria()
              then (select count(*)::int from public.pedidos_voluntaria where departamento_id = private.dept_kids())
              else 0 end $$;

-- Foto do pedido (pela foto-assinada): só a liderança
create or replace function public.fotos_pedidos_voluntaria(p_ids uuid[])
returns table (id uuid, foto_public_id text)
language sql stable security definer set search_path to '' as $$
  select p.id, p.foto_public_id from public.pedidos_voluntaria p
   where p.id = any (p_ids) and p.foto_public_id is not null and private.pode_aprovar_voluntaria() $$;

-- Aprovar. p_pessoa: pessoa já cadastrada com o mesmo telefone (opcional; senão cria uma nova).
-- Devolve { pessoa_id, voluntaria_id, tem_login, foto_descartar }
create or replace function public.aprovar_pedido_voluntaria(p_pedido uuid, p_pessoa uuid default null) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare
  v public.pedidos_voluntaria%rowtype;
  v_pessoa uuid;
  v_igreja uuid;
  v_perfil uuid;
  v_vol uuid;
  v_descartar text;
  v_foto_atual text;
begin
  if not private.pode_aprovar_voluntaria() then raise exception 'Sem permissão'; end if;
  select * into v from public.pedidos_voluntaria where id = p_pedido for update;
  if not found then raise exception 'Este pedido não existe mais (já foi aprovado ou recusado).'; end if;
  select igreja_id into v_igreja from public.departamentos where id = v.departamento_id;

  if p_pessoa is not null then
    -- reaproveita só quem tem exatamente o mesmo telefone
    select id, foto_public_id into v_pessoa, v_foto_atual from public.pessoas
     where id = p_pessoa and telefone = v.telefone;
    if v_pessoa is null then raise exception 'Essa pessoa não tem o mesmo telefone do pedido.'; end if;
    if exists (select 1 from public.voluntarias where pessoa_id = v_pessoa and departamento_id = v.departamento_id) then
      raise exception 'Essa pessoa já é voluntária do Fonte Kids. Recuse este pedido.';
    end if;
    -- completa só o que estiver vazio (não sobrescreve o cadastro existente)
    update public.pessoas set
      data_nascimento = coalesce(data_nascimento, v.data_nascimento),
      sexo = coalesce(sexo, v.sexo),
      foto_public_id = coalesce(foto_public_id, v.foto_public_id)
     where id = v_pessoa;
    if v_foto_atual is not null then v_descartar := v.foto_public_id; end if;
  else
    if exists (select 1 from public.perfis f join public.pessoas x on x.id = f.pessoa_id where x.telefone = v.telefone) then
      raise exception 'Este telefone já é login de outra pessoa. Use o cadastro existente.';
    end if;
    insert into public.pessoas (igreja_id, nome, telefone, data_nascimento, sexo, foto_public_id)
    values (v_igreja, v.nome, v.telefone, v.data_nascimento, v.sexo, v.foto_public_id)
    returning id into v_pessoa;
  end if;

  insert into public.voluntarias (departamento_id, pessoa_id, email, profissao, funcao, salas_preferidas,
                                  cultos_preferidos, status, aprovada_por, aprovada_em, termo_versao, termo_aceito_em)
  values (v.departamento_id, v_pessoa, v.email, v.profissao, v.funcao, v.salas_preferidas, v.cultos_preferidos,
          'ativa', auth.uid(), now(), v.termo_versao, v.aceito_em)
  returning id into v_vol;

  -- já tem login: ganha o papel de voluntária (o gatilho dá recepção junto)
  select id into v_perfil from public.perfis where pessoa_id = v_pessoa;
  if v_perfil is not null then
    insert into public.papeis_usuario (perfil_id, departamento_id, papel, concedido_por)
    values (v_perfil, v.departamento_id, 'voluntaria', auth.uid())
    on conflict do nothing;
  end if;

  delete from public.pedidos_voluntaria where id = p_pedido;
  return jsonb_build_object('pessoa_id', v_pessoa, 'voluntaria_id', v_vol,
                            'tem_login', v_perfil is not null, 'foto_descartar', v_descartar);
end $$;

-- Recusar: apaga o pedido. Devolve a foto (public_id) para a Edge Function apagar.
create or replace function public.recusar_pedido_voluntaria(p_pedido uuid) returns text
language plpgsql security definer set search_path to '' as $$
declare v_foto text;
begin
  if not private.pode_aprovar_voluntaria() then raise exception 'Sem permissão'; end if;
  delete from public.pedidos_voluntaria where id = p_pedido returning foto_public_id into v_foto;
  if not found then raise exception 'Este pedido não existe mais (já foi aprovado ou recusado).'; end if;
  return coalesce(v_foto, '');
end $$;

-- 7) Permissões --------------------------------------------------------------------------
revoke all on function private.avisar_aprovadores_kids(text, text, text, text) from public, anon, authenticated;
revoke all on function private.pode_aprovar_voluntaria() from public, anon, authenticated;

revoke all on function public.voluntaria_link_opcoes() from public, anon, authenticated;
revoke all on function public.pedido_voluntaria_criar(jsonb) from public, anon, authenticated;
revoke all on function public.pedido_voluntaria_gravar_foto(uuid, text) from public, anon, authenticated;
grant execute on function public.voluntaria_link_opcoes() to service_role;
grant execute on function public.pedido_voluntaria_criar(jsonb) to service_role;
grant execute on function public.pedido_voluntaria_gravar_foto(uuid, text) to service_role;

revoke all on function public.pedidos_voluntaria_lista() from public, anon;
revoke all on function public.contar_pedidos_voluntaria() from public, anon;
revoke all on function public.fotos_pedidos_voluntaria(uuid[]) from public, anon;
revoke all on function public.aprovar_pedido_voluntaria(uuid, uuid) from public, anon;
revoke all on function public.recusar_pedido_voluntaria(uuid) from public, anon;
grant execute on function public.pedidos_voluntaria_lista() to authenticated;
grant execute on function public.contar_pedidos_voluntaria() to authenticated;
grant execute on function public.fotos_pedidos_voluntaria(uuid[]) to authenticated;
grant execute on function public.aprovar_pedido_voluntaria(uuid, uuid) to authenticated;
grant execute on function public.recusar_pedido_voluntaria(uuid) to authenticated;
