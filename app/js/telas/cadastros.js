// =====================================================================
// Tela: Cadastros (Fase 10 · Etapa 5B) – lista e busca, só leitura
//   • Crianças e Famílias: recepção (todas as voluntárias), liderança,
//     pastores e admin.
//   • Voluntárias: só liderança, pastores e admin.
// O banco (RLS) decide o que volta para cada login; a tela só organiza.
// A lista não carrega fotos (só iniciais); a foto aparece na ficha.
// Endereço: #/cadastros?aba=criancas | familias | voluntarias
// =====================================================================
import { el, montar, aviso, carregando, iniciais } from "../ui.js";
import { icone } from "../icones.js";
import { meuPerfil, listarSalas, listarCriancas, listarFamilias, listarVoluntarias } from "../supabase.js";
import { avatarLista, preencherFotos } from "../foto.js";

export const layout = "padrao";
export const titulo = "Cadastros";

const POR_PAGINA = 50;
const NOMES_FUNCAO = { professora: "Professora", auxiliar: "Auxiliar" };
const NOMES_STATUS = { ativa: "Ativa", pendente: "Aguardando aprovação", inativa: "Inativa" };

export const normalizar = (s) => String(s || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();

/** Idade em anos a partir de "AAAA-MM-DD" (ou null). */
export function idade(dataIso) {
  if (!dataIso) return null;
  const [a, m, d] = dataIso.split("-").map(Number);
  const hoje = new Date();
  let anos = hoje.getFullYear() - a;
  if (hoje.getMonth() + 1 < m || (hoje.getMonth() + 1 === m && hoje.getDate() < d)) anos--;
  return anos >= 0 ? anos : null;
}
/**
 * Sala da criança: a sala fixa, quando a liderança definiu uma (exceção);
 * senão, a sala ativa da faixa de idade (como no app atual).
 * Acima de 12 anos ou sem data de nascimento: sem sala (com aviso).
 * Retorna { sala, porIdade, motivo }.
 */
export function salaDaCrianca(salaFixaId, anos, salas) {
  if (salaFixaId) {
    const s = salas.find((x) => x.id === salaFixaId);
    if (s) return { sala: s, porIdade: false };
  }
  if (anos === null) return { sala: null, motivo: "Sem data de nascimento: sem sala" };
  const s = salas.filter((x) => x.ativa).find((x) => anos >= x.idade_min && anos <= x.idade_max);
  if (s) return { sala: s, porIdade: true };
  return { sala: null, motivo: anos > 12 ? "Acima de 12 anos: sem sala" : "Nenhuma sala para esta idade" };
}
export const textoSala = (r) => (r.sala ? `Sala ${r.sala.nome}${r.porIdade ? "" : " (definida pela liderança)"}` : r.motivo);

export const textoIdade = (n) => (n === null ? "Idade não informada" : n === 0 ? "Menos de 1 ano" : `${n} ano${n > 1 ? "s" : ""}`);

function parametro(nome) {
  const q = location.hash.split("?")[1] || "";
  return new URLSearchParams(q).get(nome);
}

/** Lista com busca fixa, filtros em chips e "Mostrar mais". */
function listaComBusca(painel, { itens, rotuloBusca, filtros, desenharItem, vazio }) {
  const busca = el("input", { type: "search", id: "busca-cadastros", placeholder: rotuloBusca, autocomplete: "off" });
  let filtroAtual = filtros ? filtros[0].valor : null;
  const chips = filtros ? filtros.map((f) => el("button", {
    class: "chip", type: "button", "aria-pressed": f.valor === filtroAtual ? "true" : "false", text: f.texto,
    onclick: () => { filtroAtual = f.valor; chips.forEach((c, k) => c.setAttribute("aria-pressed", String(filtros[k].valor === filtroAtual))); atualizar(); },
  })) : null;
  const resumo = el("p", { class: "resumo-lista", role: "status" });
  const lista = el("ul", { class: "lista-compacta" });
  const mais = el("button", { class: "botao botao--pequeno", type: "button", text: "Mostrar mais", hidden: true });
  let achados = [];
  let mostrando = 0;

  function desenharMais() {
    const proximos = achados.slice(mostrando, mostrando + POR_PAGINA);
    lista.append(...proximos.map((x) => el("li", {}, desenharItem(x))));
    mostrando += proximos.length;
    preencherFotos(lista); // fotos só dos itens que estão aparecendo
    mais.hidden = mostrando >= achados.length;
    resumo.textContent = achados.length
      ? `${achados.length} encontrad${achados.length > 1 ? "os" : "o"}${mostrando < achados.length ? ` · mostrando ${mostrando}` : ""}`
      : "";
  }
  function atualizar() {
    const termo = normalizar(busca.value);
    const f = filtros ? filtros.find((x) => x.valor === filtroAtual) || filtros[0] : null;
    achados = itens.filter((x) => (!f || f.teste(x)) && (!termo || x.busca.includes(termo)));
    lista.replaceChildren();
    mostrando = 0;
    lista.hidden = !achados.length;
    if (!achados.length) { mais.hidden = true; resumo.textContent = vazio; return; }
    desenharMais();
  }
  let espera = null;
  busca.addEventListener("input", () => { clearTimeout(espera); espera = setTimeout(atualizar, 200); });
  mais.addEventListener("click", desenharMais);

  montar(painel,
    el("div", { class: "busca" },
      el("label", { class: "busca__campo" }, icone("busca"), el("span", { class: "so-leitor", text: rotuloBusca }), busca),
      chips ? el("div", { class: "chips mt-3", role: "group", "aria-label": "Filtro" }, chips) : null),
    resumo, lista, el("p", { class: "centro mt-3" }, mais));
  atualizar();
}

function itemLink(href, nome, linhas, etiquetas = [], foto = null) {
  return el("a", { class: "item-compacto", href },
    foto ? avatarLista(foto.tipo, foto.id, nome) : el("div", { class: "avatar", "aria-hidden": "true", text: iniciais(nome) }),
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: nome }),
      el("span", { class: "item-compacto__linha", text: linhas.filter(Boolean).join(" · ") })),
    etiquetas.length ? el("span", { class: "item-compacto__etiquetas" }, etiquetas) : null,
    icone("seta", null, "item-compacto__seta"));
}

