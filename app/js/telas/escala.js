// =====================================================================
// Tela: Escala do mês (Fase 6 · 6B)   #/escala?mes=YYYY-MM
// Liderança (o banco confere tudo):
//   • Começar o mês, vagas por sala (inclusive salas juntas) e por culto.
//   • Gerar o rascunho (motor no banco), trocar/esvaziar/remover/adicionar
//     vagas, líder do culto e publicar (avisa cada voluntária).
//   • Regras da escala, teto por voluntária e quem já respondeu a
//     indisponibilidade.
// Equipe (recepção/voluntária): só a escala publicada, com os nomes.
// Sem telefones aqui: os lembretes ficam em #/lembretes-escala.
// =====================================================================
import { el, montar, aviso, carregando, menuAcoes, toast } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela, campo } from "../janela.js";
import {
  meuPerfil, escalaDoMes, configurarEscala, definirVagasCulto, gerarRascunho, candidatasVaga, trocarVaga,
  adicionarVaga, removerVaga, publicarEscala, regrasEscalaAtuais, definirRegrasEscala, voluntariasEscala,
  definirTetoVoluntaria, indisponibilidadeDoMes,
} from "../supabase.js";

export const layout = "padrao";
export const titulo = "Escala";

const FUSO = "America/Sao_Paulo";
const FUNCOES = { professora: "Professora(o)", auxiliar: "Auxiliar", reserva: "Reserva", lider_culto: "Líder do culto" };
const AVISOS = {
  max: "já no teto do mês", no_dia: "já escalada neste dia", indisponivel: "marcou indisponível",
  fora_da_faixa: "fora da faixa preferida", fora_do_culto: "fora do culto preferido", nao_lidera: "não pode ser professora",
};

let alvoTela = null;
let mes = "";          // "YYYY-MM-01"
let dados = null;      // resultado de escala_do_mes
let soVazias = false;

const param = (nome) => new URLSearchParams(location.hash.split("?")[1] || "").get(nome);
const mesHoje = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO }).slice(0, 7);

function somarMes(aaaamm, n) {
  const [a, m] = aaaamm.split("-").map(Number);
  const d = new Date(Date.UTC(a, m - 1 + n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}

function nomeMes(aaaamm) {
  const t = new Date(`${aaaamm}-15T12:00:00`).toLocaleDateString("pt-BR", { timeZone: FUSO, month: "long" });
  return t.charAt(0).toUpperCase() + t.slice(1);
}

function dataBr(iso) {
  const d = new Date(`${iso}T12:00:00`);
  const semana = d.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short" }).replace(".", "");
  const dia = d.toLocaleDateString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit" });
  return `${semana.charAt(0).toUpperCase()}${semana.slice(1)} ${dia}`;
}

export async function render(alvo) {
  alvoTela = alvo;
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: titulo }), aviso("erro", perfil.erro)); return; }
  if (!perfil.temPapel("admin", "pastor", "lider", "recepcao", "voluntaria")) {
    montar(alvo, el("h1", { text: titulo }), aviso("atencao", "Esta tela é só para a equipe do Fonte Kids."));
    return;
  }
  const lider = perfil.temPapel("admin", "pastor", "lider");
  const pedido = param("mes");
  const valido = /^\d{4}-\d{2}$/.test(pedido || "") ? pedido : null;
  // liderança monta o próximo mês; a equipe quer ver o mês atual
  mes = `${valido || (lider ? somarMes(mesHoje(), 1) : mesHoje())}-01`;
  await desenhar();
}

