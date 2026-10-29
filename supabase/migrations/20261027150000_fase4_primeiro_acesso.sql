-- =====================================================================
-- Fase 4 · Etapa 4 – 1º acesso do responsável (só banco)
-- Decisões (Rebeca, 27/10/2026):
--   a) O termo LGPD é aceito por CADA responsável, no próprio login.
--   b) Os aceites vindos da planilha (versão "legado-planilha") ficam
--      guardados como histórico; todo responsável aceita a v1 uma vez.
--   c) Até aceitar a v1, o responsável não vê dado nenhum (como na troca
--      de senha). Quem não aceitar fica sem acesso; o check-in pela
--      recepção continua normal. Não existe "recusar": quem não concorda
--      fala com a liderança (exclusão por família, se quiser sair).
--   d) Relação não informada é só AVISO (pendência); não bloqueia check-in.
-- Ordem do 1º acesso: trocar a senha → aceitar o termo v1 → informar a
-- relação com cada criança. estado_primeiro_acesso() diz ao app em que
-- passo a pessoa está.
-- Pendências: as automáticas abrem e somem sozinhas; as manuais (vindas
-- da importação) somem quando o dado é corrigido ou quando a família
-- confirma que está certo.
-- =====================================================================

-- ---------------------------------------------------------------
-- 1. Versões do termo LGPD
-- ---------------------------------------------------------------
create table public.termos_lgpd_versoes (
  id            uuid primary key default gen_random_uuid(),   -- a auditoria usa "id"
  versao        text not null unique check (char_length(versao) between 1 and 20),
  texto         text not null check (char_length(texto) between 50 and 20000),
  vigente       boolean not null default false,
  publicado_em  timestamptz not null default now()
);
comment on table public.termos_lgpd_versoes is
  'Textos do termo LGPD. Só uma versão vigente. Mudar de versão faz todos os responsáveis aceitarem de novo.';
create unique index termos_versoes_uma_vigente on public.termos_lgpd_versoes (vigente) where vigente;

alter table public.termos_lgpd_versoes enable row level security;
-- leitura liberada a qualquer login (inclusive quem ainda não aceitou: precisa ler para aceitar)
create policy termos_versoes_ler on public.termos_lgpd_versoes for select to authenticated using (true);
create policy termos_versoes_admin on public.termos_lgpd_versoes for all to authenticated
  using ((select private.e_admin())) with check ((select private.e_admin()));
revoke all on public.termos_lgpd_versoes from anon;
grant select, insert, update, delete on public.termos_lgpd_versoes to authenticated;
create trigger termos_versoes_auditoria after insert or update or delete on public.termos_lgpd_versoes
  for each row execute function private.auditar();

