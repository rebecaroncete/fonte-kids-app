// =====================================================================
// Tela: Enquetes (Fase 7)   #/enquetes  (aba "Enquetes" dentro de Avisos)
// Todos veem as enquetes do seu público (equipe, responsáveis ou todos) e
// votam; dá para mudar o voto até encerrar. Quem vota vê só os totais
// (sem nomes) depois de votar ou quando a enquete encerra.
// Liderança: "Nova enquete" (pergunta, público, opções, uma ou várias
// escolhas, prazo opcional), vê quem votou, encerra, apaga e manda a
// enquete no grupo pelo WhatsApp (wa.me, com o link do app).
// =====================================================================
import { el, montar, aviso, carregando, toast, menuAcoes } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela, campo, novoId } from "../janela.js";
import { meuPerfil, enquetesLista, criarEnquete, votarEnquete, encerrarEnquete, apagarEnquete, enderecoApp } from "../supabase.js";
import { abasAvisos, botaoWhatsapp, quando } from "./notificacoes.js";

export const layout = "padrao";
export const titulo = "Enquetes";

const FUSO = "America/Sao_Paulo";
const LIDERANCA = ["admin", "pastor", "lider"];
const PUBLICOS = [["equipe", "Equipe"], ["familias", "Responsáveis"], ["todos", "Todos (equipe e responsáveis)"]];
const NOME_PUBLICO = { equipe: "Equipe", familias: "Responsáveis", todos: "Todos" };

const isoHoje = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO });
const dataHora = (iso) => new Date(iso).toLocaleString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
function ultimoDia(iso) {
  // encerra_em = meia-noite do dia seguinte ao prazo → mostra o próprio prazo
  const d = new Date(new Date(iso).getTime() - 60 * 1000);
  return d.toLocaleDateString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit" });
}

let alvoTela = null;
let lider = false;

export async function render(alvo) {
  alvoTela = alvo;
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  lider = perfil.ok && perfil.temPapel(...LIDERANCA);
  await desenhar();
}

async function desenhar() {
  const r = await enquetesLista();
  if (!alvoTela?.isConnected) return;
  const cabecalho = el("div", { class: "cabecalho-tela" }, el("h1", { text: "Avisos" }),
    lider ? el("button", { class: "botao botao--primario botao--pequeno", type: "button", onclick: janelaNova },
      icone("adicionar"), "Nova enquete") : null);
  const partes = [cabecalho, abasAvisos("enquetes", lider, () => {})];
  if (!r.ok) { montar(alvoTela, partes, aviso("erro", r.erro)); return; }
  const lista = r.resultado || [];
  if (!lista.length) {
    partes.push(aviso("info", lider ? "Nenhuma enquete ainda. Toque em \"Nova enquete\"." : "Nenhuma enquete por enquanto."));
  } else {
    partes.push(el("div", {}, lista.map(cartaoEnquete)));
  }
  montar(alvoTela, partes);
}

function cartaoEnquete(q) {
  const votei = (q.meus_votos || []).length > 0;
  const etiquetas = el("div", { class: "linha" },
    q.aberta ? el("span", { class: "etiqueta etiqueta--sucesso", text: "Aberta" }) : el("span", { class: "etiqueta etiqueta--neutra", text: "Encerrada" }),
    lider ? el("span", { class: "etiqueta etiqueta--azul", text: NOME_PUBLICO[q.publico] || q.publico }) : null,
    votei ? el("span", { class: "etiqueta etiqueta--laranja", text: "Você respondeu" }) : null);

  const prazo = q.encerra_em
    ? (q.aberta ? `Responda até ${ultimoDia(q.encerra_em)}` : `Encerrada em ${dataHora(q.encerra_em)}`)
    : (q.aberta ? "Sem prazo" : "");
  const info = [quando(q.criado_em), prazo, q.multipla ? "Pode marcar mais de uma" : null,
    q.ve_totais && q.votantes != null ? `${q.votantes}${lider && q.destinatarios != null ? ` de ${q.destinatarios}` : ""} responderam` : null]
    .filter(Boolean).join(" · ");

  const menu = lider ? menuAcoes([
    q.aberta ? { texto: "Encerrar", acao: () => confirmar("Encerrar a enquete?", "Ninguém mais poderá votar. Os totais ficam visíveis para todos que receberam.", "Encerrar", () => encerrarEnquete(q.id), "Enquete encerrada.") } : null,
    { texto: "Apagar", perigo: true, acao: () => confirmar("Apagar a enquete?", "A enquete e os votos somem para todos. Não dá para desfazer.", "Apagar", () => apagarEnquete(q.id), "Enquete apagada.", true) },
  ], "Mais ações da enquete") : null;

  const corpo = el("div", {});
  if (q.pode_votar) corpo.append(formVoto(q));
  if (q.ve_totais) corpo.append(resultados(q));
  else if (!q.pode_votar) corpo.append(el("p", { class: "suave", text: "Os resultados aparecem quando a enquete encerrar." }));
  if (lider && (q.quem_votou || []).length) corpo.append(quemVotou(q));

  const textoZap = `📊 *Enquete do Fonte Kids*\n${q.pergunta}\n${(q.opcoes || []).map((o) => `• ${o.texto}`).join("\n")}\n\nResponda no app: ${enderecoApp("/enquetes")}`;
  return el("section", { class: "cartao" },
    el("div", { class: "cartao-topo" },
      el("div", { class: "flex-1" }, el("h2", { text: q.pergunta }), etiquetas),
      menu),
    el("p", { class: "suave mt-2", text: info }),
    corpo,
    lider && q.aberta ? el("div", { class: "linha mt-3" }, botaoWhatsapp(textoZap)) : null);
}

