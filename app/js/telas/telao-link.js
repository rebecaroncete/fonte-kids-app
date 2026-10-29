// =====================================================================
// Tela: Link do telão (Fase 5 · Etapa 5C – decisão 88)
// Para líderes, pastores e admin. O link é FIXO: gera uma vez e salva
// nos favoritos do computador do telão. Só muda se a liderança tocar em
// "Gerar novo link" (ex.: se o link vazar) – aí o antigo para na hora.
// O banco guarda só o hash do código: o link aparece uma única vez aqui.
// Endereço: #/telao-link
// =====================================================================
import { el, montar, aviso, carregando, toast } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela } from "../janela.js";
import { situacaoTelao, gerarLinkTelao, desligarTelao, enderecoTelao } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Link do telão";

let alvoTela = null;

export async function render(alvo) {
  alvoTela = alvo;
  await desenhar();
}

async function desenhar(linkNovo) {
  montar(alvoTela, carregando());
  const r = await situacaoTelao();
  if (!r.ok) { montar(alvoTela, el("h1", { text: "Link do telão" }), aviso("erro", r.erro)); return; }

  const quando = r.ativo
    ? new Date(r.criado_em).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" })
    : "";

  montar(alvoTela,
    el("div", { class: "saudacao" },
      el("h1", { text: "Link do telão" }),
      el("p", { class: "suave", text: "Tela aberta no computador do telão, sem senha. Mostra quando uma voluntária chama o responsável." })),
    linkNovo ? cartaoLink(linkNovo) : null,
    el("section", { class: "cartao mt-3" },
      el("div", { class: "linha" },
        el("span", { class: "numero__icone" }, icone("telao")),
        el("div", { class: "flex-1" },
          el("strong", { text: r.ativo ? "Telão ligado" : "Nenhum link criado" }),
          el("p", { class: "suave sem-margem", text: r.ativo
            ? `Link criado em ${quando}${r.criado_por ? ` por ${r.criado_por}` : ""}.`
            : "Gere o link e abra no computador do telão." }))),
      r.ativo && !linkNovo ? el("p", { class: "suave mt-3 sem-margem",
        text: "Por segurança, o link não fica guardado no app. Ele continua valendo no computador do telão. Se precisar dele em outro computador, gere um novo (o antigo para de funcionar)." }) : null,
      el("div", { class: "linha mt-3" },
        el("button", { class: r.ativo ? "botao botao--secundario" : "botao botao--primario", type: "button",
          text: r.ativo ? "Gerar novo link" : "Gerar link",
          onclick: () => (r.ativo ? confirmarNovo() : gerar()) }),
        r.ativo ? el("button", { class: "botao botao--secundario", type: "button", text: "Desligar telão", onclick: confirmarDesligar }) : null)),
    el("section", { class: "cartao mt-3" },
      el("strong", { text: "Como usar" }),
      el("ol", { class: "lista-passos" },
        el("li", { text: "Gere o link e copie." }),
        el("li", { text: "Abra no navegador do computador do telão e salve nos favoritos." }),
        el("li", { text: "Quando a voluntária toca em “Chamar responsável”, a criança aparece no telão." }),
        el("li", { text: "Depois de anunciar, toque em “Anunciado”. A voluntária vê na lista de Presentes." }))));
}

function cartaoLink(link) {
  const campo = el("input", { class: "entrada", type: "text", readonly: true, value: link, "aria-label": "Link do telão" });
  const copiar = el("button", { class: "botao botao--primario", type: "button" }, icone("check"), "Copiar link");
  copiar.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(link); toast("sucesso", "Link copiado."); }
    catch { campo.select(); toast("info", "Selecione o link e copie."); }
  });
  return el("section", { class: "cartao cartao--link-telao mt-3" },
    aviso("atencao", "Copie agora: este link aparece só esta vez. Não envie em grupos."),
    el("div", { class: "mt-3" }, campo),
    el("div", { class: "linha mt-3" }, copiar,
      el("a", { class: "botao botao--secundario", href: link, target: "_blank", rel: "noopener noreferrer", text: "Abrir telão" })));
}

async function gerar() {
  const r = await gerarLinkTelao();
  if (!r.ok) { toast("erro", r.erro, 6000); return; }
  await desenhar(enderecoTelao(r.codigo));
}

function confirmarNovo() {
  abrirJanela({
    titulo: "Gerar novo link",
    conteudo: [el("p", { text: "O link atual para de funcionar na hora. Depois, abra o novo link no computador do telão e salve nos favoritos." })],
    textoSalvar: "Gerar novo",
    perigo: true,
    aoSalvar: async () => {
      const r = await gerarLinkTelao();
      if (!r.ok) return r.erro;
      setTimeout(() => desenhar(enderecoTelao(r.codigo)), 0);
      return null;
    },
  });
}

function confirmarDesligar() {
  abrirJanela({
    titulo: "Desligar telão",
    conteudo: [el("p", { text: "O link atual para de funcionar. As chamadas continuam aparecendo em Presentes. Para ligar de novo, gere um link novo." })],
    textoSalvar: "Desligar",
    perigo: true,
    sucesso: "Telão desligado.",
    aoSalvar: async () => {
      const r = await desligarTelao();
      if (!r.ok) return r.erro;
      setTimeout(() => desenhar(), 0);
      return null;
    },
  });
}
