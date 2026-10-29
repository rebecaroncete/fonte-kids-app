// =====================================================================
// Tela: Estação de etiquetas (Fase 11)
// Aberta no computador da recepção, SEM login, por um link fixo com código
// secreto: #/estacao?c=<código> (a liderança gera em Mais → Etiquetas e
// pode trocar: o antigo para na hora). O Chrome tem a Brother QL-800 como
// impressora padrão e é aberto com --kiosk-printing (imprime sem a janela).
//   * A cada 4 s dá o sinal de "no ar", pega os pedidos feitos nos
//     celulares (check-in e "Reimprimir") e imprime cada etiqueta
//     (sem login não há tempo real seguro, como no telão).
//   * Pedido de mais de 10 min com a estação fechada vira "Não impressa" e
//     só sai tocando em "Imprimir de novo".
//   * O navegador não sabe se a impressora está ligada ou sem papel: a
//     etiqueta fica na fila do computador e sai quando a impressora voltar.
// Mostra só as etiquetas de hoje.
// =====================================================================
import { el, montar, aviso, toast } from "../ui.js";
import { icone } from "../icones.js";
import { estacaoBuscar, estacaoConcluir, estacaoLista, estacaoReimprimir } from "../supabase.js";
import { imprimirEtiquetas, desenharEtiqueta, etiquetasTeste } from "../etiquetas.js";

export const layout = "estacao";
export const titulo = "Estação de etiquetas";

const INTERVALO = 4000;
const STATUS = { pendente: "Na fila", imprimindo: "Imprimindo", impresso: "Impressa", erro: "Não impressa" };
const hora = (iso) => new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });

let timer = null;
window.addEventListener("hashchange", () => { if (!location.hash.startsWith("#/estacao")) { clearTimeout(timer); timer = null; } });

