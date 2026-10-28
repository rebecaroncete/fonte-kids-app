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
import { icone } from "../icones.js";
import { el, montar, aviso, carregando } from "../ui.js";
import { meuPerfil, listarPendencias, confirmarPendencia, nomePendencia, voluntariasSemAcesso, contarPedidosVoluntaria } from "../supabase.js";
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
    el("h1", { text: "Pendências" }),
    el("div", { class: "abas", role: "tablist", "aria-label": "Situação" }, abas),
    area);

  montar(area, carregando());
  const [r, vol, novas] = await Promise.all([listarPendencias(situacao),
    situacao === "abertas" ? voluntariasSemAcesso(true) : Promise.resolve({ ok: true, lista: [] }),
    situacao === "abertas" ? contarPedidosVoluntaria() : Promise.resolve(0)]);
  if (!area.isConnected) return;
  if (!r.ok) { montar(area, aviso("erro", r.erro)); return; }
  desenharLista(area, situacao, r.lista, vol.ok ? vol.lista : []);
  // Fase 5 · 5F: cadastros de voluntária aguardando aprovação (só liderança)
  if (novas > 0) area.prepend(el("section", { class: "cartao cartao--pendencias" },
    el("a", { class: "pendencia__familia-link", href: "#/voluntarias-novas" },
      el("span", { class: "pendencia__familia", text: `Voluntárias novas aguardando aprovação (${novas})` }),
      icone("seta", null, "item-compacto__seta"))));
}

/** Cartão das voluntárias que ainda não entraram no app (só liderança). */
function cartaoVoluntarias(lista) {
  return el("section", { class: "cartao cartao--pendencias" },
    el("a", { class: "pendencia__familia-link", href: "#/logins" },
      el("span", { class: "pendencia__familia", text: `Voluntárias sem acesso (${lista.length})` }), icone("seta", null, "item-compacto__seta")),
    el("ul", { class: "lista-pendencias" }, lista.map((v) => el("li", { class: "pendencia" },
      el("div", { class: "pendencia__linha" },
        el("div", { class: "flex-1" },
          el("p", { class: "sem-margem" }, el("strong", { text: v.nome })),
          el("p", { class: "item-compacto__linha", text: [v.motivo, v.telefone].filter(Boolean).join(" · ") })))))));
}