async function desenhar() {
  const r = await escalaDoMes(mes);
  if (!alvoTela?.isConnected) return;
  if (!r.ok) { montar(alvoTela, el("h1", { text: titulo }), escolherMes(false), aviso("erro", r.erro)); return; }
  dados = r.resultado;
  const lider = !!dados.pode_editar;
  const esc = dados.escala;

  const partes = [el("h1", { text: titulo }), escolherMes(lider)];

  if (!esc) {
    partes.push(lider
      ? el("section", { class: "cartao" },
          el("strong", { text: `A escala de ${dados.nome_mes} ainda não foi começada.` }),
          el("p", { class: "suave", text: "Começar copia as vagas por sala do mês anterior. Depois dá para ajustar." }),
          el("button", { class: "botao botao--primario", type: "button", onclick: comecar }, "Começar a escala"))
      : aviso("info", `A escala de ${dados.nome_mes} ainda não foi publicada.`));
    montar(alvoTela, partes);
    return;
  }

  partes.push(resumo(lider));

  const cultos = dados.cultos || [];
  if (lider) {
    partes.push(el("div", { class: "chips mt-2" },
      [["Todas as vagas", false], ["Só as vazias", true]].map(([texto, v]) => el("button", {
        class: "chip", type: "button", "aria-pressed": String(soVazias === v), text: texto,
        onclick: () => { soVazias = v; desenhar(); } }))));
  }
  if (!cultos.length) {
    partes.push(el("p", { class: "suave mt-3", text: "Nenhum culto neste mês." }));
  } else if (esc.status === "rascunho" && !cultos.some((c) => c.itens.length)) {
    partes.push(el("p", { class: "suave mt-3", text: "Confira as vagas por sala e toque em \"Gerar escala\"." }));
  }
  for (const c of cultos) partes.push(secaoCulto(c, lider));
  montar(alvoTela, partes);
}

function escolherMes(lider) {
  const atual = mes.slice(0, 7);
  const opcoes = [0, 1, 2, 3].map((n) => somarMes(mesHoje(), n));
  if (!opcoes.includes(atual)) opcoes.unshift(atual);
  if (!lider) opcoes.splice(2);
  return el("div", { class: "chips" }, opcoes.map((m) => el("button", {
    class: "chip", type: "button", "aria-pressed": String(m === atual), text: nomeMes(m),
    onclick: () => { if (m !== atual) location.hash = `#/escala?mes=${m}`; } })));
}

// ---------- Resumo e ações do mês ----------

function resumo(lider) {
  const esc = dados.escala;
  const rs = dados.resumo || {};
  const rascunho = esc.status === "rascunho";
  const temItens = (dados.cultos || []).some((c) => c.itens.length);
  const linhas = [
    `${rs.vagas || 0} vagas · ${rs.vazias || 0} vazias${rascunho ? "" : ` · ${rs.cientes || 0} cientes`}`,
    rs.lider_culto_vazias ? `${rs.lider_culto_vazias} culto(s) sem líder do culto` : null,
    lider && dados.indisponibilidade
      ? `Indisponibilidade: ${dados.indisponibilidade.responderam} de ${dados.indisponibilidade.ativas} responderam` : null,
  ].filter(Boolean);

  const acoes = lider ? [
    rascunho ? el("button", { class: "botao botao--secundario botao--pequeno", type: "button", onclick: janelaVagasMes }, "Vagas por sala") : null,
    rascunho ? el("button", { class: temItens ? "botao botao--secundario botao--pequeno" : "botao botao--primario botao--pequeno",
      type: "button", onclick: () => gerar(temItens) }, temItens ? "Gerar de novo" : "Gerar escala") : null,
    rascunho && temItens ? el("button", { class: "botao botao--primario botao--pequeno", type: "button", onclick: publicar }, "Publicar") : null,
    !rascunho ? el("a", { class: "botao botao--secundario botao--pequeno", href: "#/lembretes-escala" }, icone("conversa"), "Lembretes") : null,
  ].filter(Boolean) : [];
  // o ⋯ fica no canto direito do cartão, para o menu abrir dentro da tela
  const menu = lider ? menuAcoes([
    { texto: "Regras da escala", acao: janelaRegras },
    { texto: "Teto por voluntária", acao: janelaTetos },
    { texto: "Quem respondeu a indisponibilidade", acao: janelaIndisponibilidade },
  ], "Mais ações da escala") : null;

  return el("section", { class: "cartao mt-3" },
    el("div", { class: "linha linha--entre" },
      el("strong", { text: `Escala de ${dados.nome_mes}` }),
      el("span", { class: "linha" },
        el("span", { class: rascunho ? "etiqueta etiqueta--laranja" : "etiqueta etiqueta--sucesso", text: rascunho ? "Rascunho" : "Publicada" }),
        menu)),
    linhas.map((t) => el("p", { class: "suave sem-margem mt-1", text: t })),
    acoes.length ? el("div", { class: "linha acoes-cartao" }, acoes) : null);
}

