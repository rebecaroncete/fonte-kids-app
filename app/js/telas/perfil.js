// =====================================================================
// Tela: Meu perfil (Fase 10 · Etapa 4; edição na Etapa 5C)
// Foto, nome, data de nascimento, telefone de login e papéis.
// A pessoa pode editar nome, data de nascimento e foto (vale na hora,
// fica na auditoria e a liderança recebe aviso). O telefone é o login:
// só a liderança troca.
// =====================================================================
import { el, montar, aviso, carregando, mascararTelefone } from "../ui.js";
import { meuPerfil, manterConectadoAtual, nascimentoDe, editarMeuPerfil } from "../supabase.js";
import { avatarComFoto } from "../foto.js";
import { abrirJanela, janelaFoto, campo } from "../janela.js";
import { fazerSair } from "../app.js";

export const layout = "padrao";
export const titulo = "Meu perfil";

const FUSO = "America/Sao_Paulo";
const hojeIso = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO });
const dataBr = (iso) => {
  if (!iso) return "—";
  const [a, m, d] = iso.slice(0, 10).split("-");
  return `${d}/${m}/${a}`;
};

let alvoTela = null;

export async function render(alvo) {
  alvoTela = alvo;
  montar(alvo, carregando());
  await desenhar();
}

async function desenhar() {
  const p = await meuPerfil(true);
  if (!p.ok) { montar(alvoTela, el("h1", { text: "Meu perfil" }), aviso("erro", p.erro)); return; }
  const nascimento = await nascimentoDe(p.pessoaId);

  const nome = p.nome || "Sem nome no cadastro";
  const papeis = p.papeis.length
    ? el("ul", { class: "lista-simples" }, p.papeis.map((x) =>
        el("li", { text: x.departamento && !["admin", "pastor"].includes(x.papel) ? `${x.nomePapel} · ${x.departamento}` : x.nomePapel })))
    : el("p", { class: "suave", text: "Nenhum papel ativo. Fale com a liderança do Fonte Kids." });

  const avatar = p.pessoaId ? avatarComFoto("pessoa", p.pessoaId, p.nome) : el("div", { class: "avatar avatar--foto" });
  avatar.classList.add("avatar--grande");

  montar(alvoTela,
    el("h1", { text: "Meu perfil" }),
    el("section", { class: "cartao" },
      el("div", { class: "perfil-cabecalho" }, avatar,
        el("p", { class: "perfil-cabecalho__nome", text: nome })),
      el("dl", { class: "dados" },
        el("dt", { text: "Data de nascimento" }),
        el("dd", { text: dataBr(nascimento) }),
        el("dt", { text: "Telefone de login" }),
        el("dd", { text: mascararTelefone(p.telefone) || "—" }),
        el("dt", { text: "Papéis" }),
        el("dd", {}, papeis),
        el("dt", { text: "Neste aparelho" }),
        el("dd", { text: manterConectadoAtual() ? "Fica conectado até você sair." : "Sai ao fechar o navegador." })),
      p.pessoaId ? el("div", { class: "linha acoes-cartao" },
        el("button", { class: "botao botao--pequeno botao--secundario", type: "button", text: "Editar", onclick: () => janelaEditar(p.nome, nascimento) }),
        el("button", { class: "botao botao--pequeno", type: "button", text: "Foto",
          onclick: () => janelaFoto({ tipo: "eu", id: null, nome: p.nome, tipoFoto: "pessoa", idFoto: p.pessoaId, aoTrocar: desenhar }) })) : null),
    aviso("info", "O telefone é o seu login. Para trocá-lo, fale com a liderança do Fonte Kids."),
    el("div", { class: "linha" },
      el("a", { class: "botao", href: "#/trocar-senha", text: "Trocar senha" }),
      el("button", { class: "botao botao--texto", type: "button", text: "Sair", onclick: fazerSair })));
}

function janelaEditar(nomeAtual, nascAtual) {
  const nome = el("input", { class: "entrada", type: "text", maxlength: "120", autocomplete: "name", value: nomeAtual || "" });
  const nasc = el("input", { class: "entrada", type: "date", max: hojeIso(), value: nascAtual || "" });
  abrirJanela({
    titulo: "Meus dados",
    conteudo: [campo("Nome completo", nome), campo("Data de nascimento", nasc)],
    sucesso: "Dados salvos.",
    aoSalvar: async () => {
      if (nome.value.trim().length < 3) { nome.focus(); return "Informe o nome completo."; }
      const r = await editarMeuPerfil(nome.value, nasc.value);
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}
