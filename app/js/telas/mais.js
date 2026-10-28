// =====================================================================
// Tela: Mais (Fase 10 · Etapa 7)
// Itens que não cabem na barra de baixo: perfil, trocar senha, gestão de
// logins (liderança), "Minha família" (equipe que também é responsável)
// e Sair. A lista vem de ITENS_MAIS em js/casca.js.
// =====================================================================
import { el, montar, iniciais } from "../ui.js";
import { icone } from "../icones.js";
import { meuPerfil } from "../supabase.js";
import { itensMaisDo } from "../casca.js";
import { fazerSair } from "../app.js";

export const layout = "padrao";
export const titulo = "Mais";

export async function render(alvo) {
  const perfil = await meuPerfil();
  const itens = itensMaisDo(perfil);

  const linha = (i) => el("li", {}, el("a", { class: "item-compacto", href: `#${i.rota}` },
    el("span", { class: "numero__icone" }, icone(i.icone)),
    el("span", { class: "item-compacto__texto" }, el("span", { class: "item-compacto__nome", text: i.texto })),
    icone("seta", null, "item-compacto__seta")));

  montar(alvo,
    el("h1", { text: "Mais" }),
    perfil.ok ? el("div", { class: "perfil-cabecalho" },
      el("span", { class: "avatar", "aria-hidden": "true", text: iniciais(perfil.nome) }),
      el("div", {},
        el("p", { class: "perfil-cabecalho__nome", text: perfil.nome || "Meu login" }),
        el("p", { class: "suave", text: perfil.papeis.map((p) => p.nomePapel).filter((v, k, a) => a.indexOf(v) === k).join(" · ") }))) : null,
    el("ul", { class: "lista-compacta" }, itens.map(linha)),
    el("p", { class: "mt-5" },
      el("button", { class: "botao botao--largo", type: "button", onclick: fazerSair }, icone("sair"), "Sair")));
}
