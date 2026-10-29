// =====================================================================
// Tela: Etiquetas (Fase 11) – Mais → Etiquetas, só liderança
//   * Interruptor "Etiquetas": desligado (começo), o check-in fica como
//     antes (só o código na tela e no telão). Ligado, cada check-in pede a
//     etiqueta da criança e a do responsável.
//   * Link da estação: como o telão, um link fixo com código secreto para
//     abrir no computador da recepção (sem login). O banco guarda só o
//     hash: o link aparece uma única vez aqui. "Gerar novo link" faz o
//     antigo parar na hora.
//   * Mostra se a estação está no ar (deu sinal no último minuto e meio).
// Endereço: #/etiquetas
// =====================================================================
import { el, montar, aviso, carregando, toast } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela } from "../janela.js";
import { situacaoEtiquetas, ligarEtiquetas, gerarLinkEstacao, desligarLinkEstacao, enderecoEstacao } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Etiquetas";

const quando = (iso) => new Date(iso).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric",
  hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });

let alvoTela = null;

export async function render(alvo) {
  alvoTela = alvo;
  await desenhar();
}

async function desenhar(linkNovo) {
  montar(alvoTela, carregando());
  const r = await situacaoEtiquetas();
  if (!r.ok) { montar(alvoTela, el("h1", { text: "Etiquetas" }), aviso("erro", r.erro)); return; }
  const s = r.resultado;
  if (!s.pode_ligar) {
    montar(alvoTela, el("h1", { text: "Etiquetas" }), aviso("info", "Só a liderança mexe nas etiquetas."));
    return;
  }
  const link = s.link || { ativo: false };

  montar(alvoTela,
    el("div", { class: "saudacao" },
      el("h1", { text: "Etiquetas" }),
      el("p", { class: "suave", text: "Impressora Brother QL-800 da recepção, rolo de 62 mm (DK-22205)." })),
    linkNovo ? cartaoLink(linkNovo) : null,
    el("section", { class: "cartao mt-3" },
      el("div", { class: "linha" },
        el("span", { class: "numero__icone" }, icone("imprimir")),
        el("div", { class: "flex-1" },
          el("strong", { text: s.ligadas ? "Etiquetas ligadas" : "Etiquetas desligadas" }),
          el("p", { class: "suave sem-margem", text: s.ligadas
            ? "Cada check-in pede a etiqueta da criança e a do responsável."
            : "O check-in mostra só o código na tela e no telão." }))),
      el("div", { class: "linha mt-3" },
        el("button", { class: s.ligadas ? "botao botao--secundario" : "botao botao--primario", type: "button",
          text: s.ligadas ? "Desligar etiquetas" : "Ligar etiquetas",
          onclick: () => (s.ligadas ? confirmarDesligar() : alternar(true)) }))),
    el("section", { class: "cartao mt-3" },
      el("div", { class: "estacao-status" },
        el("span", { class: s.estacao_ativa ? "estacao-status__ponto estacao-status__ponto--no-ar" : "estacao-status__ponto", "aria-hidden": "true" }),
        el("div", { class: "flex-1" },
          el("strong", { text: !link.ativo ? "Nenhum link da estação" : s.estacao_ativa ? "Estação no ar" : "Estação fechada" }),
          el("p", { class: "suave sem-margem", text: link.ativo
            ? `Link criado em ${quando(link.criado_em)}${link.criado_por ? ` por ${link.criado_por}` : ""}.`
            : "Gere o link e abra no computador da recepção." }))),
      link.ativo && !linkNovo ? el("p", { class: "suave mt-3 sem-margem",
        text: "Por segurança, o link não fica guardado no app. Ele continua valendo no computador da recepção. Para usar em outro computador, gere um novo (o antigo para de funcionar)." }) : null,
      el("div", { class: "linha mt-3" },
        el("button", { class: link.ativo ? "botao botao--secundario" : "botao botao--primario", type: "button",
          text: link.ativo ? "Gerar novo link" : "Gerar link",
          onclick: () => (link.ativo ? confirmarNovo() : gerar()) }),
        link.ativo ? el("button", { class: "botao botao--secundario", type: "button", text: "Desligar link", onclick: confirmarDesligarLink }) : null)),
    el("section", { class: "cartao mt-3" },
      el("strong", { text: "Como usar" }),
      el("ol", { class: "lista-passos" },
        el("li", { text: "No computador da recepção: driver da QL-800, impressora padrão com papel de 62 mm e um atalho do Chrome com --kiosk-printing." }),
        el("li", { text: "Gere o link, abra pelo atalho, salve nos favoritos e toque em Imprimir teste." }),
        el("li", { text: "Ligue as etiquetas. Cada check-in imprime a etiqueta da criança e a do responsável." }),
        el("li", { text: "Para reimprimir: ⋯ da criança no check-in ou “Imprimir de novo” na estação." }))));
}

async function alternar(ligar) {
  const r = await ligarEtiquetas(ligar);
  if (!r.ok) { toast("erro", r.erro); return; }
  toast("sucesso", ligar ? "Etiquetas ligadas." : "Etiquetas desligadas.");
  desenhar();
}

function confirmarDesligar() {
  abrirJanela({
    titulo: "Desligar etiquetas",
    conteudo: [el("p", { text: "O check-in volta a mostrar só o código. As etiquetas que estiverem na fila não saem." })],
    textoSalvar: "Desligar",
    perigo: true,
    aoSalvar: async () => {
      const r = await ligarEtiquetas(false);
      if (!r.ok) return r.erro;
      setTimeout(() => desenhar(), 0);
      return null;
    },
  });
}

function cartaoLink(link) {
  const campo = el("input", { class: "entrada", type: "text", readonly: true, value: link, "aria-label": "Link da estação" });
  const copiar = el("button", { class: "botao botao--primario", type: "button" }, icone("check"), "Copiar link");
  copiar.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(link); toast("sucesso", "Link copiado."); }
    catch { campo.select(); toast("info", "Selecione o link e copie."); }
  });
  return el("section", { class: "cartao cartao--link-telao mt-3" },
    aviso("atencao", "Copie agora: este link aparece só esta vez. Ele mostra nomes e telefones das etiquetas de hoje: não envie em grupos."),
    el("div", { class: "mt-3" }, campo),
    el("div", { class: "linha mt-3" }, copiar,
      el("a", { class: "botao botao--secundario", href: link, target: "_blank", rel: "noopener noreferrer", text: "Abrir estação" })));
}

async function gerar() {
  const r = await gerarLinkEstacao();
  if (!r.ok) { toast("erro", r.erro, 6000); return; }
  await desenhar(enderecoEstacao(r.codigo));
}

function confirmarNovo() {
  abrirJanela({
    titulo: "Gerar novo link",
    conteudo: [el("p", { text: "O link atual para de funcionar na hora. Depois, abra o novo link no computador da recepção e salve nos favoritos." })],
    textoSalvar: "Gerar novo",
    perigo: true,
    aoSalvar: async () => {
      const r = await gerarLinkEstacao();
      if (!r.ok) return r.erro;
      setTimeout(() => desenhar(enderecoEstacao(r.codigo)), 0);
      return null;
    },
  });
}

function confirmarDesligarLink() {
  abrirJanela({
    titulo: "Desligar link",
    conteudo: [el("p", { text: "A estação para de imprimir na hora. Para voltar, gere um link novo." })],
    textoSalvar: "Desligar",
    perigo: true,
    sucesso: "Link desligado.",
    aoSalvar: async () => {
      const r = await desligarLinkEstacao();
      if (!r.ok) return r.erro;
      setTimeout(() => desenhar(), 0);
      return null;
    },
  });
}
