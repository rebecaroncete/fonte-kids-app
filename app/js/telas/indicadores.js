// =====================================================================
// Tela: Indicadores e relatórios (Fase 9)
//   #/indicadores?aba=semana&dia=YYYY-MM-DD   semana (domingo a sábado)
//   #/indicadores?aba=mes&mes=YYYY-MM         mês
//   #/indicadores?aba=mes&mes=YYYY-MM&ver=relatorio   Relatório do mês
//   #/indicadores?aba=cuidado                 "Sentimos falta" e
//                                             voluntárias sem escala
// Só a liderança (líder, pastor, admin); o banco confere.
// Semana e mês comparam com o período anterior. O relatório e o
// "Mandar no grupo" usam só indicadores_mes, que não traz nomes nem
// telefones: dá para mandar ao pastor ou no grupo sem expor crianças.
// No app instalado no iPhone o "Imprimir" não funciona: "Imagem do relatório".
// Nomes aparecem só na aba "Cuidado", dentro do app (nada é exportado).
// =====================================================================
import { el, montar, aviso, carregando, toast } from "../ui.js";
import { icone } from "../icones.js";
import { meuPerfil, indicadoresSemana, indicadoresMes, sentimosFalta, voluntariasSemEscala } from "../supabase.js";
import { botaoWhatsapp } from "./notificacoes.js";
import { imagemDoRelatorio } from "../imagem-relatorio.js";
import { janelaImagem } from "../compartilhar-imagem.js";
import { CONFIG } from "../../config.js";

export const layout = "padrao";
export const titulo = "Indicadores";

const FUSO = "America/Sao_Paulo";
const ABAS = [["semana", "Semana"], ["mes", "Mês"], ["cuidado", "Cuidado"]];
const FUNCOES = { professora: "Professora(o)", auxiliar: "Auxiliar" };

const param = (nome) => new URLSearchParams(location.hash.split("?")[1] || "").get(nome);
const isoHoje = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO });
const ddmm = (iso) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}` : "–");
const ddmmaa = (iso) => (iso ? `${iso.slice(8, 10)}/${iso.slice(5, 7)}/${iso.slice(0, 4)}` : "–");
const num = (v) => Number(v || 0).toLocaleString("pt-BR", { maximumFractionDigits: 1 });
const pct = (a, b) => (b ? Math.round((100 * a) / b) : 0);
const plural = (n, um, varios) => `${num(n)} ${Number(n) === 1 ? um : varios}`;
const primeiroNome = (nome) => String(nome || "").trim().split(/\s+/)[0] || "";

function somarDias(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
function somarMes(aaaamm, n) {
  const [a, m] = aaaamm.split("-").map(Number);
  const d = new Date(Date.UTC(a, m - 1 + n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}
const inicioSemana = (iso) => somarDias(iso, -new Date(`${iso}T12:00:00Z`).getUTCDay());

function diaCurto(iso) {
  const d = new Date(`${iso}T12:00:00`);
  const s = d.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short" }).replace(".", "");
  return `${s.charAt(0).toUpperCase()}${s.slice(1)} ${ddmm(iso)}`;
}
const maiuscula = (t) => (t ? t.charAt(0).toUpperCase() + t.slice(1) : "");

export async function render(alvo) {
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: titulo }), aviso("erro", perfil.erro)); return; }
  if (!perfil.temPapel("admin", "pastor", "lider")) {
    montar(alvo, el("h1", { text: titulo }), aviso("atencao", "Esta tela é só para a liderança do Fonte Kids."));
    return;
  }
  const aba = ABAS.some(([a]) => a === param("aba")) ? param("aba") : "semana";
  if (aba === "mes" && param("ver") === "relatorio") { await relatorio(alvo); return; }
  if (aba === "semana") await semana(alvo);
  else if (aba === "mes") await mes(alvo);
  else await cuidado(alvo);
}

// ---------- Peças ----------

function cabecalho(aba) {
  return [
    el("h1", { text: "Indicadores" }),
    el("div", { class: "chips" }, ABAS.map(([a, texto]) => el("button", {
      class: "chip", type: "button", "aria-pressed": String(a === aba), text: texto,
      onclick: () => { if (a !== aba) location.hash = `#/indicadores?aba=${a}`; } }))),
  ];
}

