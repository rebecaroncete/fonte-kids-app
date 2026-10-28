// =====================================================================
// Fonte Kids – janelinha de preferências da voluntária (Fase 8)
// Usada na ficha da voluntária (liderança: função, e-mail, profissão,
// faixas de idade e cultos) e em "Minha escala" (a própria voluntária:
// só faixas de idade e cultos). A ordem das marcações é a ordem de
// preferência (1º, 2º…), como no cadastro pelo link.
// =====================================================================
import { el, toast } from "./ui.js";
import { abrirJanela, campo } from "./janela.js";
import { voluntariaPreferencias, salvarVoluntaria } from "./supabase.js";

/** Lista de caixas em que a ordem dos cliques vira a ordem de preferência. */
function escolhaOrdenada(opcoes, marcadas, maximo, rotulo) {
  const ordem = [...marcadas];
  const numeros = new Map();
  const legenda = el("legend", { class: "campo__rotulo", text: rotulo });
  const caixas = opcoes.map((o) => {
    const caixa = el("input", { type: "checkbox", value: o.id });
    caixa.checked = ordem.includes(o.id);
    const numero = el("span", { class: "suave" });
    numeros.set(o.id, numero);
    caixa.addEventListener("change", () => {
      if (caixa.checked) {
        if (ordem.length >= maximo) { caixa.checked = false; toast("atencao", `Escolha no máximo ${maximo}.`); return; }
        ordem.push(o.id);
      } else {
        ordem.splice(ordem.indexOf(o.id), 1);
      }
      atualizar();
    });
    return el("label", { class: "marcar" }, caixa, o.nome, " ", numero);
  });
  function atualizar() {
    for (const [id, numero] of numeros) {
      const i = ordem.indexOf(id);
      numero.textContent = i >= 0 ? `(${i + 1}ª)` : "";
    }
  }
  atualizar();
  return { no: el("fieldset", { class: "enquete-opcoes" }, legenda, caixas), valor: () => [...ordem] };
}

/**
 * Abre a janelinha. voluntaria: id (liderança) ou null (a própria).
 * aoSalvar(): redesenha a tela de quem chamou.
 */
export async function janelaPreferencias(voluntaria, aoSalvar) {
  const r = await voluntariaPreferencias(voluntaria);
  if (!r.ok) { toast("erro", r.erro); return; }
  const v = r.resultado || {};
  const salas = escolhaOrdenada(v.opcoes_salas || [], v.salas || [], 4, "Faixas de idade (de 1 a 4, na ordem de preferência)");
  const cultos = escolhaOrdenada(v.opcoes_cultos || [], v.cultos || [], 3, "Cultos (de 1 a 3, na ordem de preferência)");

  const conteudo = [];
  let funcao = null; let email = null; let profissao = null;
  if (v.pode_tudo) {
    funcao = el("select", { class: "entrada" },
      el("option", { value: "professora", text: "Professor(a)" }),
      el("option", { value: "auxiliar", text: "Auxiliar" }));
    funcao.value = v.funcao || "auxiliar";
    email = el("input", { class: "entrada", type: "email", maxlength: "120", autocomplete: "off" });
    email.value = v.email || "";
    profissao = el("input", { class: "entrada", type: "text", maxlength: "80", autocomplete: "off" });
    profissao.value = v.profissao || "";
    conteudo.push(campo("Função", funcao), campo("E-mail (opcional)", email), campo("Profissão (opcional)", profissao));
  } else {
    conteudo.push(el("p", { class: "suave", text: "Vale para as próximas escalas. A função (professor/auxiliar) quem muda é a liderança." }));
  }
  conteudo.push(salas.no, cultos.no);

  abrirJanela({
    titulo: v.pode_tudo ? "Editar voluntária" : "Minhas preferências",
    conteudo,
    sucesso: "Preferências salvas.",
    aoSalvar: async () => {
      if (!salas.valor().length) return "Escolha pelo menos uma faixa de idade.";
      if (!cultos.valor().length) return "Escolha pelo menos um culto.";
      const dados = { salas: salas.valor(), cultos: cultos.valor() };
      if (v.pode_tudo) Object.assign(dados, { funcao: funcao.value, email: email.value.trim(), profissao: profissao.value.trim() });
      const res = await salvarVoluntaria(v.id, dados);
      if (!res.ok) return res.erro;
      if (aoSalvar) await aoSalvar();
      return null;
    },
  });
}
