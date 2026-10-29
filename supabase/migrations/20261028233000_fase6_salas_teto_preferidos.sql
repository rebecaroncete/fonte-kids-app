-- =====================================================================
-- Fase 6 · Salas do mês, teto do mês e cultos preferidos (28/10/2026)
-- • Escala do mês: a liderança vê também os cultos cancelados (para
--   reativar) e as salas de cada culto (fechar/juntar) de qualquer data
--   do mês, não só dos próximos 14 dias.
-- • Formulário de indisponibilidade: a voluntária informa quantas vezes
--   pode servir naquele mês (0 = não pode no mês); o motor usa esse teto.
-- • O formulário mostra só os cultos preferidos da voluntária
--   (cultos extras aparecem para todas).
-- Toda alteração com WHERE (a API usa pg_safeupdate).
-- =====================================================================

alter table public.indisponibilidade_respostas
  add column if not exists teto smallint check (teto between 0 and 10);

create or replace function private.esc_preparar(p_escala uuid)
returns void language plpgsql security definer set search_path = '' as $$
declare v_mes date; v_fim date; v_teto int;
begin
  select mes_referencia into v_mes from public.escalas where id = p_escala;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  v_teto := coalesce((private.esc_regra('teto_padrao'))::int, 3);

  drop table if exists pg_temp.esc_vg;
  drop table if exists pg_temp.esc_cand;
  drop table if exists pg_temp.esc_ind;
  create temp table esc_vg (
    id uuid primary key default gen_random_uuid(), culto_id uuid, data date, horario time,
    rec_id uuid, sala_id uuid, salas uuid[], sala_ordem int, idade_min_max int,
    funcao public.funcao_escala, n int, voluntaria_id uuid, cobrindo boolean not null default false,
    n_cand int, esgotada boolean not null default false
  ) on commit drop;
  create temp table esc_cand (
    id uuid primary key, sexo text, pode_liderar boolean, teto int,
    salas_pref uuid[], cultos_pref uuid[], alocadas int not null default 0, dias date[] not null default '{}'
  ) on commit drop;
  create temp table esc_ind (voluntaria_id uuid, culto_id uuid) on commit drop;

  insert into pg_temp.esc_vg (culto_id, data, horario, rec_id, sala_id, salas, sala_ordem, idade_min_max, funcao, n)
  select c.id, c.data, c.horario, c.culto_recorrente_id, g.sala_id, g.salas, g.ordem, g.idade_min_max, f.funcao, gs.n
  from public.cultos c
  join public.departamentos d on d.id = private.dept_kids() and d.igreja_id = c.igreja_id
  cross join lateral private.esc_grupos(c.id) g
  left join public.escala_vagas_culto vc on vc.escala_id = p_escala and vc.culto_id = c.id and vc.sala_id = g.sala_id
  left join public.escala_config_salas cj on cj.escala_id = p_escala and cj.sala_id = g.sala_id and cj.juntas = g.juntas
  left join public.escala_config_salas cs on cs.escala_id = p_escala and cs.sala_id = g.sala_id and not cs.juntas
  cross join lateral (values
    ('professora'::public.funcao_escala, coalesce(vc.qtd_professora, cj.qtd_professora, cs.qtd_professora, 0)),
    ('auxiliar'::public.funcao_escala,   coalesce(vc.qtd_auxiliar,   cj.qtd_auxiliar,   cs.qtd_auxiliar,   0)),
    ('reserva'::public.funcao_escala,    coalesce(vc.qtd_reserva,    cj.qtd_reserva,    cs.qtd_reserva,    0))
  ) as f(funcao, qtd)
  cross join lateral generate_series(1, f.qtd) as gs(n)
  where c.data between v_mes and v_fim and not c.cancelado;

  insert into pg_temp.esc_cand (id, sexo, pode_liderar, teto, salas_pref, cultos_pref)
  select v.id, p.sexo::text, private.esc_pode_liderar(v.id), coalesce(r.teto, v.teto_mensal, v_teto),
         coalesce(v.salas_preferidas, '{}'), coalesce(v.cultos_preferidos, '{}')
  from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id
  left join public.indisponibilidade_respostas r on r.voluntaria_id = v.id and r.mes = v_mes  -- teto que ela deu para o mês
  where v.departamento_id = private.dept_kids() and v.status = 'ativa';

  insert into pg_temp.esc_ind (voluntaria_id, culto_id)
  select i.voluntaria_id, c.id
  from public.indisponibilidades i
  join public.cultos c on c.data = i.data and c.horario = i.horario
  where i.data between v_mes and v_fim;
end $$;