/** ‹ período › (o "›" some quando o próximo período ainda não começou) */
function navegar(texto, hrefAntes, hrefDepois) {
  return el("div", { class: "ind-nav" },
    el("a", { class: "botao-icone", href: hrefAntes, "aria-label": "Período anterior" }, icone("voltar")),
    el("strong", { class: "ind-nav__texto", text: texto }),
    hrefDepois
      ? el("a", { class: "botao-icone", href: hrefDepois, "aria-label": "Próximo período" }, icone("seta"))
      : el("span", { class: "botao-icone ind-nav__vazio", "aria-hidden": "true" }));
}

/** "+3 vs semana anterior" (periodo: "semana anterior" | "mês anterior") */
function variacao(atual, anterior, periodo) {
  if (atual === null || atual === undefined || anterior === null || anterior === undefined) return null;
  const d = Number(atual) - Number(anterior);
  const texto = d === 0 ? `igual ${periodo.startsWith("semana") ? "à" : "ao"} anterior`
    : `${d > 0 ? "+" : "−"}${num(Math.abs(d))} vs anterior`;
  return el("span", { class: `ind-var ${d > 0 ? "ind-var--sobe" : d < 0 ? "ind-var--desce" : ""}`, text: texto });
}

function numero(nomeIcone, valor, rotulo, extra, destaque) {
  return el("div", { class: destaque ? "numero numero--destaque" : "numero" },
    el("span", { class: "numero__icone" }, icone(nomeIcone)),
    el("span", {},
      el("span", { class: "numero__valor", text: valor === null || valor === undefined ? "–" : num(valor) }),
      el("span", { class: "numero__rotulo", text: rotulo }), extra));
}

/** Linha com barra: rótulo · barra · valor */
function linhaBarra(rotulo, valor, maximo, textoValor) {
  const max = Math.max(Number(maximo) || 0, Number(valor) || 0, 1);
  return el("li", { class: "ind-linha" },
    el("span", { class: "ind-linha__rotulo", text: rotulo }),
    el("progress", { class: "barra-voto ind-linha__barra", max: String(max), value: String(Number(valor) || 0), "aria-label": `${rotulo}: ${textoValor}` }),
    el("span", { class: "ind-linha__valor", text: textoValor }));
}

const secao = (tituloSecao, ...filhos) => [el("div", { class: "secao-titulo" }, el("h2", { text: tituloSecao })), ...filhos];

function notaHistorico(inicio) {
  return el("p", { class: "suave ind-nota", text: `"Primeira vez" conta a partir de ${ddmmaa(inicio)}, quando o histórico de check-in começa.` });
}

// ---------- Semana ----------

