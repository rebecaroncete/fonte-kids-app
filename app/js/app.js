// =====================================================================
// Fonte Kids – início do app e navegação entre telas
// Navegação por "#/endereco" (funciona em hospedagem estática, sem servidor).
// Cada tela fica em js/telas/<nome>.js e exporta:
//   layout: "central" (sem barra do topo) ou "padrao"
//   titulo: texto da aba do navegador
//   render(alvo): desenha a tela dentro de "alvo"
// =====================================================================
import { CONFIG } from "../config.js";
import { el, montar, carregando, aviso } from "./ui.js";

const ROTAS = {
  "/entrar":  () => import("./telas/login.js"),
  "/vitrine": () => import("./telas/vitrine.js"),
};
const ROTA_INICIAL = "/entrar";

const raiz = document.getElementById("app");
let renderAtual = 0;

function rotaAtual() {
  const h = location.hash.replace(/^#/, "");
  return h.split("?")[0] || ROTA_INICIAL;
}

export function irPara(rota) {
  if (rotaAtual() === rota) mostrar(); else location.hash = rota;
}

function topo() {
  return el("header", { class: "topo" },
    el("img", { class: "topo__logo", src: "img/logo.png", alt: "" }),
    el("p", { class: "topo__nome", text: CONFIG.nomeApp }),
    el("nav", { class: "topo__acoes", "aria-label": "Atalhos" }));
}

async function mostrar() {
  const meu = ++renderAtual;
  const rota = rotaAtual();
  montar(raiz, carregando());

  let tela;
  try {
    tela = await (ROTAS[rota] || (() => import("./telas/nao-encontrada.js")))();
  } catch (e) {
    console.error(e);
    montar(raiz, el("main", { class: "conteudo" },
      aviso("erro", "Não foi possível abrir esta tela. Verifique a internet e tente de novo.")));
    return;
  }
  if (meu !== renderAtual) return; // usuário já navegou para outra tela

  document.title = tela.titulo ? `${tela.titulo} · ${CONFIG.nomeApp}` : CONFIG.nomeApp;
  const principal = el("main", { class: tela.layout === "central" ? "tela-central" : "conteudo", id: "principal", tabindex: "-1" });
  const partes = tela.layout === "central" ? [principal] : [topo(), principal,
    el("footer", { class: "rodape", text: `${CONFIG.nomeApp} · versão ${CONFIG.versao}` })];
  montar(raiz, partes);

  try {
    await tela.render(principal);
  } catch (e) {
    console.error(e);
    montar(principal, aviso("erro", "Algo deu errado nesta tela. Tente recarregar a página."));
  }
  principal.focus({ preventScroll: true });
  window.scrollTo(0, 0);
}

window.addEventListener("hashchange", mostrar);
mostrar();
