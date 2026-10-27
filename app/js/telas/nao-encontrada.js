// Tela: endereço que não existe
import { el, montar } from "../ui.js";

export const layout = "central";
export const titulo = "Página não encontrada";

export function render(alvo) {
  montar(alvo,
    el("div", { class: "marca" },
      el("img", { src: "img/logo.png", alt: "" }),
      el("h1", { class: "marca__titulo", text: "Ops!" }),
      el("p", { class: "marca__sub", text: "Esta página não existe." })),
    el("a", { class: "botao botao--primario botao--largo", href: "#/entrar", text: "Voltar ao início" }));
}
