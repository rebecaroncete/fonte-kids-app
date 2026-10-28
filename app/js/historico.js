// =====================================================================
// Fonte Kids – histórico de check-ins de uma criança (Fase 5 · 5E)
// • secaoHistorico(): seção da ficha (resumo + últimos 5 + "Ver tudo")
// • janelaHistorico(): janelinha com a lista completa ("Carregar mais")
// Leitura só pela função historico_crianca() do banco: recepção/liderança
// veem qualquer criança do Fonte Kids; o responsável, só os próprios filhos.
// Nunca vem data de nascimento, telefone nem alergias.
// =====================================================================
import { el, montar, aviso, carregando } from "./ui.js";
import { historicoCrianca } from "./supabase.js";

const FUSO = "America/Sao_Paulo";
const DIAS = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"];

/** "2026-10-26" → "26/10/2026" */
export function dataBr(iso) {
  if (!iso) return "—";
  const [a, m, d] = String(iso).slice(0, 10).split("-");
  return `${d}/${m}/${a}`;
}
/** "2026-10-26" → "dom, 26/10" */
export function diaCurto(iso) {
  const [a, m, d] = String(iso).slice(0, 10).split("-").map(Number);
  return `${DIAS[new Date(a, m - 1, d).getDay()]}, ${String(d).padStart(2, "0")}/${String(m).padStart(2, "0")}`;
}
/** horário de um carimbo de data/hora, em Brasília */
export function hora(iso) {
  return iso ? new Date(iso).toLocaleTimeString("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" }) : "";
}
/** "Saiu · 12:40" | "Saída automática · 13:00" | "Sem saída" */
export function textoSaida(i) {
  if (!i.saida_em) return "Sem saída";
  return i.saida_automatica ? `Saída automática · ${hora(i.saida_em)}` : `Saiu · ${hora(i.saida_em)}`;
}
/** nome do culto com o horário: "Culto 10h · 10:00" */
export function nomeCulto(c) {
  return [c.nome || c.culto || "Culto", c.horario].filter(Boolean).join(" · ");
}

function resumoTexto(res) {
  if (!res || !res.total) return "Nenhuma presença registrada ainda.";
  return [
    `${res.ultimos_30} nos últimos 30 dias`,
    `${res.ultimos_90} em 90 dias`,
    res.ultima_vez ? `última vez em ${dataBr(res.ultima_vez)}` : null,
  ].filter(Boolean).join(" · ");
}

/** Uma linha do histórico (um check-in). */
export function itemHistorico(i) {
  const chamadas = i.chamadas || [];
  const etiqueta = chamadas.length
    ? el("span", { class: "etiqueta etiqueta--laranja",
        text: chamadas.length === 1 ? `Chamado ${hora(chamadas[0].chamada_em)}` : `Chamado ${chamadas.length}x` })
    : null;
  return el("li", {}, el("div", { class: "item-compacto" },
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: `${diaCurto(i.data)} · ${nomeCulto(i)}` }),
      el("span", { class: "item-compacto__linha item-compacto__linha--quebra", text: [
        i.sala ? `Sala ${i.sala}` : null,
        `Entrada ${hora(i.entrada_em)}`,
        textoSaida(i),
        i.codigo ? `Código ${i.codigo}` : null,
      ].filter(Boolean).join(" · ") })),
    etiqueta ? el("span", { class: "item-compacto__etiquetas" }, etiqueta) : null));
}

/** Seção "Histórico" (ficha da criança). */
export function secaoHistorico(criancaId, nome) {
  const corpo = el("div", {}, carregando());
  const secao = el("section", { class: "secao-lista" },
    el("div", { class: "secao-titulo" }, el("h2", { text: "Histórico" })), corpo);
  historicoCrianca(criancaId, null, 5).then((r) => {
    if (!r.ok) { montar(corpo, aviso("erro", r.erro)); return; }
    montar(corpo,
      el("p", { class: "resumo-lista", text: resumoTexto(r.resumo) }),
      r.itens.length ? el("ul", { class: "lista-compacta" }, r.itens.map(itemHistorico)) : null,
      r.tem_mais ? el("p", { class: "mt-2" }, el("button", {
        class: "botao botao--secundario botao--pequeno", type: "button", text: "Ver tudo",
        onclick: () => janelaHistorico(criancaId, nome) })) : null);
  });
  return secao;
}

/** Janelinha com o histórico completo, de 20 em 20. */
export function janelaHistorico(criancaId, nome) {
  document.querySelector("dialog.janela")?.remove();
  const resumo = el("p", { class: "resumo-lista" });
  const lista = el("ul", { class: "lista-compacta" });
  const situacao = el("div", {}, carregando());
  const mais = el("button", { class: "botao botao--secundario botao--pequeno", type: "button", text: "Carregar mais", hidden: true });
  const fechar = el("button", { class: "botao botao--pequeno", type: "button", text: "Fechar" });
  const janela = el("dialog", { class: "janela", "aria-label": `Histórico de ${nome || "criança"}` },
    el("h2", { text: nome ? `Histórico de ${nome}` : "Histórico" }), resumo, lista, situacao,
    el("div", { class: "linha mt-3" }, mais, fechar));
  let antes = null;

  async function carregar() {
    mais.disabled = true;
    montar(situacao, carregando());
    const r = await historicoCrianca(criancaId, antes, 20);
    if (!janela.isConnected) return;
    mais.disabled = false;
    if (!r.ok) { montar(situacao, aviso("erro", r.erro)); return; }
    montar(situacao);
    if (antes === null) {
      resumo.textContent = resumoTexto(r.resumo);
      if (!r.itens.length) montar(situacao, el("p", { class: "suave", text: "Nenhum check-in registrado." }));
    }
    lista.append(...r.itens.map(itemHistorico));
    if (r.itens.length) antes = r.itens[r.itens.length - 1].entrada_em;
    mais.hidden = !r.tem_mais;
  }

  mais.addEventListener("click", carregar);
  fechar.addEventListener("click", () => janela.close());
  janela.addEventListener("close", () => janela.remove());
  document.body.append(janela);
  janela.showModal();
  fechar.focus();
  carregar();
  return janela;
}