async function semana(alvo) {
  const pedido = /^\d{4}-\d{2}-\d{2}$/.test(param("dia") || "") ? param("dia") : isoHoje();
  const ini = inicioSemana(pedido);
  const r = await indicadoresSemana(ini);
  if (!alvo.isConnected) return;
  const partes = cabecalho("semana");
  const proxima = somarDias(ini, 7);
  partes.push(navegar(`${ddmm(ini)} a ${ddmm(somarDias(ini, 6))}`, `#/indicadores?aba=semana&dia=${somarDias(ini, -7)}`,
    proxima <= isoHoje() ? `#/indicadores?aba=semana&dia=${proxima}` : null));
  if (!r.ok) { montar(alvo, partes, aviso("erro", r.erro)); return; }
  const d = r.resultado;
  const a = d.atual || {}, b = d.anterior || {};
  const q = "semana anterior";

  partes.push(el("div", { class: "numeros" },
    numero("crianca", a.presencas, "Presenças", variacao(a.presencas, b.presencas, q), true),
    numero("familia", a.criancas, "Crianças diferentes", variacao(a.criancas, b.criancas, q)),
    numero("perfil", a.visitantes, "Visitantes", variacao(a.visitantes, b.visitantes, q)),
    numero("adicionar", a.primeira_vez, "Primeira vez", variacao(a.primeira_vez, b.primeira_vez, q))));
  if (a.primeira_vez === null) partes.push(notaHistorico(d.inicio_historico));

  const cultos = d.cultos || [];
  partes.push(...secao("Cultos da semana"));
  if (!cultos.length) partes.push(el("p", { class: "suave", text: "Nenhum culto nesta semana." }));
  for (const c of cultos) {
    // o nome só aparece quando não repete o dia e a hora (ex.: culto extra com nome próprio)
    const extra = c.nome && !/^(domingo|segunda|terça|quarta|quinta|sexta|sábado)\b/i.test(c.nome) ? ` · ${c.nome}` : "";
    const nome = `${diaCurto(c.data)} · ${c.hora}${extra}`;
    partes.push(el("section", { class: "cartao mt-2" },
      el("strong", { text: nome }),
      c.cancelado && !c.presencas
        ? el("p", { class: "suave sem-margem mt-1", text: "Sem salinha neste culto." })
        : [
            el("p", { class: "suave sem-margem mt-1", text: [plural(c.presencas, "criança", "crianças"),
              plural(c.visitantes, "visitante", "visitantes"),
              c.primeira_vez === null ? null : `${num(c.primeira_vez)} primeira vez`].filter(Boolean).join(" · ") }),
            el("ul", { class: "ind-lista mt-2" }, (c.salas || []).map((s) => linhaBarra(s.nome.replace(/ anos$/, ""),
              s.presencas, s.capacidade, s.capacidade ? `${s.presencas}/${s.capacidade}` : String(s.presencas)))),
          ]));
  }

  const e = d.escala || {};
  if (e.vagas) {
    partes.push(...secao("Escala da semana"), el("section", { class: "cartao" },
      el("p", { class: "sem-margem", text: `${e.preenchidas} de ${e.vagas} vagas preenchidas (${pct(e.preenchidas, e.vagas)}%)` }),
      el("p", { class: "suave sem-margem mt-1", text: [`${num(e.cientes)} cientes`, `${num(e.sem_resposta)} sem resposta`,
        `${num(e.nao_poderei)} "Não poderei"`, e.cultos_sem_lider ? `${e.cultos_sem_lider} culto(s) sem líder` : null].filter(Boolean).join(" · ") })));
  }

  partes.push(el("div", { class: "linha mt-5" }, botaoWhatsapp(textoSemana(d))));
  montar(alvo, partes);
}

function textoSemana(d) {
  const a = d.atual || {}, b = d.anterior || {};
  const cultos = (d.cultos || []).filter((c) => c.presencas).map((c) => `${diaCurto(c.data)} ${c.hora}: ${c.presencas}`);
  return [
    `*${CONFIG.nomeApp} · semana de ${ddmm(d.inicio)} a ${ddmm(d.fim)}*`,
    `👧 ${plural(a.presencas, "presença", "presenças")} em ${plural(a.cultos, "culto", "cultos")} (semana anterior: ${num(b.presencas)})`,
    `🧒 ${plural(a.criancas, "criança", "crianças")} · ${plural(a.visitantes, "visitante", "visitantes")}${a.primeira_vez ? ` · ${num(a.primeira_vez)} pela primeira vez` : ""}`,
    cultos.length ? cultos.join(" · ") : null,
    d.escala?.vagas ? `🙋 Escala: ${d.escala.preenchidas} de ${d.escala.vagas} vagas preenchidas` : null,
  ].filter(Boolean).join("\n");
}

// ---------- Mês ----------