// ---------- Cultos e vagas ----------

function secaoCulto(c, lider) {
  const rascunho = dados.escala.status === "rascunho";
  let itens = c.itens;
  if (soVazias) itens = itens.filter((i) => !i.nome);
  if (soVazias && !itens.length) return null;
  const nome = `${dataBr(c.data)} · ${c.hora}`;
  return el("section", { class: "secao-lista" },
    el("div", { class: "secao-titulo" },
      el("h2", { text: `${nome} · ${c.nome}` }),
      lider && !c.cancelado ? menuAcoes([
        { texto: "Adicionar vaga", acao: () => janelaAdicionar(c) },
        rascunho ? { texto: "Vagas deste culto", acao: () => janelaVagasCulto(c) } : null,
      ], `Mais ações para ${nome}`) : null),
    c.cancelado ? el("p", { class: "suave", text: "Culto cancelado." }) : null,
    itens.length
      ? el("ul", { class: "lista-compacta" }, itens.map((i) => itemVaga(i, c, lider)))
      : el("p", { class: "suave", text: rascunho ? "Ainda sem vagas geradas." : "Sem vagas." }));
}

function itemVaga(i, c, lider) {
  const publicada = dados.escala.status === "publicada";
  const etiquetas = [
    i.minha ? el("span", { class: "etiqueta etiqueta--azul", text: "Você" }) : null,
    i.cobrindo_lider ? el("span", { class: "etiqueta etiqueta--laranja", text: "Cobrindo professora" }) : null,
    publicada && i.nome && i.resposta === "ciente" ? el("span", { class: "etiqueta etiqueta--sucesso", text: "Ciente" }) : null,
    publicada && i.voluntaria_id && i.resposta !== "ciente" ? el("span", { class: "etiqueta etiqueta--neutra", text: "Aguardando" }) : null,
  ].filter(Boolean);
  const funcao = FUNCOES[i.funcao] || i.funcao;
  return el("li", {}, el("div", { class: "item-compacto" },
    el("span", { class: "item-compacto__texto" },
      el("span", { class: i.nome ? "item-compacto__nome" : "item-compacto__nome suave", text: i.nome || "Vaga aberta" }),
      el("span", { class: "item-compacto__linha", text: i.funcao === "lider_culto" ? funcao : `${i.sala} · ${funcao}` })),
    etiquetas.length ? el("span", { class: "item-compacto__etiquetas" }, etiquetas) : null,
    lider ? menuAcoes([
      { texto: i.nome ? "Trocar" : "Escolher quem", acao: () => janelaTrocar(i, c) },
      i.nome ? { texto: "Deixar vazia", acao: () => confirmar(`Deixar vazia a vaga de ${funcao} em ${dataBr(c.data)}?${publicada && i.voluntaria_id ? " A voluntária recebe um aviso." : ""}`,
          "Deixar vazia", () => trocarVaga(i.id, null, null), "Vaga esvaziada.") } : null,
      { texto: "Remover vaga", perigo: true, acao: () => confirmar(`Remover esta vaga de ${funcao} em ${dataBr(c.data)}?${publicada && i.voluntaria_id ? " A voluntária recebe um aviso." : ""}`,
          "Remover", () => removerVaga(i.id), "Vaga removida.", true) },
    ], `Mais ações para ${funcao} em ${dataBr(c.data)}`) : null));
}

// ---------- Ações ----------

async function comecar() {
  const r = await configurarEscala(mes, null);
  if (!r.ok) { toast("erro", r.erro); return; }
  await desenhar();
  janelaVagasMes();
}

function confirmar(texto, rotulo, acao, sucesso, perigo = false) {
  abrirJanela({
    titulo: rotulo, perigo, textoSalvar: rotulo, sucesso,
    conteudo: [el("p", { text: texto })],
    aoSalvar: async () => { const r = await acao(); if (!r.ok) return r.erro; await desenhar(); return null; },
  });
}