function formVoto(q) {
  const nome = novoId("enquete");
  const marcados = new Set(q.meus_votos || []);
  const caixas = (q.opcoes || []).map((o) => {
    const entrada = el("input", { type: q.multipla ? "checkbox" : "radio", name: nome, value: o.id, checked: marcados.has(o.id) });
    return { entrada, rotulo: el("label", { class: "marcar" }, entrada, o.texto) };
  });
  const botao = el("button", { class: "botao botao--primario botao--pequeno", type: "submit", text: marcados.size ? "Mudar voto" : "Votar" });
  const form = el("form", { class: "mt-3" },
    el("fieldset", { class: "enquete-opcoes" }, el("legend", { class: "campo__rotulo", text: q.multipla ? "Marque uma ou mais" : "Escolha uma" }),
      caixas.map((c) => c.rotulo)),
    el("div", { class: "linha" }, botao,
      marcados.size ? el("button", { class: "botao botao--texto botao--pequeno", type: "button", text: "Tirar meu voto",
        onclick: () => votar(q.id, [], "Voto retirado.") }) : null));
  form.addEventListener("submit", (e) => {
    e.preventDefault();
    const escolhidos = caixas.filter((c) => c.entrada.checked).map((c) => c.entrada.value);
    if (!escolhidos.length) { toast("atencao", "Escolha uma opção."); return; }
    botao.disabled = true;
    votar(q.id, escolhidos, "Voto registrado.").finally(() => { botao.disabled = false; });
  });
  return form;
}

async function votar(id, opcoes, ok) {
  const r = await votarEnquete(id, opcoes);
  if (!r.ok) { toast("erro", r.erro); return; }
  toast("sucesso", ok);
  await desenhar();
}

function resultados(q) {
  const total = (q.opcoes || []).reduce((n, o) => n + (Number(o.votos) || 0), 0);
  return el("ul", { class: "resultado-enquete", "aria-label": "Resultado" }, (q.opcoes || []).map((o) => {
    const v = Number(o.votos) || 0;
    const pct = total ? Math.round((v * 100) / total) : 0;
    return el("li", {},
      el("div", { class: "linha linha--entre" }, el("span", { text: o.texto }),
        el("strong", { text: `${v} ${v === 1 ? "voto" : "votos"} · ${pct}%` })),
      el("progress", { class: "barra-voto", max: String(Math.max(total, 1)), value: String(v), "aria-label": `${o.texto}: ${pct}%` }));
  }));
}

function quemVotou(q) {
  const lista = el("ul", { class: "lista-simples", hidden: true },
    q.quem_votou.map((x) => el("li", { text: `${x.nome}: ${(x.opcoes || []).join(", ")}` })));
  const ver = el("button", { class: "botao botao--texto botao--pequeno", type: "button", "aria-expanded": "false",
    text: `Quem respondeu (${q.quem_votou.length})` });
  ver.addEventListener("click", () => {
    lista.hidden = !lista.hidden;
    ver.setAttribute("aria-expanded", String(!lista.hidden));
  });
  return el("div", { class: "mt-2" }, ver, lista);
}

function confirmar(tit, texto, botao, acao, sucesso, perigo = false) {
  abrirJanela({
    titulo: tit,
    conteudo: [el("p", { text: texto })],
    textoSalvar: botao,
    perigo,
    sucesso,
    aoSalvar: async () => {
      const r = await acao();
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

function janelaNova() {
  const pergunta = el("input", { class: "entrada", type: "text", maxlength: "200", placeholder: "Ex.: Qual o melhor dia para a reunião?" });
  const publico = el("select", { class: "entrada" },
    el("option", { value: "", text: "Escolha…" }),
    PUBLICOS.map(([v, t]) => el("option", { value: v, text: t })));
  const opcoes = el("textarea", { class: "entrada", rows: "4", placeholder: "Uma opção por linha (de 2 a 10)" });
  const multipla = el("input", { type: "checkbox" });
  const ate = el("input", { class: "entrada", type: "date", min: isoHoje() });
  abrirJanela({
    titulo: "Nova enquete",
    conteudo: [
      campo("Pergunta", pergunta),
      campo("Para quem", publico),
      campo("Opções", opcoes, "Escreva uma opção por linha."),
      el("label", { class: "marcar" }, multipla, "Pode marcar mais de uma"),
      campo("Responder até (opcional)", ate, "Sem data, fica aberta até você encerrar."),
    ],
    textoSalvar: "Publicar",
    aoSalvar: async () => {
      if (pergunta.value.trim().length < 3) { pergunta.focus(); return "Escreva a pergunta."; }
      if (!publico.value) { publico.focus(); return "Escolha para quem é a enquete."; }
      const lista = opcoes.value.split("\n").map((s) => s.trim()).filter(Boolean);
      if (lista.length < 2 || lista.length > 10) { opcoes.focus(); return "Escreva de 2 a 10 opções, uma por linha."; }
      const r = await criarEnquete(pergunta.value.trim(), publico.value, lista, multipla.checked, ate.value || null);
      if (!r.ok) return r.erro;
      const n = r.resultado?.destinatarios ?? 0;
      toast("sucesso", `Enquete publicada. ${n === 1 ? "1 pessoa avisada" : `${n} pessoas avisadas`}.`);
      await desenhar();
      return null;
    },
  });
}
