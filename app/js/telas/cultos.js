// =====================================================================
// Tela: Cultos e salas (Fase 5 · Etapa 5A)   #/cultos
// Para liderança, pastores e admin (o banco confere tudo).
//   • Agenda: cultos fixos da semana (com sala do Kids). Criar, editar,
//     desativar/ativar e definir as salas (abertas, fechadas ou juntas),
//     que valem para todas as semanas.
//   • Próximos cultos (14 dias, criados sozinhos a partir da agenda):
//     ajustar as salas só daquele dia, voltar ao padrão, cancelar/reativar
//     e criar culto extra.
// Sem dados pessoais: só cultos e salas.
// =====================================================================
import { el, montar, aviso, carregando, menuAcoes } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela, campo } from "../janela.js";
import {
  meuPerfil, listarSalas, agendaCultos, cultosProximos, salvarCultoAgenda,
  definirSalasAgenda, definirSalasDia, cancelarCulto, criarCultoExtra,
} from "../supabase.js";

export const layout = "padrao";
export const titulo = "Cultos e salas";

const DIAS = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];
const FUSO = "America/Sao_Paulo";

let alvoTela = null;
let salasAtivas = [];

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
  const [rSalas, rAgenda, rProx] = await Promise.all([listarSalas(), agendaCultos(), cultosProximos(14)]);
  if (!alvoTela?.isConnected) return;
  const erro = [rSalas, rAgenda, rProx].find((r) => !r.ok);
  if (erro) { montar(alvoTela, el("h1", { text: titulo }), aviso("erro", erro.erro)); return; }
  salasAtivas = rSalas.lista.filter((s) => s.ativa);

  montar(alvoTela,
    el("h1", { text: titulo }),
    secao("Agenda da semana",
      el("button", { class: "botao botao--secundario botao--pequeno", type: "button", onclick: () => janelaCultoAgenda(null) },
        icone("adicionar"), "Novo"),
      rAgenda.lista.length
        ? el("ul", { class: "lista-compacta" }, rAgenda.lista.map(itemAgenda))
        : el("p", { class: "suave", text: "Nenhum culto na agenda." }),
      el("p", { class: "suave mt-3", text: "As salas da agenda valem para todas as semanas. Para mudar só um dia, use os próximos cultos." })),
    secao("Próximos cultos",
      el("button", { class: "botao botao--secundario botao--pequeno", type: "button", onclick: janelaCultoExtra },
        icone("adicionar"), "Culto extra"),
      rProx.lista.length
        ? el("ul", { class: "lista-compacta" }, rProx.lista.map(itemProximo))
        : el("p", { class: "suave", text: "Nenhum culto nos próximos 14 dias." })));
}

function secao(tituloSecao, acao, ...conteudo) {
  return el("section", { class: "secao-lista" },
    el("div", { class: "secao-titulo" }, el("h2", { text: tituloSecao }), acao), ...conteudo);
}

// ---------- Textos ----------

/** "0 a 2 · 3 a 6 · 7 a 12" e, se houver, "fechada: 10 a 12". */
function textoSalas(grupos) {
  const curto = (g) => g.nome.replace(/ anos$/, "");
  const abertas = grupos.filter((g) => !g.cancelada).map(curto);
  const fechadas = grupos.filter((g) => g.cancelada).map(curto);
  return [abertas.length ? `Salas ${abertas.join(" · ")}` : "Nenhuma sala aberta",
    fechadas.length ? `fechada: ${fechadas.join(", ")}` : null].filter(Boolean).join(" — ");
}

function dataBr(iso) {
  const d = new Date(`${iso}T12:00:00`);
  const semana = d.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short" }).replace(".", "");
  const dia = d.toLocaleDateString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit" });
  return `${semana.charAt(0).toUpperCase()}${semana.slice(1)} ${dia}`;
}

// ---------- Listas ----------

