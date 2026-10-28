-- Fase 5 · Etapa 5E – Histórico (só leitura)
-- * historico_crianca(criança, antes_de, limite): check-ins de uma criança + resumo.
--   Recepção/liderança/pastor/admin do Fonte Kids; responsável só os próprios filhos.
-- * historico_cultos(dias, antes_de): cultos que já aconteceram, com totais por sala (equipe).
-- * historico_culto(culto): quem veio num culto, por sala (equipe).
-- Nunca devolve data de nascimento, telefone, alergias nem "retirado por".
-- Sem tabela nova e sem coluna nova.

create index if not exists checkins_crianca_entrada_idx on public.checkins (crianca_id, entrada_em desc);
create index if not exists checkins_culto_idx on public.checkins (culto_id);
create index if not exists cultos_data_idx on public.cultos (data desc, horario desc);

-- Chamadas de um check-in (sem quem chamou)
create or replace function private.chamadas_json(p_checkin uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'chamada_em', ch.chamada_em, 'situacao', ch.situacao, 'anunciada_em', ch.anunciada_em)
           order by ch.chamada_em), '[]'::jsonb)
    from public.chamadas_responsavel ch
   where ch.checkin_id = p_checkin and ch.situacao <> 'cancelada' $$;

-- 1) Histórico de uma criança ----------------------------------------------------
create or replace function public.historico_crianca(p_crianca uuid, p_antes timestamptz default null,
                                                    p_limite int default 20)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare
  v_familia uuid;
  v_lim int := least(greatest(coalesce(p_limite, 20), 1), 50);
  v_itens jsonb;
  v_n int;
begin
  select familia_id into v_familia from public.criancas where id = p_crianca;
  if not found then raise exception 'Sem permissão'; end if;
  if not (private.e_recepcao(private.dept_kids())
          or v_familia in (select private.minhas_familias())) then
    raise exception 'Sem permissão';
  end if;

  select coalesce(jsonb_agg(i order by (i->>'entrada_em')::timestamptz desc), '[]'::jsonb), count(*)
    into v_itens, v_n
    from (
      select jsonb_build_object(
               'checkin_id', k.id, 'culto_id', cu.id, 'data', cu.data,
               'horario', to_char(cu.horario, 'HH24:MI'), 'culto', cu.nome,
               'sala', coalesce(private.nome_sala_culto(
                         private.salas_do_culto_json(cu.id, cu.culto_recorrente_id, false), k.sala_id),
                         s.nome),
               'codigo', k.codigo_seguranca, 'entrada_em', k.entrada_em, 'saida_em', k.saida_em,
               'saida_automatica', k.saida_automatica,
               'chamadas', private.chamadas_json(k.id)) as i
        from public.checkins k
        join public.cultos cu on cu.id = k.culto_id
        left join public.salas s on s.id = k.sala_id
       where k.crianca_id = p_crianca
         and (p_antes is null or k.entrada_em < p_antes)
       order by k.entrada_em desc
       limit v_lim + 1
    ) z;

  if v_n > v_lim then
    v_itens := v_itens - v_lim;      -- tira o item extra (só servia para saber se há mais)
  end if;

  return jsonb_build_object(
    'resumo', (select jsonb_build_object(
                 'total', count(*),
                 'ultimos_30', count(*) filter (where cu.data > private.hoje() - 30),
                 'ultimos_90', count(*) filter (where cu.data > private.hoje() - 90),
                 'ultima_vez', max(cu.data))
                 from public.checkins k join public.cultos cu on cu.id = k.culto_id
                where k.crianca_id = p_crianca),
    'itens', v_itens,
    'tem_mais', v_n > v_lim);
end $$;

-- 2) Lista de cultos que já aconteceram -------------------------------------------
create or replace function public.historico_cultos(p_dias int default 30, p_antes date default null)
returns jsonb language plpgsql stable security definer set search_path to '' as $$
declare
  v_desde date := case when p_dias is null then null else private.hoje() - p_dias end;
  v_lim int := 40;
  v_itens jsonb;
  v_n int;
  v_corte date;
