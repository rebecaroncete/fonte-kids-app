-- =====================================================================
-- Migração 0008: dados iniciais de estrutura (SEM dados pessoais)
-- Igreja, departamento Fonte Kids, salas, cultos da semana e regras.
-- Os valores podem ser ajustados depois pela tela de configurações.
-- =====================================================================
do $$
declare
  v_igreja uuid;
  v_kids   uuid;
begin
  insert into public.igrejas (nome) values ('Fonte de Vida Itaparica') returning id into v_igreja;

  insert into public.departamentos (igreja_id, nome, slug)
  values (v_igreja, 'Fonte Kids', 'kids') returning id into v_kids;

  -- Salas por faixa etária (capacidades da aba Configuracoes)
  insert into public.salas (departamento_id, nome, idade_min, idade_max, capacidade, ordem) values
    (v_kids, '0 a 2 anos',   0,  2, 15, 1),
    (v_kids, '3 a 6 anos',   3,  6, 20, 2),
    (v_kids, '7 a 9 anos',   7,  9, 25, 3),
    (v_kids, '10 a 12 anos', 10, 12, 25, 4);

  -- Cultos fixos (Cultos_Semana: Dom_10h, Dom_19h, Ter_20h)
  insert into public.cultos_recorrentes (igreja_id, nome, dia_semana, horario) values
    (v_igreja, 'Domingo 10h', 0, '10:00'),
    (v_igreja, 'Domingo 19h', 0, '19:00'),
    (v_igreja, 'Terça 20h',   2, '20:00');

  -- Regras do motor de escala (parametrizadas; lidas na Fase 6)
  insert into public.regras_escala (departamento_id, chave, valor, descricao) values
    (v_kids, 'uma_vaga_por_dia',                 'true',  'Voluntária ocupa no máximo 1 vaga por dia'),
    (v_kids, 'nao_escalar_semanas_consecutivas', 'true',  'Evita escalar a mesma voluntária em semanas seguidas'),
    (v_kids, 'idade_minima_professora',          '16',    'Menores desta idade entram só como Auxiliar'),
    (v_kids, 'lider_homem_exige_auxiliar_mulher','{"idade_min_sala": 10}', 'Sala 10–12: se a professora for homem, auxiliares mulheres'),
    (v_kids, 'preencher_lider_culto_automatico', 'false', 'Líder do Culto nunca é preenchido automaticamente'),
    (v_kids, 'preferencias_como_trava',          'true',  'Faixa e culto preferidos são respeitados como trava'),
    (v_kids, 'dia_limite_indisponibilidade',     '20',    'Dia do mês para enviar indisponibilidade do mês seguinte');

  insert into public.configuracoes (departamento_id, chave, valor, descricao) values
    (v_kids, 'versao_termo_lgpd', 'v1', 'Versão atual do termo de aceite LGPD');
end $$;
