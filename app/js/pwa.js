// =====================================================================
// Fonte Kids – app instalável (Fase 10 · Etapa 6)
//  • registra o service worker (sw.js), que guarda só os arquivos do app;
//  • aviso "Versão nova disponível – Atualizar" (procura ao abrir, ao voltar
//    para o app e a cada 30 min);
//  • aviso "Sem conexão";
//  • convite "Instale o app na tela inicial" (só no navegador, depois do
//    login; "Agora não" esconde por 24 h). No aparelho fica guardada só a
//    data do "Agora não" — nenhum dado pessoal.
// =====================================================================
import { el } from "./ui.js";

const CHAVE_ADIADO = "fk_convite_instalar_ate";
const ADIAR_MS = 24 * 60 * 60 * 1000;
const VERIFICAR_MS = 30 * 60 * 1000;

let pedidoInstalacao = null;   // evento do Chrome/Android para o botão "Instalar"
let adiadoNaMemoria = 0;       // se o navegador não deixar guardar a data
const faixasConvite = new Set();

// ---------- Situação do aparelho ----------

export function estaInstalado() {
  return window.matchMedia?.("(display-mode: standalone)").matches
    || window.matchMedia?.("(display-mode: fullscreen)").matches
    || window.navigator.standalone === true;
}

function aparelho() {
  const ua = navigator.userAgent || "";
  const ios = /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/i.test(ua) && navigator.maxTouchPoints > 1);
  if (ios) return { tipo: "ios", safari: !/CriOS|FxiOS|EdgiOS|OPiOS|GSA\//i.test(ua) };
  if (/Android/i.test(ua)) return { tipo: "android", samsung: /SamsungBrowser/i.test(ua) };
  return { tipo: "computador" };
}

function adiadoAte() {
  try { return Number(localStorage.getItem(CHAVE_ADIADO)) || adiadoNaMemoria; } catch { return adiadoNaMemoria; }
}
function adiar() {
  adiadoNaMemoria = Date.now() + ADIAR_MS;
  try { localStorage.setItem(CHAVE_ADIADO, String(adiadoNaMemoria)); } catch { /* sem armazenamento */ }
}

// ---------- Convite de instalação ----------

function passos(ap) {
  if (ap.tipo === "ios") {
    if (!ap.safari) {
      return [
        "Abra este mesmo endereço no Safari (o navegador da bússola azul).",
        "Toque em Compartilhar (o quadrado com a seta para cima).",
        "Toque em \"Adicionar à Tela de Início\" e depois em \"Adicionar\".",
      ];
    }
    return [
      "Toque em Compartilhar (o quadrado com a seta para cima), na barra do Safari.",
      "Role a lista e toque em \"Adicionar à Tela de Início\".",
      "Toque em \"Adicionar\". O ícone do Fonte Kids aparece na tela inicial.",
    ];
  }
  if (ap.tipo === "android" && ap.samsung) {
    return [
      "Toque no menu ≡ (embaixo, à direita).",
      "Toque em \"Adicionar página a\" e escolha \"Tela inicial\".",
    ];
  }
  return [
    "Toque no menu ⋮ (no alto, à direita do endereço).",
    "Toque em \"Instalar app\" ou \"Adicionar à tela inicial\".",
    "Confirme. O ícone do Fonte Kids aparece na tela inicial.",
  ];
}

function deveConvidar() {
  if (estaInstalado()) return false;
  if (Date.now() < adiadoAte()) return false;
  const ap = aparelho();
  // No computador só convida quando o navegador oferece instalação de verdade.
  if (ap.tipo === "computador") return !!pedidoInstalacao;
  return true;
}