create or replace function public.candidatas_vaga(p_item uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids(); i record; v_teto int; v_fem jsonb; v_lider_m boolean; v_mes date;
begin
  if not private.e_lider(v_dept) then raise exception 'Sem permissão'; end if;
  select ei.*, c.data, c.horario, c.culto_recorrente_id as rec_id
    into i from public.escala_itens ei join public.cultos c on c.id = ei.culto_id where ei.id = p_item;
  if i.id is null then raise exception 'Vaga não encontrada'; end if;
  v_teto := coalesce((private.esc_regra('teto_padrao'))::int, 3);
  select mes_referencia into v_mes from public.escalas where id = i.escala_id;
  return (
    select coalesce(jsonb_agg(x order by jsonb_array_length(x->'avisos'), x->>'nome'), '[]'::jsonb)
    from (
      select jsonb_build_object(
        'voluntaria_id', v.id, 'nome', p.nome, 'funcao', v.funcao,
        'no_mes', aloc.n, 'teto', coalesce(rt.teto, v.teto_mensal, v_teto),
        'avisos', to_jsonb(array_remove(array[
          case when aloc.n >= coalesce(rt.teto, v.teto_mensal, v_teto) then 'max' end,
          case when exists (select 1 from public.escala_itens o join public.cultos oc on oc.id = o.culto_id
                            where o.voluntaria_id = v.id and oc.data = i.data and o.id <> i.id) then 'no_dia' end,
          case when exists (select 1 from public.indisponibilidades d
                            where d.voluntaria_id = v.id and d.data = i.data and d.horario = i.horario) then 'indisponivel' end,
          case when i.sala_id is not null and not (coalesce(v.salas_preferidas, '{}') &&
                 coalesce((select g.salas from private.esc_grupos(i.culto_id) g where g.sala_id = i.sala_id), array[i.sala_id]))
               then 'fora_da_faixa' end,
          case when i.rec_id is not null and not (i.rec_id = any (coalesce(v.cultos_preferidos, '{}'))) then 'fora_do_culto' end,
          case when i.funcao = 'professora' and not private.esc_pode_liderar(v.id) then 'nao_lidera' end
        ], null))) as x
      from public.voluntarias v
      join public.pessoas p on p.id = v.pessoa_id
      left join public.indisponibilidade_respostas rt on rt.voluntaria_id = v.id and rt.mes = v_mes
      cross join lateral (select count(*)::int as n from public.escala_itens o
                          where o.escala_id = i.escala_id and o.voluntaria_id = v.id and o.funcao <> 'lider_culto') aloc
      where v.departamento_id = v_dept and v.status = 'ativa'
    ) z
  );
end $$;

create or replace function public.minha_indisponibilidade(p_mes date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_vol uuid; v_mes date := date_trunc('month', p_mes)::date; v_fim date; v_esc public.escalas;
  v_pref uuid[]; v_teto_vol int; v_teto_mes int;
begin
  select id into v_vol from public.voluntarias
   where id in (select private.minhas_voluntarias()) and departamento_id = private.dept_kids() limit 1;
  if v_vol is null then raise exception 'Sem permissão'; end if;
  if v_mes < date_trunc('month', private.hoje())::date then raise exception 'Esse mês já passou'; end if;
  if v_mes > date_trunc('month', private.hoje())::date + interval '6 months' then raise exception 'Mês muito distante'; end if;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  perform private.esc_garantir_cultos(v_mes);
  select coalesce(v.cultos_preferidos, '{}'), coalesce(v.teto_mensal, (private.esc_regra('teto_padrao'))::int, 3)
    into v_pref, v_teto_vol from public.voluntarias v where v.id = v_vol;
  select r.teto into v_teto_mes from public.indisponibilidade_respostas r where r.voluntaria_id = v_vol and r.mes = v_mes;
  v_esc := private.esc_do_mes(v_mes);
  return jsonb_build_object(
    'mes', v_mes, 'nome_mes', private.esc_nome_mes(v_mes),
    'aberta', v_esc.id is null or v_esc.status = 'rascunho',
    'respondeu', exists (select 1 from public.indisponibilidade_respostas r where r.voluntaria_id = v_vol and r.mes = v_mes),
    'teto', v_teto_mes, 'teto_padrao', v_teto_vol,
    'prazo', v_esc.prazo_indisponibilidade,
    'cultos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'data', c.data, 'horario', to_char(c.horario, 'HH24:MI'), 'hora', private.esc_hora(c.horario),
               'nome', c.nome,
               'indisponivel', exists (select 1 from public.indisponibilidades i
                                       where i.voluntaria_id = v_vol and i.data = c.data and i.horario = c.horario))
             order by c.data, c.horario), '[]'::jsonb)
      from public.cultos c
      join public.departamentos d on d.id = private.dept_kids() and d.igreja_id = c.igreja_id
      where c.data between v_mes and v_fim and not c.cancelado
        -- só os cultos que ela prefere (cultos extras aparecem para todas; sem preferência: todos)
        and (cardinality(v_pref) = 0 or c.culto_recorrente_id is null or c.culto_recorrente_id = any (v_pref))));
