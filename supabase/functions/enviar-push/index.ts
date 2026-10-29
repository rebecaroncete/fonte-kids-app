// =====================================================================
// Edge Function: enviar-push  (Fase 7 – push no celular)
//
// Chamada pelo próprio banco (gatilho em "notificacoes", via pg_net) com
// { ids: [...] } das notificações novas de quem tem aparelho inscrito.
// Esta função:
//   1. pede ao banco o que mostrar (push_preparar): cada notificação vai
//      uma única vez e só nos primeiros 15 minutos; as automáticas vão só
//      com o título + "Abra o app para ver." (sem nomes de crianças);
//   2. criptografa e envia para cada aparelho (Web Push com VAPID);
//   3. apaga os aparelhos que o serviço de push recusou de vez (404/410).
// Quem chama não recebe nenhum dado de volta (só contagens).
//
// Publicar com verify_jwt = false (o banco chama sem login). Chamar com
// ids que não são novos não faz nada.
// Segredos (painel do Supabase → Edge Functions → Secrets):
//   VAPID_PUBLIC_KEY   – chave pública (a mesma de app/config.js)
//   VAPID_PRIVATE_KEY  – chave privada (NUNCA no código)
//   VAPID_SUBJECT      – opcional (padrão: endereço do app)
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem por padrão.
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";
import { enviarPush, type Inscricao } from "./webpush.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_IDS = 1000;
const SIMULTANEOS = 10;

function resposta(corpo: unknown, status = 200) {
  return new Response(JSON.stringify(corpo), {
    status, headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

type Item = { id: string; titulo: string; corpo: string; link: string | null; inscricoes: Inscricao[] };

Deno.serve(async (req) => {
  if (req.method !== "POST") return resposta({ erro: "Método não permitido." }, 405);

  const vapid = {
    publica: Deno.env.get("VAPID_PUBLIC_KEY") || "",
    privada: Deno.env.get("VAPID_PRIVATE_KEY") || "",
    assunto: Deno.env.get("VAPID_SUBJECT") || "https://rebecaroncete.github.io/fonte-kids-app/app/",
  };
  if (!vapid.publica || !vapid.privada) return resposta({ erro: "Push não configurado." }, 503);

  let ids: string[];
  try {
    const corpo = await req.json();
    ids = Array.isArray(corpo?.ids) ? corpo.ids.filter((x: unknown) => typeof x === "string" && UUID.test(x)) : [];
  } catch {
    return resposta({ erro: "Pedido inválido." }, 400);
  }
  if (!ids.length) return resposta({ enviados: 0 });
  ids = [...new Set(ids)].slice(0, MAX_IDS);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await sb.rpc("push_preparar", { p_ids: ids });
  if (error) { console.error("push_preparar falhou", error.code); return resposta({ erro: "Falha ao preparar." }, 500); }

  // uma tarefa por aparelho
  const tarefas: { insc: Inscricao; conteudo: unknown }[] = [];
  for (const n of (data || []) as Item[]) {
    const conteudo = { titulo: n.titulo, corpo: n.corpo, link: n.link || "#/notificacoes", tag: n.id };
    for (const insc of n.inscricoes || []) tarefas.push({ insc, conteudo });
  }

  let enviados = 0, falhas = 0;
  const recusados = new Set<string>();
  let proxima = 0;
  async function trabalhador() {
    while (proxima < tarefas.length) {
      const t = tarefas[proxima++];
      try {
        const status = await enviarPush(t.insc, t.conteudo, vapid);
        if (status >= 200 && status < 300) enviados++;
        else {
          falhas++;
          if (status === 404 || status === 410) recusados.add(t.insc.endpoint);
        }
      } catch {
        falhas++;
      }
    }
  }
  await Promise.all(Array.from({ length: Math.min(SIMULTANEOS, tarefas.length) }, trabalhador));

  let removidos = 0;
  if (recusados.size) {
    const r = await sb.rpc("push_remover_inscricoes", { p_endpoints: [...recusados] });
    if (!r.error) removidos = Number(r.data) || 0;
  }
  // só contagens no log (nada de endereços, nomes ou textos)
  console.log(`push: ${enviados} enviados, ${falhas} falhas, ${removidos} aparelhos removidos`);
  return resposta({ enviados, falhas, removidos });
});
