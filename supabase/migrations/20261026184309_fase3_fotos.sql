-- =====================================================================
-- Fase 3 – Fotos no Cloudinary (privadas)
-- As fotos ficam no Cloudinary em modo "authenticated", com o id interno
-- do registro como identificador:
--   pessoas/criancas/<uuid>      pessoas/voluntarias/<uuid>
-- O app NUNCA monta o link da foto. Ele chama a Edge Function
-- "foto-assinada", que usa as funções abaixo para saber quais fotos o
-- usuário logado pode ver e devolve links que expiram em poucos minutos.
-- =====================================================================

-- Voluntária menor de idade (pela data de nascimento, no fuso de São Paulo).
-- Sem data de nascimento conta como menor (mais seguro).
create function private.e_menor(p_nascimento date) returns boolean
language sql stable set search_path = '' as $$
  select p_nascimento is null
      or p_nascimento > private.hoje() - interval '18 years'
$$;

-- Fotos de crianças que o usuário logado pode ver.
-- SECURITY INVOKER: obedece exatamente às mesmas regras (RLS) da tabela
-- criancas — família vê as suas; recepção/líder/pastor veem o departamento;
-- voluntária vê as crianças das salas em que foi escalada.
create function public.fotos_criancas(p_ids uuid[])
returns table (id uuid, foto_public_id text)
language sql stable security invoker set search_path = '' as $$
  select c.id, c.foto_public_id
  from public.criancas c
  where c.id = any (p_ids)
    and c.foto_public_id is not null
$$;

-- Fotos de voluntárias que o usuário logado pode ver:
--   * a própria foto;
--   * líder do departamento, pastor e admin: todas;
--   * equipe do departamento (voluntária/recepção): só de voluntárias
--     ATIVAS e MAIORES de idade. Foto de menor só a própria e a liderança.
create function public.fotos_voluntarias(p_ids uuid[])
returns table (id uuid, foto_public_id text)
language sql stable security definer set search_path = '' as $$
  select v.id, v.foto_public_id
  from public.voluntarias v
  where v.id = any (p_ids)
    and v.foto_public_id is not null
    and (
         v.perfil_id = (select auth.uid())
      or private.e_lider(v.departamento_id)
      or (private.e_equipe(v.departamento_id)
          and v.status = 'ativa'
          and not private.e_menor(v.data_nascimento))
    )
$$;

-- Lista da equipe: a foto de voluntária menor de idade só aparece para a
-- liderança (a equipe continua vendo nome, função e dia/mês do aniversário).
create or replace function public.equipe_departamento(p_departamento uuid)
returns table (id uuid, nome text, funcao public.funcao_voluntaria, foto_public_id text,
               aniversario_dia int, aniversario_mes int)
language sql stable security definer set search_path = '' as $$
  select v.id, v.nome, v.funcao,
         case when private.e_menor(v.data_nascimento)
                   and not private.e_lider(p_departamento)
                   and v.perfil_id is distinct from (select auth.uid())
              then null else v.foto_public_id end,
         extract(day from v.data_nascimento)::int, extract(month from v.data_nascimento)::int
  from public.voluntarias v
  where v.departamento_id = p_departamento and v.status = 'ativa'
    and private.e_equipe(p_departamento)
  order by v.nome
$$;

revoke all on function private.e_menor(date) from public, anon, authenticated;
revoke all on function public.fotos_criancas(uuid[])    from public, anon;
revoke all on function public.fotos_voluntarias(uuid[]) from public, anon;
grant execute on function public.fotos_criancas(uuid[])    to authenticated;
grant execute on function public.fotos_voluntarias(uuid[]) to authenticated;
