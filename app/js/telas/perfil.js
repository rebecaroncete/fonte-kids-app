// =====================================================================
// Tela: Meu perfil (Fase 10 · Etapa 4) – só leitura
// Nome, telefone de login e papéis. A edição de dados chega com o
// cadastro (Fase 5); até lá, correções são feitas pela liderança.
// =====================================================================
import { el, montar, aviso, carregando, iniciais, mascararTelefone } from "../ui.js";
import { meuPerfil, manterConectadoAtual } from "../supabase.js";
import { fazerSair } from "../app.js";

export const layout = "padrao";
export const titulo = "Meu perfil";

export async function render(alvo) {
  montar(alvo, carregando());
  const p = await meuPerfil(true);
  if (!p.ok) { montar(alvo, el("h1", { text: "Meu perfil" }), aviso("erro", p.erro)); return; }

  const nome = p.nome || "Sem nome no cadastro";
  const papeis = p.papeis.length
    ? el("ul", { class: "lista-simples" }, p.papeis.map((x) =>
        el("li", { text: x.departamento && !["admin", "pastor"].includes(x.papel) ? `${x.nomePapel} · ${x.departamento}` : x.nomePapel })))
    : el("p", { class: "suave", text: "Nenhum papel ativo. Fale com a liderança do Fonte Kids." });

  montar(alvo,
    el("h1", { text: "Meu perfil" }),
    el("section", { class: "cartao" },
      el("div", { class: "perfil-cabecalho" },
        el("div", { class: "avatar avatar--grande", "aria-hidden": "true", text: iniciais(p.nome) }),
        el("p", { class: "perfil-cabecalho__nome", text: nome })),
      el("dl", { class: "dados" },
        el("dt", { text: "Telefone de login" }),
        el("dd", { text: mascararTelefone(p.telefone) || "—" }),
        el("dt", { text: "Papéis" }),
        el("dd", {}, papeis),
        el("dt", { text: "Neste aparelho" }),
        el("dd", { text: manterConectadoAtual() ? "Fica conectado até você sair." : "Sai ao fechar o navegador." }))),
    aviso("info", "Para corrigir nome ou telefone, fale com a liderança do Fonte Kids."),
    el("div", { class: "linha" },
      el("a", { class: "botao botao--secundario", href: "#/trocar-senha", text: "Trocar senha" }),
      el("button", { class: "botao", type: "button", text: "Sair", onclick: fazerSair })));
}