function itemAgenda(a) {
  const etiquetas = [
    !a.ativo ? el("span", { class: "etiqueta etiqueta--neutra", text: "Desativado" }) : null,
  ].filter(Boolean);
  return el("li", {}, el("div", { class: "item-compacto" },
    el("span", { class: "numero__icone" }, icone("calendario")),
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: a.nome }),
      el("span", { class: "item-compacto__linha", text: `${DIAS[a.dia_semana]} · ${a.horario}` }),
      el("span", { class: "item-compacto__linha", text: textoSalas(a.salas) })),
    etiquetas.length ? el("span", { class: "item-compacto__etiquetas" }, etiquetas) : null,
    menuAcoes([
      { texto: "Salas", acao: () => janelaSalas({ titulo: `Salas – ${a.nome}`, grupos: a.salas,
          ajuda: "Vale para todas as semanas (menos os dias ajustados à mão).",
          salvar: (lista) => definirSalasAgenda(a.id, lista) }) },
      { texto: "Editar", acao: () => janelaCultoAgenda(a) },
      a.ativo
        ? { texto: "Desativar", perigo: true, acao: () => janelaAtivar(a, false) }
        : { texto: "Ativar", acao: () => janelaAtivar(a, true) },
    ], `Mais ações para ${a.nome}`)));
}

function itemProximo(c) {
  const etiquetas = [
    c.cancelado ? el("span", { class: "etiqueta etiqueta--neutra", text: "Cancelado" }) : null,
    c.extra ? el("span", { class: "etiqueta etiqueta--azul", text: "Extra" }) : null,
    !c.extra && c.personalizado ? el("span", { class: "etiqueta etiqueta--laranja", text: "Ajustado" }) : null,
  ].filter(Boolean);
  const nome = `${dataBr(c.data)} · ${c.horario}`;
  return el("li", {}, el("div", { class: "item-compacto" },
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: nome }),
      el("span", { class: "item-compacto__linha", text: c.nome }),
      el("span", { class: "item-compacto__linha", text: c.cancelado ? "Sem sala do Kids neste dia" : textoSalas(c.salas) })),
    etiquetas.length ? el("span", { class: "item-compacto__etiquetas" }, etiquetas) : null,
    menuAcoes([
      c.cancelado ? null : { texto: "Salas deste dia", acao: () => janelaSalas({ titulo: `Salas – ${nome}`, grupos: c.salas,
          ajuda: "Vale só para este dia. Quem já fez check-in numa sala juntada passa para a sala que recebe.",
          salvar: (lista) => definirSalasDia(c.id, lista) }) },
      !c.extra && c.personalizado && !c.cancelado
        ? { texto: "Voltar ao padrão", acao: () => confirmar(`Voltar ${nome} às salas da agenda?`, "Voltar",
            () => definirSalasDia(c.id, null), "Salas da agenda aplicadas.") }
        : null,
      c.cancelado
        ? { texto: "Reativar", acao: () => confirmar(`Reativar o culto de ${nome}?`, "Reativar",
            () => cancelarCulto(c.id, false), "Culto reativado.") }
        : { texto: "Cancelar culto", perigo: true, acao: () => confirmar(
            `Cancelar o culto de ${nome}? Ele some do check-in deste dia.`, "Cancelar culto",
            () => cancelarCulto(c.id, true), "Culto cancelado.", true) },
    ], `Mais ações para ${nome}`)));
}

// ---------- Janelinhas ----------

function confirmar(texto, rotulo, acao, sucesso, perigo = false) {
  abrirJanela({
    titulo: rotulo, perigo, textoSalvar: rotulo, sucesso,
    conteudo: [el("p", { text: texto })],
    aoSalvar: async () => { const r = await acao(); if (!r.ok) return r.erro; await desenhar(); return null; },
  });
}

function janelaAtivar(a, ativar) {
  confirmar(ativar
    ? `Ativar "${a.nome}"? Os próximos dias aparecem sozinhos.`
    : `Desativar "${a.nome}"? Os próximos dias saem da lista (os que já têm check-in ficam).`,
  ativar ? "Ativar" : "Desativar",
  () => salvarCultoAgenda(a.id, a.nome, a.dia_semana, a.horario, ativar),
  ativar ? "Culto ativado." : "Culto desativado.", !ativar);
}

