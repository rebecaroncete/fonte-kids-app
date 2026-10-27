// =====================================================================
// Fonte Kids – casca do app (Fase 10 · Etapa 4)
// Barra do topo com logo, sino de notificações e menu.
// O menu mostra só as telas que já existem, filtradas pelos papéis do
// login. Para incluir uma tela nova: acrescente um item em ITENS_MENU
// (com "papeis" quando for só para alguns papéis).
// =====================================================================
import { CONFIG } from "../config.js";
import { el } from "./ui.js";
import { meuPerfil } from "./supabase.js";
import { aoMudarContagem } from "./notificacoes.js";

// papeis: admin | pastor | lider | recepcao | voluntaria | responsavel
// (sem "papeis" = todos os logins)
const ITENS_MENU = [
  { rota: "/inicio", texto: "Início" },
  { rota: "/notificacoes", texto: "Notificações" },
  { rota: "/perfil", texto: "Meu perfil" },
  { rota: "/trocar-senha", texto: "Trocar senha" },
  { rota: "/logins", texto: "Gestão de logins", papeis: ["admin", "pastor", "lider"] },
];

const SVG = "http://www.w3.org/2000/svg";
const ICONES = {
  sino: "M12 3a6 6 0 0 0-6 6v3.6l-1.6 2.7A1 1 0 0 0 5.3 17h13.4a1 1 0 0 0 .9-1.7L18 12.6V9a6 6 0 0 0-6-6zm-2.5 15.5a2.5 2.5 0 0 0 5 0z",
  menu: "M4 6h16v2.2H4zm0 4.9h16v2.2H4zm0 4.9h16V18H4z",
};

function icone(nome) {
  const s = document.createElementNS(SVG, "svg");
  s.setAttribute("viewBox", "0 0 24 24");
  s.setAttribute("aria-hidden", "true");
  s.setAttribute("class", "icone");
  const p = document.createElementNS(SVG, "path");
  p.setAttribute("d", ICONES[nome]);
  s.append(p);
  return s;
}

let desligarContagem = null;
let fecharMenuAberto = null;

/** Barra do topo. opcoes: { logado, rota, aoSair } */
export function montarTopo({ logado, rota, aoSair }) {
  if (desligarContagem) { desligarContagem(); desligarContagem = null; }
  if (fecharMenuAberto) { fecharMenuAberto(); fecharMenuAberto = null; }

  const marca = el("a", { class: "topo__marca", href: logado ? "#/inicio" : "#/entrar", "aria-label": `${CONFIG.nomeApp} – início` },
    el("img", { class: "topo__logo", src: "img/logo.png", alt: "" }),
    el("span", { class: "topo__nome", text: CONFIG.nomeApp }));

  if (!logado) return el("header", { class: "topo" }, marca);

  // ---------- Sino ----------
  const contagem = el("span", { class: "sino__contagem", hidden: true, "aria-hidden": "true" });
  const sino = el("a", { class: "botao-icone", href: "#/notificacoes", "aria-label": "Notificações" },
    icone("sino"), contagem);
  if (rota === "/notificacoes") sino.setAttribute("aria-current", "page");
  desligarContagem = aoMudarContagem((n) => {
    contagem.hidden = n < 1;
    contagem.textContent = n > 9 ? "9+" : String(n);
    sino.setAttribute("aria-label", n > 0 ? `Notificações, ${n} nova${n > 1 ? "s" : ""}` : "Notificações");
  });

  // ---------- Menu ----------
  const lista = el("ul", { class: "menu__lista" });
  const painel = el("nav", { class: "menu", id: "menu-principal", "aria-label": "Menu", hidden: true }, lista);
  const botaoMenu = el("button", {
    class: "botao-icone", type: "button", "aria-label": "Abrir menu",
    "aria-expanded": "false", "aria-controls": "menu-principal",
  }, icone("menu"));

  let preenchido = false;
  async function preencher() {
    if (preenchido) return;
    preenchido = true;
    const perfil = await meuPerfil();
    const meusPapeis = perfil.ok ? perfil.papeis.map((p) => p.papel) : [];
    const itens = ITENS_MENU.filter((i) => !i.papeis || i.papeis.some((p) => meusPapeis.includes(p)));
    lista.replaceChildren(
      ...itens.map((i) => el("li", {},
        el("a", { class: "menu__item", href: `#${i.rota}`, "aria-current": i.rota === rota ? "page" : null, text: i.texto }))),
      el("li", {}, el("button", { class: "menu__item menu__item--sair", type: "button", text: "Sair", onclick: () => { fechar(); aoSair(); } })));
  }

  function aoClicarFora(e) { if (!painel.contains(e.target) && !botaoMenu.contains(e.target)) fechar(); }
  function aoTeclar(e) { if (e.key === "Escape") { fechar(); botaoMenu.focus(); } }

  function fechar() {
    painel.hidden = true;
    botaoMenu.setAttribute("aria-expanded", "false");
    botaoMenu.setAttribute("aria-label", "Abrir menu");
    document.removeEventListener("click", aoClicarFora, true);
    document.removeEventListener("keydown", aoTeclar);
  }
  async function abrir() {
    await preencher();
    painel.hidden = false;
    botaoMenu.setAttribute("aria-expanded", "true");
    botaoMenu.setAttribute("aria-label", "Fechar menu");
    document.addEventListener("click", aoClicarFora, true);
    document.addEventListener("keydown", aoTeclar);
    painel.querySelector("a, button")?.focus();
  }
  botaoMenu.addEventListener("click", () => (painel.hidden ? abrir() : fechar()));
  painel.addEventListener("click", (e) => { if (e.target.closest("a")) fechar(); });
  fecharMenuAberto = fechar;

  return el("header", { class: "topo" },
    marca,
    el("div", { class: "topo__acoes" }, sino, botaoMenu),
    painel);
}