insert into public.termos_lgpd_versoes (versao, vigente, texto) values ('v1', true, $termo$
TERMO DE CONSENTIMENTO PARA TRATAMENTO DE DADOS PESSOAIS – FONTE KIDS (versão 1)

Este termo segue a Lei Geral de Proteção de Dados (Lei 13.709/2018). Por envolver dados de crianças, o tratamento depende do consentimento de pelo menos um dos pais ou do responsável legal (art. 14).

1. Quem trata os dados
A igreja, por meio do ministério infantil Fonte Kids, é responsável pelos dados cadastrados neste aplicativo.

2. Quais dados
- Da criança: nome, data de nascimento, sexo, foto, alergias e observações de cuidado, sala e registros de entrada e saída nos cultos (check-in e check-out).
- Dos responsáveis e pessoas autorizadas a buscar a criança: nome, telefone, foto (quando houver) e a relação de cada um com a criança (mãe, pai, avó, tio etc.).

3. Para que usamos
- Garantir a segurança da criança: identificar quem entrega e quem busca, com código de segurança.
- Organizar as salas, a escala de voluntárias, os avisos e o contato com a família (inclusive por WhatsApp).
- Lembrar aniversários e registrar a participação nos cultos e eventos.
Não vendemos nem compartilhamos os dados com empresas para fins comerciais.

4. Quem pode ver
- Os responsáveis veem só os dados da própria família.
- A recepção e a liderança do Fonte Kids veem o cadastro da família.
- A voluntária vê as crianças da sala em que está escalada, e o contato dos responsáveis só no dia do culto.
- Pastores e líderes de qualquer departamento da igreja podem consultar as relações familiares (por exemplo, quem é mãe ou pai de quem), para cuidar das famílias de forma integrada entre os ministérios.
- As fotos ficam guardadas de forma privada e só aparecem, por poucos minutos, para quem tem permissão.

5. Onde ficam guardados
Em serviços de computação em nuvem contratados pela igreja, com acesso protegido por senha, cópias de segurança criptografadas e registro de alterações.

6. Por quanto tempo
Enquanto a família participar do Fonte Kids. Se a família pedir para sair, o cadastro, o histórico e as fotos são apagados, exceto o que a lei exigir guardar.

7. Seus direitos
Você pode, a qualquer momento: ver os dados da sua família, corrigir o que estiver errado, pedir uma cópia dos dados, retirar este consentimento e pedir a exclusão do cadastro. Para isso, fale com a liderança do Fonte Kids.

Ao tocar em "Aceito", declaro que sou responsável pela(s) criança(s) da minha família, que li este termo e que concordo com o tratamento dos dados descrito acima.
$termo$);

-- Aceite registrado por quem está logado (ninguém registra aceite em nome de outro login)
create function private.trava_termos()
returns trigger language plpgsql set search_path = '' as $$
begin
  if private.chamada_do_app() then
    new.aceito_por_perfil := auth.uid();
    new.aceito_em := now();
  end if;
  return new;
end $$;
create trigger termos_trava before insert on public.termos_lgpd
  for each row execute function private.trava_termos();

-- ---------------------------------------------------------------
-- 2. Bloqueio até aceitar o termo vigente
-- ---------------------------------------------------------------
-- Em dia = não é responsável, ou aceitou a versão vigente em TODAS as
-- famílias em que é responsável (no próprio login).
create function private.termo_em_dia(p_perfil uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (
    select 1
    from public.perfis p
    join public.responsaveis r on r.pessoa_id = p.pessoa_id
    cross join (select versao from public.termos_lgpd_versoes where vigente) v
    where p.id = p_perfil
      and not exists (select 1 from public.termos_lgpd t
                      where t.familia_id = r.familia_id
                        and t.aceito_por_perfil = p_perfil
                        and t.versao = v.versao)) $$;

-- Login liberado = ativo + senha inicial trocada + termo em dia
create function private.perfil_liberado() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.perfis p
                 where p.id = (select auth.uid()) and p.ativo and not p.troca_senha_obrigatoria)
     and private.termo_em_dia((select auth.uid())) $$;

-- As funções de acesso passam a usar perfil_liberado()
create or replace function private.sessao_liberada() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.perfil_liberado() $$;

create or replace function private.tem_papel_global(p_papeis public.papel_tipo[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.papeis_usuario pu
                 where pu.perfil_id = (select auth.uid()) and pu.papel = any (p_papeis))
     and private.perfil_liberado() $$;

create or replace function private.tem_papel_dept(p_papeis public.papel_tipo[], p_dept uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.papeis_usuario pu
                 where pu.perfil_id = (select auth.uid())
                   and pu.departamento_id = p_dept and pu.papel = any (p_papeis))
     and private.perfil_liberado() $$;

create or replace function private.e_lider_algum() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.e_pastor_ou_admin()
      or (exists (select 1 from public.papeis_usuario pu
                  where pu.perfil_id = (select auth.uid()) and pu.papel = 'lider')
          and private.perfil_liberado()) $$;

create or replace function private.tem_algum_papel() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.papeis_usuario pu where pu.perfil_id = (select auth.uid()))
     and private.perfil_liberado() $$;

