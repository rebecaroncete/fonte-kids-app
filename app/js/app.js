// =====================================================================
// Fonte Kids – início do app e navegação entre telas
// Navegação por "#/endereco" (funciona em hospedagem estática, sem servidor).
// Cada tela fica em js/telas/<nome>.js e exporta:
//   layout: "central" (sem barra do topo) ou "padrao"
//   titulo: texto da aba do navegador
//   render(alvo): desenha a tela dentro de "alvo"
// Rotas privadas exigem login; sem sessão, a pessoa vai para "Entrar".
// =====================================================================
import { CONFIG } from "../config.js";
import { el, montar, carregando, aviso, toast } from "./ui.js";
import { sb, sessaoAtual, sair } from "./supabase.js";

const ROTAS = {
  "/entrar":        { publica: true, soDeslogado: true, carregar: () => import("./telas/login.js") },
  "/esqueci-senha": { publica: true, soDeslogado: true, carregar: () => import("./telas/esqueci-senha.js") },
  "/vitrine":       { publica: true, carregar: () => import("./telas/vitrine.js") },
  "/inicio":        { publica: false, carregar: () => import("./telas/inicio.js") },
};
const ROTA_INICIAL = "/entrar";
const ROTA_LOGADO = "/inicio";

const raiz = document.getElementById("app");
let renderAtual = 0;

function rotaAtual() {
  const h = location.hash.replace(/^#/, "");
  return h.split("?")[0] || ROTA_INICIAL;
}

export function irPara(rota) {
  if (rotaAtual() === rota) mostrar(); else location.hash = rota;
}

async function fazerSair() {
  await sair();
  toast("info", "Você saiu.");
  irPara("/entrar");
}

function topo(logado) {
  return el("header", { class: "topo" },
    el("img", { class: "topo__logo", src: "img/logo.png", alt: "" }),
    el("p", { class: "topo__nome", text: CONFIG.nomeApp }),
    el("nav", { class: "topo__acoes", "aria-label": "Atalhos" },
      logado ? el("button", { class: "botao botao--texto", type: "button", text: "Sair", onclick: fazerSair }) : null));
}

async function mostrar() {
  const meu = ++renderAtual;
  const rota = rotaAtual();
  const def = ROTAS[rota];
  montar(raiz, carregando());

  const sessao = await sessaoAtual();
  if (meu !== renderAtual) return;

  // Proteção das rotas
  if (def && !def.publica && !sessao) { irPara("/entrar"); return; }
  if (def && def.soDeslogado && sessao) { irPara(ROTA_LOGADO); return; }

  let tela;
  try {
    tela = await (def ? def.carregar() : import("./telas/nao-encontrada.js"));
  } catch (e) {
    console.error(e);
    montar(raiz, el("main", { class: "conteudo" },
      aviso("erro", "Não foi possível abrir esta tela. Verifique a internet e tente de novo.")));
    return;
  }
  if (meu !== renderAtual) return; // usuário já navegou para outra tela

  document.title = tela.titulo ? `${tela.titulo} · ${CONFIG.nomeApp}` : CONFIG.nomeApp;
  const principal = el("main", { class: tela.layout === "central" ? "tela-central" : "conteudo", id: "principal", tabindex: "-1" });
  const partes = tela.layout === "central" ? [principal] : [topo(!!sessao), principal,
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

// Sessão encerrada (sair em outra aba, sessão expirada): volta para "Entrar".
sb.auth.onAuthStateChange((evento) => {
  if (evento === "SIGNED_OUT") {
    const def = ROTAS[rotaAtual()];
    if (!def || !def.publica) setTimeout(() => irPara("/entrar"), 0);
  }
});

window.addEventListener("hashchange", mostrar);
mostrar();
