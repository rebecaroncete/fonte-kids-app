-- =====================================================================
-- Fonte Kids – Fase 2: importação a partir da área de carga (staging)
-- Este arquivo NÃO contém dados. Os dados entram em migracao_fase2.carga
-- (gerados por fase2_gerar_carga.py) e a área é apagada ao final.
--
--   select migracao_fase2.importar(true);   -- TESTE: faz tudo e desfaz (o
--                                           -- resultado vem na mensagem de erro)
--   select migracao_fase2.importar(false);  -- importação definitiva
--   drop schema migracao_fase2 cascade;     -- limpeza da área de carga
-- =====================================================================
create schema if not exists migracao_fase2;
revoke all on schema migracao_fase2 from public, anon, authenticated;
create table if not exists migracao_fase2.carga (
  id bigserial primary key, tabela text not null, dados jsonb not null);

create or replace function migracao_fase2.importar(p_teste boolean default true)
returns jsonb language plpgsql set search_path = '' as $$
declare
  v_dept uuid; v_igreja uuid; v jsonb;
  tz constant text := 'America/Sao_Paulo';
begin
  select d.id, d.igreja_id into strict v_dept, v_igreja from public.departamentos d where d.slug = 'kids';
  if exists (select 1 from public.familias where codigo_legado is not null)
     or exists (select 1 from public.voluntarias where codigo_legado is not null) then
    raise exception 'Já existem dados importados – importação cancelada para não duplicar.';
  end if;

  create temp table x on commit drop as
    select c.tabela t, e from migracao_fase2.carga c, jsonb_array_elements(c.dados) e;

  -- famílias, responsáveis, termo LGPD da planilha
  insert into public.familias (departamento_id, codigo_legado, observacoes, criado_em)
  select v_dept, e->>0,
         case when jsonb_array_length(e->1) > 0 then 'Cadastros antigos mesclados: ' ||
              (select string_agg(m, ', ') from jsonb_array_elements_text(e->1) m) end,
         coalesce((e->>2)::timestamp at time zone tz, now())
  from x where t = 'familias';

  insert into public.responsaveis (familia_id, nome, telefone, principal, criado_em)
  select f.id, r->>0, r->>1, (r->>2)::boolean, f.criado_em
  from x join public.familias f on f.codigo_legado = x.e->>0 and f.departamento_id = v_dept,
       jsonb_array_elements(x.e->3) r
  where t = 'familias';

  insert into public.termos_lgpd (familia_id, versao, aceito_em, aceito_por_nome, aceito_por_perfil)
  select f.id, 'legado-planilha', f.criado_em,
         (select r.nome from public.responsaveis r where r.familia_id = f.id order by r.principal desc limit 1), null
  from public.familias f where f.departamento_id = v_dept and f.codigo_legado is not null;

  -- crianças (sem sala fixa: a sala sai da idade) e vínculos responsável–criança
  insert into public.criancas (familia_id, nome, data_nascimento, alergias_observacoes, foto_legado_url, perfil, codigo_legado)
  select f.id, e->>2, (e->>3)::date, e->>4, e->>5, (e->>6)::public.perfil_crianca, e->>0
  from x join public.familias f on f.codigo_legado = x.e->>1 and f.departamento_id = v_dept
  where t = 'criancas';

  insert into public.responsaveis_criancas (responsavel_id, crianca_id)
  select r.id, c.id from public.responsaveis r join public.criancas c using (familia_id)
  join public.familias f on f.id = c.familia_id
  where f.departamento_id = v_dept and c.codigo_legado is not null;

  -- voluntárias (sem login: Fase 4)
  insert into public.voluntarias (departamento_id, codigo_legado, nome, telefone, email, data_nascimento, sexo,
         profissao, funcao, salas_preferidas, cultos_preferidos, status, foto_legado_url, teto_mensal,
         aprovada_em, criado_em)
  select v_dept, e->>0, e->>1, e->>2, e->>3, (e->>4)::date, (e->>5)::public.sexo_tipo, e->>6,
         (e->>7)::public.funcao_voluntaria,
         array(select s.id from jsonb_array_elements_text(e->8) with ordinality z(nome, o)
               join public.salas s on s.nome = z.nome and s.departamento_id = v_dept order by z.o),
         array(select cr.id from jsonb_array_elements_text(e->9) with ordinality z(cod, o)
               join public.cultos_recorrentes cr on cr.igreja_id = v_igreja
                and cr.dia_semana = case z.cod when 'ter20' then 2 else 0 end
                and cr.horario = case z.cod when 'dom10' then '10:00'::time when 'dom19' then '19:00'::time else '20:00'::time end
               order by z.o),
         (e->>10)::public.status_voluntaria, e->>11, (e->>12)::smallint,
         case when e->>10 = 'ativa' then coalesce((e->>13)::timestamp at time zone tz, now()) end,
         coalesce((e->>13)::timestamp at time zone tz, now())
  from x where t = 'voluntarias';

  insert into public.indisponibilidades (voluntaria_id, data, horario)
  select v.id, (e->>1)::date, (e->>2)::time
  from x join public.voluntarias v on v.codigo_legado = x.e->>0 and v.departamento_id = v_dept
  where t = 'indisponibilidades';

  -- cultos e salas canceladas/combinadas
  insert into public.cultos (igreja_id, culto_recorrente_id, data, horario, nome)
  select v_igreja, cr.id, (e->>0)::date, (e->>1)::time, cr.nome
  from x join public.cultos_recorrentes cr on cr.igreja_id = v_igreja
       and cr.dia_semana = case x.e->>2 when 'ter20' then 2 else 0 end and cr.horario = (x.e->>1)::time
  where t = 'cultos';

  insert into public.culto_salas (culto_id, sala_id, cancelada, combinada_com_sala_id)
  select cu.id, s.id, (e->>3)::boolean, s2.id
  from x join public.cultos cu on cu.igreja_id = v_igreja and cu.data = (x.e->>0)::date and cu.horario = (x.e->>1)::time
         join public.salas s on s.departamento_id = v_dept and s.nome = x.e->>2
         left join public.salas s2 on s2.departamento_id = v_dept and s2.nome = x.e->>4
  where t = 'culto_salas';

  -- escalas
  insert into public.escalas (departamento_id, mes_referencia, status, teto_mensal, criado_por)
  select v_dept, (e->>0)::date, (e->>1)::public.status_escala, (e->>2)::smallint, null
  from x where t = 'escalas';

  insert into public.escala_config_salas (escala_id, sala_id, qtd_professora, qtd_auxiliar, qtd_reserva)
  select es.id, s.id, (cfg.value->>0)::smallint, (cfg.value->>1)::smallint, (cfg.value->>2)::smallint
  from x join public.escalas es on es.departamento_id = v_dept and es.mes_referencia = (x.e->>0)::date,
       jsonb_each(x.e->3) cfg join public.salas s on s.departamento_id = v_dept and s.nome = cfg.key
  where t = 'escalas' and jsonb_typeof(x.e->3) = 'object';

  insert into public.configuracoes (departamento_id, chave, valor, descricao)
  select v_dept, 'vagas_terca_sala_combinada_7_12',
         jsonb_build_object('professora', e->4->0, 'auxiliar', e->4->1, 'reserva', e->4->2)::text,
         'Vagas por culto da sala combinada 7 a 12 anos (terça)'
  from x where t = 'escalas' and jsonb_typeof(e->4) = 'array'
  order by e->>0 desc limit 1;

  insert into public.escala_itens (escala_id, culto_id, sala_id, funcao, voluntaria_id, nome_livre, resposta)
  select es.id, cu.id, s.id, (e->>4)::public.funcao_escala, v.id, e->>6, (e->>7)::public.resposta_escala
  from x join public.escalas es on es.departamento_id = v_dept and es.mes_referencia = (x.e->>0)::date
         join public.cultos cu on cu.igreja_id = v_igreja and cu.data = (x.e->>1)::date and cu.horario = (x.e->>2)::time
         left join public.salas s on s.departamento_id = v_dept and s.nome = x.e->>3
         left join public.voluntarias v on v.departamento_id = v_dept and v.codigo_legado = x.e->>5
  where t = 'escala_itens';

  -- histórico de check-in (saída = entrada: o sistema antigo não registrava a saída)
  insert into public.checkins (culto_id, crianca_id, sala_id, codigo_seguranca, entrada_em, entrada_por, saida_em, observacao)
  select cu.id, c.id, s.id, e->>4, (e->>5)::timestamp at time zone tz, null, (e->>5)::timestamp at time zone tz,
         'Importado da planilha; horário de saída não era registrado no sistema antigo.'
  from x join public.cultos cu on cu.igreja_id = v_igreja and cu.data = (x.e->>0)::date and cu.horario = (x.e->>1)::time
         join public.criancas c on c.codigo_legado = x.e->>2
         join public.salas s on s.departamento_id = v_dept and s.nome = x.e->>3
  where t = 'checkins';

  -- mensagens, configurações, pendências
  insert into public.mensagens_whatsapp_modelos (departamento_id, chave, titulo, texto)
  select v_dept, e->>0, e->>1, e->>2 from x where t = 'mensagens';
  insert into public.configuracoes (departamento_id, chave, valor, descricao)
  select v_dept, e->>0, e->>1, e->>2 from x where t = 'configuracoes';
  insert into public.pendencias_cadastro (familia_id, crianca_id, tipo, mensagem)
  select f.id, c.id, e->>2, e->>3
  from x join public.familias f on f.codigo_legado = x.e->>0 and f.departamento_id = v_dept
         left join public.criancas c on c.codigo_legado = x.e->>1
  where t = 'pendencias';

  select jsonb_build_object(
    'familias', (select count(*) from public.familias),
    'responsaveis', (select count(*) from public.responsaveis),
    'termos_lgpd', (select count(*) from public.termos_lgpd),
    'criancas', (select count(*) from public.criancas),
    'responsaveis_criancas', (select count(*) from public.responsaveis_criancas),
    'voluntarias', (select count(*) from public.voluntarias),
    'voluntarias_menores', (select count(*) from public.voluntarias where data_nascimento > (current_date - interval '18 years')),
    'indisponibilidades', (select count(*) from public.indisponibilidades),
    'cultos', (select count(*) from public.cultos),
    'culto_salas', (select count(*) from public.culto_salas),
    'escalas', (select count(*) from public.escalas),
    'escala_config_salas', (select count(*) from public.escala_config_salas),
    'escala_itens', (select count(*) from public.escala_itens),
    'escala_itens_com_voluntaria', (select count(*) from public.escala_itens where voluntaria_id is not null),
    'checkins', (select count(*) from public.checkins),
    'checkins_em_aberto', (select count(*) from public.checkins where saida_em is null),
    'mensagens_whatsapp_modelos', (select count(*) from public.mensagens_whatsapp_modelos),
    'configuracoes', (select count(*) from public.configuracoes),
    'pendencias_cadastro', (select count(*) from public.pendencias_cadastro),
    'criancas_com_foto_legado', (select count(*) from public.criancas where foto_legado_url is not null),
    'linhas_na_carga', (select count(*) from x)
  ) into v;

  if p_teste then
    raise exception 'TESTE OK – tudo desfeito. Contagens: %', v;
  end if;
  return v;
end $$;
revoke all on function migracao_fase2.importar(boolean) from public, anon, authenticated;