create or replace function private.minha_pessoa() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.pessoa_id from public.perfis p
  where p.id = (select auth.uid())
    and exists (select 1 from public.papeis_usuario pu where pu.perfil_id = p.id)
    and private.perfil_liberado() $$;

create or replace function private.minha_igreja() returns uuid
language sql stable security definer set search_path = '' as $$
  select p.igreja_id from public.perfis p
  where p.id = (select auth.uid()) and private.perfil_liberado() $$;

-- ---------------------------------------------------------------
-- 3. Pendências automáticas
-- ---------------------------------------------------------------
-- tipos automáticos (abrem e somem sozinhos):
--   relacao_nao_informada .. algum responsável da criança sem relação gravada com ela
--   nascimento_vazio ....... criança sem data de nascimento
-- tipos manuais (importação/recepção): somem quando o dado é corrigido
--   (conferir_nascimento, nome_responsavel) ou pela confirmar_pendencia().
create unique index pendencias_automaticas_uk on public.pendencias_cadastro (crianca_id, tipo)
  where resolvida_em is null and tipo in ('relacao_nao_informada', 'nascimento_vazio');

-- A criança tem algum responsável sem relação gravada com ela?
create function private.falta_relacao(p_crianca uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1
    from public.criancas c
    join public.responsaveis_criancas rc on rc.crianca_id = c.id
    join public.responsaveis r on r.id = rc.responsavel_id
    where c.id = p_crianca
      and not exists (select 1 from public.relacoes_pessoas x
                      where (x.pessoa_id = r.pessoa_id and x.relacionada_id = c.pessoa_id)
                         or (x.pessoa_id = c.pessoa_id and x.relacionada_id = r.pessoa_id))) $$;