end $$;

drop function if exists public.salvar_indisponibilidade(date, uuid[]);
create or replace function public.salvar_indisponibilidade(p_mes date, p_cultos uuid[], p_teto int default null)
returns void language plpgsql security definer set search_path = '' as $$
declare v_vol uuid; v_mes date := date_trunc('month', p_mes)::date; v_fim date; v_esc public.escalas;
begin
  select id into v_vol from public.voluntarias
   where id in (select private.minhas_voluntarias()) and departamento_id = private.dept_kids() limit 1;
  if v_vol is null then raise exception 'Sem permissão'; end if;
  if v_mes < date_trunc('month', private.hoje())::date then raise exception 'Esse mês já passou'; end if;
  if p_teto is not null and p_teto not between 0 and 10 then raise exception 'Escolha de 0 a 10 vezes no mês'; end if;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  v_esc := private.esc_do_mes(v_mes);
  if v_esc.id is not null and v_esc.status <> 'rascunho' then
    raise exception 'A escala de % já foi publicada. Use "Não poderei" na sua vaga.', private.esc_nome_mes(v_mes);
  end if;
  if exists (select 1 from unnest(coalesce(p_cultos, '{}')) x
             where not exists (select 1 from public.cultos c where c.id = x and c.data between v_mes and v_fim)) then
    raise exception 'Culto fora do mês';
  end if;
  delete from public.indisponibilidades where voluntaria_id = v_vol and data between v_mes and v_fim;
  insert into public.indisponibilidades (voluntaria_id, data, horario)
  select distinct v_vol, c.data, c.horario from public.cultos c where c.id = any (coalesce(p_cultos, '{}'));
  insert into public.indisponibilidade_respostas (voluntaria_id, mes, teto) values (v_vol, v_mes, p_teto)
  on conflict (voluntaria_id, mes) do update set respondido_em = now(), teto = excluded.teto;
end $$;