function mesPedido() {
  const m = param("mes");
  return /^\d{4}-\d{2}$/.test(m || "") ? m : isoHoje().slice(0, 7);
}

async function mes(alvo) {
  const m = mesPedido();
  const r = await indicadoresMes(`${m}-01`);
  if (!alvo.isConnected) return;
  const partes = cabecalho("mes");
  const prox = somarMes(m, 1);
  partes.push(navegar(r.ok ? maiuscula(r.resultado.nome_mes) : m, `#/indicadores?aba=mes&mes=${somarMes(m, -1)}`,
    prox <= isoHoje().slice(0, 7) ? `#/indicadores?aba=mes&mes=${prox}` : null));
  if (!r.ok) { montar(alvo, partes, aviso("erro", r.erro)); return; }
  const d = r.resultado;
  const a = d.atual || {}, b = d.anterior || {};
  const q = "mês anterior";
  const media = a.cultos ? a.presencas / a.cultos : null;
  const mediaAnt = b.cultos ? b.presencas / b.cultos : null;

  partes.push(el("div", { class: "numeros" },
    numero("crianca", a.presencas, "Presenças", variacao(a.presencas, b.presencas, q), true),
    numero("grafico", media === null ? null : Math.round(media * 10) / 10, "Média por culto",
      media === null || mediaAnt === null ? null : variacao(Math.round(media * 10) / 10, Math.round(mediaAnt * 10) / 10, q)),
    numero("familia", a.criancas, "Crianças diferentes", variacao(a.criancas, b.criancas, q)),
    numero("perfil", a.visitantes, "Visitantes", variacao(a.visitantes, b.visitantes, q)),
    numero("adicionar", a.primeira_vez, "Primeira vez", variacao(a.primeira_vez, b.primeira_vez, q)),
    numero("inicio", a.familias_novas, "Famílias novas", variacao(a.familias_novas, b.familias_novas, q))));
  if (a.primeira_vez === null) partes.push(notaHistorico(d.inicio_historico));

  partes.push(el("div", { class: "linha mt-3" },
    el("a", { class: "botao botao--primario botao--pequeno", href: `#/indicadores?aba=mes&mes=${m}&ver=relatorio` }, icone("imprimir"), "Relatório do mês"),
    botaoWhatsapp(textoMes(d))));

  const semanas = d.semanas || [];
  if (semanas.length) {
    const max = Math.max(...semanas.map((s) => Number(s.presencas) || 0));
    partes.push(...secao("Presença por semana"),
      el("ul", { class: "ind-lista cartao" }, semanas.map((s) => linhaBarra(`Semana de ${ddmm(s.inicio)}`, s.presencas, max, num(s.presencas)))));
  }

  if ((d.por_tipo || []).length) {
    const max = Math.max(...d.por_tipo.map((t) => Number(t.maximo) || 0));
    partes.push(...secao("Média por culto"),
      el("ul", { class: "ind-lista cartao" }, d.por_tipo.map((t) => linhaBarra(t.nome, t.media, max,
        `${num(t.media)} · máx. ${num(t.maximo)} · ${plural(t.cultos, "culto", "cultos")}`))),
      el("p", { class: "suave ind-nota", text: "Só os cultos com check-in entram na média." }));
  }

  if ((d.por_sala || []).length) {
    partes.push(...secao("Por sala"),
      el("ul", { class: "ind-lista cartao" }, d.por_sala.map((s) => linhaBarra(s.nome.replace(/ anos$/, ""), s.media, s.capacidade || s.maximo,
        [`média ${num(s.media)}${s.capacidade ? ` de ${s.capacidade}` : ""}`, `máx. ${num(s.maximo)}`,
          s.lotou ? `lotou ${s.lotou}x` : null].filter(Boolean).join(" · ")))));
  }

  if (d.retorno && d.retorno.visitantes_novos) {
    const rt = d.retorno;
    partes.push(...secao("Visitantes"), el("section", { class: "cartao" },
      el("p", { class: "sem-margem", text: `${plural(rt.visitantes_novos, "visitante veio", "visitantes vieram")} pela primeira vez; ${num(rt.voltaram)} ${Number(rt.voltaram) === 1 ? "voltou" : "voltaram"} (${pct(rt.voltaram, rt.visitantes_novos)}%).` })));
  }

  const v = d.voluntarias || {};
  partes.push(...secao("Voluntárias e escala"), el("section", { class: "cartao" },
    el("p", { class: "sem-margem", text: `${plural(v.ativas, "voluntária ativa", "voluntárias ativas")} · ${num(v.escaladas)} escaladas no mês` }),
    v.escala_status === "rascunho" || !v.escala_status
      ? el("p", { class: "suave sem-margem mt-1", text: v.escala_status ? "A escala deste mês ainda está em rascunho." : "Sem escala neste mês." })
      : [
          el("p", { class: "sem-margem mt-1", text: `${v.preenchidas} de ${v.vagas} vagas preenchidas (${pct(v.preenchidas, v.vagas)}%)` }),
          el("p", { class: "suave sem-margem mt-1", text: [`${num(v.cientes)} cientes`, `${num(v.sem_resposta)} sem resposta`,
            `${num(v.nao_poderei)} "Não poderei"`, v.cultos_sem_lider ? `${v.cultos_sem_lider} culto(s) sem líder` : null].filter(Boolean).join(" · ") }),
        ]));

  const eventos = d.eventos || [];
  if (eventos.length) {
    partes.push(...secao("Eventos"), el("ul", { class: "lista-compacta" }, eventos.map((e) => el("li", {},
      el("div", { class: "item-compacto" }, el("span", { class: "item-compacto__texto" },
        el("span", { class: "item-compacto__nome", text: e.titulo }),
        el("span", { class: "item-compacto__linha", text: e.cancelado ? `${diaCurto(dataLocal(e.inicio))} · Cancelado`
          : `${diaCurto(dataLocal(e.inicio))} · ${plural(e.inscritos, "inscrito", "inscritos")} · ${num(e.presentes)} presentes · ${plural(e.ajudantes, "ajudante", "ajudantes")}` })))))));
  }

  montar(alvo, partes);
}

