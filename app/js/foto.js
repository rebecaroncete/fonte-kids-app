// =====================================================================
// Fonte Kids – fotos privadas (Fase 10 · Etapa 5B)
// O app nunca monta o link da foto: pede à Edge Function "foto-assinada",
// que pergunta ao BANCO (com o login da pessoa) se ela pode ver a foto e
// devolve um link temporário (5 min). Sem permissão ou sem foto → iniciais.
// O link fica só na memória desta aba, até 1 min antes de vencer.
// =====================================================================
import { CONFIG } from "../config.js";
import { el, iniciais } from "./ui.js";
import { sessaoAtual } from "./supabase.js";

const guardadas = new Map(); // "tipo:id" → { url, vence }
const MARGEM_MS = 60 * 1000;

/** Link temporário da foto (ou null). tipo: "crianca" | "voluntaria" */
export async function linkFoto(tipo, id) {
  const chave = `${tipo}:${id}`;
  const g = guardadas.get(chave);
  if (g && g.vence - MARGEM_MS > Date.now()) return g.url;

  const s = await sessaoAtual();
  if (!s) return null;
  try {
    const r = await fetch(`${CONFIG.supabaseUrl}/functions/v1/foto-assinada`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: CONFIG.supabaseChavePublica,
        Authorization: `Bearer ${s.access_token}`,
      },
      body: JSON.stringify({ tipo, ids: [id] }),
    });
    if (!r.ok) return null;
    const j = await r.json().catch(() => ({}));
    const url = j?.fotos?.[id];
    if (!url || !/^https:\/\/(res|api)\.cloudinary\.com\//.test(url)) { guardadas.delete(chave); return null; }
    guardadas.set(chave, { url, vence: Date.parse(j.expira_em) || Date.now() + 4 * 60 * 1000 });
    return url;
  } catch {
    return null;
  }
}

/** Esquece os links (ao sair). */
export function limparFotos() { guardadas.clear(); }

/**
 * Avatar grande com as iniciais; troca pela foto quando ela chegar.
 * A foto só é pedida quando a ficha abre (economiza a cota do Cloudinary).
 */
export function avatarComFoto(tipo, id, nome) {
  const caixa = el("div", { class: "avatar avatar--foto", role: "img", "aria-label": `Foto de ${nome || "pessoa"}` },
    el("span", { "aria-hidden": "true", text: iniciais(nome) }));
  linkFoto(tipo, id).then((url) => {
    if (!url || !caixa.isConnected) return;
    const img = el("img", { src: url, alt: "", referrerpolicy: "no-referrer", decoding: "async" });
    img.addEventListener("load", () => caixa.replaceChildren(img), { once: true });
    img.addEventListener("error", () => guardadas.delete(`${tipo}:${id}`), { once: true });
  });
  return caixa;
}
