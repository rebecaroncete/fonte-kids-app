// =====================================================================
// Edge Function: pedir-redefinicao  (Fase 10 · Etapa 2 – plano, seção 4.2)
//
// "Esqueci minha senha": a pessoa informa o telefone e passa pelo captcha.
// Esta função:
//   1. confere o captcha (Cloudflare Turnstile) NO SERVIDOR;
//   2. procura um login ativo com aquele telefone;
//   3. se achar, registra o pedido e avisa no sino líderes do Fonte Kids,
//      admin e pastores (função do banco registrar_pedido_redefinicao,
//      que também aplica o limite de 1 pedido a cada 24 h);
//   4. responde SEMPRE a mesma mensagem, exista o telefone ou não.
// NUNCA redefine a senha. Não guarda telefone digitado nem IP.
//
// Pública (sem login): publicar com verify_jwt = false.
// Segredos (painel do Supabase → Edge Functions → Secrets):
//   TURNSTILE_SECRET_KEY  – chave secreta do Turnstile (obrigatória)
//   ORIGENS_PERMITIDAS    – opcional, lista separada por vírgula
//                           (padrão: https://rebecaroncete.github.io)
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem por padrão.
// =====================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const MENSAGEM = "Pedido enviado. A liderança vai falar com você.";
const TELEFONE = /^55\d{10,11}$/;

const ORIGENS = (Deno.env.get("ORIGENS_PERMITIDAS") || "https://rebecaroncete.github.io")
  .split(",").map((s) => s.trim()).filter(Boolean);

function cabecalhos(origem: string | null): HeadersInit {
  const h: Record<string, string> = {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
  if (origem && ORIGENS.includes(origem)) h["Access-Control-Allow-Origin"] = origem;
  return h;
}

function resposta(corpo: unknown, status: number, origem: string | null) {
  return new Response(JSON.stringify(corpo), { status, headers: cabecalhos(origem) });
}

/** Normaliza para 55 + DDD + número (igual ao app). */
function normalizarTelefone(v: unknown): string | null {
  let d = String(v ?? "").replace(/\D/g, "");
  if (d.startsWith("55") && (d.length === 12 || d.length === 13)) d = d.slice(2);
  if (d.length !== 10 && d.length !== 11) return null;
  if (d[0] === "0") return null;
  const t = "55" + d;
  return TELEFONE.test(t) ? t : null;
}

async function captchaValido(token: string, ip: string | null): Promise<boolean> {
  const segredo = Deno.env.get("TURNSTILE_SECRET_KEY");
  if (!segredo || !token || token.length > 2048) return false;
  const form = new FormData();
  form.append("secret", segredo);
  form.append("response", token);
  if (ip) form.append("remoteip", ip); // só repassado ao Turnstile; não é guardado
  try {
    const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form });
    const j = await r.json();
    return j?.success === true;
  } catch {
    return false;
  }
}

Deno.serve(async (req) => {
  const origem = req.headers.get("origin");

  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cabecalhos(origem) });
  if (req.method !== "POST") return resposta({ erro: "Método não permitido." }, 405, origem);
  if (origem && !ORIGENS.includes(origem)) return resposta({ erro: "Origem não permitida." }, 403, origem);

  let corpo: { telefone?: unknown; captchaToken?: unknown };
  try { corpo = await req.json(); } catch { return resposta({ erro: "Pedido inválido." }, 400, origem); }

  const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || null;
  if (!(await captchaValido(String(corpo.captchaToken ?? ""), ip))) {
    return resposta({ erro: "captcha" }, 400, origem);
  }

  const telefone = normalizarTelefone(corpo.telefone);
  if (telefone) {
    try {
      const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data: perfil } = await admin.from("perfis")
        .select("id").eq("telefone", telefone).eq("ativo", true).maybeSingle();
      if (perfil?.id) {
        const { error } = await admin.rpc("registrar_pedido_redefinicao", { p_perfil: perfil.id });
        if (error) console.error("registrar_pedido_redefinicao falhou:", error.code);
      }
    } catch (e) {
      // Sem detalhes no log (nada de telefone).
      console.error("pedir-redefinicao: erro interno", (e as Error)?.name);
    }
  }

  // Resposta igual em todos os casos (existe ou não, limite de 24 h ou não).
  return resposta({ ok: true, mensagem: MENSAGEM }, 200, origem);
});
