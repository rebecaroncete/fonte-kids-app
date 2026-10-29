-- =====================================================================
-- Fase 13 · Aniversariantes do mês (29/10/2026)
--   1. aniversariantes_mes(mes)  só leitura, equipe do Fonte Kids
--      (liderança, recepção, voluntárias) → crianças ATIVAS e voluntárias
--      ATIVAS que fazem aniversário no mês, com o dia (29/02 vira 28/02 em
--      ano comum; recém-nascido do ano fica de fora). Telefones (responsável
--      principal da criança, ou outro com telefone; a própria voluntária) SÓ
--      para liderança e recepção, que já veem as fichas (desde 27/10/2026
--      toda voluntária também tem a recepção): é o botão de parabéns
--      (wa.me, enviado por quem toca; nada sai sozinho).
--      Mensagens prontas nos modelos 'aniversario_crianca' e
--      'aniversario_voluntaria' (mensagens_whatsapp_modelos).
--   2. Aviso do dia: private.avisar_aniversariantes_dia() manda UMA vez por
--      dia (aniversarios_avisados), a partir das 8h de Brasília, o aviso
--      "Hoje tem aniversário no Fonte Kids" para a equipe (público
--      'equipe' do private.destinatarios), menos a própria aniversariante.
--      Na tela bloqueada vai só o título (tipo automático, sem nomes).
--      Roda no keep_alive() diário (agora às 08:17) e, de reserva, quando
--      alguém da equipe abre a tela de aniversariantes.
-- Escrita só por funções security definer; RLS em tudo.
-- Toda alteração com WHERE (a API usa pg_safeupdate).
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Estrutura
-- ---------------------------------------------------------------------
create table if not exists public.aniversarios_avisados (
  dia            date primary key,
  destinatarios  integer not null default 0,
  avisado_em     timestamptz not null default now()
);
alter table public.aniversarios_avisados enable row level security;
revoke all on public.aniversarios_avisados from anon, authenticated;

-- Mensagens prontas (dá para mudar o texto direto na tabela, sem mexer no app)
insert into public.mensagens_whatsapp_modelos (departamento_id, chave, titulo, texto)
select d.id, 'aniversario_crianca', 'Parabéns para a criança (ao responsável)',
       'Olá, {nome_responsavel}! 🎉 Passando para desejar um feliz aniversário para o(a) {nome_crianca}! Que Deus abençoe essa vida linda com muita saúde, alegria e amor. Com carinho, equipe Fonte Kids 💙🎂'
  from public.departamentos d where d.slug = 'kids'
on conflict (departamento_id, chave) do nothing;

insert into public.mensagens_whatsapp_modelos (departamento_id, chave, titulo, texto)
select d.id, 'aniversario_voluntaria', 'Parabéns para a voluntária',
       'Feliz aniversário, {nome_voluntaria}! 🎉 Obrigada por servir com tanto amor no Fonte Kids. Que Deus te abençoe muito neste novo ano de vida! 💙🎂'
  from public.departamentos d where d.slug = 'kids'
on conflict (departamento_id, chave) do nothing;

-- ---------------------------------------------------------------------
-- 2. Ajudantes (privados)
-- ---------------------------------------------------------------------
-- Dia do aniversário num ano (29/02 vira 28/02 em ano comum)
create or replace function private.aniversario_no_ano(p_nasc date, p_ano int) returns date
language sql immutable set search_path to '' as $$
  select case when p_nasc is null then null
              when extract(month from p_nasc) = 2 and extract(day from p_nasc) = 29
                   and not (p_ano % 4 = 0 and (p_ano % 100 <> 0 or p_ano % 400 = 0))
              then make_date(p_ano, 2, 28)
              else make_date(p_ano, extract(month from p_nasc)::int, extract(day from p_nasc)::int) end $$;

-- Crianças ativas do Fonte Kids com aniversário no mês (dia, nome, idade que faz)
create or replace function private.aniv_criancas(p_mes date)
returns table (crianca_id uuid, familia_id uuid, pessoa_id uuid, dia date, nome text, idade int)
language sql stable security definer set search_path = '' as $$
  select c.id, c.familia_id, p.id, a.dia, p.nome,
         extract(year from p_mes)::int - extract(year from p.data_nascimento)::int
    from public.criancas c
    join public.familias f on f.id = c.familia_id and f.departamento_id = private.dept_kids()
    join public.pessoas p on p.id = c.pessoa_id
    cross join lateral (select private.aniversario_no_ano(p.data_nascimento, extract(year from p_mes)::int) dia) a
   where c.ativo and p.data_nascimento is not null
     and extract(year from p.data_nascimento) < extract(year from p_mes)   -- já fez 1 ano
     and date_trunc('month', a.dia) = date_trunc('month', p_mes) $$;

-- Voluntárias ativas do Fonte Kids com aniversário no mês
create or replace function private.aniv_voluntarias(p_mes date)
returns table (voluntaria_id uuid, pessoa_id uuid, dia date, nome text, telefone text)
language sql stable security definer set search_path = '' as $$
  select v.id, p.id, a.dia, p.nome, p.telefone
    from public.voluntarias v
    join public.pessoas p on p.id = v.pessoa_id
    cross join lateral (select private.aniversario_no_ano(p.data_nascimento, extract(year from p_mes)::int) dia) a
   where v.departamento_id = private.dept_kids() and v.status = 'ativa' and p.data_nascimento is not null
     and date_trunc('month', a.dia) = date_trunc('month', p_mes) $$;