create or replace function public.indisponibilidade_do_mes(p_mes date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_mes date := date_trunc('month', p_mes)::date; v_fim date;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  return (select coalesce(jsonb_agg(jsonb_build_object(
            'voluntaria_id', v.id, 'nome', p.nome,
            'respondeu', exists (select 1 from public.indisponibilidade_respostas r where r.voluntaria_id = v.id and r.mes = v_mes),
            'teto', (select r.teto from public.indisponibilidade_respostas r where r.voluntaria_id = v.id and r.mes = v_mes),
            'cultos', (select count(*) from public.indisponibilidades i where i.voluntaria_id = v.id and i.data between v_mes and v_fim))
          order by p.nome), '[]'::jsonb)
          from public.voluntarias v join public.pessoas p on p.id = v.pessoa_id
          where v.departamento_id = private.dept_kids() and v.status = 'ativa');
end $$;

create or replace function public.escala_do_mes(p_mes date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_dept uuid := private.dept_kids(); v_mes date := date_trunc('month', p_mes)::date;
  v_fim date; v_lider boolean; v_esc public.escalas; v_minhas uuid[];
begin
  v_lider := private.e_lider(v_dept);
  if not (v_lider or private.e_equipe(v_dept)) then raise exception 'Sem permissão'; end if;
  v_fim := (v_mes + interval '1 month' - interval '1 day')::date;
  v_esc := private.esc_do_mes(v_mes);
  v_minhas := array(select private.minhas_voluntarias());
  if v_esc.id is null or (v_esc.status = 'rascunho' and not v_lider) then
    return jsonb_build_object('mes', v_mes, 'nome_mes', private.esc_nome_mes(v_mes), 'escala', null, 'pode_editar', v_lider);
  end if;

  return jsonb_build_object(
    'mes', v_mes, 'nome_mes', private.esc_nome_mes(v_mes), 'pode_editar', v_lider,
    'escala', jsonb_build_object('id', v_esc.id, 'status', v_esc.status, 'publicada_em', v_esc.publicada_em,
                  'prazo_indisponibilidade', v_esc.prazo_indisponibilidade, 'indisponibilidade_pedida_em', v_esc.indisponibilidade_pedida_em),
    'config', case when v_lider then (
       select coalesce(jsonb_agg(jsonb_build_object('sala_id', c.sala_id, 'sala', s.nome, 'juntas', c.juntas,
                 'professora', c.qtd_professora, 'auxiliar', c.qtd_auxiliar, 'reserva', c.qtd_reserva)
               order by s.ordem, c.juntas), '[]'::jsonb)
       from public.escala_config_salas c join public.salas s on s.id = c.sala_id where c.escala_id = v_esc.id) end,
    'ajustes', case when v_lider then (
       select coalesce(jsonb_agg(jsonb_build_object('culto_id', a.culto_id, 'sala_id', a.sala_id,
                 'professora', a.qtd_professora, 'auxiliar', a.qtd_auxiliar, 'reserva', a.qtd_reserva)), '[]'::jsonb)
       from public.escala_vagas_culto a where a.escala_id = v_esc.id) end,
    'cultos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', c.id, 'data', c.data, 'horario', to_char(c.horario, 'HH24:MI'), 'hora', private.esc_hora(c.horario),
               'nome', c.nome, 'cancelado', c.cancelado, 'extra', c.culto_recorrente_id is null,
               'personalizado', c.salas_personalizadas,
               'grupos', case when v_lider then private.salas_do_culto_json(c.id, c.culto_recorrente_id, false) end,
               'salas', (select coalesce(jsonb_agg(jsonb_build_object('sala_id', g.sala_id, 'nome', g.nome) order by g.ordem), '[]'::jsonb)
                         from private.esc_grupos(c.id) g),
               'itens', (
                 select coalesce(jsonb_agg(jsonb_build_object(
                          'id', i.id, 'sala_id', i.sala_id, 'sala', case when i.sala_id is null then 'Geral' else private.esc_nome_sala(c.id, i.sala_id) end,
                          'funcao', i.funcao, 'voluntaria_id', i.voluntaria_id, 'nome', coalesce(p.nome, i.nome_livre),
                          'nome_livre', i.nome_livre is not null, 'resposta', i.resposta,
                          'cobrindo_lider', i.cobrindo_lider, 'minha', i.voluntaria_id = any (v_minhas))
                        order by i.sala_id is null, s.ordem nulls last,
                                 case i.funcao when 'professora' then 1 when 'auxiliar' then 2 when 'reserva' then 3 else 4 end,
                                 i.criado_em, i.id), '[]'::jsonb)
                 from public.escala_itens i
                 left join public.salas s on s.id = i.sala_id
                 left join public.voluntarias v on v.id = i.voluntaria_id
                 left join public.pessoas p on p.id = v.pessoa_id
                 where i.escala_id = v_esc.id and i.culto_id = c.id))
             order by c.data, c.horario), '[]'::jsonb)
      from public.cultos c
      where c.data between v_mes and v_fim
        and (exists (select 1 from public.escala_itens i where i.escala_id = v_esc.id and i.culto_id = c.id)
             or (v_lider and v_esc.status = 'rascunho'
                 and c.igreja_id = (select igreja_id from public.departamentos where id = v_dept)))),
    'resumo', (select jsonb_build_object(
                 'vagas', count(*) filter (where funcao <> 'lider_culto'),
                 'vazias', count(*) filter (where funcao <> 'lider_culto' and voluntaria_id is null and nome_livre is null),
                 'cientes', count(*) filter (where resposta = 'ciente'),
                 'lider_culto_vazias', count(*) filter (where funcao = 'lider_culto' and voluntaria_id is null and nome_livre is null))
               from public.escala_itens where escala_id = v_esc.id),
    'indisponibilidade', case when v_lider then (
       select jsonb_build_object('ativas', count(*), 'responderam',
                count(*) filter (where exists (select 1 from public.indisponibilidade_respostas r
                                                where r.voluntaria_id = v.id and r.mes = v_mes)),
                'marcaram', count(*) filter (where exists (select 1 from public.indisponibilidades i
                                                where i.voluntaria_id = v.id and i.data between v_mes and v_fim)
                                       or exists (select 1 from public.indisponibilidade_respostas r
                                                where r.voluntaria_id = v.id and r.mes = v_mes and r.teto is not null)))
       from public.voluntarias v where v.departamento_id = v_dept and v.status = 'ativa') end
  );
end $$;

revoke all on function private.esc_preparar(uuid) from public, anon, authenticated;
revoke all on function public.salvar_indisponibilidade(date, uuid[], integer) from public, anon;
grant execute on function public.salvar_indisponibilidade(date, uuid[], integer) to authenticated;
do $$
declare f text;
begin
  foreach f in array array['public.candidatas_vaga(uuid)', 'public.minha_indisponibilidade(date)',
                           'public.indisponibilidade_do_mes(date)', 'public.escala_do_mes(date)'] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;
