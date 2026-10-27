// =====================================================================
// Fonte Kids – início do app e navegação entre telas
// Navegação por "#/endereco" (funciona em hospedagem estática, sem servidor).
// Cada tela fica em js/telas/<nome>.js e exporta:
//   layout: "central" (sem barra do topo) ou "padrao"
//   titulo: texto da aba do navegador
//   render(alvo): desenha a tela dentro de "alvo"
// Rotas privadas exigem login; sem sessão, a pessoa vai para "Entrar".
// Enquanto o 1º acesso não termina (senha → termo → relações), qualquer rota
// privada leva para "#/primeiro-acesso", retomando de onde a pessoa parou.
// Telas "padrao" com login ganham a casca (js/casca.js): sino + menu por papel.
// App instalável (Etapa 6, js/pwa.js): service worker, aviso de versão nova,
// aviso sem conexão e convite de instalação (abaixo do topo, só com login).
// =====================================================================
import { CONFIG } from "../config.js";
import { el, montar, carregando, aviso, toast } from "./ui.js";
import { sb, sessaoAtual, sair, estadoPrimeiroAcesso, limparPerfilGuardado } from "./supabase.js";
import { montarTopo } from "./casca.js";
import { iniciarNotificacoes, pararNotificacoes } from "./notificacoes.js";
import { limparFotos } from "./foto.js";
import { iniciarPWA, faixaInstalacao } from "./pwa.js";

const ROTAS = {
  "/entrar":        { publica: true, soDeslogado: true, carregar: () => import("./telas/login.js") },
  "/esqueci-senha": { publica: true, soDeslogado: true, carregar: () => import("./telas/esqueci-senha.js") },
  "/vitrine":       { publica: true, carregar: () => import("./telas/vitrine.js") },
  "/inicio":        { publica: false, carregar: () => import("./telas/inicio.js") },
  "/primeiro-acesso": { publica: false, carregar: () => import("./telas/primeiro-acesso.js") },
  "/notificacoes":  { publica: false, carregar: () => import("./telas/notificacoes.js") },
  "/perfil":        { publica: false, carregar: () => import("./telas/perfil.js") },
  "/trocar-senha":  { publica: false, carregar: () => import("./telas/trocar-senha.js") },
  "/logins":        { publica: false, carregar: () => import("./telas/logins.js") },
  "/cadastros":     { publica: false, carregar: () => import("./telas/cadastros.js") },
  "/ficha":         { publica: false, carregar: () => import("./telas/ficha.js") },
  "/minha-familia": { publica: false, carregar: () => import("./telas/minha-familia.js") },
  "/pendencias":    { publica: false, carregar: () => import("./telas/pendencias.js") },
};

/** Endereço interno conhecido? (usado para abrir links de notificações) */
export function rotaExiste(rota) { return Object.prototype.hasOwnProperty.call(ROTAS, rota); }
const ROTA_PRIMEIRO_ACESSO = "/primeiro-acesso";
const ROTA_INICIAL = "/entrar";
const ROTA_LOGADO = "/inicio";

const raiz = document.getElementById("app");
let renderAtual = 0;

// ---------- Situação do 1º acesso (guardada só na memória desta aba) ----------
// etapa: trocar_senha | aceitar_termo | informar_relacoes | pronto | sem_acesso
let etapaGuardada = null;
let relacoesAdiadas = false; // "Deixar para depois" vale só até sair ou fechar a aba

/** A tela do 1º acesso avisa aqui quando a pessoa avança de passo. */
export function definirEtapaAcesso(etapa) { etapaGuardada = etapa; }
/** Relação não informada é só aviso: a pessoa pode deixar para depois. */
export function adiarRelacoes() { relacoesAdiadas = true; }

async function precisaPrimeiroAcesso() {
  if (!etapaGuardada) {
    const r = await estadoPrimeiroAcesso();
    if (!r.ok) return false; // sem resposta: a tela mostra o erro; o banco continua protegendo os dados
    etapaGuardada = r.etapa;
  }
  if (etapaGuardada === "trocar_senha" || etapaGuardada === "aceitar_termo") return true;
  return etapaGuardada === "informar_relacoes" && !relacoesAdiadas;
}

function rotaAtual() {
  const h = location.hash.replace(/^#/, "");
  return h.split("?")[0] || ROTA_INICIAL;
}

export function irPara(rota) {
  if (rotaAtual() === rota) mostrar(); else location.hash = rota;
}

export async function fazerSair() {
  await pararNotificacoes();
  await sair();
  toast("info", "Você saiu.");
  irPara("/entrar");
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
  if (def && !def.publica && sessao && rota !== ROTA_PRIMEIRO_ACESSO) {
    const precisa = await precisaPrimeiroAcesso();
    if (meu !== renderAtual) return;
    if (precisa) { irPara(ROTA_PRIMEIRO_ACESSO); return; }
  }

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
  if (sessao && tela.layout !== "central") iniciarNotificacoes(); // sino (só depois do 1º acesso)
  const partes = tela.layout === "central" ? [principal] : [montarTopo({ logado: !!sessao, rota, aoSair: fazerSair }),
    sessao ? faixaInstalacao() : null, principal,
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
  if (evento === "SIGNED_IN") etapaGuardada = null;
  if (evento === "SIGNED_OUT") { etapaGuardada = null; relacoesAdiadas = false; limparPerfilGuardado(); limparFotos(); pararNotificacoes(); }
  if (evento === "SIGNED_OUT") {
    const def = ROTAS[rotaAtual()];
    if (!def || !def.publica) setTimeout(() => irPara("/entrar"), 0);
  }
});

window.addEventListener("hashchange", mostrar);
iniciarPWA();
mostrar();