const dataLocal = (iso) => new Date(iso).toLocaleDateString("en-CA", { timeZone: FUSO });

function textoMes(d) {
  const a = d.atual || {}, b = d.anterior || {};
  const v = d.voluntarias || {};
  const media = a.cultos ? a.presencas / a.cultos : 0;
  const publicada = v.escala_status && v.escala_status !== "rascunho" && v.vagas;
  return [
    `*${CONFIG.nomeApp} · Relatório de ${d.nome_mes}*`,
    `👧 Presenças: ${num(a.presencas)} em ${plural(a.cultos, "culto", "cultos")} (média ${num(media)} por culto)`,
    `🧒 Crianças diferentes: ${num(a.criancas)} · visitantes: ${num(a.visitantes)}${a.primeira_vez !== null ? ` · primeira vez: ${num(a.primeira_vez)}` : ""}`,
    `🏠 Famílias novas: ${num(a.familias_novas)}`,
    (d.por_tipo || []).length ? `⛪ Média por culto: ${d.por_tipo.map((t) => `${t.nome} ${num(t.media)}`).join(" · ")}` : null,
    `🙋 Voluntárias: ${num(v.escaladas)} escaladas de ${num(v.ativas)} ativas${publicada ? ` · escala ${pct(v.preenchidas, v.vagas)}% preenchida` : ""}`,
    (d.eventos || []).filter((e) => !e.cancelado).length
      ? `🎉 Eventos: ${d.eventos.filter((e) => !e.cancelado).map((e) => `${e.titulo} (${num(e.inscritos)} inscritos, ${num(e.presentes)} presentes)`).join(" · ")}`
      : null,
    `📊 Mês anterior: ${plural(b.presencas, "presença", "presenças")}`,
  ].filter(Boolean).join("\n");
}