/** Faixa do convite (ou null). Usada na casca, abaixo da barra do topo. */
export function faixaInstalacao() {
  if (!deveConvidar()) return null;
  const ap = aparelho();

  const lista = el("ol", { class: "instalar__passos" }, passos(ap).map((t) => el("li", { text: t })));
  const acoes = el("div", { class: "linha" });
  const faixa = el("section", { class: "instalar", "aria-labelledby": "instalar-titulo" },
    el("img", { class: "instalar__icone", src: "img/icones/icone-192.png", alt: "" }),
    el("div", { class: "instalar__texto" },
      el("h2", { class: "instalar__titulo", id: "instalar-titulo", text: "Instale o app na tela inicial" }),
      el("p", { class: "instalar__sub", text: "Abre mais rápido, em tela cheia, como um aplicativo." }),
      acoes));

  function fechar() { faixa.remove(); faixasConvite.delete(faixa); }

  if (pedidoInstalacao) {
    acoes.append(el("button", {
      class: "botao botao--primario botao--pequeno", type: "button", text: "Instalar",
      onclick: async () => {
        const ev = pedidoInstalacao;
        if (!ev) return;
        pedidoInstalacao = null;
        ev.prompt();
        try {
          const { outcome } = await ev.userChoice;
          if (outcome === "accepted") fechar();
        } catch { /* ignora */ }
      },
    }));
    const ver = el("button", { class: "botao botao--texto botao--pequeno", type: "button", text: "Como instalar", "aria-expanded": "false" });
    lista.hidden = true;
    ver.addEventListener("click", () => {
      lista.hidden = !lista.hidden;
      ver.setAttribute("aria-expanded", String(!lista.hidden));
    });
    acoes.append(ver);
  }
  acoes.append(el("button", {
    class: "botao botao--texto botao--pequeno", type: "button", text: "Agora não",
    onclick: () => { adiar(); fechar(); },
  }));
  faixa.querySelector(".instalar__texto").insertBefore(lista, acoes);
  faixasConvite.add(faixa);
  return faixa;
}

// Chrome/Android/computador: guarda o pedido para o nosso botão "Instalar".
window.addEventListener("beforeinstallprompt", (e) => {
  e.preventDefault();
  pedidoInstalacao = e;
  // Se o convite já está na tela, redesenha com o botão "Instalar".
  for (const f of [...faixasConvite]) {
    faixasConvite.delete(f);
    const nova = faixaInstalacao();
    if (nova) f.replaceWith(nova); else f.remove();
  }
});
window.addEventListener("appinstalled", () => {
  pedidoInstalacao = null;
  for (const f of faixasConvite) f.remove();
  faixasConvite.clear();
});

// ---------- Aviso de versão nova ----------

let faixaVersao = null;
let atualizando = false;

function avisarVersaoNova(registro) {
  if (faixaVersao || !registro.waiting) return;
  const botao = el("button", {
    class: "botao botao--azul botao--pequeno", type: "button", text: "Atualizar",
    onclick: () => {
      const espera = registro.waiting;
      if (!espera) { location.reload(); return; }
      atualizando = true;
      botao.disabled = true;
      botao.textContent = "Atualizando…";
      espera.postMessage({ tipo: "atualizar" });
    },
  });
  faixaVersao = el("div", { class: "faixa-fixa faixa-fixa--versao", role: "status" },
    el("p", { text: "Versão nova disponível." }), botao);
  document.body.append(faixaVersao);
}

function acompanhar(registro) {
  if (registro.waiting && navigator.serviceWorker.controller) avisarVersaoNova(registro);
  registro.addEventListener("updatefound", () => {
    const novo = registro.installing;
    if (!novo) return;
    novo.addEventListener("statechange", () => {
      // Só avisa se já havia uma versão rodando (na 1ª instalação não há o que trocar).
      if (novo.state === "installed" && navigator.serviceWorker.controller) avisarVersaoNova(registro);
    });
  });
}

async function registrar() {
  if (!("serviceWorker" in navigator) || !window.isSecureContext) return;
  let registro;
  try {
    registro = await navigator.serviceWorker.register("./sw.js", { scope: "./", updateViaCache: "none" });
  } catch (e) {
    console.warn("Service worker não registrado:", e);
    return;
  }
  acompanhar(registro);

  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (atualizando) location.reload(); // só recarrega quando a pessoa pediu
  });

  let ultima = Date.now();
  const procurar = () => {
    ultima = Date.now();
    registro.update().catch(() => { /* sem internet: tenta depois */ });
  };
  setInterval(procurar, VERIFICAR_MS);
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && Date.now() - ultima > 60 * 1000) procurar();
  });
}

// ---------- Sem conexão ----------

let faixaOffline = null;
function atualizarConexao() {
  if (navigator.onLine) { faixaOffline?.remove(); faixaOffline = null; return; }
  if (faixaOffline) return;
  faixaOffline = el("div", { class: "faixa-fixa faixa-fixa--offline", role: "alert" },
    el("p", { text: "Sem conexão com a internet. Os dados aparecem quando a conexão voltar." }));
  document.body.append(faixaOffline);
}

/** Chamado uma vez, ao abrir o app (js/app.js). */
export function iniciarPWA() {
  registrar();
  window.addEventListener("online", atualizarConexao);
  window.addEventListener("offline", atualizarConexao);
  atualizarConexao();
}
