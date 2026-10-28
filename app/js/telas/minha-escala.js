// =====================================================================
// Tela: Minha escala (Fase 6 · 6C)   #/minha-escala
// Para a voluntária (o banco confere tudo):
//   • Próximas vagas: Ciente, "Não poderei" (libera a vaga e avisa a
//     liderança), "Adicionar à agenda" (.ics feito aqui no aparelho) e
//     quem serve junto.
//   • Vagas abertas da escala publicada: "Quero esta vaga".
//   • Indisponibilidade dos meses em que a liderança pediu (até publicar).
// =====================================================================
import { el, montar, aviso, carregando, menuAcoes, toast } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela } from "../janela.js";
import { minhaEscala, responderEscala, pegarVaga, minhaIndisponibilidade, salvarIndisponibilidade } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Minha escala";

const FUSO = "America/Sao_Paulo";
const FUNCOES = { professora: "Professora(o)", auxiliar: "Auxiliar", reserva: "Reserva", lider_culto: "Líder do culto" };

let alvoTela = null;

function dataBr(iso) {
  const d = new Date(`${iso}T12:00:00`);
  const semana = d.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short" }).replace(".", "");
  const dia = d.toLocaleDateString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit" });
  return `${semana.charAt(0).toUpperCase()}${semana.slice(1)} ${dia}`;
}

export async function render(alvo) {
  alvoTela = alvo;
  montar(alvo, carregando());
  await desenhar();
}

async function desenhar() {
  const r = await minhaEscala();
  if (!alvoTela?.isConnected) return;
  if (!r.ok) {
    montar(alvoTela, el("h1", { text: titulo }),
      aviso("atencao", r.erro === "Sem permissão" ? "Esta tela é para quem serve na escala do Fonte Kids." : r.erro));
    return;
  }
  const { minhas = [], abertas = [], pedidos = [] } = r.resultado || {};
  const partes = [el("h1", { text: titulo })];

  // indisponibilidade pedida pela liderança (só responde quem tiver culto em que não pode)
  for (const p of pedidos) {
    const prazo = p.prazo ? `${p.prazo.slice(8, 10)}/${p.prazo.slice(5, 7)}` : null;
    partes.push(el("section", { class: p.respondeu ? "cartao cartao--compacto" : "cartao cartao--atencao cartao--compacto" },
      el("span", { class: "numero__icone" }, icone("calendario")),
      el("div", { class: "flex-1" }, el("strong", { text: `Indisponibilidade de ${p.nome_mes}` }), el("br"),
        el("span", { class: "suave", text: p.respondeu
          ? "Respondida. Dá para mudar até a escala sair."
          : `Tem algum culto em que não pode servir? Marque${prazo ? ` até ${prazo}` : ""}.` })),
      el("button", { class: p.respondeu ? "botao botao--secundario botao--pequeno" : "botao botao--primario botao--pequeno",
        type: "button", onclick: () => janelaIndisponibilidade(p.mes) }, p.respondeu ? "Mudar" : "Marcar")));
  }

  partes.push(el("div", { class: "secao-titulo" }, el("h2", { text: "Minhas próximas vagas" }),
    el("a", { href: "#/escala", text: "Escala completa" })));
  partes.push(minhas.length
    ? el("div", { class: "pendencias" }, minhas.map(itemMeu))
    : el("p", { class: "suave", text: "Você não está escalada nos próximos cultos." }));

  if (abertas.length) {
    partes.push(el("div", { class: "secao-titulo" }, el("h2", { text: "Vagas abertas" })),
      el("p", { class: "resumo-lista", text: "Quer ajudar? Pegue uma vaga e ela já fica sua." }),
      el("ul", { class: "lista-compacta" }, abertas.map(itemAberto)));
  }
  montar(alvoTela, partes);
}

function itemMeu(m) {
  const funcao = FUNCOES[m.funcao] || m.funcao;
  const ciente = m.resposta === "ciente";
  const colegas = (m.colegas || []).map((c) => `${c.nome} (${(FUNCOES[c.funcao] || c.funcao).toLowerCase()})`);
  return el("section", { class: "cartao" },
    el("div", { class: "linha linha--entre" },
      el("strong", { text: `${dataBr(m.data)} · ${m.hora}` }),
      m.cancelado ? el("span", { class: "etiqueta etiqueta--neutra", text: "Culto cancelado" })
        : el("span", { class: ciente ? "etiqueta etiqueta--sucesso" : "etiqueta etiqueta--laranja", text: ciente ? "Ciente" : "Confirme" })),
    el("p", { class: "sem-margem mt-1", text: m.funcao === "lider_culto" ? `${m.culto} · ${funcao}` : `${m.culto} · ${m.sala} · ${funcao}` }),
    m.cobrindo_lider ? el("p", { class: "suave sem-margem mt-1", text: "Você vai conduzir a sala neste dia." }) : null,
    colegas.length ? el("p", { class: "suave sem-margem mt-1", text: `Junto com: ${colegas.join(", ")}` }) : null,
    m.cancelado ? null : el("div", { class: "linha acoes-cartao" },
      ciente ? null : el("button", { class: "botao botao--primario botao--pequeno", type: "button", onclick: () => responder(m, "ciente") },
        icone("check"), "Ciente"),
      el("button", { class: "botao botao--secundario botao--pequeno", type: "button", onclick: () => baixarIcs(m) },
        icone("calendario"), "Adicionar à agenda"),
      menuAcoes([{ texto: "Não poderei", perigo: true, acao: () => naoPoderei(m) }], `Mais ações para ${dataBr(m.data)}`)));
}

