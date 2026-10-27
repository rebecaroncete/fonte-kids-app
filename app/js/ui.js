// =====================================================================
// Fonte Kids – utilidades de interface
// Regra de segurança: textos sempre via textContent (nunca innerHTML com
// dados), para que nada vindo do banco possa virar código na página.
// =====================================================================

/** Cria um elemento: el("button", { class: "botao", onclick: fn }, "Texto") */
export function el(tag, attrs = {}, ...filhos) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === "class") n.className = v;
    else if (k === "text") n.textContent = v;
    else if (k.startsWith("on") && typeof v === "function") n.addEventListener(k.slice(2), v);
    else if (v === true) n.setAttribute(k, "");
    else n.setAttribute(k, String(v));
  }
  for (const f of filhos.flat()) {
    if (f === undefined || f === null || f === false) continue;
    n.append(f instanceof Node ? f : document.createTextNode(String(f)));
  }
  return n;
}

const ICONES = { info: "i", sucesso: "✓", atencao: "!", erro: "×" };

/** Caixa de aviso. tipo: info | sucesso | atencao | erro */
export function aviso(tipo, texto) {
  const classe = tipo === "info" ? "aviso" : `aviso aviso--${tipo}`;
  return el("div", { class: classe, role: tipo === "erro" ? "alert" : "status" },
    el("span", { class: "aviso__icone", "aria-hidden": "true", text: ICONES[tipo] || "i" }),
    el("p", { text: texto }));
}

/** Mensagem rápida que some sozinha */
export function toast(tipo, texto, ms = 4000) {
  let pilha = document.querySelector(".toasts");
  if (!pilha) { pilha = el("div", { class: "toasts", "aria-live": "polite" }); document.body.append(pilha); }
  const a = aviso(tipo, texto);
  pilha.append(a);
  setTimeout(() => a.remove(), ms);
}

export function carregando(texto = "Carregando…") {
  return el("div", { class: "carregando", role: "status" },
    el("span", { class: "girando", "aria-hidden": "true" }), texto);
}

/** Troca todo o conteúdo de um elemento */
export function montar(alvo, ...filhos) {
  alvo.replaceChildren(...filhos.flat().filter(Boolean));
}

/** Iniciais para o avatar (sem foto) */
export function iniciais(nome = "") {
  const p = nome.trim().split(/\s+/).filter(Boolean);
  return ((p[0]?.[0] || "") + (p.length > 1 ? p[p.length - 1][0] : "")).toUpperCase() || "?";
}

// ---------- Telefone (login) ----------

/** Só dígitos */
export const digitos = (s) => String(s || "").replace(/\D/g, "");

/** Máscara enquanto digita: (27) 99999-9999 */
export function mascararTelefone(valor) {
  let d = digitos(valor);
  if (d.startsWith("55") && d.length > 11) d = d.slice(2);
  d = d.slice(0, 11);
  if (d.length <= 2) return d ? `(${d}` : "";
  if (d.length <= 6) return `(${d.slice(0, 2)}) ${d.slice(2)}`;
  if (d.length <= 10) return `(${d.slice(0, 2)}) ${d.slice(2, 6)}-${d.slice(6)}`;
  return `(${d.slice(0, 2)}) ${d.slice(2, 7)}-${d.slice(7)}`;
}

/** Telefone no padrão do banco (55 + DDD + número) ou null se inválido */
export function telefoneParaLogin(valor) {
  let d = digitos(valor);
  if (d.startsWith("55") && (d.length === 12 || d.length === 13)) d = d.slice(2);
  if (d.length !== 10 && d.length !== 11) return null;
  if (d[0] === "0") return null;
  return "55" + d;
}
