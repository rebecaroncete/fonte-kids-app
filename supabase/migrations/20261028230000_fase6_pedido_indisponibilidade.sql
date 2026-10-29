-- =====================================================================
-- Fase 6 · Pedido de indisponibilidade (28/10/2026)
-- A líder configura as vagas do mês, define o prazo e pede a
-- indisponibilidade: todas as voluntárias ativas recebem o aviso no app.
-- Só precisa responder quem tiver algum culto em que não pode servir.
-- O prazo é por mês (muda a cada escala) e pode ser alterado.
-- Toda alteração com WHERE (a API usa pg_safeupdate).
-- =====================================================================

alter table public.escalas
  add column if not exists prazo_indisponibilidade date,
  add column if not exists indisponibilidade_pedida_em timestamptz;

-- define o prazo do mês e (p_avisar) avisa todas as voluntárias ativas; devolve quantas foram avisadas
create or replace function public.pedir_indisponibilidade(p_mes date, p_prazo date, p_avisar boolean default true)
returns integer language plpgsql security definer set search_path = '' as $$
declare v_esc public.escalas; v_fim date; v record; n int := 0; v_nome text;
begin
  if not private.e_lider(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  v_esc := private.esc_do_mes(p_mes);
  if v_esc.id is null then raise exception 'Comece a escala do mês primeiro'; end if;
  if v_esc.status <> 'rascunho' then raise exception 'A escala de % já foi publicada', private.esc_nome_mes(v_esc.mes_referencia); end if;
  v_fim := (v_esc.mes_referencia + interval '1 month' - interval '1 day')::date;
  if p_prazo is null or p_prazo < private.hoje() then raise exception 'Escolha um prazo a partir de hoje'; end if;
  if p_prazo > v_fim then raise exception 'O prazo precisa ser até o fim do mês da escala'; end if;

  update public.escalas
     set prazo_indisponibilidade = p_prazo,
         indisponibilidade_pedida_em = coalesce(indisponibilidade_pedida_em, now())
   where id = v_esc.id;

  if p_avisar then
    v_nome := private.esc_nome_mes(v_esc.mes_referencia);
    for v in select vo.id from public.voluntarias vo
             where vo.departamento_id = private.dept_kids() and vo.status = 'ativa' loop
      perform private.avisar_voluntaria(v.id, 'Indisponibilidade de ' || v_nome,
        'Tem algum culto de ' || v_nome || ' em que você não pode servir? Marque até '
          || to_char(p_prazo, 'DD/MM') || ' em "Minha escala". Se puder em todos, não precisa fazer nada.',
        '#/minha-escala', 'escala');
      n := n + 1;
    end loop;
  end if;
  return n;
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
               'nome', c.nome, 'cancelado', c.cancelado,
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
             or (v_lider and v_esc.status = 'rascunho' and not c.cancelado
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
                                                where i.voluntaria_id = v.id and i.data between v_mes and v_fim)))
       from public.voluntarias v where v.departamento_id = v_dept and v.status = 'ativa') end
  );
end $$;

create or replace function public.minha_escala()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_vols uuid[] := array(select private.minhas_voluntarias()); v_prox date; v_resp boolean; v_lim jsonb;
  v_esc_prox public.escalas;
begin
  if cardinality(v_vols) = 0 then raise exception 'Sem permissão'; end if;
  v_prox := (date_trunc('month', private.hoje()) + interval '1 month')::date;
  v_esc_prox := private.esc_do_mes(v_prox);
  v_resp := exists (select 1 from public.indisponibilidade_respostas r where r.voluntaria_id = any (v_vols) and r.mes = v_prox);
  v_lim := private.esc_regra('dia_limite_indisponibilidade');
  return jsonb_build_object(
    'minhas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', i.id, 'culto_id', c.id, 'data', c.data, 'horario', to_char(c.horario, 'HH24:MI'), 'hora', private.esc_hora(c.horario),
               'culto', c.nome, 'cancelado', c.cancelado, 'funcao', i.funcao, 'cobrindo_lider', i.cobrindo_lider,
               'sala', case when i.sala_id is null then 'Líder do culto' else private.esc_nome_sala(c.id, i.sala_id) end,
               'resposta', i.resposta,
               'colegas', (select coalesce(jsonb_agg(jsonb_build_object('nome', coalesce(p.nome, o.nome_livre), 'funcao', o.funcao)
                                   order by o.funcao, coalesce(p.nome, o.nome_livre)), '[]'::jsonb)
                           from public.escala_itens o
                           left join public.voluntarias ov on ov.id = o.voluntaria_id
                           left join public.pessoas p on p.id = ov.pessoa_id
                           where o.culto_id = i.culto_id and o.id <> i.id
                             and (o.sala_id = i.sala_id or o.funcao = 'lider_culto')
                             and (o.voluntaria_id is not null or o.nome_livre is not null)))
             order by c.data, c.horario), '[]'::jsonb)
      from public.escala_itens i
      join public.escalas e on e.id = i.escala_id and e.status = 'publicada'
      join public.cultos c on c.id = i.culto_id
      where i.voluntaria_id = any (v_vols) and c.data >= private.hoje()),
    'abertas', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'id', i.id, 'data', c.data, 'horario', to_char(c.horario, 'HH24:MI'), 'hora', private.esc_hora(c.horario),
               'culto', c.nome, 'funcao', i.funcao, 'sala', private.esc_nome_sala(c.id, i.sala_id))
             order by c.data, c.horario), '[]'::jsonb)
      from public.escala_itens i
      join public.escalas e on e.id = i.escala_id and e.status = 'publicada' and e.departamento_id = private.dept_kids()
      join public.cultos c on c.id = i.culto_id and not c.cancelado
      where i.voluntaria_id is null and i.nome_livre is null and i.funcao <> 'lider_culto' and c.data >= private.hoje()),
    -- meses em que a liderança pediu a indisponibilidade (escala ainda em rascunho)
    'pedidos', (
      select coalesce(jsonb_agg(jsonb_build_object(
               'mes', e.mes_referencia, 'nome_mes', private.esc_nome_mes(e.mes_referencia),
               'prazo', e.prazo_indisponibilidade,
               'respondeu', exists (select 1 from public.indisponibilidade_respostas r
                                    where r.voluntaria_id = any (v_vols) and r.mes = e.mes_referencia))
             order by e.mes_referencia), '[]'::jsonb)
      from public.escalas e
      where e.departamento_id = private.dept_kids() and e.status = 'rascunho'
        and e.indisponibilidade_pedida_em is not null
        and e.mes_referencia >= date_trunc('month', private.hoje())::date),
    'indisponibilidade', jsonb_build_object(
      'mes', v_prox, 'nome_mes', private.esc_nome_mes(v_prox), 'respondeu', v_resp,
      'aberta', v_esc_prox.id is null or v_esc_prox.status = 'rascunho',
      'dia_limite', case when jsonb_typeof(v_lim) = 'number' then (v_lim)::int end)
  );
end $$;

revoke all on function public.pedir_indisponibilidade(date, date, boolean) from public, anon;
grant execute on function public.pedir_indisponibilidade(date, date, boolean) to authenticated;
revoke all on function public.escala_do_mes(date) from public, anon;
grant execute on function public.escala_do_mes(date) to authenticated;
revoke all on function public.minha_escala() from public, anon;
grant execute on function public.minha_escala() to authenticated;