function itemAberto(a) {
  const funcao = FUNCOES[a.funcao] || a.funcao;
  return el("li", {}, el("div", { class: "item-compacto" },
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: `${dataBr(a.data)} · ${a.hora}` }),
      el("span", { class: "item-compacto__linha", text: `${a.sala} · ${funcao}` })),
    el("button", { class: "botao botao--secundario botao--pequeno", type: "button", onclick: () => quero(a) }, "Quero")));
}

// ---------- Ações ----------

async function responder(m, resposta) {
  const r = await responderEscala(m.id, resposta);
  if (!r.ok) { toast("erro", r.erro); return; }
  toast("sucesso", "Obrigada! Marcado como ciente.");
  await desenhar();
}

function naoPoderei(m) {
  abrirJanela({
    titulo: "Não poderei",
    textoSalvar: "Liberar a vaga",
    perigo: true,
    sucesso: "Vaga liberada. A liderança foi avisada.",
    conteudo: [
      el("p", { text: `Liberar sua vaga de ${dataBr(m.data)} às ${m.hora}?` }),
      el("p", { class: "suave", text: "A vaga fica aberta para outra pessoa e a liderança recebe um aviso." }),
    ],
    aoSalvar: async () => {
      const r = await responderEscala(m.id, "recusado");
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

function quero(a) {
  const funcao = FUNCOES[a.funcao] || a.funcao;
  abrirJanela({
    titulo: "Quero esta vaga",
    textoSalvar: "Pegar a vaga",
    sucesso: "Vaga sua! A liderança foi avisada.",
    conteudo: [el("p", { text: `${dataBr(a.data)} às ${a.hora} · ${a.sala} · ${funcao}.` }),
      el("p", { class: "suave", text: "Você entra já como Ciente." })],
    aoSalvar: async () => {
      const r = await pegarVaga(a.id);
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

async function janelaIndisponibilidade(mes) {
  const r = await minhaIndisponibilidade(mes);
  if (!r.ok) { toast("erro", r.erro); return; }
  const x = r.resultado || {};
  const caixas = (x.cultos || []).map((c) => {
    const caixa = el("input", { type: "checkbox", value: c.id });
    caixa.checked = !!c.indisponivel;
    return el("label", { class: "marcar" }, caixa, `${dataBr(c.data)} · ${c.hora} · ${c.nome}`);
  });
  abrirJanela({
    titulo: `Indisponibilidade – ${x.nome_mes}`,
    sucesso: "Indisponibilidade salva. Obrigada!",
    conteudo: [
      el("p", { text: "Marque os cultos em que você NÃO pode servir." }),
      el("p", { class: "suave", text: "Se puder em todos, não precisa fazer nada (ou salve sem marcar)." }),
      caixas.length ? el("div", { class: "mt-2" }, caixas) : el("p", { class: "suave", text: "Nenhum culto neste mês." }),
    ],
    aoSalvar: async () => {
      const ids = caixas.map((l) => l.querySelector("input")).filter((c) => c.checked).map((c) => c.value);
      const res = await salvarIndisponibilidade(x.mes, ids);
      if (!res.ok) return res.erro;
      await desenhar();
      return null;
    },
  });
}

// ---------- .ics (feito no aparelho, sem enviar nada) ----------

function baixarIcs(m) {
  // São Paulo não tem horário de verão desde 2019: UTC−3
  const inicio = new Date(`${m.data}T${m.horario}:00-03:00`);
  const fim = new Date(inicio.getTime() + 2 * 60 * 60 * 1000);
  const utc = (d) => d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
  const esc = (t) => String(t).replace(/[\\;,]/g, (c) => `\\${c}`).replace(/\n/g, "\\n");
  const funcao = FUNCOES[m.funcao] || m.funcao;
  const titulo = `Fonte Kids · ${funcao}`;
  const descricao = m.funcao === "lider_culto" ? `${m.culto} · ${funcao}` : `${m.culto} · ${m.sala} · ${funcao}`;
  const linhas = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Fonte Kids//Escala//PT", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
    "BEGIN:VEVENT",
    `UID:${m.id}@fonte-kids`,
    `DTSTAMP:${utc(new Date())}`,
    `DTSTART:${utc(inicio)}`,
    `DTEND:${utc(fim)}`,
    `SUMMARY:${esc(titulo)}`,
    `DESCRIPTION:${esc(descricao)}`,
    "BEGIN:VALARM", "TRIGGER:-PT2H", "ACTION:DISPLAY", `DESCRIPTION:${esc(titulo)}`, "END:VALARM",
    "END:VEVENT", "END:VCALENDAR",
  ];
  const blob = new Blob([linhas.join("\r\n") + "\r\n"], { type: "text/calendar;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = el("a", { href: url, download: `fonte-kids-${m.data}.ics` });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 10000);
}
