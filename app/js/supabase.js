// =====================================================================
// Fonte Kids – conexão com o Supabase e sessão
// A biblioteca oficial (supabase-js 2.118.0) vem de app/vendor/, servida
// pelo próprio app (versão fixa, sem depender de CDN).
//
// "Manter conectado":
//   marcado    → sessão salva no aparelho (localStorage)
//   desmarcado → sessão só nesta aba (sessionStorage): some ao fechar a aba
//                ou o navegador.
// =====================================================================
import { CONFIG } from "../config.js";

if (!window.supabase?.createClient) {
  throw new Error("Biblioteca do Supabase não carregou.");
}

const CHAVE_MANTER = "fk-manter-conectado"; // guarda só "1" ou "0"

function lerManter() {
  try { return localStorage.getItem(CHAVE_MANTER) !== "0"; } catch { return false; }
}

/** Define onde a próxima sessão será guardada (chamar ANTES de entrar). */
export function definirManterConectado(manter) {
  try { localStorage.setItem(CHAVE_MANTER, manter ? "1" : "0"); } catch { /* sem armazenamento */ }
}

export function manterConectadoAtual() { return lerManter(); }

// Armazenamento que escolhe entre aparelho (local) e aba (session).
const memoria = new Map();
const armazenamento = {
  getItem(k) {
    try { return localStorage.getItem(k) ?? sessionStorage.getItem(k) ?? memoria.get(k) ?? null; }
    catch { return memoria.get(k) ?? null; }
  },
  setItem(k, v) {
    try {
      if (lerManter()) { localStorage.setItem(k, v); sessionStorage.removeItem(k); }
      else { sessionStorage.setItem(k, v); localStorage.removeItem(k); }
    } catch { memoria.set(k, v); }
  },
  removeItem(k) {
    memoria.delete(k);
    try { localStorage.removeItem(k); } catch { /* ignore */ }
    try { sessionStorage.removeItem(k); } catch { /* ignore */ }
  },
};

export const sb = window.supabase.createClient(CONFIG.supabaseUrl, CONFIG.supabaseChavePublica, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false, // login é só por telefone + senha
    storageKey: "fk-sessao",
    storage: armazenamento,
  },
});

/** Telefone (55DDDnúmero) → e-mail técnico do login. */
export const emailDoLogin = (telefone55) => `${telefone55}@${CONFIG.dominioLogin}`;

/** Sessão atual ou null (sem lançar erro). */
export async function sessaoAtual() {
  try {
    const { data } = await sb.auth.getSession();
    return data?.session ?? null;
  } catch {
    return null;
  }
}

/**
 * Entrar. Retorna { ok: true } ou { ok: false, erro: "<mensagem genérica>" }.
 * Nunca diz se o telefone existe ou não.
 */
export async function entrar(telefone55, senha, captchaToken, manter) {
  definirManterConectado(manter);
  try {
    const { error } = await sb.auth.signInWithPassword({
      email: emailDoLogin(telefone55),
      password: senha,
      options: { captchaToken },
    });
    if (!error) return { ok: true };
    return { ok: false, erro: mensagemDeErro(error) };
  } catch {
    return { ok: false, erro: "Sem conexão com o servidor. Verifique a internet e tente de novo." };
  }
}

function mensagemDeErro(error) {
  const cod = String(error?.code || "");
  const msg = String(error?.message || "").toLowerCase();
  if (cod.includes("captcha") || msg.includes("captcha")) {
    return "Não foi possível confirmar a verificação anti-robô. Tente de novo.";
  }
  if (error?.status === 429 || cod.includes("rate_limit")) {
    return "Muitas tentativas seguidas. Aguarde alguns minutos e tente de novo.";
  }
  if (error?.status === 0 || msg.includes("fetch")) {
    return "Sem conexão com o servidor. Verifique a internet e tente de novo.";
  }
  // invalid_credentials, usuário inexistente, desativado etc.: mesma mensagem
  return "Telefone ou senha incorretos.";
}

/** Sair (só deste aparelho). */
export async function sair() {
  try { await sb.auth.signOut({ scope: "local" }); } catch { /* segue limpando */ }
  armazenamento.removeItem("fk-sessao");
}

/** Pedido de nova senha (Edge Function pedir-redefinicao). */
export async function pedirNovaSenha(telefone55, captchaToken) {
  try {
    const r = await fetch(`${CONFIG.supabaseUrl}/functions/v1/pedir-redefinicao`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: CONFIG.supabaseChavePublica },
      body: JSON.stringify({ telefone: telefone55, captchaToken }),
    });
    const j = await r.json().catch(() => ({}));
    if (r.ok && j.ok) return { ok: true, mensagem: j.mensagem };
    if (j.erro === "captcha") return { ok: false, erro: "Não foi possível confirmar a verificação anti-robô. Tente de novo." };
    return { ok: false, erro: "Não foi possível enviar agora. Tente de novo mais tarde." };
  } catch {
    return { ok: false, erro: "Sem conexão com o servidor. Verifique a internet e tente de novo." };
  }
}

/** Confere se o app alcança o Supabase (não lê nenhum dado). */
export async function verificarConexao() {
  try {
    const r = await fetch(`${CONFIG.supabaseUrl}/auth/v1/health`, {
      headers: { apikey: CONFIG.supabaseChavePublica },
      cache: "no-store",
    });
    return r.ok;
  } catch {
    return false;
  }
}