function janelaCultoAgenda(a) {
  const nome = el("input", { class: "entrada", type: "text", maxlength: "60", autocomplete: "off", value: a?.nome || "" });
  const dia = el("select", { class: "entrada" }, DIAS.map((d, i) => el("option", { value: String(i), text: d })));
  dia.value = String(a?.dia_semana ?? 0);
  const hora = el("input", { class: "entrada", type: "time", value: a?.horario || "" });
  abrirJanela({
    titulo: a ? "Editar culto da agenda" : "Novo culto na agenda",
    sucesso: a ? "Culto atualizado." : "Culto incluído na agenda.",
    conteudo: [
      campo("Nome", nome, "Ex.: Domingo 10h"),
      campo("Dia da semana", dia),
      campo("Horário", hora),
      a ? el("p", { class: "suave", text: "Mudar o dia ou o horário tira os próximos dias antigos (os que já têm check-in ficam)." }) : null,
    ].filter(Boolean),
    aoSalvar: async () => {
      if (!hora.value) return "Informe o horário.";
      const r = await salvarCultoAgenda(a?.id, nome.value.trim(), Number(dia.value), hora.value, a ? a.ativo : true);
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

function janelaCultoExtra() {
  const hoje = new Date().toLocaleDateString("en-CA", { timeZone: FUSO });
  const data = el("input", { class: "entrada", type: "date", min: hoje, value: hoje });
  const hora = el("input", { class: "entrada", type: "time" });
  const nome = el("input", { class: "entrada", type: "text", maxlength: "60", autocomplete: "off", placeholder: "Ex.: Culto de Natal" });
  abrirJanela({
    titulo: "Culto extra",
    sucesso: "Culto extra criado.",
    conteudo: [
      campo("Data", data), campo("Horário", hora), campo("Nome", nome),
      el("p", { class: "suave", text: "Começa com todas as salas abertas. Depois, em ⋯ → \"Salas deste dia\", dá para juntar ou fechar." }),
    ],
    aoSalvar: async () => {
      if (!data.value) return "Informe a data.";
      if (!hora.value) return "Informe o horário.";
      const r = await criarCultoExtra(data.value, hora.value, nome.value.trim());
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

/**
 * Salas de um culto: para cada sala, "Aberta", "Fechada" ou "Junto com …".
 * grupos: como vêm do banco (sala principal + salas juntas, ou fechada).
 */
function janelaSalas({ titulo: tituloJanela, grupos, ajuda, salvar }) {
  // situação atual de cada sala
  const atual = new Map();
  for (const g of grupos) {
    for (const id of g.salas) {
      if (id !== g.sala_id) atual.set(id, `junto:${g.sala_id}`);
      else atual.set(id, g.cancelada ? "fechada" : "aberta");
    }
  }
  const seletores = salasAtivas.map((s) => {
    const sel = el("select", { class: "entrada" },
      el("option", { value: "aberta", text: "Aberta" }),
      el("option", { value: "fechada", text: "Fechada" }),
      salasAtivas.filter((o) => o.id !== s.id).map((o) => el("option", { value: `junto:${o.id}`, text: `Junto com ${o.nome}` })));
    sel.value = atual.get(s.id) || "aberta";
    return { sala: s, sel };
  });

  abrirJanela({
    titulo: tituloJanela,
    sucesso: "Salas salvas.",
    conteudo: [
      el("p", { class: "suave", text: ajuda }),
      ...seletores.map(({ sala, sel }) => campo(sala.nome, sel)),
      el("p", { class: "suave", text: "Ex.: na terça, \"10 a 12 anos\" junto com \"7 a 9 anos\" vira a sala \"7 a 12 anos\"." }),
    ],
    aoSalvar: async () => {
      const lista = [];
      for (const { sala, sel } of seletores) {
        if (sel.value === "fechada") lista.push({ sala_id: sala.id, cancelada: true, junto_com: null });
        else if (sel.value.startsWith("junto:")) lista.push({ sala_id: sala.id, cancelada: false, junto_com: sel.value.slice(6) });
      }
      const r = await salvar(lista);
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

