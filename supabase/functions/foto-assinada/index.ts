// =====================================================================
// Edge Function "foto-assinada" – Fase 3
// Devolve links TEMPORÁRIOS para as fotos privadas (Cloudinary) que o
// usuário logado tem permissão de ver.
//
// Chamada pelo app (usuário logado):
//   POST /functions/v1/foto-assinada
//   Authorization: Bearer <token da sessão do usuário>
//   { "tipo": "crianca" | "voluntaria" | "pessoa", "ids": ["<uuid>", ...] }   (até 100 ids)
//   ("pessoa" = foto de adulto/responsável, por id da pessoa – Etapa 5C)
// Resposta:
//   { "fotos": { "<uuid>": "<link temporário>", ... }, "expira_em": "<data ISO>" }
//   Ids sem permissão ou sem foto simplesmente não aparecem em "fotos".
//
// Quem decide a permissão é o BANCO (funções fotos_criancas,
// fotos_voluntarias e fotos_pessoas, chamadas com o token do próprio usuário).
//
// Variáveis de ambiente (Edge Functions → Secrets):
//   CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET   (obrigatórias, cadastradas pela admin)
//   CLOUDINARY_CLOUD_NAME   (opcional; padrão: conta da igreja)
//   FOTO_LINK_SEGUNDOS      (opcional; padrão 300 = 5 min; máximo 3600)
//   SUPABASE_URL, SUPABASE_ANON_KEY  (já fornecidas pelo Supabase)
// Nenhum dado pessoal é registrado em log.
// =====================================================================
import { linkTemporario } from "./assinatura.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_IDS = 100;
const RPC: Record<string, string> = {
  crianca: "fotos_criancas",
  voluntaria: "fotos_voluntarias",
  pessoa: "fotos_pessoas",
};

function resposta(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return resposta({ erro: "Use POST." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
  const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
  const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME") || "tzoi5ks7";
  const segundos = Math.min(
    Math.max(Number(Deno.env.get("FOTO_LINK_SEGUNDOS")) || 300, 60),
    3600,
  );
  if (!supabaseUrl || !anonKey || !apiKey || !apiSecret) {
    return resposta({ erro: "Configuração incompleta no servidor." }, 500);
  }

  // 1) Precisa ser um usuário logado (não basta a chave pública do app)
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return resposta({ erro: "Faça login." }, 401);
  const quem = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { apikey: anonKey, Authorization: auth },
  });
  if (!quem.ok) return resposta({ erro: "Sessão inválida ou expirada." }, 401);

  // 2) Valida o pedido
  let corpo: { tipo?: unknown; ids?: unknown };
  try {
    corpo = await req.json();
  } catch {
    return resposta({ erro: "Corpo da requisição inválido." }, 400);
  }
  const rpc = typeof corpo.tipo === "string" ? RPC[corpo.tipo] : undefined;
  if (!rpc) return resposta({ erro: 'tipo deve ser "crianca", "voluntaria" ou "pessoa".' }, 400);
  if (!Array.isArray(corpo.ids) || corpo.ids.length === 0 || corpo.ids.length > MAX_IDS) {
    return resposta({ erro: `Envie de 1 a ${MAX_IDS} ids.` }, 400);
  }
  const ids = [...new Set(corpo.ids)];
  if (!ids.every((i) => typeof i === "string" && UUID.test(i))) {
    return resposta({ erro: "Há ids inválidos." }, 400);
  }

  // 3) Pergunta ao banco, COM O TOKEN DO USUÁRIO, quais fotos ele pode ver
  const r = await fetch(`${supabaseUrl}/rest/v1/rpc/${rpc}`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: auth, "Content-Type": "application/json" },
    body: JSON.stringify({ p_ids: ids }),
  });
  if (!r.ok) return resposta({ erro: "Não foi possível verificar as permissões." }, 502);
  const permitidas: { id: string; foto_public_id: string }[] = await r.json();

  // 4) Gera um link temporário para cada foto permitida
  const cred = { cloudName, apiKey, apiSecret };
  const agora = Math.floor(Date.now() / 1000);
  const fotos: Record<string, string> = {};
  for (const p of permitidas) {
    fotos[p.id] = await linkTemporario(p.foto_public_id, cred, segundos, agora);
  }
  return resposta({ fotos, expira_em: new Date((agora + segundos) * 1000).toISOString() });
});
