-- =====================================================================
-- Fase 5 – Grupos de WhatsApp dos responsáveis (decisões 87, 91 e 92)
--  * Dois grupos: crianças de 0 a 9 anos e de 10 a 12 anos. Os links de
--    convite ficam em `configuracoes` (link_grupo_whatsapp_0_9 e _10_12),
--    nunca no código (repositório público). A chave única antiga
--    link_grupo_whatsapp (vazia) é apagada.
--  * Tabela membros_grupo_whatsapp: quem já está em cada grupo (só a marcação;
--    nada do print fica salvo). Leitura: liderança (líder, pastor, admin).
--    Gravação: só por funções (a tela vem na 5D).
--  * A marcação inicial do grupo 0–9 (a partir do print enviado em 28/10/2026)
--    foi feita à parte, pelo SQL do MCP, e NÃO está neste arquivo
--    (o arquivo não guarda telefones).
-- =====================================================================
delete from public.configuracoes where chave = 'link_grupo_whatsapp';
insert into public.configuracoes (departamento_id, chave, valor, descricao)
select d.id, x.chave, '', x.descricao
from public.departamentos d
cross join (values
  ('link_grupo_whatsapp_0_9',   'Link de convite do grupo de WhatsApp dos responsáveis de crianças de 0 a 9 anos'),
  ('link_grupo_whatsapp_10_12', 'Link de convite do grupo de WhatsApp dos responsáveis de crianças de 10 a 12 anos')
) as x(chave, descricao)
where d.slug = 'kids'
on conflict (departamento_id, chave) do nothing;
-- os links são gravados à parte (SQL Editor / tela da liderança), não neste arquivo

create table if not exists public.membros_grupo_whatsapp (
  id uuid primary key default gen_random_uuid(),
  pessoa_id uuid not null references public.pessoas(id) on delete cascade,
  grupo text not null check (grupo in ('0_9', '10_12')),
  marcado_em timestamptz not null default now(),
  marcado_por uuid references public.perfis(id) on delete set null,
  unique (pessoa_id, grupo)
);
comment on table public.membros_grupo_whatsapp is
  'Quem já está em cada grupo de WhatsApp dos responsáveis (0_9 ou 10_12)';

alter table public.membros_grupo_whatsapp enable row level security;
drop policy if exists mgw_ler on public.membros_grupo_whatsapp;
create policy mgw_ler on public.membros_grupo_whatsapp for select to authenticated
  using ((select private.e_lider_algum()));
revoke insert, update, delete on public.membros_grupo_whatsapp from anon, authenticated;

drop trigger if exists membros_grupo_whatsapp_auditoria on public.membros_grupo_whatsapp;
create trigger membros_grupo_whatsapp_auditoria after insert or update or delete
  on public.membros_grupo_whatsapp for each row execute function private.auditar();