function desenharLista(area, situacao, todas, voluntarias = []) {
  if (!todas.length && !voluntarias.length) {
    montar(area, aviso(situacao === "abertas" ? "sucesso" : "info",
      situacao === "abertas" ? "Nenhuma pendência aberta. Tudo em dia!" : "Nenhuma pendência resolvida ainda."));
    return;
  }

  const itens = todas.map((p) => ({ ...p, busca: normalizar(`${p.familia_nome || ""} ${p.crianca_nome || ""}`) }));

  // Filtro por tipo, com contagem
  const porTipo = new Map();
  for (const p of itens) porTipo.set(p.tipo, (porTipo.get(p.tipo) || 0) + 1);
  if (escolhas.tipo !== "todos" && !porTipo.has(escolhas.tipo) && !(escolhas.tipo === "voluntarias" && voluntarias.length)) escolhas.tipo = "todos";
  // Filtros em chips: tipo (com contagem) e forma de mostrar
  const tipos = [["todos", `Todos (${itens.length + voluntarias.length})`],
    ...(voluntarias.length ? [["voluntarias", `Voluntárias (${voluntarias.length})`]] : []),
    ...[...porTipo.entries()].sort((a, b) => b[1] - a[1]).map(([t, n]) => [t, `${nomePendencia(t)} (${n})`])];
  const chipsTipo = tipos.map(([valor, texto]) => el("button", { class: "chip", type: "button", text: texto,
    "aria-pressed": String(escolhas.tipo === valor), onclick: () => { escolhas.tipo = valor; marcar(); atualizar(); } }));
  const formas = [["familia", "Por família"], ["lista", "Lista"]];
  const chipsForma = formas.map(([valor, texto]) => el("button", { class: "chip", type: "button", text: texto,
    "aria-pressed": String(escolhas.agrupar === valor), onclick: () => { escolhas.agrupar = valor; marcar(); atualizar(); } }));
  function marcar() {
    chipsTipo.forEach((c, k) => c.setAttribute("aria-pressed", String(tipos[k][0] === escolhas.tipo)));
    chipsForma.forEach((c, k) => c.setAttribute("aria-pressed", String(formas[k][0] === escolhas.agrupar)));
  }
  if (!tipos.some(([v]) => v === escolhas.tipo)) { escolhas.tipo = "todos"; marcar(); }

  const busca = el("input", { type: "search", id: "busca-pendencias",
    placeholder: "Buscar responsável ou criança", autocomplete: "off", value: escolhas.busca });

  const resumo = el("p", { class: "resumo-lista", role: "status" });
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
    escolhas.busca = busca.value;
    const termo = normalizar(busca.value);
    const achados = escolhas.tipo === "voluntarias" ? []
      : itens.filter((p) => (escolhas.tipo === "todos" || p.tipo === escolhas.tipo) && (!termo || p.busca.includes(termo)));
    const vols = ["todos", "voluntarias"].includes(escolhas.tipo)
      ? voluntarias.filter((v) => !termo || normalizar(v.nome).includes(termo)) : [];

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
      blocos = achados.map((p) => () => el("ul", { class: "lista-pendencias cartao cartao--pendencias" }, itemPendencia(p, situacao, true)));
      resumo.textContent = achados.length ? `${achados.length} pendência${achados.length > 1 ? "s" : ""}` : "";
    }

    if (vols.length) {
      blocos.unshift(() => cartaoVoluntarias(vols));
      resumo.textContent = [resumo.textContent, `${vols.length} voluntária${vols.length > 1 ? "s" : ""} sem acesso`].filter(Boolean).join(" · ");
    }

    lista.replaceChildren();
    mostrando = 0;
    if (!blocos.length) { lista.append(aviso("info", "Nenhuma pendência encontrada com esses filtros.")); mais.hidden = true; return; }
    desenharMais();
  }

  let espera = null;
  busca.addEventListener("input", () => { clearTimeout(espera); espera = setTimeout(atualizar, 200); });
  mais.addEventListener("click", desenharMais);

  montar(area,
    el("div", { class: "busca" },
      el("label", { class: "busca__campo" }, icone("busca"), el("span", { class: "so-leitor", text: "Buscar responsável ou criança" }), busca),
      el("div", { class: "chips mt-3", role: "group", "aria-label": "Tipo" }, chipsTipo),
      el("div", { class: "chips mt-2", role: "group", "aria-label": "Mostrar" }, chipsForma)),
    resumo, lista, el("p", { class: "centro mt-3" }, mais));
  atualizar();
}

function nomeFamilia(p) {
  return p.familia_nome ? `Família de ${p.familia_nome}` : "Família sem responsável";
}

function cartaoFamilia(grupo, situacao) {
  const p0 = grupo[0];
  return el("section", { class: "cartao cartao--pendencias" },
    el("a", { class: "pendencia__familia-link", href: `#/ficha?tipo=familia&id=${encodeURIComponent(p0.familia_id)}` },
      el("span", { class: "pendencia__familia", text: nomeFamilia(p0) }), icone("seta", null, "item-compacto__seta")),
    el("ul", { class: "lista-pendencias" }, grupo.map((p) => itemPendencia(p, situacao, false))));
}

function itemPendencia(p, situacao, mostrarFamilia) {
  const resolver = situacao === "abertas" && !p.automatica
    ? el("button", { class: "botao botao--pequeno botao--secundario", type: "button", text: "Resolver", onclick: () => janelaResolver(p) })
    : null;
  const nome = p.crianca_id
    ? el("a", { href: `#/ficha?tipo=crianca&id=${encodeURIComponent(p.crianca_id)}`, text: p.crianca_nome || "Criança" })
    : null;

  return el("li", { class: "pendencia" },
    el("div", { class: "pendencia__linha" },
      el("div", { class: "flex-1" },
        el("div", { class: "linha" },
          el("span", { class: p.automatica ? "etiqueta etiqueta--azul" : "etiqueta", text: nomePendencia(p.tipo) }), nome),
        mostrarFamilia ? el("p", { class: "item-compacto__linha" },
          el("a", { href: `#/ficha?tipo=familia&id=${encodeURIComponent(p.familia_id)}`, text: nomeFamilia(p) })) : null,
        el("p", { class: "notif__corpo", text: p.mensagem }),
        el("p", { class: "notif__quando", text: situacao === "resolvidas"
          ? `Resolvida em ${dataBr(p.resolvida_em)}${p.resolvida_por_nome ? ` por ${p.resolvida_por_nome}` : " (automática)"}`
          : `Aberta em ${dataBr(p.criado_em)}${p.automatica ? " · some sozinha" : ""}` })),
      resolver));
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