// ---------------- Abas ----------------

async function abaCriancas(painel) {
  montar(painel, carregando());
  const [rc, rs] = await Promise.all([listarCriancas(), listarSalas()]);
  if (!painel.isConnected) return;
  if (!rc.ok) { montar(painel, aviso("erro", rc.erro)); return; }
  const salas = rs.ok ? rs.lista : [];
  const itens = rc.lista
    .map((c) => {
      const anos = idade(c.pessoa?.data_nascimento);
      return { ...c, nome: c.pessoa?.nome || "Sem nome", busca: normalizar(c.pessoa?.nome), anos, sala: salaDaCrianca(c.sala_fixa_id, anos, salas) };
    })
    .sort((a, b) => a.busca.localeCompare(b.busca));
  const filtros = [
    { valor: "ativas", texto: "Todas", teste: (c) => c.ativo },
    ...salas.filter((s) => s.ativa).map((s) => ({ valor: s.id, texto: `Sala ${s.nome}`, teste: (c) => c.ativo && c.sala.sala?.id === s.id })),
    { valor: "sem_sala", texto: "Sem sala", teste: (c) => c.ativo && !c.sala.sala },
    { valor: "inativas", texto: "Inativas", teste: (c) => !c.ativo },
  ];
  listaComBusca(painel, {
    itens, filtros, rotuloBusca: "Buscar criança", vazio: "Nenhuma criança encontrada.",
    desenharItem: (c) => itemLink(`#/ficha?tipo=crianca&id=${encodeURIComponent(c.id)}`, c.nome,
      [textoIdade(c.anos), c.sala.sala ? `Sala ${c.sala.sala.nome}` : "Sem sala"],
      [c.perfil === "visitante" ? el("span", { class: "etiqueta etiqueta--azul", text: "Visitante" }) : null,
       !c.ativo ? el("span", { class: "etiqueta etiqueta--neutra", text: "Inativa" }) : null].filter(Boolean),
      { tipo: "crianca", id: c.id }),
  });
}

async function abaFamilias(painel) {
  montar(painel, carregando());
  const r = await listarFamilias();
  if (!painel.isConnected) return;
  if (!r.ok) { montar(painel, aviso("erro", r.erro)); return; }
  const itens = r.lista.map((f) => {
    const resp = [...(f.responsaveis || [])].sort((a, b) => Number(b.principal) - Number(a.principal));
    const nomesResp = resp.map((x) => x.pessoa?.nome).filter(Boolean);
    const cri = (f.criancas || []).filter((c) => c.ativo).map((c) => c.pessoa?.nome).filter(Boolean);
    const nome = nomesResp[0] ? `Família de ${nomesResp[0]}` : "Família sem responsável";
    const busca = normalizar([...nomesResp, ...(f.criancas || []).map((c) => c.pessoa?.nome)].join(" "));
    return { id: f.id, nome, nomesResp, cri, busca, ordem: normalizar(nomesResp[0] || "zzz") };
  }).sort((a, b) => a.ordem.localeCompare(b.ordem));
  listaComBusca(painel, {
    itens, rotuloBusca: "Buscar responsável ou criança", vazio: "Nenhuma família encontrada.",
    desenharItem: (f) => itemLink(`#/ficha?tipo=familia&id=${encodeURIComponent(f.id)}`, f.nome, [
      f.cri.length ? f.cri.join(", ") : "Nenhuma criança ativa",
    ]),
  });
}

