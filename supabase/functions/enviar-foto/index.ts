// =====================================================================
// Edge Function "enviar-foto" – Fase 10 · Etapa 5C (edição pelo responsável)
// Troca a foto da própria pessoa ou de uma criança da família.
//
// Chamada pelo app (usuário logado):
//   POST /functions/v1/enviar-foto
//   Authorization: Bearer <token da sessão do usuário>
//   { "tipo": "eu" | "crianca", "id": "<id da criança>" (só para crianca),
//     "imagem": "data:image/jpeg;base64,..." }   (o app já reduz a foto)
// Resposta: { "ok": true } ou { "erro": "..." }
//
// Passos:
//   1) confere o login;
//   2) pergunta ao BANCO, com o token do usuário, se ele pode trocar esta
//      foto (função alvo_foto) — o banco decide;
//   3) envia ao Cloudinary como foto PRIVADA, limitada a 400 px;
//   4) grava no cadastro com a service_role (função gravar_foto: auditoria
//      em nome do login + aviso à liderança);
//   5) apaga a foto antiga (melhor esforço).
//
// Variáveis de ambiente (Edge Functions → Secrets), as mesmas da foto-assinada:
//   CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET, CLOUDINARY_CLOUD_NAME (opcional)
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY (do Supabase)
// Nenhum dado pessoal nem a imagem são registrados em log.
// =====================================================================
import { apagarPrivada, enviarPrivada } from "./cloudinary.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const IMAGEM = /^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/]+=*$/;
const MAX_CARACTERES = 3_000_000; // ~2,2 MB de imagem

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
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
  const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
  const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME") || "tzoi5ks7";
  if (!supabaseUrl || !anonKey || !serviceKey || !apiKey || !apiSecret) {
    return resposta({ erro: "Configuração incompleta no servidor." }, 500);
  }

  // 1) Login
  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) return resposta({ erro: "Faça login." }, 401);
  const quem = await fetch(`${supabaseUrl}/auth/v1/user`, { headers: { apikey: anonKey, Authorization: auth } });
  if (!quem.ok) return resposta({ erro: "Sessão inválida ou expirada." }, 401);
  const usuario = await quem.json().catch(() => null);
  const perfilId = typeof usuario?.id === "string" && UUID.test(usuario.id) ? usuario.id : null;
  if (!perfilId) return resposta({ erro: "Sessão inválida ou expirada." }, 401);

  // Pedido
  let corpo: { tipo?: unknown; id?: unknown; imagem?: unknown };
  try { corpo = await req.json(); } catch { return resposta({ erro: "Corpo da requisição inválido." }, 400); }
  const tipo = corpo.tipo;
  if (tipo !== "eu" && tipo !== "crianca") return resposta({ erro: 'tipo deve ser "eu" ou "crianca".' }, 400);
  const id = tipo === "crianca" ? corpo.id : null;
  if (tipo === "crianca" && (typeof id !== "string" || !UUID.test(id))) return resposta({ erro: "id inválido." }, 400);
  const imagem = corpo.imagem;
  if (typeof imagem !== "string" || imagem.length > MAX_CARACTERES || !IMAGEM.test(imagem)) {
    return resposta({ erro: "Imagem inválida ou grande demais." }, 400);
  }

  // 2) O banco decide, com o token do usuário
  const alvo = await fetch(`${supabaseUrl}/rest/v1/rpc/alvo_foto`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: auth, "Content-Type": "application/json" },
    body: JSON.stringify({ p_tipo: tipo, p_id: id }),
  });
  if (!alvo.ok) return resposta({ erro: "Sem permissão para trocar esta foto." }, 403);
  const linhas: { pessoa_id: string; foto_atual: string | null; pasta: string }[] = await alvo.json().catch(() => []);
  const a = linhas[0];
  if (!a || !UUID.test(a.pessoa_id) || !/^pessoas\/(adultos|criancas)$/.test(a.pasta)) {
    return resposta({ erro: "Sem permissão para trocar esta foto." }, 403);
  }

  // 3) Cloudinary (privada, até 400 px)
  const cred = { cloudName, apiKey, apiSecret };
  let novo: string;
  try {
    novo = await enviarPrivada(imagem, `${a.pasta}/${a.pessoa_id}_${Date.now()}`, cred);
  } catch {
    return resposta({ erro: "Não foi possível enviar a foto agora. Tente de novo." }, 502);
  }

  // 4) Grava no cadastro (service_role)
  const grava = await fetch(`${supabaseUrl}/rest/v1/rpc/gravar_foto`, {
    method: "POST",
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_perfil: perfilId, p_pessoa: a.pessoa_id, p_public_id: novo, p_tipo: tipo, p_crianca: id }),
  });
  if (!grava.ok) {
    await apagarPrivada(novo, cred).catch(() => {});
    return resposta({ erro: "Não foi possível salvar a foto agora. Tente de novo." }, 502);
  }

  // 5) Apaga a antiga
  if (a.foto_atual && a.foto_atual !== novo) await apagarPrivada(a.foto_atual, cred).catch(() => {});
  return resposta({ ok: true });
});
