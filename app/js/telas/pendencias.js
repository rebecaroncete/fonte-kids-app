// =====================================================================
// Tela: Pendências de cadastro (Fase 10 · Etapa 5D)
//   #/pendencias?situacao=abertas|resolvidas
// Para recepção (todas as voluntárias), liderança, pastores e admin.
//   • Abertas / Resolvidas (as 300 mais recentes).
//   • Filtro por tipo (com contagem), busca por nome da família ou da
//     criança, agrupado por família ou lista simples.
//   • Links para a ficha da criança e da família.
//   • "Marcar como resolvida" só nas pendências manuais; as automáticas
//     (relação não informada, sem data de nascimento) somem sozinhas.
// O banco (listar_pendencias / confirmar_pendencia) decide o que aparece
// e quem pode resolver; a tela só organiza.
// =====================================================================
import { el, montar, aviso, carregando } from "../ui.js";
import { meuPerfil, listarPendencias, confirmarPendencia, nomePendencia } from "../supabase.js";
import { abrirJanela } from "../janela.js";
import { normalizar } from "./cadastros.js";

export const layout = "padrao";
export const titulo = "Pendências";

const POR_PAGINA = 30; // famílias (agrupado) ou pendências (lista) por vez
const FUSO = "America/Sao_Paulo";
const dataBr = (iso) => new Date(iso).toLocaleDateString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", year: "numeric" });

function parametro(nome) {
  const q = location.hash.split("?")[1] || "";
  return new URLSearchParams(q).get(nome);
}

let alvoTela = null;
// Escolhas que continuam valendo ao recarregar a lista (só nesta aba)
const escolhas = { tipo: "todos", agrupar: "familia", busca: "" };

export async function render(alvo) {
  alvoTela = alvo;
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: "Pendências de cadastro" }), aviso("erro", perfil.erro)); return; }
  if (!perfil.temPapel("admin", "pastor", "lider", "recepcao")) {
    montar(alvo, el("h1", { text: "Pendências de cadastro" }),
      aviso("atencao", "Esta tela é para a equipe do Fonte Kids. As pendências da sua família aparecem em \"Minha família\"."));
    return;
  }
  await desenhar(parametro("situacao") === "resolvidas" ? "resolvidas" : "abertas");
}

async function desenhar(situacao) {
  const area = el("section", { id: "pendencias-area", role: "tabpanel" });
  const abas = [["abertas", "Abertas"], ["resolvidas", "Resolvidas"]].map(([id, texto]) => el("button", {
    class: "aba", type: "button", role: "tab", id: `aba-${id}`, "aria-controls": "pendencias-area",
    "aria-selected": id === situacao ? "true" : "false", text: texto,
    onclick: () => { history.replaceState(null, "", `#/pendencias?situacao=${id}`); desenhar(id); },
  }));
  area.setAttribute("aria-labelledby", `aba-${situacao}`);

  montar(alvoTela,
    el("h1", { text: "Pendências de cadastro" }),
    el("p", { class: "suave", text: "Avisos sobre dados que faltam ou precisam ser conferidos. A família também vê as próprias pendências em \"Minha família\"." }),
    el("div", { class: "abas", role: "tablist", "aria-label": "Situação" }, abas),
    area);

  montar(area, carregando());
  const r = await listarPendencias(situacao);
  if (!area.isConnected) return;
  if (!r.ok) { montar(area, aviso("erro", r.erro)); return; }
  desenharLista(area, situacao, r.lista);
}

