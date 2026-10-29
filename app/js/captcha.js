// =====================================================================
// Fonte Kids – verificação anti-robô (Cloudflare Turnstile)
// Só a chave PÚBLICA (site key) fica no app (config.js).
// A chave secreta fica no painel do Supabase (Auth e Edge Functions).
// =====================================================================
import { CONFIG } from "../config.js";

const URL_SCRIPT = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";
let carregandoScript = null;

function carregarScript() {
  if (window.turnstile) return Promise.resolve();
  if (carregandoScript) return carregandoScript;
  carregandoScript = new Promise((ok, falha) => {
    const s = document.createElement("script");
    s.src = URL_SCRIPT;
    s.async = true;
    s.onload = () => ok();
    s.onerror = () => { carregandoScript = null; falha(new Error("captcha")); };
    document.head.append(s);
  });
  return carregandoScript;
}

/**
 * Coloca o captcha dentro de "lugar".
 * aoMudar(temToken) é chamado quando o token aparece ou expira.
 * Retorna { token(), reiniciar() }.
 */
export async function criarCaptcha(lugar, aoMudar = () => {}) {
  let token = "";
  let id = null;
  const controle = {
    token: () => token,
    reiniciar() {
      token = ""; aoMudar(false);
      try { if (id !== null) window.turnstile.reset(id); } catch { /* ignore */ }
    },
  };
  if (!CONFIG.turnstileChavePublica) throw new Error("captcha-sem-chave");
  await carregarScript();
  id = window.turnstile.render(lugar, {
    sitekey: CONFIG.turnstileChavePublica,
    language: "pt-br",
    theme: "light",
    action: lugar.dataset.acao || "login",
    callback: (t) => { token = t; aoMudar(true); },
    "expired-callback": () => { token = ""; aoMudar(false); },
    "error-callback": () => { token = ""; aoMudar(false); },
  });
  return controle;
}
