// =====================================================================
// Tela: Vitrine – catálogo dos componentes (Fase 10 · Etapa 7)
// Só para conferir o visual. Todos os nomes e números são fictícios.
// =====================================================================
import { el, montar, aviso, toast, iniciais } from "../ui.js";
import { icone, NOMES_ICONES } from "../icones.js";
import { verificarConexao } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Vitrine";

const secao = (titulo, ...filhos) => el("section", { class: "cartao" }, el("h2", { text: titulo }), ...filhos);

function numero(nomeIcone, valor, rotulo, variante) {
  return el("a", { class: `numero${variante ? " numero--" + variante : ""}`, href: "#/vitrine" },
    el("span", { class: "numero__icone" }, icone(nomeIcone)),
    el("span", {}, el("span", { class: "numero__valor", text: valor }), el("span", { class: "numero__rotulo", text: rotulo })));
}

function atalho(nomeIcone, rotulo) {
  return el("a", { class: "atalhos__item", href: "#/vitrine" },
    el("span", { class: "atalhos__icone" }, icone(nomeIcone)), rotulo);
}

function itemCompacto(nome, linha, novo) {
  return el("li", {}, el("a", { class: "item-compacto", href: "#/vitrine" },
    novo === undefined
      ? el("span", { class: "avatar", "aria-hidden": "true", text: iniciais(nome) })
      : el("span", { class: novo ? "item-compacto__ponto" : "item-compacto__ponto item-compacto__ponto--lido", "aria-hidden": "true" }),
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: nome }),
      el("span", { class: "item-compacto__linha", text: linha })),
    icone("seta", null, "item-compacto__seta")));
}

function menuMais() {
  const menu = el("div", { class: "menu", hidden: true },
    el("ul", { class: "menu__lista" },
      el("li", {}, el("button", { class: "menu__item", type: "button", text: "Editar" })),
      el("li", {}, el("button", { class: "menu__item", type: "button", text: "Trocar foto" })),
      el("li", {}, el("button", { class: "menu__item menu__item--sair", type: "button", text: "Remover" }))));
  const botao = el("button", {
    class: "botao-icone mais-acoes__botao", type: "button", "aria-label": "Mais ações", "aria-expanded": "false",
    onclick: () => { const abrir = menu.hidden; menu.hidden = !abrir; botao.setAttribute("aria-expanded", String(abrir)); },
  }, icone("mais"));
  return el("div", { class: "mais-acoes" }, botao, menu);
}

