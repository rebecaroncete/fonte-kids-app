// =====================================================================
// Fonte Kids – janela "prévia + Compartilhar/Baixar" de uma imagem feita
// no aparelho (Fase 9: imagem da escala e imagem do relatório do mês).
// No celular, Compartilhar abre a folha do sistema (WhatsApp etc.);
// onde não dá para compartilhar arquivo (computador), baixa o PNG.
// =====================================================================
import { el } from "./ui.js";
import { abrirJanela } from "./janela.js";

/** titulo: da janela; blob: PNG; nomeArquivo: "x.png"; alt: texto da prévia */
export function janelaImagem({ titulo, blob, nomeArquivo, alt }) {
  const arquivo = new File([blob], nomeArquivo, { type: "image/png" });
  const url = URL.createObjectURL(blob);
  const compartilha = !!(navigator.canShare && navigator.canShare({ files: [arquivo] }));
  const janela = abrirJanela({
    titulo,
    textoSalvar: compartilha ? "Compartilhar" : "Baixar imagem",
    conteudo: [
      el("img", { class: "previa-escala", src: url, alt }),
      el("p", { class: "suave", text: compartilha
        ? "Toque em Compartilhar e escolha o WhatsApp (ou salve nas fotos)."
        : "A imagem vai para os downloads; depois é só mandar no grupo." }),
    ],
    aoSalvar: async () => {
      if (compartilha) {
        try { await navigator.share({ files: [arquivo], title: titulo }); }
        catch (e) { if (e?.name !== "AbortError") return "Não foi possível compartilhar. Tente Baixar pelo computador."; }
        return null;
      }
      const a = el("a", { href: url, download: nomeArquivo });
      document.body.append(a); a.click(); a.remove();
      return null;
    },
  });
  janela.addEventListener("close", () => setTimeout(() => URL.revokeObjectURL(url), 60000), { once: true });
}