function desenharLista(area, situacao, todas) {
  if (!todas.length) {
    montar(area, aviso(situacao === "abertas" ? "sucesso" : "info",
      situacao === "abertas" ? "Nenhuma pendência aberta. Tudo em dia!" : "Nenhuma pendência resolvida ainda."));
    return;
  }

  const itens = todas.map((p) => ({ ...p, busca: normalizar(`${p.familia_nome || ""} ${p.crianca_nome || ""}`) }));

  // Filtro por tipo, com contagem
  const porTipo = new Map();
  for (const p of itens) porTipo.set(p.tipo, (porTipo.get(p.tipo) || 0) + 1);
  if (escolhas.tipo !== "todos" && !porTipo.has(escolhas.tipo)) escolhas.tipo = "todos";
  const selTipo = el("select", { class: "entrada", id: "filtro-tipo" },
    el("option", { value: "todos", text: `Todos os tipos (${itens.length})` }),
    [...porTipo.entries()].sort((a, b) => b[1] - a[1])
      .map(([t, n]) => el("option", { value: t, text: `${nomePendencia(t)} (${n})` })));
  selTipo.value = escolhas.tipo;

  const selAgrupar = el("select", { class: "entrada", id: "filtro-agrupar" },
    el("option", { value: "familia", text: "Agrupado por família" }),
    el("option", { value: "lista", text: "Lista simples" }));
  selAgrupar.value = escolhas.agrupar;

  const busca = el("input", { class: "entrada", type: "search", id: "busca-pendencias",
    placeholder: "Digite parte do nome", autocomplete: "off", value: escolhas.busca });

  const resumo = el("p", { class: "suave", role: "status" });
  const lista = el("div", { class: "pendencias" });
  const mais = el("button", { class: "botao botao--pequeno", type: "button", text: "Mostrar mais", hidden: true });

  let blocos = [];
  let mostrando = 0;

  function desenharMais() {
    const proximos = blocos.slice(mostrando, mostrando + POR_PAGINA);
    lista.append(...proximos.map((b) => b()));
    mostrando += proximos.length;
    mais.hidden = mostrando >= blocos.length;
  }

  function atualizar() {
    escolhas.tipo = selTipo.value;
    escolhas.agrupar = selAgrupar.value;
    escolhas.busca = busca.value;
    const termo = normalizar(busca.value);
    const achados = itens.filter((p) => (escolhas.tipo === "todos" || p.tipo === escolhas.tipo) && (!termo || p.busca.includes(termo)));

    if (escolhas.agrupar === "familia") {
      const grupos = new Map();
      for (const p of achados) {
        if (!grupos.has(p.familia_id)) grupos.set(p.familia_id, []);
        grupos.get(p.familia_id).push(p);
      }
      const ordenados = [...grupos.values()].sort((a, b) =>
        normalizar(a[0].familia_nome || "zzz").localeCompare(normalizar(b[0].familia_nome || "zzz")));
      blocos = ordenados.map((g) => () => cartaoFamilia(g, situacao));
      resumo.textContent = achados.length
        ? `${achados.length} pendência${achados.length > 1 ? "s" : ""} em ${grupos.size} família${grupos.size > 1 ? "s" : ""}`
        : "";
    } else {
      blocos = achados.map((p) => () => el("ul", { class: "lista" }, itemPendencia(p, situacao, true)));
      resumo.textContent = achados.length ? `${achados.length} pendência${achados.length > 1 ? "s" : ""}` : "";
    }

    lista.replaceChildren();
    mostrando = 0;
    if (!achados.length) { lista.append(aviso("info", "Nenhuma pendência encontrada com esses filtros.")); mais.hidden = true; return; }
    desenharMais();
  }

  let espera = null;
  busca.addEventListener("input", () => { clearTimeout(espera); espera = setTimeout(atualizar, 200); });
  selTipo.addEventListener("change", atualizar);
  selAgrupar.addEventListener("change", atualizar);
  mais.addEventListener("click", desenharMais);

  montar(area,
    el("div", { class: "campo" }, el("label", { class: "campo__rotulo", for: "busca-pendencias", text: "Buscar pelo nome de um responsável ou de uma criança" }), busca),
    el("div", { class: "grade" },
      el("div", { class: "campo" }, el("label", { class: "campo__rotulo", for: "filtro-tipo", text: "Tipo" }), selTipo),
      el("div", { class: "campo" }, el("label", { class: "campo__rotulo", for: "filtro-agrupar", text: "Mostrar" }), selAgrupar)),
    resumo, lista, el("div", { class: "linha" }, mais));
  atualizar();
}

function nomeFamilia(p) {
  return p.familia_nome ? `Família de ${p.familia_nome}` : "Família sem responsável";
}

function cartaoFamilia(grupo, situacao) {
  const p0 = grupo[0];
  return el("section", { class: "cartao" },
    el("div", { class: "linha pendencia__topo" },
      el("h2", { class: "pendencia__familia", text: nomeFamilia(p0) }),
      el("a", { class: "botao botao--pequeno", href: `#/ficha?tipo=familia&id=${encodeURIComponent(p0.familia_id)}`, text: "Ver família" })),
    el("ul", { class: "lista" }, grupo.map((p) => itemPendencia(p, situacao, false))));
}

function itemPendencia(p, situacao, mostrarFamilia) {
  const acoes = [];
  if (p.crianca_id) {
    acoes.push(el("a", { class: "botao botao--pequeno", href: `#/ficha?tipo=crianca&id=${encodeURIComponent(p.crianca_id)}`,
      text: p.crianca_nome ? `Ver ${p.crianca_nome.trim().split(/\s+/)[0]}` : "Ver criança" }));
  }
  if (mostrarFamilia) {
    acoes.push(el("a", { class: "botao botao--pequeno", href: `#/ficha?tipo=familia&id=${encodeURIComponent(p.familia_id)}`, text: "Ver família" }));
  }
  if (situacao === "abertas" && !p.automatica) {
    acoes.push(el("button", { class: "botao botao--pequeno botao--secundario", type: "button", text: "Marcar como resolvida",
      onclick: () => janelaResolver(p) }));
  }

  return el("li", { class: "notif pendencia" },
    el("div", { class: "linha" },
      el("span", { class: p.automatica ? "etiqueta etiqueta--azul" : "etiqueta etiqueta--laranja", text: nomePendencia(p.tipo) }),
      p.crianca_nome ? el("span", { class: "notif__titulo", text: p.crianca_nome }) : null),
    mostrarFamilia ? el("p", { class: "notif__quando", text: nomeFamilia(p) }) : null,
    el("p", { class: "notif__corpo", text: p.mensagem }),
    el("p", { class: "notif__quando", text: situacao === "resolvidas"
      ? `Resolvida em ${dataBr(p.resolvida_em)}${p.resolvida_por_nome ? ` por ${p.resolvida_por_nome}` : " (automaticamente)"}`
      : `Aberta em ${dataBr(p.criado_em)}${p.automatica ? " · some sozinha quando o dado for preenchido" : ""}` }),
    acoes.length ? el("div", { class: "linha acoes-cartao" }, acoes) : null);
}

function janelaResolver(p) {
  abrirJanela({
    titulo: "Marcar como resolvida",
    conteudo: [
      el("p", { class: "notif__titulo", text: nomePendencia(p.tipo) }),
      el("p", { text: p.mensagem }),
      el("p", { class: "suave", text: "Confirme que o dado foi conferido ou corrigido. Fica registrado quem resolveu." }),
    ],
    textoSalvar: "Marcar como resolvida",
    sucesso: "Pendência resolvida.",
    aoSalvar: async () => {
      const r = await confirmarPendencia(p.id);
      if (!r.ok) return r.erro;
      await desenhar("abertas");
      return null;
    },
  });
}
