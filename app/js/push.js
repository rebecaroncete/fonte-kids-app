// =====================================================================
// Fonte Kids – push no celular (Fase 7)
// Liga/desliga o push NESTE aparelho para o login atual. O app nunca pede
// sozinho: só quando a pessoa toca em "Ativar" (cartão em Avisos ou chave
// no Perfil). O aparelho fica guardado no banco só pelas funções
// salvar_push/remover_push; ao sair, o push deste aparelho é desligado.
// A chave VAPID daqui é a PÚBLICA (a privada fica só nos segredos do
// Supabase). No iPhone/iPad o push só existe com o app instalado na tela
// inicial (iOS 16.4 ou mais novo).
// =====================================================================
import { CONFIG } from "../config.js";
import { salvarPush, removerPush, sessaoAtual } from "./supabase.js";
import { estaInstalado } from "./pwa.js";

// Login dono do push deste aparelho (só o id interno, nenhum dado pessoal).
// Num aparelho compartilhado, quem entra depois NÃO herda o push de outro.
const CHAVE_DONO = "fk_push_dono";
const lerDono = () => { try { return localStorage.getItem(CHAVE_DONO) || ""; } catch { return ""; } };
const gravarDono = (uid) => { try { if (uid) localStorage.setItem(CHAVE_DONO, uid); else localStorage.removeItem(CHAVE_DONO); } catch { /* ignore */ } };
const uidAtual = async () => (await sessaoAtual())?.user?.id || "";

const ios = () => {
  const ua = navigator.userAgent || "";
  return /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1);
};

function chaveAplicacao() {
  const s = CONFIG.vapidChavePublica;
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

function suportaPush() {
  return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
    && window.isSecureContext && !!CONFIG.vapidChavePublica;
}

async function registro() {
  // o service worker é registrado em js/pwa.js; aqui só espera ficar pronto
  return Promise.race([
    navigator.serviceWorker.ready,
    new Promise((_, nao) => setTimeout(() => nao(new Error("sem service worker")), 8000)),
  ]);
}

async function inscricaoAtual() {
  if (!suportaPush()) return null;
  try { return await (await registro()).pushManager.getSubscription(); } catch { return null; }
}

/**
 * Situação do push neste aparelho:
 *   "ativo" | "desligado" | "bloqueado" (permissão negada no navegador)
 *   | "instalar" (iPhone sem o app instalado) | "sem_suporte"
 */
export async function situacaoPush() {
  if (ios() && !estaInstalado()) return "instalar";
  if (!suportaPush()) return "sem_suporte";
  if (Notification.permission === "denied") return "bloqueado";
  const insc = await inscricaoAtual();
  const meu = insc && lerDono() === (await uidAtual());
  return meu && Notification.permission === "granted" ? "ativo" : "desligado";
}

/** Pede a permissão (só depois de um toque) e grava o aparelho. Devolve { ok, erro }. */
export async function ativarPush() {
  const s = await situacaoPush();
  if (s === "instalar") return { ok: false, erro: "No iPhone, instale o app na tela inicial primeiro (Compartilhar → Adicionar à Tela de Início)." };
  if (s === "sem_suporte") return { ok: false, erro: "Este navegador não recebe notificações. Tente pelo Chrome (Android) ou com o app instalado." };
  if (s === "bloqueado") return { ok: false, erro: "As notificações estão bloqueadas para este site. Libere nas configurações do navegador." };

  const permissao = await Notification.requestPermission();
  if (permissao !== "granted") return { ok: false, erro: "Sem permissão, o celular não mostra os avisos. Você continua vendo tudo na aba Avisos." };
  try {
    const reg = await registro();
    let insc = await reg.pushManager.getSubscription();
    if (!insc) insc = await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: chaveAplicacao() });
    const j = insc.toJSON();
    const r = await salvarPush(j.endpoint, j.keys?.p256dh, j.keys?.auth, nomeAparelho());
    if (!r.ok) { try { await insc.unsubscribe(); } catch { /* ignore */ } return r; }
    gravarDono(await uidAtual());
    return { ok: true };
  } catch {
    return { ok: false, erro: "Não foi possível ativar agora. Tente de novo em instantes." };
  }
}

/** Desliga neste aparelho (também ao sair). */
export async function desativarPush() {
  gravarDono("");
  const insc = await inscricaoAtual();
  if (!insc) return { ok: true };
  const endpoint = insc.endpoint;
  try { await insc.unsubscribe(); } catch { /* ignore */ }
  return removerPush(endpoint);
}

/**
 * Ao entrar no app: se o aparelho já tem push ligado PARA ESTE LOGIN, grava
 * de novo (o navegador pode ter trocado a inscrição). Se era de outro login,
 * desliga neste aparelho (a pessoa ativa de novo se quiser). Silencioso.
 */
export async function renovarPush() {
  try {
    if (!suportaPush() || Notification.permission !== "granted") return;
    const insc = await inscricaoAtual();
    if (!insc) return;
    const uid = await uidAtual();
    if (!uid) return;
    if (lerDono() !== uid) { gravarDono(""); try { await insc.unsubscribe(); } catch { /* ignore */ } return; }
    const j = insc.toJSON();
    await salvarPush(j.endpoint, j.keys?.p256dh, j.keys?.auth, nomeAparelho());
  } catch { /* ignore */ }
}

/** Só o tipo do aparelho (nada que identifique a pessoa). */
function nomeAparelho() {
  const ua = navigator.userAgent || "";
  if (ios()) return "iPhone/iPad";
  if (/Android/i.test(ua)) return "Android";
  if (/Windows/i.test(ua)) return "Windows";
  if (/Mac/i.test(ua)) return "Mac";
  return "Outro";
}
