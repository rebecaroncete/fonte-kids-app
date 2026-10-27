// =====================================================================
// Tela: Vitrine de componentes (só para conferir o visual; dados fictícios)
// =====================================================================
import { el, montar, aviso, toast, iniciais } from "../ui.js";
import { verificarConexao } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Vitrine";

export async function render(alvo) {
  const status = el("p", { class: "etiqueta", text: "Testando conexão…" });

  const cores = [
    ["Laranja", "bg-laranja"], ["Amarelo", "bg-amarelo"], ["Azul", "bg-azul"],
    ["Fundo", "bg-fundo"], ["Contorno", "bg-contorno"],
  ].map(([n, c]) => el("div", { class: `amostra ${c}`, text: n }));

  const ficticios = ["Criança Exemplo Um", "Criança Exemplo Dois"];

  montar(alvo,
    el("h1", { text: "Vitrine do visual" }),
    el("p", { class: "suave", text: "Página de conferência da Etapa 1. Todos os nomes abaixo são fictícios." }),

    el("section", { class: "cartao" },
      el("h2", { text: "Conexão" }),
      el("div", { class: "linha" }, el("span", { text: "Supabase:" }), status)),

    el("section", { class: "cartao" },
      el("h2", { text: "Cores da logo" }),
      el("div", { class: "grade" }, cores)),

    el("section", { class: "cartao" },
      el("h2", { text: "Botões" }),
      el("div", { class: "linha" },
        el("button", { class: "botao botao--primario", text: "Principal" }),
        el("button", { class: "botao botao--secundario", text: "Secundário" }),
        el("button", { class: "botao botao--azul", text: "Azul" }),
        el("button", { class: "botao", text: "Neutro" }),
        el("button", { class: "botao botao--perigo", text: "Excluir" }),
        el("button", { class: "botao", disabled: true, text: "Desativado" }),
        el("button", { class: "botao botao--texto", text: "Link" }))),

    el("section", { class: "cartao" },
      el("h2", { text: "Avisos" }),
      aviso("info", "Informação: o culto começa às 18h."),
      aviso("sucesso", "Check-in feito com sucesso."),
      aviso("atencao", "Falta informar a relação com 1 criança."),
      aviso("erro", "Não foi possível salvar. Tente de novo."),
      el("button", { class: "botao botao--pequeno", text: "Mostrar mensagem rápida",
        onclick: () => toast("sucesso", "Mensagem rápida de exemplo.") })),

    el("section", { class: "cartao" },
      el("h2", { text: "Campos" }),
      el("div", { class: "campo" },
        el("label", { class: "campo__rotulo", for: "ex1", text: "Nome" }),
        el("input", { class: "entrada", id: "ex1", placeholder: "Digite aqui" }),
        el("span", { class: "campo__ajuda", text: "Texto de ajuda do campo." })),
      el("div", { class: "campo" },
        el("label", { class: "campo__rotulo", for: "ex2", text: "Com erro" }),
        el("input", { class: "entrada", id: "ex2", "aria-invalid": "true" }),
        el("span", { class: "campo__erro", text: "Este campo é obrigatório." }))),

    el("section", { class: "cartao" },
      el("h2", { text: "Lista e etiquetas" }),
      el("ul", { class: "lista" }, ficticios.map((n, i) =>
        el("li", { class: "lista__item" },
          el("span", { class: "avatar", "aria-hidden": "true", text: iniciais(n) }),
          el("div", {}, el("strong", { text: n }), el("br"),
            el("span", { class: "suave", text: i ? "Sala Exemplo B" : "Sala Exemplo A" })),
          el("span", { class: `etiqueta ${i ? "etiqueta--laranja" : "etiqueta--azul"}`, text: i ? "Saiu" : "Presente" })))),
    ),

    el("p", { class: "centro" }, el("a", { href: "#/entrar", text: "Voltar para a tela de entrar" })));

  const ok = await verificarConexao();
  status.textContent = ok ? "Conectado" : "Sem conexão";
  status.className = `etiqueta ${ok ? "etiqueta--azul" : "etiqueta--laranja"}`;
}