// ---------- Relatório do mês (para imprimir / PDF; só números) ----------

async function relatorio(alvo) {
  const m = mesPedido();
  const r = await indicadoresMes(`${m}-01`);
  if (!alvo.isConnected) return;
  const voltar = el("a", { class: "botao botao--pequeno", href: `#/indicadores?aba=mes&mes=${m}` }, icone("voltar"), "Voltar");
  if (!r.ok) { montar(alvo, el("div", { class: "linha nao-imprimir" }, voltar), aviso("erro", r.erro)); return; }
  const d = r.resultado;
  const secoes = secoesRelatorio(d);
  const titulo = `Relatório de ${d.nome_mes}`;
  const subtitulo = `${CONFIG.nomeApp} · gerado em ${ddmmaa(isoHoje())}`;

  const tabela = (cabecas, linhas) => el("table", { class: "tabela-relatorio" },
    cabecas.some(Boolean) ? el("thead", {}, el("tr", {}, cabecas.map((c, i) => el("th", { class: i ? "numero-celula" : null, scope: "col", text: c })))) : null,
    el("tbody", {}, linhas.map((l) => el("tr", {}, l.map((c, i) => i ? el("td", { class: "numero-celula", text: c }) : el("th", { scope: "row", text: c }))))));

  async function imagem() {
    try {
      const blob = await imagemDoRelatorio(titulo, subtitulo, secoes, NOTA_RELATORIO);
      janelaImagem({ titulo: "Imagem do relatório", blob, nomeArquivo: `relatorio-fonte-kids-${m}.png`, alt: `Prévia do ${titulo.toLowerCase()}` });
    } catch (e) { toast("erro", e?.message || "Não foi possível gerar a imagem."); }
  }

  // No iPhone, com o app instalado na tela inicial, o "Imprimir" do navegador não funciona:
  // lá fica só a imagem (e o "Imprimir" pelo Safari).
  const imprime = typeof window.print === "function" && navigator.standalone !== true;
  const partes = [
    el("div", { class: "linha nao-imprimir" }, voltar,
      imprime ? el("button", { class: "botao botao--primario botao--pequeno", type: "button", onclick: () => window.print() }, icone("imprimir"), "Imprimir ou salvar PDF") : null,
      el("button", { class: imprime ? "botao botao--secundario botao--pequeno" : "botao botao--primario botao--pequeno", type: "button", onclick: imagem }, icone("imagem"), "Imagem do relatório"),
      botaoWhatsapp(textoMes(d))),
    el("p", { class: "suave nao-imprimir mt-2", text: imprime
      ? "Só números, sem nomes nem dados de crianças: pode mandar ao pastor ou no grupo."
      : "Só números, sem nomes nem dados de crianças. No app instalado no iPhone não dá para imprimir: use a imagem ou abra o app no Safari (Compartilhar → Imprimir)." }),
    el("header", { class: "relatorio__topo" },
      el("img", { class: "relatorio__logo", src: "img/logo.png", alt: "" }),
      el("div", {},
        el("h1", { class: "sem-margem", text: titulo }),
        el("p", { class: "suave sem-margem", text: subtitulo }))),
  ];
  for (const sc of secoes) {
    partes.push(el("h2", { text: sc.titulo }));
    if (sc.texto) partes.push(el("p", { text: sc.texto }));
    if (sc.linhas?.length) partes.push(tabela(sc.cabecas, sc.linhas));
    if (sc.nota) partes.push(sc.nota);
  }
  partes.push(el("p", { class: "suave ind-nota mt-5", text: NOTA_RELATORIO }));
  montar(alvo, el("article", { class: "relatorio" }, partes));
}

const NOTA_RELATORIO = "Presenças contam cada check-in; \"crianças diferentes\" conta cada criança uma vez no mês. Visitante e membro seguem o perfil da ficha.";