export async function render(alvo) {
  const status = el("span", { class: "etiqueta etiqueta--neutra", text: "Testando…" });

  const cores = [
    ["Destaque (ação)", "destaque"], ["Azul (links)", "azul"], ["Amarelo (atenção)", "amarelo"],
    ["Alergia/erro", "erro"], ["Fundo", "fundo"], ["Cartão", "cartao"],
  ].map(([n, c]) => el("div", { class: `amostra amostra--${c}`, text: n }));

  const chips = ["Todas", "0–2", "3–6", "7–9", "10–12"].map((t, i) =>
    el("button", { class: "chip", type: "button", "aria-pressed": i === 0 ? "true" : "false", text: t,
      onclick: (e) => { for (const c of e.currentTarget.parentNode.children) c.setAttribute("aria-pressed", String(c === e.currentTarget)); } }));

  montar(alvo,
    el("div", { class: "cabecalho-tela" },
      el("h1", { text: "Vitrine" }),
      el("span", { class: "linha" }, el("span", { class: "suave", text: "Supabase" }), status)),
    el("p", { class: "suave", text: "Catálogo dos componentes do app. Nomes e números fictícios." }),

    el("div", { class: "busca" }, el("label", { class: "busca__campo" },
      icone("busca"), el("span", { class: "so-leitor", text: "Buscar" }),
      el("input", { type: "search", placeholder: "Buscar criança ou família" }))),

    el("div", { class: "chips", role: "group", "aria-label": "Filtro por idade" }, chips),

    el("div", { class: "secao-titulo" }, el("h2", { text: "Cartões de número" })),
    el("div", { class: "numeros" },
      numero("crianca", "48", "Crianças", "destaque"),
      numero("inicio", "36", "Famílias"),
      numero("pendencias", "5", "Pendências", "atencao"),
      numero("avisos", "2", "Avisos")),

    el("div", { class: "secao-titulo" }, el("h2", { text: "Atalhos" })),
    el("div", { class: "atalhos" },
      atalho("familia", "Família"), atalho("autorizados", "Autorizados"),
      atalho("pendencias", "Pendências"), atalho("senha", "Senha")),

    el("div", { class: "secao-titulo" }, el("h2", { text: "Lista compacta" }), el("a", { href: "#/vitrine", text: "Ver todas" })),
    el("ul", { class: "lista-compacta" },
      itemCompacto("Criança Exemplo Um", "Sala Exemplo · 5 anos"),
      itemCompacto("Família Exemplo Dois", "2 crianças · 1 pendência"),
      itemCompacto("Aviso de exemplo", "Hoje, 09:30", true)),

    el("div", { class: "cartao cartao--atencao cartao--compacto mt-5" },
      el("span", { class: "numero__icone" }, icone("pendencias")),
      el("div", { class: "flex-1" },
        el("strong", { text: "1 item para completar" }), el("br"),
        el("span", { class: "suave", text: "Relação com uma criança" })),
      el("a", { class: "botao botao--primario botao--pequeno", href: "#/vitrine", text: "Completar" })),

    secao("Cores",
      el("div", { class: "grade" }, cores)),

    secao("Botões",
      el("p", { class: "suave", text: "Uma ação principal por tela; as outras com contorno ou como link." }),
      el("div", { class: "linha" },
        el("button", { class: "botao botao--primario", type: "button", text: "Salvar" }),
        el("button", { class: "botao botao--secundario", type: "button", text: "Editar" }),
        el("button", { class: "botao", type: "button", text: "Cancelar" }),
        el("button", { class: "botao botao--azul", type: "button" }, icone("atualizar"), "Atualizar"),
        el("button", { class: "botao botao--texto", type: "button", text: "Ver mais" })),
      el("div", { class: "linha mt-3" },
        el("button", { class: "botao botao--primario botao--pequeno", type: "button", text: "Pequeno" }),
        el("button", { class: "botao botao--perigo botao--pequeno", type: "button", text: "Remover" }),
        el("button", { class: "botao botao--pequeno", type: "button", disabled: true, text: "Desativado" }),
        el("button", { class: "botao botao--whatsapp botao--pequeno", type: "button" }, icone("conversa"), "WhatsApp"))),

    secao("Etiquetas",
      el("div", { class: "linha" },
        el("span", { class: "etiqueta etiqueta--alergia" }, icone("alergia"), "Alergia"),
        el("span", { class: "etiqueta etiqueta--azul", text: "Sala 3–6" }),
        el("span", { class: "etiqueta", text: "Pendente" }),
        el("span", { class: "etiqueta etiqueta--sucesso", text: "Presente" }),
        el("span", { class: "etiqueta etiqueta--laranja", text: "Responsável" }),
        el("span", { class: "etiqueta etiqueta--neutra", text: "Inativa" }))),

    secao("Menu ⋯ no cartão",
      el("div", { class: "linha linha--entre" },
        el("div", { class: "linha" },
          el("span", { class: "avatar", "aria-hidden": "true", text: "AE" }),
          el("strong", { text: "Autorizado Exemplo" })),
        menuMais())),

    secao("Avisos",
      aviso("info", "O culto começa às 18h."),
      aviso("sucesso", "Salvo."),
      aviso("atencao", "Falta informar a relação com 1 criança."),
      aviso("erro", "Não foi possível salvar. Tente de novo."),
      el("button", { class: "botao botao--pequeno", type: "button", text: "Mensagem rápida",
        onclick: () => toast("sucesso", "Mensagem rápida de exemplo.") })),

    secao("Campos",
      el("div", { class: "campo" },
        el("label", { class: "campo__rotulo", for: "ex1", text: "Nome" }),
        el("input", { class: "entrada", id: "ex1", placeholder: "Digite aqui" }),
        el("span", { class: "campo__ajuda", text: "Texto de ajuda do campo." })),
      el("div", { class: "campo" },
        el("label", { class: "campo__rotulo", for: "ex2", text: "Com erro" }),
        el("input", { class: "entrada", id: "ex2", "aria-invalid": "true" }),
        el("span", { class: "campo__erro", text: "Campo obrigatório." }))),

    secao("Ícones",
      el("div", { class: "atalhos" }, NOMES_ICONES.map((n) =>
        el("div", { class: "atalhos__item" }, el("span", { class: "atalhos__icone" }, icone(n)), n)))),

    el("p", { class: "centro" }, el("a", { href: "#/entrar", text: "Voltar para entrar" })));

  const ok = await verificarConexao();
  status.textContent = ok ? "Conectado" : "Sem conexão";
  status.className = `etiqueta ${ok ? "etiqueta--sucesso" : "etiqueta--laranja"}`;
}
