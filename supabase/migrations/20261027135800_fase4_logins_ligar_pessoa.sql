-- =====================================================================
-- Fase 4 · Etapa 3 – ajuste (27/10/2026)
-- O Auth, ao criar um usuário pelo servidor (admin.createUser), grava o
-- app_metadata DEPOIS de inserir o usuário. O gatilho de criação do
-- perfil ainda não via a pessoa. Este gatilho liga o perfil à pessoa
-- quando o metadata chega. Só o servidor grava raw_app_meta_data; só
-- liga perfis que ainda não têm pessoa (não troca a pessoa de ninguém).
-- =====================================================================
create function private.ligar_perfil_por_metadata()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_pessoa uuid; v_igreja uuid;
begin
  begin
    v_pessoa := nullif(new.raw_app_meta_data ->> 'pessoa_id', '')::uuid;
  exception when invalid_text_representation then v_pessoa := null;
  end;
  if v_pessoa is null then return new; end if;
  select igreja_id into v_igreja from public.pessoas where id = v_pessoa;
  if v_igreja is null then return new; end if;
  update public.perfis
     set pessoa_id = v_pessoa,
         igreja_id = v_igreja,
         telefone  = coalesce(telefone, nullif(new.raw_app_meta_data ->> 'telefone', ''))
   where id = new.id and pessoa_id is null;
  return new;
end $$;

create trigger perfil_ligar_pessoa
  after update of raw_app_meta_data on auth.users
  for each row
  when (new.raw_app_meta_data ->> 'pessoa_id' is distinct from old.raw_app_meta_data ->> 'pessoa_id')
  execute function private.ligar_perfil_por_metadata();