function gerar(deNovo) {
  abrirJanela({
    titulo: deNovo ? "Gerar de novo" : "Gerar escala",
    textoSalvar: deNovo ? "Gerar de novo" : "Gerar",
    perigo: deNovo,
    conteudo: [
      el("p", { text: deNovo
        ? `Isso apaga o rascunho de ${dados.nome_mes} (inclusive as trocas feitas à mão) e monta tudo de novo.`
        : `Montar a escala de ${dados.nome_mes} com as vagas por sala, as preferências, o teto e a indisponibilidade de cada voluntária.` }),
      el("p", { class: "suave", text: "Nada é enviado às voluntárias até você publicar." }),
    ],
    aoSalvar: async () => {
      const r = await gerarRascunho(mes);
      if (!r.ok) return r.erro;
      const x = r.resultado || {};
      toast("sucesso", `${x.preenchidas} de ${x.vagas} vagas preenchidas${x.vazias ? ` · ${x.vazias} vazias` : ""}.`, 6000);
      await desenhar();
      return null;
    },
  });
}

function publicar() {
  const rs = dados.resumo || {};
  abrirJanela({
    titulo: "Publicar escala",
    textoSalvar: "Publicar",
    conteudo: [
      el("p", { text: `Publicar a escala de ${dados.nome_mes}? Cada voluntária escalada recebe um aviso no app para marcar Ciente.` }),
      rs.vazias ? el("p", { class: "suave", text: `${rs.vazias} vaga(s) vazia(s) ficam abertas para quem quiser pegar.` }) : null,
      el("p", { class: "suave", text: "Depois de publicada, a escala não pode ser gerada de novo; os ajustes são vaga a vaga." }),
    ].filter(Boolean),
    aoSalvar: async () => {
      const r = await publicarEscala(mes);
      if (!r.ok) return r.erro;
      toast("sucesso", `Escala publicada. ${r.resultado?.voluntarias ?? 0} voluntárias avisadas.`, 6000);
      await desenhar();
      return null;
    },
  });
}

// ---------- Janelas de vagas ----------

function seletorNumero(valor, rotulo, max = 9) {
  const s = el("select", { class: "entrada", "aria-label": rotulo },
    Array.from({ length: max + 1 }, (_, n) => el("option", { value: String(n), text: String(n) })));
  s.value = String(valor ?? 0);
  return s;
}

/** Três seletores (professora, auxiliar, reserva) para uma sala. */
function trioVagas(rotulo, v) {
  const prof = seletorNumero(v?.professora, `${rotulo}: professoras`);
  const aux = seletorNumero(v?.auxiliar, `${rotulo}: auxiliares`);
  const res = seletorNumero(v?.reserva, `${rotulo}: reservas`);
  const bloco = el("div", { class: "grade grade--tres" },
    campo("Professora", prof), campo("Auxiliar", aux), campo("Reserva", res));
  return { bloco, ler: () => ({ professora: Number(prof.value), auxiliar: Number(aux.value), reserva: Number(res.value) }) };
}

