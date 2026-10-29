// =====================================================================
// Tela: Telão (Fase 5 · Etapa 5C – decisões 86 e 88)
// Aberta no computador do telão, SEM login, por um link fixo com código
// secreto: #/telao?c=<código>. A liderança gera o link em "Link do telão"
// (e pode trocar: o antigo para de funcionar na hora).
// Mostra só as chamadas aguardando de hoje: primeiro e último nome da
// criança e do responsável principal, código e sala. Nada de telefone,
// foto, alergia ou data de nascimento.
// "Anunciado" tira a chamada da tela; a voluntária vê em Presentes.
// Atualiza a cada 4 segundos (sem login não há tempo real seguro).
// =====================================================================
import { el, montar, aviso } from "../ui.js";
import { telaoChamadas, telaoAnunciar } from "../supabase.js";

export const layout = "telao";
export const titulo = "Telão";

const INTERVALO = 4000;

export async function render(alvo) {
  const codigo = (new URLSearchParams(location.hash.split("?")[1] || "").get("c") || "").trim().toLowerCase();
  const relogio = el("span", { class: "telao__relogio" });
  const situacao = el("p", { class: "telao__situacao", role: "status" });
  const lista = el("div", { class: "telao__lista", "aria-live": "polite" });
  let somLigado = false;
  let audio = null;
  const conhecidas = new Set();
  let primeira = true;
  let timer = null;

  const botaoSom = el("button", { class: "botao botao--secundario botao--pequeno telao__som", type: "button", text: "Ligar som" });
  botaoSom.addEventListener("click", () => {
    somLigado = !somLigado;
    botaoSom.textContent = somLigado ? "Desligar som" : "Ligar som";
    if (somLigado) {
      try { audio = audio || new (window.AudioContext || window.webkitAudioContext)(); audio.resume(); bip(); } catch { /* sem som */ }
    }
  });

  montar(alvo,
    el("header", { class: "telao__topo" },
      el("img", { class: "telao__logo", src: "img/logo.png", alt: "Fonte Kids" }),
      el("h1", { class: "telao__titulo", text: "Chamando o responsável" }),
      relogio, botaoSom),
    situacao, lista);

  if (!/^[0-9a-f]{32}$/.test(codigo)) {
    montar(lista, aviso("erro", "Link do telão inválido. Peça o link à liderança do Fonte Kids."));
    return;
  }

  function bip() {
    if (!somLigado || !audio) return;
    try {
      const o = audio.createOscillator();
      const g = audio.createGain();
      o.frequency.value = 880;
      g.gain.setValueAtTime(0.2, audio.currentTime);
      g.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + 0.6);
      o.connect(g); g.connect(audio.destination);
      o.start(); o.stop(audio.currentTime + 0.6);
    } catch { /* sem som */ }
  }

  function desenhar(chamadas) {
    if (!chamadas.length) {
      montar(lista, el("p", { class: "telao__vazio", text: "Nenhuma chamada no momento." }));
      return;
    }
    let nova = false;
    montar(lista, chamadas.map((c) => {
      const eNova = !conhecidas.has(c.id);
      if (eNova) { conhecidas.add(c.id); if (!primeira) nova = true; }
      const botao = el("button", { class: "botao botao--primario telao__anunciado", type: "button", text: "Anunciado" });
      botao.addEventListener("click", async () => {
        botao.disabled = true;
        const r = await telaoAnunciar(codigo, c.id);
        if (!r.ok) { botao.disabled = false; situacao.textContent = r.erro; return; }
        atualizar();
      });
      return el("article", { class: eNova && !primeira ? "telao__chamada telao__chamada--nova" : "telao__chamada" },
        el("div", { class: "telao__dados" },
          el("p", { class: "telao__crianca", text: c.crianca }),
          el("p", { class: "telao__responsavel" }, "Responsável: ", el("strong", { text: c.responsavel || "—" })),
          el("p", { class: "telao__sala", text: c.sala ? `Sala ${c.sala}` : "" })),
        el("div", { class: "telao__codigo-caixa" },
          el("span", { class: "telao__codigo-rotulo", text: "Código" }),
          el("span", { class: "telao__codigo", text: c.codigo })),
        botao);
    }));
    primeira = false;
    if (nova) bip();
  }

  async function atualizar() {
    clearTimeout(timer);
    if (!alvo.isConnected) return;               // saiu da tela: para de perguntar
    relogio.textContent = new Date().toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });
    const r = await telaoChamadas(codigo);
    if (!alvo.isConnected) return;
    if (r.ok) {
      situacao.textContent = "";
      desenhar(r.lista);
    } else if (/inválido/i.test(r.erro || "")) {
      montar(lista, aviso("erro", "Este link do telão foi trocado ou desligado. Peça o link novo à liderança do Fonte Kids."));
      situacao.textContent = "";
      return;                                     // não insiste com link inválido
    } else {
      situacao.textContent = "Sem conexão. Tentando de novo…";
    }
    timer = setTimeout(atualizar, INTERVALO);
  }

  atualizar();
}
