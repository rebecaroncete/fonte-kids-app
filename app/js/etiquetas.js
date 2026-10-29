// =====================================================================
// Etiquetas da Brother QL-800 (Fase 11)
// Rolo DK-22205 (62 mm contínuo, preto no branco).
//   Criança      62 × 40 mm: nome curto, sala, código grande, data/culto,
//                só o AVISO de alergia (qual é fica no app, em Presentes) e,
//                para urgência, primeiro nome e telefone do responsável.
//   Responsável  62 × (30 + 10 por criança) mm, até 6 crianças por etiqueta:
//                nome curto, sala e código de cada criança, data/culto.
// A do responsável não leva telefone. O conteúdo vem pronto do banco
// (estacao_buscar / estacao_lista).
// Impressão: window.print() de uma "folha" só com as etiquetas; o CSS de
// impressão (componentes.css, "Fase 11") esconde todo o resto e escolhe o
// tamanho da página. No Chrome aberto com --kiosk-printing sai direto na
// impressora padrão, sem a janela de impressão.
// =====================================================================
import { el } from "./ui.js";

const POR_ETIQUETA = 6;
const salaCurta = (nome) => (nome ? nome.replace(/ anos$/, "") : "");
const cabecalho = (e, rotulo) => el("div", { class: "etq__topo" },
  el("span", { text: rotulo }), el("span", { text: `${e.data.slice(0, 5)} · ${e.horario}` }));

function etiquetaCrianca(e) {
  const c = e.criancas[0];
  return el("div", { class: "etq etq--crianca" },
    cabecalho(e, "FONTE KIDS"),
    el("div", { class: "etq__nome", text: c.nome }),
    el("div", { class: "etq__sala", text: `Sala ${salaCurta(c.sala)}` }),
    el("div", { class: "etq__codigo", text: c.codigo }),
    c.alergia ? el("div", { class: "etq__alergia", text: "⚠ ALERGIA · ver no app" }) : null,
    c.responsavel || c.telefone
      ? el("div", { class: "etq__responsavel", text: [c.responsavel, c.telefone].filter(Boolean).join(" · ") }) : null);
}

function etiquetasResponsavel(e) {
  const partes = [];
  for (let i = 0; i < e.criancas.length; i += POR_ETIQUETA) partes.push(e.criancas.slice(i, i + POR_ETIQUETA));
  return partes.map((lista) => el("div", { class: `etq etq--resp etq--resp-${lista.length}` },
    cabecalho(e, "RESPONSÁVEL"),
    el("ul", { class: "etq__lista" }, lista.map((c) => el("li", { class: "etq__linha" },
      el("span", { class: "etq__linha-nome", text: c.nome }),
      el("span", { class: "etq__linha-sala", text: salaCurta(c.sala) }),
      el("span", { class: "etq__linha-codigo", text: c.codigo })))),
    el("div", { class: "etq__rodape", text: "Mostre na porta da sala para buscar" })));
}

/** Elementos de uma etiqueta (a do responsável pode virar mais de uma). */
export function desenharEtiqueta(e) {
  if (!e || !e.criancas?.length) return [];
  return e.tipo === "responsavel" ? etiquetasResponsavel(e) : [etiquetaCrianca(e)];
}

/** Etiqueta fictícia para o "Imprimir teste" (nenhum dado real). */
export function etiquetasTeste() {
  const agora = new Date();
  const data = agora.toLocaleDateString("pt-BR", { timeZone: "America/Sao_Paulo" });
  const horario = agora.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });
  const base = { data, horario, culto: "Teste" };
  return [
    { ...base, tipo: "crianca", criancas: [{ nome: "Teste T.", sala: "3 a 6 anos", codigo: "T123", alergia: true,
      responsavel: "Exemplo", telefone: "(00) 00000-0000" }] },
    { ...base, tipo: "responsavel", criancas: [
      { nome: "Teste T.", sala: "3 a 6 anos", codigo: "T123" },
      { nome: "Exemplo E.", sala: "7 a 12 anos", codigo: "E456" }] },
  ];
}

/**
 * Imprime uma lista de etiquetas (dados do banco), uma página por etiqueta.
 * Devolve quando o navegador terminou de mandar para a impressora.
 */
export async function imprimirEtiquetas(lista) {
  const paginas = lista.flatMap(desenharEtiqueta);
  if (!paginas.length) return;
  const folha = el("div", { class: "folha-etiquetas", "aria-hidden": "true" }, paginas);
  document.body.append(folha);
  document.body.classList.add("modo-etiqueta");
  // O Chrome dispara o afterprint DENTRO do print(); Firefox/Safari, depois.
  // Por isso a escuta começa antes (e há um limite de 3 s).
  const terminou = new Promise((ok) => {
    const fim = () => { window.removeEventListener("afterprint", fim); clearTimeout(t); ok(); };
    const t = setTimeout(fim, 3000);
    window.addEventListener("afterprint", fim);
  });
  try {
    await new Promise((ok) => setTimeout(ok, 60)); // desenha antes (rAF não roda com a aba escondida)
    window.print();
    await terminou;
  } finally {
    document.body.classList.remove("modo-etiqueta");
    folha.remove();
  }
}
