// =====================================================================
// Fonte Kids – janelinha de formulário (Etapa 5C: edição pelo responsável)
// Abre um <dialog> por cima da tela com campos, "Salvar" e "Cancelar".
// aoSalvar() devolve null (deu certo → fecha) ou o texto do erro.
// Também tem a janelinha de troca de foto (prévia + envio).
// =====================================================================
import { el, montar, aviso, toast } from "./ui.js";
import { prepararFoto, enviarFoto, esquecerFoto } from "./foto.js";

let contador = 0;
/** Id único para ligar rótulo e campo. */
export const novoId = (base) => `${base}-${++contador}`;

/** Campo com rótulo (e ajuda opcional). */
export function campo(rotulo, entrada, ajuda) {
  if (!entrada.id) entrada.id = novoId("campo");
  return el("div", { class: "campo" },
    el("label", { class: "campo__rotulo", for: entrada.id, text: rotulo }),
    entrada,
    ajuda ? el("span", { class: "campo__ajuda", text: ajuda }) : null);
}

/**
 * Abre a janelinha.
 * opcoes: { titulo, conteudo: [nós], textoSalvar, perigo, aoSalvar: async () => null | "erro", sucesso }
 */
export function abrirJanela({ titulo, conteudo = [], textoSalvar = "Salvar", perigo = false, aoSalvar, sucesso }) {
  document.querySelector("dialog.janela")?.remove();
  const caixaErro = el("div", {});
  const salvar = el("button", { class: perigo ? "botao botao--perigo" : "botao", type: "submit", text: textoSalvar });
  const cancelar = el("button", { class: "botao botao--pequeno", type: "button", text: "Cancelar" });
  const form = el("form", { novalidate: true },
    el("h2", { text: titulo }), ...conteudo, caixaErro,
    el("div", { class: "linha" }, salvar, cancelar));
  const janela = el("dialog", { class: "janela", "aria-label": titulo }, form);

  const fechar = () => { if (janela.open) janela.close(); janela.remove(); };
  cancelar.addEventListener("click", fechar);
  janela.addEventListener("close", () => janela.remove());
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    montar(caixaErro);
    salvar.disabled = true;
    cancelar.disabled = true;
    const original = salvar.textContent;
    salvar.textContent = "Salvando…";
    let erro;
    try { erro = await aoSalvar(); } catch (x) { erro = x?.message || "Algo deu errado. Tente de novo."; }
    if (erro) {
      salvar.disabled = false;
      cancelar.disabled = false;
      salvar.textContent = original;
      montar(caixaErro, aviso("erro", erro));
      return;
    }
    fechar();
    if (sucesso) toast("sucesso", sucesso);
  });

  document.body.append(janela);
  janela.showModal();
  form.querySelector("input, select, textarea, button")?.focus();
  return janela;
}

/**
 * Janelinha "Trocar foto": escolher (câmera ou galeria), ver a prévia e enviar.
 * tipo: "eu" | "crianca"; id: id da criança (ou null). tipoFoto/idFoto: chave do
 * link guardado (para esquecer a foto antiga). aoTrocar(): redesenha a tela.
 */
export function janelaFoto({ tipo, id, nome, tipoFoto, idFoto, aoTrocar }) {
  let pronta = null;
  const previa = el("div", { class: "avatar avatar--grande previa-foto", "aria-hidden": "true" });
  const situacao = el("p", { class: "suave", text: "Nenhuma foto escolhida ainda." });
  const arquivo = el("input", { type: "file", accept: "image/*", class: "entrada" });
  arquivo.addEventListener("change", async () => {
    pronta = null;
    previa.replaceChildren();
    const f = arquivo.files?.[0];
    if (!f) { situacao.textContent = "Nenhuma foto escolhida ainda."; return; }
    situacao.textContent = "Preparando a foto…";
    try {
      pronta = await prepararFoto(f);
      previa.replaceChildren(el("img", { src: pronta, alt: "" }));
      situacao.textContent = "Confira a prévia e toque em Enviar foto.";
    } catch (e) {
      situacao.textContent = e.message;
    }
  });

  abrirJanela({
    titulo: nome ? `Foto de ${nome}` : "Trocar foto",
    conteudo: [
      campo("Escolha uma foto", arquivo, "Pode tirar na hora ou escolher da galeria. Só o rosto, de frente, com boa luz."),
      el("div", { class: "linha" }, previa, situacao),
    ],
    textoSalvar: "Enviar foto",
    sucesso: "Foto atualizada.",
    aoSalvar: async () => {
      if (!pronta) return "Escolha uma foto primeiro.";
      const r = await enviarFoto(tipo, id, pronta);
      if (!r.ok) return r.erro;
      esquecerFoto(tipoFoto, idFoto);
      if (aoTrocar) await aoTrocar();
      return null;
    },
  });
}