-- ---------------------------------------------------------------------
-- 3. Aviso do dia (uma vez por dia, a partir das 8h de Brasília)
-- ---------------------------------------------------------------------
-- p_dia é só para o teste (com p_dia, não confere o horário).
create or replace function private.avisar_aniversariantes_dia(p_dia date default null)
returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_dia date := coalesce(p_dia, private.hoje());
  v_nomes text[]; v_criancas text; v_voluntarias text; v_corpo text; n integer;
begin
  if p_dia is null and (now() at time zone 'America/Sao_Paulo')::time < time '08:00' then return 0; end if;

  select string_agg(private.primeiro_ultimo(x.nome) || ' (' || x.idade || case when x.idade = 1 then ' ano)' else ' anos)' end,
                    ', ' order by x.nome)
    into v_criancas from private.aniv_criancas(v_dia) x where x.dia = v_dia;
  select string_agg(private.primeiro_ultimo(x.nome), ', ' order by x.nome)
    into v_voluntarias from private.aniv_voluntarias(v_dia) x where x.dia = v_dia;
  if v_criancas is null and v_voluntarias is null then return 0; end if;

  insert into public.aniversarios_avisados (dia) values (v_dia) on conflict (dia) do nothing;
  if not found then return 0; end if;

  v_corpo := concat_ws(' · ',
    case when v_criancas is not null then 'Crianças: ' || v_criancas end,
    case when v_voluntarias is not null then 'Voluntárias: ' || v_voluntarias end,
    'Abra para ver os aniversariantes do mês.');

  insert into public.notificacoes (destinatario_id, titulo, corpo, link, tipo, criado_por)
  select d, '🎂 Hoje tem aniversário no Fonte Kids', left(v_corpo, 1000), '#/aniversariantes', 'aniversario', null
    from private.destinatarios('equipe') d
   where d not in (select pf.id from public.perfis pf
                    where pf.pessoa_id in (select x.pessoa_id from private.aniv_voluntarias(v_dia) x where x.dia = v_dia));
  get diagnostics n = row_count;
  update public.aniversarios_avisados set destinatarios = n where dia = v_dia;
  return n;
end $$;

-- ---------------------------------------------------------------------
-- 4. Tela "Aniversariantes" (equipe)
-- ---------------------------------------------------------------------
create or replace function public.aniversariantes_mes(p_mes date default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids();
  v_mes date := date_trunc('month', coalesce(p_mes, private.hoje()))::date;
  v_tel boolean;
begin
  if not private.e_equipe(v_dept) then raise exception 'Sem permissão'; end if;
  v_tel := private.e_recepcao(v_dept);
  perform private.avisar_aniversariantes_dia();   -- reserva, se o keep-alive falhar

  return jsonb_build_object(
    'mes', v_mes,
    'hoje', private.hoje(),
    'pode_whatsapp', v_tel,
    'mensagem_crianca', case when v_tel then (select m.texto from public.mensagens_whatsapp_modelos m
                                               where m.departamento_id = v_dept and m.chave = 'aniversario_crianca') end,
    'mensagem_voluntaria', case when v_tel then (select m.texto from public.mensagens_whatsapp_modelos m
                                                  where m.departamento_id = v_dept and m.chave = 'aniversario_voluntaria') end,
    'criancas', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dia', x.dia, 'nome', private.primeiro_ultimo(x.nome), 'idade', x.idade,
               'responsavel', case when v_tel then (
                 select jsonb_build_object('nome', private.primeiro_ultimo(pr.nome), 'telefone', pr.telefone)
                   from public.responsaveis r join public.pessoas pr on pr.id = r.pessoa_id
                  where r.familia_id = x.familia_id
                    and length(regexp_replace(coalesce(pr.telefone, ''), '\D', '', 'g')) >= 10
                  order by r.principal desc, pr.nome limit 1) end)
             order by x.dia, x.nome)
        from private.aniv_criancas(v_mes) x), '[]'::jsonb),
    'voluntarias', coalesce((
      select jsonb_agg(jsonb_build_object(
               'dia', x.dia, 'nome', private.primeiro_ultimo(x.nome),
               'telefone', case when v_tel then x.telefone end)
             order by x.dia, x.nome)
        from private.aniv_voluntarias(v_mes) x), '[]'::jsonb));
end $$;

-- ---------------------------------------------------------------------
-- 5. keep_alive() também avisa os aniversariantes do dia
-- ---------------------------------------------------------------------
create or replace function public.keep_alive() returns text
language plpgsql security definer set search_path to '' as $$
begin
  perform private.fechar_checkins_vencidos();
  perform private.avisar_relatorio_mes();
  perform private.avisar_aniversariantes_dia();
  return 'ok';
end $$;

-- ---------------------------------------------------------------------
-- Permissões
-- ---------------------------------------------------------------------
revoke all on function private.aniversario_no_ano(date, int) from public, anon, authenticated;
revoke all on function private.aniv_criancas(date) from public, anon, authenticated;
revoke all on function private.aniv_voluntarias(date) from public, anon, authenticated;
revoke all on function private.avisar_aniversariantes_dia(date) from public, anon, authenticated;
revoke all on function public.aniversariantes_mes(date) from public, anon;
grant execute on function public.aniversariantes_mes(date) to authenticated;
revoke all on function public.keep_alive() from public;
grant execute on function public.keep_alive() to anon, authenticated;