/** Seções do relatório (só números), usadas na página e na imagem. */
function secoesRelatorio(d) {
  const a = d.atual || {}, b = d.anterior || {}, v = d.voluntarias || {};
  const media = (x) => (x.cultos ? num(x.presencas / x.cultos) : "–");
  const publicada = v.escala_status && v.escala_status !== "rascunho";
  const secoes = [{
    titulo: "Presença",
    cabecas: ["", maiuscula(d.nome_mes), "Mês anterior"],
    linhas: [
      ["Presenças (check-ins)", num(a.presencas), num(b.presencas)],
      ["Cultos com check-in", num(a.cultos), num(b.cultos)],
      ["Média por culto", media(a), media(b)],
      ["Crianças diferentes", num(a.criancas), num(b.criancas)],
      ["Membros", num(a.membros), num(b.membros)],
      ["Visitantes", num(a.visitantes), num(b.visitantes)],
      ["Primeira vez", a.primeira_vez === null ? "–" : num(a.primeira_vez), b.primeira_vez === null ? "–" : num(b.primeira_vez)],
      ["Famílias novas", num(a.familias_novas), num(b.familias_novas)],
    ],
    nota: a.primeira_vez === null ? notaHistorico(d.inicio_historico) : null,
  }];
  if ((d.por_tipo || []).length) {
    secoes.push({ titulo: "Por culto", cabecas: ["Culto", "Cultos", "Média", "Máximo"],
      linhas: d.por_tipo.map((t) => [t.nome, num(t.cultos), num(t.media), num(t.maximo)]) });
  }
  if ((d.por_sala || []).length) {
    secoes.push({ titulo: "Por sala", cabecas: ["Sala", "Capacidade", "Média", "Máximo", "Lotou"],
      linhas: d.por_sala.map((s) => [s.nome, s.capacidade ? num(s.capacidade) : "–", num(s.media), num(s.maximo), s.lotou ? `${s.lotou}x` : "–"]) });
  }
  if (d.retorno && d.retorno.visitantes_novos) {
    secoes.push({ titulo: "Visitantes", cabecas: [], linhas: [],
      texto: `${plural(d.retorno.visitantes_novos, "visitante veio", "visitantes vieram")} pela primeira vez; ${num(d.retorno.voltaram)} ${Number(d.retorno.voltaram) === 1 ? "voltou" : "voltaram"} (${pct(d.retorno.voltaram, d.retorno.visitantes_novos)}%).` });
  }
  secoes.push({ titulo: "Voluntárias e escala", cabecas: ["", ""], linhas: [
    ["Voluntárias ativas", num(v.ativas)],
    ["Escaladas no mês", num(v.escaladas)],
    ...(publicada ? [
      ["Vagas preenchidas", `${num(v.preenchidas)} de ${num(v.vagas)} (${pct(v.preenchidas, v.vagas)}%)`],
      ["Cientes", num(v.cientes)],
      ["Sem resposta", num(v.sem_resposta)],
      ["\"Não poderei\"", num(v.nao_poderei)],
      ["Cultos sem líder do culto", num(v.cultos_sem_lider)],
    ] : [["Escala do mês", v.escala_status ? "em rascunho" : "sem escala"]]),
  ] });
  const eventos = d.eventos || [];
  if (eventos.length) {
    secoes.push({ titulo: "Eventos", cabecas: ["Evento", "Data", "Inscritos", "Presentes", "Ajudantes"],
      linhas: eventos.map((e) => [e.cancelado ? `${e.titulo} (cancelado)` : e.titulo, ddmm(dataLocal(e.inicio)), num(e.inscritos), num(e.presentes), num(e.ajudantes)]) });
  }
  return secoes;
}

// ---------- Cuidado (com nomes; só no app) ----------

