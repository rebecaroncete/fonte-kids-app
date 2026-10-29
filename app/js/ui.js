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

// ---------- Menu ⋯ (ações secundárias de um cartão) – Etapa 7 ----------
const SVG_NS = "http://www.w3.org/2000/svg";
function iconeMais() {
  const s = document.createElementNS(SVG_NS, "svg");
  s.setAttribute("viewBox", "0 0 24 24"); s.setAttribute("class", "icone-linha"); s.setAttribute("aria-hidden", "true");
  for (const cx of [5, 12, 19]) {
    const c = document.createElementNS(SVG_NS, "circle");
    c.setAttribute("cx", cx); c.setAttribute("cy", 12); c.setAttribute("r", 1);
    s.append(c);
  }
  return s;
}
let fecharMenuAcoes = null;

/**
 * Botão ⋯ com uma lista de ações.
 * itens: [{ texto, acao, perigo }] (itens nulos são ignorados).
 * rotulo: texto para o leitor de tela (ex.: "Mais ações para Ana").
 */
export function menuAcoes(itens, rotulo = "Mais ações") {
  const validos = itens.filter(Boolean);
  if (!validos.length) return null;
  const lista = el("ul", { class: "menu__lista" }, validos.map((i) => el("li", {},
    el("button", { class: i.perigo ? "menu__item menu__item--perigo" : "menu__item", type: "button", text: i.texto,
      onclick: () => { fechar(); i.acao(); } }))));
  const painel = el("div", { class: "menu", hidden: true }, lista);
  const botao = el("button", { class: "botao-icone mais-acoes__botao", type: "button", "aria-label": rotulo, "aria-expanded": "false" }, iconeMais());

  function foraOuEsc(e) {
    if (e.type === "keydown" ? e.key === "Escape" : !painel.contains(e.target) && !botao.contains(e.target)) {
      fechar(); if (e.type === "keydown") botao.focus();
    }
  }
  function fechar() {
    painel.hidden = true; botao.setAttribute("aria-expanded", "false");
    document.removeEventListener("click", foraOuEsc, true); document.removeEventListener("keydown", foraOuEsc);
    if (fecharMenuAcoes === fechar) fecharMenuAcoes = null;
  }
  function abrir() {
    if (fecharMenuAcoes) fecharMenuAcoes();
    painel.hidden = false; botao.setAttribute("aria-expanded", "true");
    document.addEventListener("click", foraOuEsc, true); document.addEventListener("keydown", foraOuEsc);
    fecharMenuAcoes = fechar;
    painel.querySelector("button")?.focus();
  }
  botao.addEventListener("click", () => (painel.hidden ? abrir() : fechar()));
  return el("div", { class: "mais-acoes" }, botao, painel);
}