async function abaVoluntarias(painel) {
  montar(painel, carregando());
  const r = await listarVoluntarias();
  if (!painel.isConnected) return;
  if (!r.ok) { montar(painel, aviso("erro", r.erro)); return; }
  const itens = r.lista
    .map((v) => ({ ...v, nome: v.pessoa?.nome || "Sem nome", busca: normalizar(v.pessoa?.nome), anos: idade(v.pessoa?.data_nascimento) }))
    .sort((a, b) => a.busca.localeCompare(b.busca));
  const filtros = [
    { valor: "ativa", texto: "Ativas", teste: (v) => v.status === "ativa" },
    { valor: "pendente", texto: "Aguardando", teste: (v) => v.status === "pendente" },
    { valor: "inativa", texto: "Inativas", teste: (v) => v.status === "inativa" },
    { valor: "menor", texto: "Menores", teste: (v) => v.anos !== null && v.anos < 18 },
    { valor: "todas", texto: "Todas", teste: () => true },
  ];
  listaComBusca(painel, {
    itens, filtros, rotuloBusca: "Buscar voluntária", vazio: "Nenhuma voluntária encontrada.",
    desenharItem: (v) => itemLink(`#/ficha?tipo=voluntaria&id=${encodeURIComponent(v.id)}`, v.nome,
      [NOMES_FUNCAO[v.funcao] || null],
      [v.status !== "ativa" ? el("span", { class: "etiqueta etiqueta--laranja", text: NOMES_STATUS[v.status] || v.status }) : null,
       v.anos !== null && v.anos < 18 ? el("span", { class: "etiqueta", text: "Menor" }) : null].filter(Boolean),
      { tipo: "voluntaria", id: v.id }),
  });
}

// ---------------- Tela ----------------

export async function render(alvo) {
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: titulo }), aviso("erro", perfil.erro)); return; }

  const lideranca = perfil.temPapel("admin", "pastor", "lider");
  const recepcao = lideranca || perfil.temPapel("recepcao");
  const soVoluntaria = !recepcao && perfil.temPapel("voluntaria");

  const abas = [
    ...(recepcao || soVoluntaria ? [{ id: "criancas", texto: soVoluntaria ? "Minhas salas" : "Crianças", desenhar: abaCriancas }] : []),
    ...(recepcao ? [{ id: "familias", texto: "Famílias", desenhar: abaFamilias }] : []),
    ...(lideranca ? [{ id: "voluntarias", texto: "Voluntárias", desenhar: abaVoluntarias }] : []),
  ];
  if (!abas.length) {
    montar(alvo, el("h1", { text: titulo }), aviso("atencao", "Esta tela é para a equipe do Fonte Kids."));
    return;
  }

  const area = el("section", { id: "cadastros-area", role: "tabpanel" });
  const botoes = abas.map((a) => el("button", {
    class: "aba", type: "button", role: "tab", id: `aba-${a.id}`, "aria-controls": "cadastros-area",
    text: a.texto, onclick: () => abrir(a.id, true),
  }));

  function abrir(id, gravar) {
    const a = abas.find((x) => x.id === id) || abas[0];
    abas.forEach((x, i) => botoes[i].setAttribute("aria-selected", x.id === a.id ? "true" : "false"));
    area.setAttribute("aria-labelledby", `aba-${a.id}`);
    // guarda a aba no endereço sem recarregar a tela (o "voltar" da ficha volta para ela)
    if (gravar) history.replaceState(null, "", `#/cadastros?aba=${a.id}`);
    a.desenhar(area);
  }

  montar(alvo,
    el("h1", { text: lideranca ? "Cadastros" : "Crianças e famílias" }),
    abas.length > 1 ? el("div", { class: "abas", role: "tablist", "aria-label": "Cadastros" }, botoes) : null,
    area);
  abrir(parametro("aba"), false);
}
