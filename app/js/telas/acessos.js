// =====================================================================
// Tela: Acessos da equipe (Fase 5 · Etapa 5A)   #/acessos
// Para liderança, pastores e admin (o banco confere).
// Lista as voluntárias com login e deixa dar/tirar os acessos de
// "Líder" e "Recepção" (definir_papel). Regras do banco:
//   • só voluntárias com login; • ninguém tira o próprio acesso de líder;
//   • pastor e admin não são dados por aqui.
// Mostra só nomes (sem telefone nem outros dados).
// =====================================================================
import { el, montar, aviso, carregando, toast } from "../ui.js";
import { abrirJanela } from "../janela.js";
import { meuPerfil, papeisVoluntarias, definirPapel } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Acessos da equipe";

const normalizar = (s) => String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();

let alvoTela = null;
const escolhas = { filtro: "todas", busca: "" };

export async function render(alvo) {
  alvoTela = alvo;
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: titulo }), aviso("erro", perfil.erro)); return; }
  if (!perfil.temPapel("admin", "pastor", "lider")) {
    montar(alvo, el("h1", { text: titulo }), aviso("atencao", "Esta tela é só para a liderança do Fonte Kids."));
    return;
  }
  await desenhar();
}

async function desenhar() {
  const r = await papeisVoluntarias();
  if (!alvoTela?.isConnected) return;
  if (!r.ok) { montar(alvoTela, el("h1", { text: titulo }), aviso("erro", r.erro)); return; }
  const todas = r.lista.map((v) => ({ ...v, busca: normalizar(v.nome) }));

  const FILTROS = [
    ["todas", `Todas (${todas.length})`, () => true],
    ["lider", `Líderes (${todas.filter((v) => v.lider).length})`, (v) => v.lider],
    ["recepcao", `Recepção (${todas.filter((v) => v.recepcao).length})`, (v) => v.recepcao],
    ["sem", `Sem recepção (${todas.filter((v) => !v.recepcao).length})`, (v) => !v.recepcao],
  ];
  const chips = FILTROS.map(([valor, texto]) => el("button", { class: "chip", type: "button", text: texto,
    "aria-pressed": String(escolhas.filtro === valor),
    onclick: () => { escolhas.filtro = valor; chips.forEach((c, k) => c.setAttribute("aria-pressed", String(FILTROS[k][0] === valor))); atualizar(); } }));
  const busca = el("input", { type: "search", class: "entrada", placeholder: "Buscar voluntária", autocomplete: "off",
    "aria-label": "Buscar voluntária", value: escolhas.busca });
  busca.addEventListener("input", () => { escolhas.busca = busca.value; atualizar(); });
  const resumo = el("p", { class: "resumo-lista", role: "status" });
  const lista = el("ul", { class: "lista-compacta" });

  function atualizar() {
    const teste = FILTROS.find(([v]) => v === escolhas.filtro)?.[2] || (() => true);
    const termo = normalizar(escolhas.busca);
    const vis = todas.filter((v) => teste(v) && (!termo || v.busca.includes(termo)));
    resumo.textContent = vis.length === 1 ? "1 voluntária" : `${vis.length} voluntárias`;
    montar(lista, vis.map(item));
  }

  montar(alvoTela,
    el("h1", { text: titulo }),
    el("p", { class: "suave", text: "Líder: cuida de cadastros, logins, cultos e salas. Recepção: faz check-in e vê as famílias." }),
    busca,
    el("div", { class: "chips mt-3" }, chips),
    el("div", { class: "mt-3" }, resumo, lista));
  atualizar();
}

function item(v) {
  const botao = (papel, texto, ativo) => {
    const travado = papel === "lider" && ativo && v.sou_eu;
    return el("button", { class: "chip", type: "button", text: texto, "aria-pressed": String(ativo),
      disabled: travado,
      title: travado ? "Você não pode tirar o seu próprio acesso de líder" : null,
      "aria-label": `${texto} para ${v.nome}: ${ativo ? "sim" : "não"}`,
      onclick: () => alternar(v, papel, !ativo) });
  };
  return el("li", {}, el("div", { class: "item-compacto" },
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: v.nome }),
      v.sou_eu ? el("span", { class: "item-compacto__linha", text: "Você" }) : null),
    el("span", { class: "item-compacto__etiquetas" },
      botao("lider", "Líder", v.lider), botao("recepcao", "Recepção", v.recepcao))));
}

function alternar(v, papel, dar) {
  if (papel === "lider") {
    abrirJanela({
      titulo: dar ? "Dar acesso de líder" : "Tirar acesso de líder",
      textoSalvar: dar ? "Dar acesso" : "Tirar acesso",
      perigo: !dar,
      sucesso: dar ? "Acesso de líder concedido." : "Acesso de líder retirado.",
      conteudo: [el("p", { text: dar
        ? `${v.nome} vai poder ver e editar cadastros, criar logins, mudar cultos e salas e dar acessos. Confirma?`
        : `${v.nome} deixa de ter acesso de líder. Continua como voluntária${v.recepcao ? " e recepção" : ""}.` })],
      aoSalvar: async () => { const r = await definirPapel(v.perfil_id, "lider", dar); if (!r.ok) return r.erro; await desenhar(); return null; },
    });
    return;
  }
  definirPapel(v.perfil_id, "recepcao", dar).then(async (r) => {
    if (!r.ok) { toast("erro", r.erro); return; }
    toast("sucesso", dar ? `${v.nome} agora faz check-in.` : `${v.nome} não faz mais check-in.`);
    await desenhar();
  });
}