function zap(telefone, texto, nome) {
  const d = String(telefone || "").replace(/\D/g, "");
  if (!/^55[1-9][0-9]9?[0-9]{8}$/.test(d)) return null;
  return el("a", { class: "botao-icone botao-icone--whatsapp", href: `https://wa.me/${d}?text=${encodeURIComponent(texto)}`,
    target: "_blank", rel: "noopener noreferrer", "aria-label": `Chamar ${nome || "contato"} no WhatsApp` }, icone("conversa"));
}

async function cuidado(alvo) {
  const [falta, sem] = await Promise.all([sentimosFalta(), voluntariasSemEscala()]);
  if (!alvo.isConnected) return;
  const partes = cabecalho("cuidado");
  partes.push(aviso("info", "Esta aba mostra nomes: é só para a liderança cuidar das famílias e da equipe. Não tire print nem compartilhe a lista."));

  partes.push(...secao("Sentimos falta"),
    el("p", { class: "suave ind-nota", text: "Crianças que vinham (3 vezes ou mais nos últimos 3 meses) e não aparecem há 4 semanas." }));
  if (!falta.ok) partes.push(aviso("erro", falta.erro));
  else if (!(falta.resultado || []).length) partes.push(el("p", { class: "suave", text: "Ninguém nesta lista agora." }));
  else {
    partes.push(el("ul", { class: "lista-compacta" }, falta.resultado.map((c) => {
      const resp = (c.responsaveis || []).find((x) => zap(x.telefone, "", x.nome)) || null;
      const texto = resp ? `Oi, ${primeiroNome(resp.nome)}! Aqui é do ${CONFIG.nomeApp}. Sentimos falta de ${primeiroNome(c.nome)} nos últimos cultos. Está tudo bem com vocês? Estamos com saudade!` : "";
      return el("li", {}, el("div", { class: "item-compacto" },
        el("span", { class: "item-compacto__texto" },
          el("a", { class: "item-compacto__nome", href: `#/ficha?tipo=crianca&id=${encodeURIComponent(c.crianca_id)}`, text: c.nome }),
          el("span", { class: "item-compacto__linha", text: [c.idade !== null && c.idade !== undefined ? `${c.idade} ${c.idade === 1 ? "ano" : "anos"}` : null,
            c.perfil === "visitante" ? "Visitante" : null, `última vez ${ddmm(c.ultima_vez)}`, `${c.vezes} vezes em 3 meses`,
            resp ? `responsável: ${primeiroNome(resp.nome)}` : "sem WhatsApp"].filter(Boolean).join(" · ") })),
        resp ? zap(resp.telefone, texto, resp.nome) : null));
    })));
  }

  partes.push(...secao("Voluntárias sem escala há 2 meses"),
    el("p", { class: "suave ind-nota", text: "Ativas que não aparecem em nenhuma escala publicada nos últimos 2 meses nem nas próximas." }));
  if (!sem.ok) partes.push(aviso("erro", sem.erro));
  else if (!(sem.resultado || []).length) partes.push(el("p", { class: "suave", text: "Todas as voluntárias ativas estão na escala." }));
  else {
    partes.push(el("ul", { class: "lista-compacta" }, sem.resultado.map((v) => {
      const texto = `Oi, ${primeiroNome(v.nome)}! Tudo bem? Faz um tempinho que você não aparece na escala do ${CONFIG.nomeApp}. Quer servir no próximo mês?`;
      return el("li", {}, el("div", { class: "item-compacto" },
        el("span", { class: "item-compacto__texto" },
          el("span", { class: "item-compacto__nome", text: v.nome }),
          el("span", { class: "item-compacto__linha", text: [FUNCOES[v.funcao] || null,
            v.ultima_vez ? `última escala ${ddmmaa(v.ultima_vez)}` : `nunca escalada · desde ${ddmmaa(v.desde)}`].filter(Boolean).join(" · ") })),
        zap(v.telefone, texto, v.nome)));
    })));
  }
  montar(alvo, partes);
}
