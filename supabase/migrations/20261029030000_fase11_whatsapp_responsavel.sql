-- =====================================================================
-- Fase 11 · "WhatsApp" do responsável em Presentes (29/10/2026)
--   Como no app antigo (botão "Pais"): a recepção manda ao responsável a
--   mensagem pronta do modelo "choro" (mensagens_whatsapp_modelos), pelo
--   WhatsApp do próprio celular (wa.me). Com mais de um responsável, a
--   recepção escolhe para quem.
--   whatsapp_responsaveis(checkin)  só leitura, recepção/liderança, só
--   check-in de hoje → { mensagem, responsaveis: [{ nome, telefone, principal }] }
--   O telefone já é visível à recepção (fichas); nada novo é gravado.
-- =====================================================================
create or replace function public.whatsapp_responsaveis(p_checkin uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_k public.checkins%rowtype;
  v_cu public.cultos%rowtype;
  v_familia uuid;
  v_nome text;
  v_sala text;
  v_modelo text;
begin
  v_k := private.checkin_do_dia(p_checkin);   -- confere permissão e "hoje"
  select * into v_cu from public.cultos where id = v_k.culto_id;
  select c.familia_id, p.nome into v_familia, v_nome
    from public.criancas c join public.pessoas p on p.id = c.pessoa_id where c.id = v_k.crianca_id;
  v_sala := private.nome_sala_culto(private.salas_do_culto_json(v_cu.id, v_cu.culto_recorrente_id, false), v_k.sala_id);
  select m.texto into v_modelo from public.mensagens_whatsapp_modelos m
   where m.departamento_id = private.dept_sala(v_k.sala_id) and m.chave = 'choro';
  v_modelo := coalesce(nullif(btrim(v_modelo), ''),
    'Olá! Favor comparecer na salinha do Kids assim que possível. O(a) {nome_crianca} precisa de você.');
  return jsonb_build_object(
    'mensagem', replace(replace(replace(v_modelo,
                  '{nome_crianca}', private.primeiro_ultimo(v_nome)),
                  '{sala}', coalesce(v_sala, 'sala')),
                  '{codigo}', v_k.codigo_seguranca),
    'responsaveis', coalesce((
      select jsonb_agg(jsonb_build_object('nome', private.primeiro_ultimo(pr.nome), 'telefone', pr.telefone,
                                          'principal', r.principal)
                       order by r.principal desc, pr.nome)
        from public.responsaveis r join public.pessoas pr on pr.id = r.pessoa_id
       where r.familia_id = v_familia
         and length(regexp_replace(coalesce(pr.telefone, ''), '\D', '', 'g')) >= 10), '[]'::jsonb));
end $$;

revoke all on function public.whatsapp_responsaveis(uuid) from public, anon;
grant execute on function public.whatsapp_responsaveis(uuid) to authenticated;