create function private.atualizar_pendencias(p_familia uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_familia is null then return; end if;

  -- abre o que falta
  insert into public.pendencias_cadastro (familia_id, crianca_id, tipo, mensagem)
  select c.familia_id, c.id, 'relacao_nao_informada',
         'Falta informar a relação de um responsável com esta criança (ex.: mãe, pai, avó).'
  from public.criancas c
  where c.familia_id = p_familia and c.ativo and private.falta_relacao(c.id)
    and not exists (select 1 from public.pendencias_cadastro p
                    where p.crianca_id = c.id and p.tipo = 'relacao_nao_informada' and p.resolvida_em is null);

  insert into public.pendencias_cadastro (familia_id, crianca_id, tipo, mensagem)
  select c.familia_id, c.id, 'nascimento_vazio', 'Falta a data de nascimento desta criança.'
  from public.criancas c join public.pessoas pe on pe.id = c.pessoa_id
  where c.familia_id = p_familia and c.ativo and pe.data_nascimento is null
    and not exists (select 1 from public.pendencias_cadastro p
                    where p.crianca_id = c.id and p.tipo = 'nascimento_vazio' and p.resolvida_em is null);

  -- fecha o que já foi corrigido (ou a criança saiu da família / ficou inativa)
  update public.pendencias_cadastro p
     set resolvida_em = now(), resolvida_por = auth.uid()
   where p.familia_id = p_familia and p.resolvida_em is null
     and p.tipo = 'relacao_nao_informada'
     and not exists (select 1 from public.criancas c
                     where c.id = p.crianca_id and c.familia_id = p_familia and c.ativo
                       and private.falta_relacao(c.id));

  update public.pendencias_cadastro p
     set resolvida_em = now(), resolvida_por = auth.uid()
   where p.familia_id = p_familia and p.resolvida_em is null
     and p.tipo = 'nascimento_vazio'
     and not exists (select 1 from public.criancas c join public.pessoas pe on pe.id = c.pessoa_id
                     where c.id = p.crianca_id and c.familia_id = p_familia and c.ativo
                       and pe.data_nascimento is null);
end $$;

-- Gatilhos que recalculam
create function private.pendencias_por_relacao()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_ids uuid[]; f uuid;
begin
  if tg_op in ('INSERT', 'UPDATE') then v_ids := array[new.pessoa_id, new.relacionada_id]; end if;
  if tg_op in ('DELETE', 'UPDATE') then v_ids := coalesce(v_ids, '{}') || array[old.pessoa_id, old.relacionada_id]; end if;
  for f in select distinct c.familia_id from public.criancas c where c.pessoa_id = any (v_ids) loop
    perform private.atualizar_pendencias(f);
  end loop;
  return null;
end $$;
create trigger relacoes_pendencias after insert or update or delete on public.relacoes_pessoas
  for each row execute function private.pendencias_por_relacao();

create function private.pendencias_por_vinculo()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_ids uuid[]; f uuid;
begin
  if tg_op in ('INSERT', 'UPDATE') then v_ids := array[new.crianca_id]; end if;
  if tg_op in ('DELETE', 'UPDATE') then v_ids := coalesce(v_ids, '{}') || old.crianca_id; end if;
  for f in select distinct c.familia_id from public.criancas c where c.id = any (v_ids) loop
    perform private.atualizar_pendencias(f);
  end loop;
  return null;
end $$;
create trigger responsaveis_criancas_pendencias after insert or update or delete on public.responsaveis_criancas
  for each row execute function private.pendencias_por_vinculo();

create function private.pendencias_por_crianca()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  perform private.atualizar_pendencias(new.familia_id);
  if tg_op = 'UPDATE' and old.familia_id is distinct from new.familia_id then
    perform private.atualizar_pendencias(old.familia_id);
  end if;
  return null;
end $$;
create trigger criancas_pendencias after insert or update of ativo, familia_id, pessoa_id on public.criancas
  for each row execute function private.pendencias_por_crianca();

create function private.pendencias_por_pessoa()
returns trigger language plpgsql security definer set search_path = '' as $$
declare f uuid;
begin
  if new.data_nascimento is distinct from old.data_nascimento then
    update public.pendencias_cadastro p
       set resolvida_em = now(), resolvida_por = auth.uid()
     where p.tipo = 'conferir_nascimento' and p.resolvida_em is null
       and p.crianca_id in (select c.id from public.criancas c where c.pessoa_id = new.id);
    for f in select distinct c.familia_id from public.criancas c where c.pessoa_id = new.id loop
      perform private.atualizar_pendencias(f);
    end loop;
  end if;
  if new.nome is distinct from old.nome then
    update public.pendencias_cadastro p
       set resolvida_em = now(), resolvida_por = auth.uid()
     where p.tipo = 'nome_responsavel' and p.resolvida_em is null
       and p.familia_id in (select r.familia_id from public.responsaveis r where r.pessoa_id = new.id);
  end if;
  return null;
end $$;
create trigger pessoas_pendencias after update of data_nascimento, nome on public.pessoas
  for each row execute function private.pendencias_por_pessoa();

-- Pendências: a família não edita direto (usa confirmar_pendencia); recepção/liderança sim
drop policy pend_resolver on public.pendencias_cadastro;
create policy pend_editar on public.pendencias_cadastro for update to authenticated
  using (private.e_recepcao(private.dept_familia(familia_id)))
  with check (private.e_recepcao(private.dept_familia(familia_id)));

-- ---------------------------------------------------------------
-- 4. Relação informada pelo responsável
-- ---------------------------------------------------------------
alter table public.relacoes_pessoas drop constraint relacoes_pessoas_origem_check;
alter table public.relacoes_pessoas add constraint relacoes_pessoas_origem_check
  check (origem in ('app', 'lideranca', 'legado', 'responsavel'));

-- ---------------------------------------------------------------
-- 5. Funções para o app (respostas sem dados pessoais)
-- ---------------------------------------------------------------
-- Em que passo do 1º acesso a pessoa está
create function public.estado_primeiro_acesso() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_perfil public.perfis%rowtype;
  v_termo_ok boolean;
  v_liberado boolean;
  v_criancas uuid[] := '{}';
  v_pend int := 0;
begin
  select * into v_perfil from public.perfis where id = v_uid;
  if not found or not v_perfil.ativo then
    return jsonb_build_object('etapa', 'sem_acesso');
  end if;
  v_termo_ok := private.termo_em_dia(v_uid);
  v_liberado := not v_perfil.troca_senha_obrigatoria and v_termo_ok;

  if v_liberado and v_perfil.pessoa_id is not null then
    select coalesce(array_agg(distinct c.id), '{}') into v_criancas
    from public.responsaveis r
    join public.responsaveis_criancas rc on rc.responsavel_id = r.id
    join public.criancas c on c.id = rc.crianca_id and c.ativo
    where r.pessoa_id = v_perfil.pessoa_id
      and not exists (select 1 from public.relacoes_pessoas x
                      where (x.pessoa_id = r.pessoa_id and x.relacionada_id = c.pessoa_id)
                         or (x.pessoa_id = c.pessoa_id and x.relacionada_id = r.pessoa_id));
    select count(*) into v_pend from public.pendencias_cadastro p
    where p.resolvida_em is null
      and p.familia_id in (select r.familia_id from public.responsaveis r where r.pessoa_id = v_perfil.pessoa_id);
  end if;

  return jsonb_build_object(
    'etapa', case when v_perfil.troca_senha_obrigatoria then 'trocar_senha'
                  when not v_termo_ok then 'aceitar_termo'
                  when cardinality(v_criancas) > 0 then 'informar_relacoes'
                  else 'pronto' end,
    'termo_versao', case when not v_termo_ok then
                      (select versao from public.termos_lgpd_versoes where vigente) end,
    'criancas_sem_relacao', to_jsonb(v_criancas),
    'pendencias_abertas', v_pend);
end $$;

-- Aceite do termo vigente (um registro por família em que a pessoa é responsável)
create function public.aceitar_termo_lgpd(p_versao text) returns text
language plpgsql security definer set search_path = '' as $$
declare v_perfil public.perfis%rowtype; v_vigente text;
begin
  select * into v_perfil from public.perfis where id = auth.uid();
  if not found or not v_perfil.ativo then raise exception 'Login inativo'; end if;
  if v_perfil.troca_senha_obrigatoria then raise exception 'Troque a senha inicial antes de continuar'; end if;
  select versao into v_vigente from public.termos_lgpd_versoes where vigente;
  if v_vigente is null or p_versao is distinct from v_vigente then
    raise exception 'Versão do termo desatualizada: recarregue o aplicativo';
  end if;
  if not exists (select 1 from public.responsaveis r where r.pessoa_id = v_perfil.pessoa_id) then
    raise exception 'O termo é aceito pelos responsáveis das crianças';
  end if;
  insert into public.termos_lgpd (familia_id, versao, aceito_por_nome, aceito_por_perfil, aceito_em)
  select r.familia_id, v_vigente, pe.nome, v_perfil.id, now()
  from public.responsaveis r join public.pessoas pe on pe.id = r.pessoa_id
  where r.pessoa_id = v_perfil.pessoa_id
    and not exists (select 1 from public.termos_lgpd t
                    where t.familia_id = r.familia_id and t.aceito_por_perfil = v_perfil.id
                      and t.versao = v_vigente);
  return 'termo aceito';
end $$;

-- Responsável informa a relação dele com uma criança da família
create function public.informar_relacao(p_crianca uuid, p_tipo public.relacao_tipo, p_detalhe text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := private.minha_pessoa(); v_cri uuid; v_rel uuid;
begin
  if v_eu is null then
    raise exception 'Conclua o primeiro acesso (senha e termo) antes de continuar';
  end if;
  select c.pessoa_id into v_cri
  from public.criancas c
  join public.responsaveis_criancas rc on rc.crianca_id = c.id
  join public.responsaveis r on r.id = rc.responsavel_id
  where c.id = p_crianca and r.pessoa_id = v_eu
  limit 1;
  if v_cri is null then raise exception 'Criança não encontrada ou sem permissão'; end if;
  if p_tipo is null or p_tipo = 'conjuge' then raise exception 'Tipo de relação inválido para uma criança'; end if;
  if p_tipo = 'outro' and btrim(coalesce(p_detalhe, '')) = '' then
    raise exception 'Descreva a relação (ex.: madrinha)';
  end if;

  -- uma relação só entre os dois: atualiza a que existir (sem reabrir pendência)
  select id into v_rel from public.relacoes_pessoas
  where (pessoa_id = v_eu and relacionada_id = v_cri) or (pessoa_id = v_cri and relacionada_id = v_eu)
  order by criado_em limit 1;
  if v_rel is null then
    insert into public.relacoes_pessoas (pessoa_id, relacionada_id, tipo, detalhe, origem, informado_por)
    values (v_eu, v_cri, p_tipo, nullif(btrim(p_detalhe), ''), 'responsavel', auth.uid());
  else
    delete from public.relacoes_pessoas
    where id <> v_rel
      and ((pessoa_id = v_eu and relacionada_id = v_cri) or (pessoa_id = v_cri and relacionada_id = v_eu));
    update public.relacoes_pessoas
       set pessoa_id = v_eu, relacionada_id = v_cri, tipo = p_tipo,
           detalhe = nullif(btrim(p_detalhe), ''), origem = 'responsavel', informado_por = auth.uid()
     where id = v_rel;
  end if;
  return 'relação registrada';
end $$;

-- Família (ou recepção) confirma que um dado apontado na importação está certo
create function public.confirmar_pendencia(p_pendencia uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare v public.pendencias_cadastro%rowtype;
begin
  select * into v from public.pendencias_cadastro where id = p_pendencia and resolvida_em is null;
  if not found or not (v.familia_id in (select private.minhas_familias())
                       or private.e_recepcao(private.dept_familia(v.familia_id))) then
    raise exception 'Pendência não encontrada ou sem permissão';
  end if;
  if v.tipo in ('relacao_nao_informada', 'nascimento_vazio') then
    raise exception 'Este aviso some sozinho quando o dado for preenchido';
  end if;
  update public.pendencias_cadastro set resolvida_em = now(), resolvida_por = auth.uid() where id = p_pendencia;
  return 'pendência resolvida';
end $$;

-- ---------------------------------------------------------------
-- 6. Permissões
-- ---------------------------------------------------------------
revoke all on function private.trava_termos(), private.termo_em_dia(uuid), private.perfil_liberado(),
                       private.falta_relacao(uuid), private.atualizar_pendencias(uuid),
                       private.pendencias_por_relacao(), private.pendencias_por_vinculo(),
                       private.pendencias_por_crianca(), private.pendencias_por_pessoa()
  from public, anon;
grant execute on function private.termo_em_dia(uuid), private.perfil_liberado(), private.falta_relacao(uuid)
  to authenticated;   -- usadas dentro das regras de acesso
revoke all on function private.atualizar_pendencias(uuid) from authenticated;

revoke all on function public.estado_primeiro_acesso(), public.aceitar_termo_lgpd(text),
                       public.informar_relacao(uuid, public.relacao_tipo, text),
                       public.confirmar_pendencia(uuid) from public, anon;
grant execute on function public.estado_primeiro_acesso(), public.aceitar_termo_lgpd(text),
                          public.informar_relacao(uuid, public.relacao_tipo, text),
                          public.confirmar_pendencia(uuid) to authenticated;

-- ---------------------------------------------------------------
-- 7. Pendências automáticas dos cadastros que já existem
-- ---------------------------------------------------------------
select private.atualizar_pendencias(f.id) from public.familias f;