function janelaVagasMes() {
  const config = dados.config || [];
  const trios = config.map((s) => ({ s, t: trioVagas(s.sala, s) }));
  abrirJanela({
    titulo: `Vagas por sala – ${dados.nome_mes}`,
    sucesso: "Vagas salvas. Gere a escala para aplicar.",
    conteudo: [
      el("p", { class: "suave", text: "Quantas pessoas em cada sala, em todos os cultos do mês. Para mudar só um culto, use ⋯ → \"Vagas deste culto\"." }),
      ...trios.map(({ s, t }) => el("div", { class: "mt-3" },
        el("strong", { text: s.sala }),
        s.juntas ? el("p", { class: "suave sem-margem", text: "Quando outras salas se juntam a ela (ex.: 7 a 12 anos na terça)." }) : null,
        t.bloco)),
    ],
    aoSalvar: async () => {
      const lista = trios.map(({ s, t }) => ({ sala_id: s.sala_id, juntas: s.juntas, ...t.ler() }));
      const r = await configurarEscala(mes, lista);
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

function padraoDaSala(c, sala) {
  const config = dados.config || [];
  const ajuste = (dados.ajustes || []).find((a) => a.culto_id === c.id && a.sala_id === sala.sala_id);
  const base = config.find((x) => x.sala_id === sala.sala_id && x.sala !== sala.nome && x.juntas)
    || config.find((x) => x.sala_id === sala.sala_id && !x.juntas) || { professora: 0, auxiliar: 0, reserva: 0 };
  return { ajuste, base };
}

function janelaVagasCulto(c) {
  const linhas = c.salas.map((sala) => {
    const { ajuste, base } = padraoDaSala(c, sala);
    return { sala, ajuste, base, t: trioVagas(sala.nome, ajuste || base) };
  });
  abrirJanela({
    titulo: `Vagas – ${dataBr(c.data)} · ${c.hora}`,
    sucesso: "Vagas deste culto salvas. Gere a escala para aplicar.",
    conteudo: [
      el("p", { class: "suave", text: "Vale só para este culto, na próxima vez que gerar a escala. Deixe igual ao padrão do mês para não mudar nada." }),
      ...linhas.map(({ sala, base, t }) => el("div", { class: "mt-3" },
        el("strong", { text: sala.nome }),
        el("p", { class: "suave sem-margem", text: `Padrão do mês: ${base.professora} · ${base.auxiliar} · ${base.reserva}` }),
        t.bloco)),
    ],
    aoSalvar: async () => {
      for (const { sala, ajuste, base, t } of linhas) {
        const v = t.ler();
        const igual = v.professora === base.professora && v.auxiliar === base.auxiliar && v.reserva === base.reserva;
        if (igual && !ajuste) continue;
        const r = await definirVagasCulto(c.id, sala.sala_id, igual ? null : v);
        if (!r.ok) return r.erro;
      }
      await desenhar();
      return null;
    },
  });
}

function janelaAdicionar(c) {
  const sala = el("select", { class: "entrada" },
    c.salas.map((s) => el("option", { value: s.sala_id, text: s.nome })),
    el("option", { value: "", text: "Geral (líder do culto)" }));
  const funcao = el("select", { class: "entrada" },
    ["professora", "auxiliar", "reserva"].map((f) => el("option", { value: f, text: FUNCOES[f] })));
  sala.addEventListener("change", () => { funcao.disabled = !sala.value; });
  if (!c.salas.length) { sala.value = ""; funcao.disabled = true; }
  abrirJanela({
    titulo: `Adicionar vaga – ${dataBr(c.data)}`,
    sucesso: "Vaga adicionada.",
    conteudo: [campo("Sala", sala), campo("Função", funcao),
      el("p", { class: "suave", text: "A vaga entra vazia. Depois, em ⋯ → \"Escolher quem\"." })],
    aoSalvar: async () => {
      const r = sala.value ? await adicionarVaga(c.id, sala.value, funcao.value) : await adicionarVaga(c.id, null, "lider_culto");
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

async function janelaTrocar(i, c) {
  const r = await candidatasVaga(i.id);
  if (!r.ok) { toast("erro", r.erro); return; }
  const lista = r.resultado || [];
  const grupo = `trocar-${i.id}`;
  const busca = el("input", { class: "entrada", type: "search", placeholder: "Buscar pelo nome", autocomplete: "off" });
  const linhas = lista.map((v) => {
    const radio = el("input", { type: "radio", name: grupo, value: v.voluntaria_id });
    if (v.voluntaria_id === i.voluntaria_id) radio.checked = true;
    const avisos = v.avisos.map((a) => a === "max" ? `${v.no_mes} de ${v.teto} no mês` : AVISOS[a] || a);
    const rotulo = el("label", { class: "marcar" }, radio,
      el("span", {}, el("span", { text: v.nome }), el("br"),
        el("span", { class: "suave", text: avisos.length ? avisos.join(" · ") : `${v.no_mes} de ${v.teto} no mês` })));
    return { v, rotulo, radio };
  });
  const livreRadio = el("input", { type: "radio", name: grupo, value: "livre" });
  const livreNome = el("input", { class: "entrada", type: "text", maxlength: "80", autocomplete: "off", placeholder: "Nome de quem vai servir" });
  if (i.nome_livre) { livreRadio.checked = true; livreNome.value = i.nome || ""; }
  livreNome.addEventListener("input", () => { livreRadio.checked = true; });
  busca.addEventListener("input", () => {
    const q = busca.value.trim().toLocaleLowerCase("pt-BR");
    for (const l of linhas) l.rotulo.hidden = !!q && !l.v.nome.toLocaleLowerCase("pt-BR").includes(q);
  });
  const funcao = FUNCOES[i.funcao] || i.funcao;
  abrirJanela({
    titulo: `${funcao} · ${dataBr(c.data)} ${c.hora}`,
    sucesso: "Vaga atualizada.",
    conteudo: [
      i.funcao === "lider_culto" ? null : el("p", { class: "suave", text: i.sala }),
      busca,
      el("div", { class: "mt-3" }, linhas.map((l) => l.rotulo)),
      el("label", { class: "marcar" }, livreRadio, el("span", { text: "Outra pessoa (sem cadastro)" })),
      livreNome,
      dados.escala.status === "publicada" ? el("p", { class: "suave mt-2", text: "Quem sai e quem entra recebem um aviso no app." }) : null,
    ].filter(Boolean),
    aoSalvar: async () => {
      const marcado = [livreRadio, ...linhas.map((l) => l.radio)].find((x) => x.checked);
      if (!marcado) return "Escolha uma voluntária ou escreva um nome.";
      const res = marcado === livreRadio
        ? (livreNome.value.trim().length < 2 ? { ok: false, erro: "Escreva o nome." } : await trocarVaga(i.id, null, livreNome.value.trim()))
        : await trocarVaga(i.id, marcado.value, null);
      if (!res.ok) return res.erro;
      await desenhar();
      return null;
    },
  });
}

// ---------- Regras, tetos e indisponibilidade ----------

async function janelaRegras() {
  const r = await regrasEscalaAtuais();
  if (!r.ok) { toast("erro", r.erro); return; }
  const g = r.resultado || {};
  const fem = g.auxiliar_feminina_lider_masculino || { ativo: true, idade_min_sala: 10 };

  const teto = seletorNumero(g.teto_padrao ?? 3, "Teto", 10);
  teto.querySelector("option[value='0']").remove();
  const umaPorDia = el("input", { type: "checkbox" }); umaPorDia.checked = g.uma_vaga_por_dia !== false;
  const idade = el("select", { class: "entrada" }, [12, 13, 14, 15, 16, 17, 18].map((n) => el("option", { value: String(n), text: `${n} anos` })));
  idade.value = String(g.idade_minima_lider ?? 16);
  const femAtivo = el("input", { type: "checkbox" }); femAtivo.checked = fem.ativo !== false;
  const femIdade = el("select", { class: "entrada" }, [0, 3, 7, 10].map((n) => el("option", { value: String(n), text: n ? `Salas a partir de ${n} anos` : "Todas as salas" })));
  femIdade.value = String(fem.idade_min_sala ?? 10);
  const limite = el("select", { class: "entrada" }, el("option", { value: "", text: "Até publicar" }),
    Array.from({ length: 28 }, (_, n) => el("option", { value: String(n + 1), text: `Até o dia ${n + 1} do mês anterior` })));
  limite.value = g.dia_limite_indisponibilidade ? String(g.dia_limite_indisponibilidade) : "";
  const ordem = el("select", { class: "entrada" },
    el("option", { value: "dificeis", text: "Vagas mais difíceis primeiro (recomendado)" }),
    el("option", { value: "datas", text: "Pela ordem das datas (como antes)" }));
  ordem.value = g.ordem_preenchimento || "dificeis";
  const msg = el("textarea", { class: "entrada", rows: "5", maxlength: "1000" });
  msg.value = g.mensagem_lembrete || "";

  abrirJanela({
    titulo: "Regras da escala",
    sucesso: "Regras salvas.",
    conteudo: [
      campo("Máximo de vagas por voluntária no mês", teto, "Dá para mudar por pessoa em \"Teto por voluntária\"."),
      el("label", { class: "marcar" }, umaPorDia, "No máximo uma vaga por dia"),
      campo("Idade mínima para ser professora(o)", idade),
      el("label", { class: "marcar" }, femAtivo, "Professor homem: auxiliares mulheres"),
      campo("Onde vale essa regra", femIdade),
      campo("Prazo para marcar indisponibilidade", limite),
      campo("Ordem de preenchimento", ordem),
      campo("Mensagem do lembrete (WhatsApp)", msg,
        "Use {nome_voluntaria}, {data_culto}, {horario_culto}, {sala} e {papel}."),
    ],
    aoSalvar: async () => {
      const res = await definirRegrasEscala({
        teto_padrao: Number(teto.value),
        uma_vaga_por_dia: umaPorDia.checked,
        idade_minima_lider: Number(idade.value),
        auxiliar_feminina_lider_masculino: { ativo: femAtivo.checked, idade_min_sala: Number(femIdade.value) },
        dia_limite_indisponibilidade: limite.value ? Number(limite.value) : null,
        ordem_preenchimento: ordem.value,
        mensagem_lembrete: msg.value.trim(),
      });
      return res.ok ? null : res.erro;
    },
  });
}

async function janelaTetos() {
  const r = await voluntariasEscala();
  if (!r.ok) { toast("erro", r.erro); return; }
  const lista = r.resultado || [];
  const busca = el("input", { class: "entrada", type: "search", placeholder: "Buscar pelo nome", autocomplete: "off" });
  const linhas = lista.map((v) => {
    const sel = el("select", { class: "entrada", "aria-label": `Teto de ${v.nome}` },
      el("option", { value: "", text: "Padrão" }),
      Array.from({ length: 11 }, (_, n) => el("option", { value: String(n), text: n === 0 ? "0 (não escalar)" : String(n) })));
    sel.value = v.teto === null || v.teto === undefined ? "" : String(v.teto);
    const bloco = campo(v.nome, sel, [v.pode_liderar ? "Pode ser professora(o)" : null, (v.salas || []).join(", ")].filter(Boolean).join(" · "));
    return { v, sel, bloco };
  });
  busca.addEventListener("input", () => {
    const q = busca.value.trim().toLocaleLowerCase("pt-BR");
    for (const l of linhas) l.bloco.hidden = !!q && !l.v.nome.toLocaleLowerCase("pt-BR").includes(q);
  });
  abrirJanela({
    titulo: "Teto por voluntária",
    sucesso: "Tetos salvos.",
    conteudo: [
      el("p", { class: "suave", text: "Máximo de vagas no mês para cada pessoa. \"Padrão\" segue as regras da escala." }),
      busca, ...linhas.map((l) => l.bloco),
    ],
    aoSalvar: async () => {
      for (const { v, sel } of linhas) {
        const novo = sel.value === "" ? null : Number(sel.value);
        if (novo === (v.teto ?? null)) continue;
        const res = await definirTetoVoluntaria(v.id, novo);
        if (!res.ok) return `${v.nome}: ${res.erro}`;
      }
      return null;
    },
  });
}

async function janelaIndisponibilidade() {
  const r = await indisponibilidadeDoMes(mes);
  if (!r.ok) { toast("erro", r.erro); return; }
  const lista = r.resultado || [];
  const faltam = lista.filter((v) => !v.respondeu);
  const responderam = lista.filter((v) => v.respondeu);
  const item = (v) => el("li", {}, el("div", { class: "item-compacto" },
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: v.nome }),
      v.respondeu ? el("span", { class: "item-compacto__linha", text: v.cultos ? `${v.cultos} culto(s) indisponível` : "Disponível em todos" }) : null)));
  abrirJanela({
    titulo: `Indisponibilidade – ${dados.nome_mes}`,
    textoSalvar: "Fechar",
    conteudo: [
      el("p", { class: "suave", text: `${responderam.length} de ${lista.length} responderam. Cada voluntária marca em "Minha escala".` }),
      faltam.length ? el("strong", { text: "Ainda não responderam" }) : null,
      faltam.length ? el("ul", { class: "lista-compacta" }, faltam.map(item)) : null,
      responderam.length ? el("strong", { class: "mt-3", text: "Responderam" }) : null,
      responderam.length ? el("ul", { class: "lista-compacta" }, responderam.map(item)) : null,
    ].filter(Boolean),
    aoSalvar: async () => null,
  });
}