begin
  if not private.e_recepcao(private.dept_kids()) then raise exception 'Sem permissão'; end if;

  select coalesce(jsonb_agg(i order by (i->>'data')::date desc, i->>'horario' desc), '[]'::jsonb), count(*)
    into v_itens, v_n
    from (
      select jsonb_build_object(
               'id', cu.id, 'data', cu.data, 'horario', to_char(cu.horario, 'HH24:MI'),
               'nome', cu.nome, 'cancelado', cu.cancelado,
               'total', (select count(*) from public.checkins k where k.culto_id = cu.id),
               'chamadas', (select count(*) from public.chamadas_responsavel ch
                             where ch.culto_id = cu.id and ch.situacao <> 'cancelada'),
               'salas', private.totais_salas_culto(cu.id, cu.culto_recorrente_id)) as i
        from public.cultos cu
       where cu.data <= private.hoje()
         and (v_desde is null or cu.data > v_desde)
         and (p_antes is null or cu.data < p_antes)
         and (not cu.cancelado or exists (select 1 from public.checkins k where k.culto_id = cu.id))
       order by cu.data desc, cu.horario desc
       limit v_lim + 1
    ) z;

  -- Há mais: corta no último dia completo (um dia nunca fica dividido entre duas páginas)
  if v_n > v_lim then
    v_corte := (v_itens->v_lim->>'data')::date;
    select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_itens
      from jsonb_array_elements(v_itens) with ordinality t(e, o)
     where (e->>'data')::date > v_corte;
    return jsonb_build_object('itens', v_itens, 'tem_mais', true, 'proximo_antes', v_corte + 1);
  end if;
  return jsonb_build_object('itens', v_itens, 'tem_mais', false);
end $$;

-- totais por grupo de sala do culto (salas juntas = um grupo)
create or replace function private.totais_salas_culto(p_culto uuid, p_rec uuid) returns jsonb
language sql stable security definer set search_path to '' as $$
  with g as (select private.salas_do_culto_json(p_culto, p_rec, false) as salas)
  select coalesce(jsonb_agg(jsonb_build_object('nome', t.nome, 'total', t.n) order by t.ordem), '[]'::jsonb)
    from (
      select coalesce(private.nome_sala_culto(g.salas, k.sala_id), s.nome) as nome,
             min(s.ordem) as ordem, count(*) as n
        from public.checkins k
        join public.salas s on s.id = k.sala_id
        cross join g
       where k.culto_id = p_culto
       group by 1
    ) t $$;

-- 3) Quem veio num culto ---------------------------------------------------------
create or replace function public.historico_culto(p_culto uuid) returns jsonb
language plpgsql stable security definer set search_path to '' as $$
declare
  v_c public.cultos%rowtype;
  v_salas jsonb;
begin
  if not private.e_recepcao(private.dept_kids()) then raise exception 'Sem permissão'; end if;
  select * into v_c from public.cultos where id = p_culto and data <= private.hoje();
  if not found then raise exception 'Culto não encontrado'; end if;
  v_salas := private.salas_do_culto_json(v_c.id, v_c.culto_recorrente_id, false);

  return jsonb_build_object(
    'culto', jsonb_build_object('id', v_c.id, 'data', v_c.data, 'horario', to_char(v_c.horario, 'HH24:MI'),
               'nome', v_c.nome, 'cancelado', v_c.cancelado,
               'total', (select count(*) from public.checkins k where k.culto_id = v_c.id)),
    'salas', coalesce((
      select jsonb_agg(jsonb_build_object('nome', z.nome, 'criancas', z.criancas) order by z.ordem)
        from (
          select coalesce(private.nome_sala_culto(v_salas, k.sala_id), s.nome) as nome,
                 min(s.ordem) as ordem,
                 jsonb_agg(jsonb_build_object(
                   'checkin_id', k.id, 'crianca_id', c.id, 'pessoa_id', c.pessoa_id, 'nome', p.nome,
                   'codigo', k.codigo_seguranca, 'entrada_em', k.entrada_em, 'saida_em', k.saida_em,
                   'saida_automatica', k.saida_automatica,
                   'chamadas', (select count(*) from public.chamadas_responsavel ch
                                 where ch.checkin_id = k.id and ch.situacao <> 'cancelada'))
                   order by p.nome) as criancas
            from public.checkins k
            join public.criancas c on c.id = k.crianca_id
            join public.pessoas p on p.id = c.pessoa_id
            join public.salas s on s.id = k.sala_id
           where k.culto_id = v_c.id
           group by 1
        ) z
    ), '[]'::jsonb));
end $$;

-- Permissões ---------------------------------------------------------------------
revoke all on function private.chamadas_json(uuid) from public, anon, authenticated;
revoke all on function private.totais_salas_culto(uuid, uuid) from public, anon, authenticated;
revoke all on function public.historico_crianca(uuid, timestamptz, int) from public, anon;
revoke all on function public.historico_cultos(int, date) from public, anon;
revoke all on function public.historico_culto(uuid) from public, anon;
grant execute on function public.historico_crianca(uuid, timestamptz, int) to authenticated;
grant execute on function public.historico_cultos(int, date) to authenticated;
grant execute on function public.historico_culto(uuid) to authenticated;
