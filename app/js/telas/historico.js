// =====================================================================
// Tela: Histórico (Fase 5 · Etapa 5E)
//   #/historico                lista de cultos que já aconteceram
//                              (chips 30 dias · 90 dias · Tudo), com o total
//                              e o total por sala de cada culto
//   #/historico?culto=<id>     quem veio naquele culto, por sala
// Só recepção, liderança, pastores e admin (o banco confere).
// Nunca mostra data de nascimento, telefone nem alergias.
// =====================================================================
import { el, montar, aviso, carregando } from "../ui.js";
import { icone } from "../icones.js";
import { meuPerfil, historicoCultos, historicoCulto } from "../supabase.js";
import { avatarLista, preencherFotos } from "../foto.js";
import { dataBr, diaCurto, hora, textoSaida, nomeCulto } from "../historico.js";

export const layout = "padrao";
export const titulo = "Histórico";

const PERIODOS = [[30, "30 dias"], [90, "90 dias"], [null, "Tudo"]];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const escolhas = { dias: 30 };
const plural = (n, um, varios) => `${n} ${n === 1 ? um : varios}`;

function parametro(nome) {
  return new URLSearchParams(location.hash.split("?")[1] || "").get(nome);
}

export async function render(alvo) {
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: titulo }), aviso("erro", perfil.erro)); return; }
  if (!perfil.temPapel("admin", "pastor", "lider", "recepcao")) {
    montar(alvo, el("h1", { text: titulo }), aviso("atencao", "Esta tela é só para a equipe do Fonte Kids."));
    return;
  }
  const culto = parametro("culto");
  if (culto) {
    if (!UUID.test(culto)) { montar(alvo, voltar(), aviso("atencao", "Endereço inválido.")); return; }
    await desenharCulto(alvo, culto);
  } else {
    await desenharLista(alvo);
  }
}

function voltar() {
  return el("p", { class: "voltar" }, el("a", { class: "botao botao--texto botao--pequeno", href: "#/historico" },
    icone("voltar"), "Voltar"));
}

// ---------------- Lista de cultos ----------------
async function desenharLista(alvo) {
  const chips = el("div", { class: "chips" });
  const resumo = el("p", { class: "resumo-lista", role: "status" });
  const lista = el("ul", { class: "lista-compacta" });
  const situacao = el("div", {});
  const mais = el("button", { class: "botao botao--secundario botao--pequeno", type: "button", text: "Carregar mais", hidden: true });
  let antes = null;
  let carregados = [];
  let versao = 0;

  montar(alvo,
    el("h1", { text: titulo }),
    el("p", { class: "suave", text: "Cultos que já aconteceram. Toque num culto para ver quem veio." }),
    chips, el("div", { class: "mt-3" }, resumo, lista, situacao, el("p", { class: "mt-2" }, mais)));

  function desenharChips() {
    montar(chips, PERIODOS.map(([v, t]) => el("button", { class: "chip", type: "button", text: t,
      "aria-pressed": String(escolhas.dias === v),
      onclick: () => { if (escolhas.dias !== v) { escolhas.dias = v; recomecar(); } } })));
  }

  function atualizarResumo() {
    const comCriancas = carregados.filter((c) => c.total > 0);
    const soma = comCriancas.reduce((s, c) => s + c.total, 0);
    resumo.textContent = !carregados.length ? "" : [
      plural(carregados.length, "culto", "cultos"),
      comCriancas.length ? `média de ${Math.round(soma / comCriancas.length)} crianças por culto` : null,
    ].filter(Boolean).join(" · ");
  }

  async function carregar() {
    const minha = versao;
    mais.disabled = true;
    montar(situacao, carregando());
    const r = await historicoCultos(escolhas.dias, antes);
    if (minha !== versao || !alvo.isConnected) return;
    mais.disabled = false;
    if (!r.ok) { montar(situacao, aviso("erro", r.erro)); return; }
    montar(situacao);
    carregados = carregados.concat(r.itens);
    lista.append(...r.itens.map(itemCulto));
    if (!carregados.length) montar(situacao, el("p", { class: "suave", text: "Nenhum culto neste período." }));
    antes = r.proximo_antes;
    mais.hidden = !r.tem_mais;
    atualizarResumo();
  }

  function recomecar() {
    versao += 1;
    antes = null;
    carregados = [];
    lista.replaceChildren();
    resumo.textContent = "";
    desenharChips();
    carregar();
  }

  mais.addEventListener("click", carregar);
  recomecar();
}

function itemCulto(c) {
  const salas = (c.salas || []).map((s) => `${s.nome}: ${s.total}`).join(" · ");
  const etiquetas = [
    el("span", { class: c.total ? "etiqueta etiqueta--azul" : "etiqueta etiqueta--neutra", text: plural(c.total, "criança", "crianças") }),
    c.cancelado ? el("span", { class: "etiqueta etiqueta--neutra", text: "Cancelado" }) : null,
    c.chamadas ? el("span", { class: "etiqueta etiqueta--laranja", text: plural(c.chamadas, "chamada", "chamadas") }) : null,
  ].filter(Boolean);
  return el("li", {}, el("a", { class: "item-compacto", href: `#/historico?culto=${encodeURIComponent(c.id)}` },
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: `${diaCurto(c.data)} · ${nomeCulto(c)}` }),
      el("span", { class: "item-compacto__linha item-compacto__linha--quebra", text: salas || "Sem check-in" })),
    el("span", { class: "item-compacto__etiquetas" }, etiquetas),
    icone("seta", null, "item-compacto__seta")));
}

// ---------------- Um culto ----------------
async function desenharCulto(alvo, id) {
  const r = await historicoCulto(id);
  if (!alvo.isConnected) return;
  if (!r.ok) { montar(alvo, voltar(), aviso("erro", r.erro)); return; }
  const c = r.culto;
  document.title = `Culto ${dataBr(c.data)} · Fonte Kids`;

  montar(alvo,
    voltar(),
    el("h1", { text: `${diaCurto(c.data)} · ${nomeCulto(c)}` }),
    el("p", { class: "resumo-lista", text: [
      plural(c.total, "criança", "crianças"),
      c.cancelado ? "culto cancelado" : null,
    ].filter(Boolean).join(" · ") }),
    r.salas.length ? r.salas.map((s) => el("section", { class: "secao-lista" },
      el("div", { class: "secao-titulo" }, el("h2", { text: `${s.nome} (${s.criancas.length})` })),
      el("ul", { class: "lista-compacta" }, s.criancas.map(itemCrianca))))
      : el("p", { class: "suave", text: "Nenhum check-in neste culto." }));
  preencherFotos(alvo);
}

function itemCrianca(k) {
  return el("li", {}, el("a", { class: "item-compacto", href: `#/ficha?tipo=crianca&id=${encodeURIComponent(k.crianca_id)}` },
    avatarLista("crianca", k.crianca_id, k.nome),
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: k.nome || "Sem nome" }),
      el("span", { class: "item-compacto__linha item-compacto__linha--quebra", text: [
        k.codigo ? `Código ${k.codigo}` : null, `Entrada ${hora(k.entrada_em)}`, textoSaida(k),
      ].filter(Boolean).join(" · ") })),
    k.chamadas ? el("span", { class: "item-compacto__etiquetas" },
      el("span", { class: "etiqueta etiqueta--laranja", text: k.chamadas === 1 ? "Chamado" : `Chamado ${k.chamadas}x` })) : null,
    icone("seta", null, "item-compacto__seta")));
}