export async function render(alvo) {
  clearTimeout(timer); timer = null;
  const codigo = (new URLSearchParams(location.hash.split("?")[1] || "").get("c") || "").trim().toLowerCase();
  const status = el("div");
  const lista = el("div", { "aria-live": "polite" });
  let ocupada = false;
  let ultimas = [];
  let ultimaBusca = null;
  let erro = null;
  let ligadas = true;
  let trava = null;

  montar(alvo,
    el("div", { class: "saudacao" },
      el("img", { class: "relatorio__logo", src: "img/logo.png", alt: "Fonte Kids" }),
      el("h1", { text: "Estação de etiquetas" }),
      el("p", { class: "suave", text: "Deixe esta tela aberta e na frente durante o culto." })),
    status, lista, comoPreparar());

  if (!/^[0-9a-f]{32}$/.test(codigo)) {
    montar(status, aviso("erro", "Link da estação inválido. Peça o link à liderança do Fonte Kids."));
    return;
  }
  // mantém a tela acesa (onde o navegador deixa)
  try { trava = await navigator.wakeLock?.request("screen"); } catch { trava = null; }
  document.addEventListener("visibilitychange", async () => {
    if (document.visibilityState === "visible" && trava?.released !== false) {
      try { trava = await navigator.wakeLock?.request("screen"); } catch { /* ignore */ }
    }
  });

  function desenharStatus() {
    const classe = erro ? "estacao-status__ponto estacao-status__ponto--erro"
      : ligadas ? "estacao-status__ponto estacao-status__ponto--no-ar" : "estacao-status__ponto";
    montar(status, el("section", { class: "cartao mt-3" },
      el("div", { class: "estacao-status" },
        el("span", { class: classe, "aria-hidden": "true" }),
        el("div", { class: "flex-1" },
          el("strong", { text: erro ? "Sem conexão" : ligadas ? "Estação no ar" : "Etiquetas desligadas" }),
          el("p", { class: "suave sem-margem", text: erro ? erro
            : ligadas ? `Imprimindo os check-ins de hoje${ultimaBusca ? ` · conferido às ${hora(ultimaBusca)}` : ""}.`
            : "A liderança desligou as etiquetas. O check-in mostra só o código." }))),
      el("div", { class: "linha mt-3" },
        el("button", { class: "botao botao--secundario", type: "button", onclick: imprimirTeste }, icone("imprimir"), "Imprimir teste")),
      ultimas.length ? el("div", {},
        el("p", { class: "suave mt-3 sem-margem", text: "Última impressa:" }),
        el("div", { class: "previa-etiquetas" }, ultimas.flatMap(desenharEtiqueta))) : null));
  }

  async function ciclo() {
    if (!alvo.isConnected) return;
    if (!ocupada) {
      ocupada = true;
      try {
        const r = await estacaoBuscar(codigo);
        if (!alvo.isConnected) return;
        if (!r.ok) {
          erro = r.erro;
          desenharStatus();
          if (/inválido/i.test(r.erro)) { montar(lista); return; } // link trocado: para
        } else {
          const antes = ligadas;
          erro = null;
          ligadas = !!r.resultado.ligadas;
          ultimaBusca = new Date().toISOString();
          const pedidos = r.resultado.pedidos || [];
          for (const p of pedidos) {
            let ok = true; let falha = null;
            try { await imprimirEtiquetas([p.etiqueta]); }
            catch (e) { ok = false; falha = (e && e.message) || "Falha ao imprimir"; }
            await estacaoConcluir(codigo, [p.id], ok, falha);
            if (ok) ultimas = [p.etiqueta];
          }
          desenharStatus();
          if (pedidos.length || antes !== ligadas || !lista.firstChild) carregarLista();
        }
      } finally {
        ocupada = false;
      }
    }
    timer = setTimeout(ciclo, INTERVALO);
  }

  async function carregarLista() {
    const r = await estacaoLista(codigo);
    if (!lista.isConnected) return;
    if (!r.ok) { montar(lista, aviso("erro", r.erro)); return; }
    const pedidos = (r.resultado.pedidos || []).filter((p) => p.etiqueta);
    const naoImpressas = pedidos.filter((p) => p.status === "erro").length;
    montar(lista, el("section", { class: "cartao mt-3" },
      el("div", { class: "cartao-topo" },
        el("div", { class: "flex-1" },
          el("strong", { text: "Etiquetas de hoje" }),
          el("p", { class: "suave sem-margem", text: pedidos.length
            ? `${pedidos.length} ${pedidos.length === 1 ? "etiqueta" : "etiquetas"}${naoImpressas ? ` · ${naoImpressas} não impressa(s)` : ""}`
            : "Nenhuma etiqueta pedida hoje." })),
        el("button", { class: "botao-icone", type: "button", "aria-label": "Atualizar a lista", onclick: carregarLista }, icone("atualizar"))),
      pedidos.length ? el("ul", { class: "lista-fila" }, pedidos.slice(0, 60).map(linha)) : null));
  }

  function linha(p) {
    const e = p.etiqueta;
    const classe = p.status === "erro" ? "etiqueta" : p.status === "impresso" ? "etiqueta etiqueta--sucesso" : "etiqueta etiqueta--azul";
    const botao = el("button", { class: "botao botao--secundario botao--pequeno", type: "button", text: "Imprimir de novo", disabled: !ligadas });
    botao.addEventListener("click", async () => {
      botao.disabled = true;
      const r = await estacaoReimprimir(codigo, p.id);
      if (!r.ok) { toast("erro", r.erro); botao.disabled = false; return; }
      toast("sucesso", "Na fila para imprimir.");
      clearTimeout(timer); ciclo();
    });
    return el("li", {},
      el("span", { class: "lista-fila__texto" },
        el("span", { class: "lista-fila__nome",
          text: `${e.tipo === "responsavel" ? "Responsável" : "Criança"} · ${e.criancas.map((c) => c.nome).join(", ")}` }),
        el("span", { class: "linha mt-1" },
          el("span", { class: classe, text: STATUS[p.status] || p.status }),
          p.reimpressao ? el("span", { class: "etiqueta etiqueta--neutra", text: "De novo" }) : null,
          el("span", { class: "suave", text: `${e.criancas.map((c) => c.codigo).join(" · ")} · ${hora(p.criado_em)}` })),
        p.status === "erro" && p.erro ? el("span", { class: "suave", text: p.erro }) : null),
      botao);
  }

  desenharStatus();
  ciclo();
}

async function imprimirTeste() {
  try {
    await imprimirEtiquetas(etiquetasTeste());
    toast("info", "Teste enviado. Confira o tamanho e se nada ficou cortado.");
  } catch {
    toast("erro", "Não foi possível imprimir o teste.");
  }
}

function comoPreparar() {
  return el("details", { class: "cartao mt-3" },
    el("summary", { text: "Como preparar o computador" }),
    el("ol", { class: "lista-passos" },
      el("li", { text: "Instale o driver da Brother QL-800 (site da Brother) e ligue a impressora no USB." }),
      el("li", { text: "Nas impressoras do computador, deixe a QL-800 como padrão, com o papel de 62 mm (rolo DK-22205)." }),
      el("li", { text: "Crie um atalho do Chrome e acrescente --kiosk-printing no fim do destino. Assim a etiqueta sai direto, sem a janela de imprimir." }),
      el("li", { text: "Abra este link pelo atalho e salve nos favoritos." }),
      el("li", { text: "Toque em Imprimir teste e confira o tamanho." })),
    el("p", { class: "suave sem-margem", text: "Se a impressora estiver desligada ou sem papel, a etiqueta espera na fila do computador e sai quando ela voltar. O código continua na tela do check-in e no telão." }));
}
