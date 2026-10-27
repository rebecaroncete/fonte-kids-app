// =====================================================================
// Fonte Kids – fotos privadas (Fase 10 · Etapa 5B)
// O app nunca monta o link da foto: pede à Edge Function "foto-assinada",
// que pergunta ao BANCO (com o login da pessoa) se ela pode ver a foto e
// devolve um link temporário (5 min). Sem permissão ou sem foto → iniciais.
// O link fica só na memória desta aba, até 1 min antes de vencer.
// Listas pedem as fotos em lote (até 100 por chamada), só dos itens
// que estão aparecendo na tela.
// =====================================================================
import { CONFIG } from "../config.js";
import { el, iniciais } from "./ui.js";
import { sessaoAtual } from "./supabase.js";

const guardadas = new Map(); // "tipo:id" → { url, vence }  (url null = sem foto)
const MARGEM_MS = 60 * 1000;
const MAX_POR_CHAMADA = 100;
const LINK_OK = /^https:\/\/(res|api)\.cloudinary\.com\//;

function guardada(tipo, id) {
  const g = guardadas.get(`${tipo}:${id}`);
  return g && g.vence - MARGEM_MS > Date.now() ? g : null;
}

/**
 * Links temporários de várias fotos de uma vez.
 * Retorna Map(id → url); quem não tem foto ou permissão fica de fora.
 * tipo: "crianca" | "voluntaria"
 */
export async function linksFotos(tipo, ids) {
  const resultado = new Map();
  const faltam = [];
  for (const id of new Set(ids)) {
    const g = guardada(tipo, id);
    if (g) { if (g.url) resultado.set(id, g.url); } else faltam.push(id);
  }
  if (!faltam.length) return resultado;

  const s = await sessaoAtual();
  if (!s) return resultado;
  for (let i = 0; i < faltam.length; i += MAX_POR_CHAMADA) {
    const parte = faltam.slice(i, i + MAX_POR_CHAMADA);
    try {
      const r = await fetch(`${CONFIG.supabaseUrl}/functions/v1/foto-assinada`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: CONFIG.supabaseChavePublica,
          Authorization: `Bearer ${s.access_token}`,
        },
        body: JSON.stringify({ tipo, ids: parte }),
      });
      if (!r.ok) continue;
      const j = await r.json().catch(() => ({}));
      const vence = Date.parse(j.expira_em) || Date.now() + 4 * 60 * 1000;
      for (const id of parte) {
        const url = j?.fotos?.[id];
        const valido = url && LINK_OK.test(url) ? url : null;
        guardadas.set(`${tipo}:${id}`, { url: valido, vence }); // sem foto também fica guardado (evita pedir de novo)
        if (valido) resultado.set(id, valido);
      }
    } catch { /* sem internet: ficam as iniciais */ }
  }
  return resultado;
}

/** Link temporário de uma foto (ou null). */
export async function linkFoto(tipo, id) {
  return (await linksFotos(tipo, [id])).get(id) || null;
}

/** Esquece os links (ao sair). */
export function limparFotos() { guardadas.clear(); }

/** Coloca a foto dentro de um avatar (só depois que ela carregar). */
export function colocarFoto(caixa, url, tipo, id) {
  if (!url || !caixa.isConnected) return;
  const img = el("img", { src: url, alt: "", referrerpolicy: "no-referrer", decoding: "async", loading: "lazy" });
  img.addEventListener("load", () => caixa.replaceChildren(img), { once: true });
  img.addEventListener("error", () => guardadas.delete(`${tipo}:${id}`), { once: true });
}

/** Avatar pequeno (lista) com iniciais; a foto entra depois, por preencherFotos(). */
export function avatarLista(tipo, id, nome) {
  return el("div", { class: "avatar", "aria-hidden": "true", "data-foto-tipo": tipo, "data-foto-id": id }, iniciais(nome));
}

/** Busca, em lote, as fotos dos avatares de lista dentro de "area" que ainda estão sem foto. */
export async function preencherFotos(area) {
  const caixas = [...area.querySelectorAll(".avatar[data-foto-id]:not([data-foto-ok])")];
  const porTipo = new Map();
  for (const c of caixas) {
    c.setAttribute("data-foto-ok", "1");
    const t = c.getAttribute("data-foto-tipo");
    if (!porTipo.has(t)) porTipo.set(t, []);
    porTipo.get(t).push(c);
  }
  for (const [tipo, lista] of porTipo) {
    const links = await linksFotos(tipo, lista.map((c) => c.getAttribute("data-foto-id")));
    for (const c of lista) {
      const id = c.getAttribute("data-foto-id");
      colocarFoto(c, links.get(id), tipo, id);
    }
  }
}

/**
 * Avatar grande (ficha) com as iniciais; troca pela foto quando ela chegar.
 */
export function avatarComFoto(tipo, id, nome) {
  const caixa = el("div", { class: "avatar avatar--foto", role: "img", "aria-label": `Foto de ${nome || "pessoa"}` },
    el("span", { "aria-hidden": "true", text: iniciais(nome) }));
  linkFoto(tipo, id).then((url) => colocarFoto(caixa, url, tipo, id));
  return caixa;
}
