-- =====================================================================
-- Fase 10 · Etapa 5B (preparação) – 27/10/2026
-- 1) keep_alive(): chamada diária do GitHub Actions para o Supabase Free
--    não pausar. Não lê nem devolve nenhum dado.
-- 2) candidatos_login(): quem divide o telefone com uma pessoa que JÁ tem
--    login (dentro do Fonte Kids) passa a aparecer como
--    "telefone_compartilhado" (antes: "telefone_em_uso", que pedia correção).
--    "telefone_em_uso" fica só para telefone usado por login de fora do grupo.
-- 3) Toda voluntária ganha também o papel "recepcao" no mesmo departamento
--    (decisão de 27/10/2026: todas as voluntárias fazem check-in).
--    Vale para as atuais e, por gatilho, para as próximas.
-- =====================================================================

-- ---------- 1) keep-alive ----------
create or replace function public.keep_alive()
returns text
language sql
stable
set search_path to ''
as $$ select 'ok'::text $$;

revoke all on function public.keep_alive() from public;
grant execute on function public.keep_alive() to anon, authenticated;

-- ---------- 2) telefone compartilhado ----------
create or replace function public.candidatos_login(p_departamento uuid)
returns table(pessoa_id uuid, telefone_login text, data_nascimento date,
              e_voluntaria boolean, e_responsavel boolean, situacao text)
language sql
stable security definer
set search_path to ''
as $function$
  with base as (
    select p.id, p.telefone, p.data_nascimento, p.criado_em,
      exists (select 1 from public.voluntarias v where v.pessoa_id = p.id
              and v.departamento_id = p_departamento and v.status = 'ativa') as vol,
      exists (select 1 from public.responsaveis r join public.familias f on f.id = r.familia_id
              where r.pessoa_id = p.id and f.departamento_id = p_departamento) as resp,
      exists (select 1 from public.responsaveis r join public.familias f on f.id = r.familia_id
              where r.pessoa_id = p.id and f.departamento_id = p_departamento and r.principal) as principal,
      exists (select 1 from public.perfis x where x.pessoa_id = p.id) as tem_login
    from public.pessoas p
    where p.id in (select v.pessoa_id from public.voluntarias v
                   where v.departamento_id = p_departamento and v.status = 'ativa'
                   union
                   select r.pessoa_id from public.responsaveis r join public.familias f on f.id = r.familia_id
                   where f.departamento_id = p_departamento)
  ), ordem as (
    select b.*,
      row_number() over (partition by b.telefone
                         order by b.tem_login desc, b.vol desc, b.principal desc, b.criado_em, b.id) as pos,
      -- alguém do mesmo grupo (mesmo telefone, mesmo departamento) já tem login
      bool_or(b.tem_login) over (partition by b.telefone) as grupo_tem_login
    from base b
  )
  select o.id, o.telefone, o.data_nascimento, o.vol, o.resp,
    case when o.tem_login then 'ja_tem_login'
         when o.telefone is null then 'sem_telefone'
         when o.telefone !~ '^55[1-9][0-9]9?[0-9]{8}$' then 'telefone_invalido'
         when o.grupo_tem_login then 'telefone_compartilhado'
         when exists (select 1 from public.perfis x where x.telefone = o.telefone) then 'telefone_em_uso'
         when o.pos > 1 then 'telefone_compartilhado'
         else 'criar' end
  from ordem o
$function$;

-- ---------- 3) voluntária também é recepção ----------
insert into public.papeis_usuario (perfil_id, departamento_id, papel)
select pu.perfil_id, pu.departamento_id, 'recepcao'
from public.papeis_usuario pu
where pu.papel = 'voluntaria'
on conflict (perfil_id, departamento_id, papel) do nothing;

create or replace function private.voluntaria_tambem_recepcao()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  if new.papel = 'voluntaria' then
    insert into public.papeis_usuario (perfil_id, departamento_id, papel, concedido_por)
    values (new.perfil_id, new.departamento_id, 'recepcao', new.concedido_por)
    on conflict (perfil_id, departamento_id, papel) do nothing;
  end if;
  return new;
end $$;

revoke all on function private.voluntaria_tambem_recepcao() from public, anon, authenticated;

drop trigger if exists papeis_voluntaria_recepcao on public.papeis_usuario;
create trigger papeis_voluntaria_recepcao
  after insert on public.papeis_usuario
  for each row execute function private.voluntaria_tambem_recepcao();
