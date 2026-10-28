// =====================================================================
// Tela: Check-in – Entrada (Fase 5 · 5B) e Presentes (Fase 5 · 5C)
// Para a recepção (todas as voluntárias), liderança, pastores e admin.
//   1) Culto de hoje (escolhido sozinho: o mais próximo do horário; dá para trocar)
//   2) Busca por criança, responsável ou 4 últimos números do telefone
//   3) Cartão da família: crianças marcáveis, sala do dia (salas juntas
//      respeitadas), alergia em vermelho, 🎂, pendências com "Resolver",
//      criança sem sala → "Corrigir dados" na hora
//   4) "Fazer check-in (N)" → tela com o código de cada criança
// Sem "quem trouxe" (decisão 75). Sem check-out aqui (decisão 80).
// Tudo grava pelas funções do banco (fazer_checkin, desfazer_checkin…).
// Presentes (5C): crianças por sala em tempo real, com código, 🎂, alergia,
// "Chamar responsável" (aparece no telão), "Saiu" opcional e ⋯ Desfazer.
// Os check-ins abertos fecham sozinhos 3 h depois do início do culto.
// Endereço: #/checkin (Entrada) ou #/checkin?aba=presentes
// =====================================================================
import { el, montar, aviso, carregando, toast, menuAcoes } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela, campo } from "../janela.js";
import { avatarLista, preencherFotos } from "../foto.js";
import { meuPerfil, cultosDeHoje, buscarParaCheckin, fazerCheckin, desfazerCheckin,
  editarCrianca, nascimentoDe, confirmarPendencia, nomePendencia,
  presentesDoCulto, marcarSaida, desfazerSaida, chamarResponsavel, cancelarChamada, ouvirCulto } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Check-in";

const MOTIVOS = {
  sem_data: "Sem data de nascimento",
  data_invalida: "Data de nascimento inválida",
  acima_idade: "Acima de 12 anos",
  sem_faixa: "Nenhuma sala para a idade",
  sala_fechada: "Sala fechada hoje",
};

let cultoEscolhido = null; // só na memória da aba
let termoAtual = "";
let alvoTela = null;
let cultos = [];
let lideranca = false;
let abaInterna = "entrada";   // "entrada" | "presentes"
let filtroSala = null;        // Presentes: sala escolhida nos chips (null = todas)
let linhaResumo = null;       // texto "N crianças com check-in" do cabeçalho
let desligarTempoReal = null;
let relogio = null;
let esperaPresentes = null;

const hojeIso = () => new Date().toLocaleDateString("en-CA", { timeZone: "America/Sao_Paulo" });
const cultoAtual = () => cultos.find((c) => c.id === cultoEscolhido) || cultos[0];
const salaCurta = (nome) => (nome ? nome.replace(/ anos$/, "") : "");
const hora = (iso) => new Date(iso).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit", timeZone: "America/Sao_Paulo" });
const textoPresentes = (n) => `${n} ${n === 1 ? "criança" : "crianças"} com check-in`;

// Sair da tela (ou trocar de aba) desliga o tempo real e o relógio
function pararPresentes() {
  if (desligarTempoReal) desligarTempoReal();
  desligarTempoReal = null;
  clearInterval(relogio); relogio = null;
  clearTimeout(esperaPresentes); esperaPresentes = null;
}
window.addEventListener("hashchange", pararPresentes);

function redesenhar() {
  if (abaInterna === "presentes") desenharPresentes(); else desenharBusca();
}

export async function render(alvo) {
  alvoTela = alvo;
  pararPresentes();
  abaInterna = new URLSearchParams(location.hash.split("?")[1] || "").get("aba") === "presentes" ? "presentes" : "entrada";
  montar(alvo, carregando());
  const [r, perfil] = await Promise.all([cultosDeHoje(), meuPerfil()]);
  lideranca = !!(perfil.ok && perfil.temPapel("admin", "pastor", "lider"));

  if (!r.ok) {
    montar(alvo, el("h1", { text: "Check-in" }), aviso("erro", r.erro));
    return;
  }
  cultos = r.lista;
  if (!cultos.length) {
    montar(alvo, el("h1", { text: "Check-in" }),
      aviso("info", "Hoje não tem culto com sala do Fonte Kids."),
      lideranca ? el("p", { class: "mt-3" }, el("a", { class: "botao botao--secundario", href: "#/cultos", text: "Cultos e salas" })) : null);
    return;
  }
  if (!cultos.some((c) => c.id === cultoEscolhido)) cultoEscolhido = (cultos.find((c) => c.sugerido) || cultos[0]).id;
  redesenhar();
}

// ---------- Cabeçalho: culto do dia e salas ----------

function cabecalho() {
  const c = cultoAtual();
  const chips = cultos.length > 1
    ? el("div", { class: "chips mt-2", role: "group", "aria-label": "Culto" }, cultos.map((x) => el("button", {
        class: "chip", type: "button", "aria-pressed": x.id === c.id ? "true" : "false",
        text: `${x.horario} · ${x.nome}`,
        onclick: () => { cultoEscolhido = x.id; termoAtual = ""; filtroSala = null; redesenhar(); },
      })))
    : null;
  const salas = (c.salas || []).map((s) => el("span", {
    class: s.cancelada ? "etiqueta etiqueta--neutra" : "etiqueta etiqueta--azul",
    text: s.cancelada ? `${salaCurta(s.nome)} fechada` : salaCurta(s.nome),
  }));
  linhaResumo = el("span", { text: textoPresentes(c.presentes) });
  return [
    el("div", { class: "saudacao" },
      el("h1", { text: "Check-in" }),
      el("p", { class: "suave" }, `${c.nome} · ${c.horario} · `, linhaResumo)),
    chips,
    salas.length ? el("div", { class: "linha mt-2", "aria-label": "Salas de hoje" }, salas) : null,
    abasInternas(),
  ];
}

// Abas internas: Entrada · Presentes
function abasInternas() {
  const abas = [{ id: "entrada", texto: "Entrada" }, { id: "presentes", texto: "Presentes" }];
  return el("div", { class: "abas", role: "tablist", "aria-label": "Check-in" }, abas.map((a) => el("button", {
    class: "aba", type: "button", role: "tab", "aria-selected": a.id === abaInterna ? "true" : "false",
    text: a.texto,
    onclick: () => {
      if (a.id === abaInterna) return;
      abaInterna = a.id;
      history.replaceState(null, "", a.id === "presentes" ? "#/checkin?aba=presentes" : "#/checkin");
      redesenhar();
    },
  })));
}

// ---------- Busca ----------

function desenharBusca() {
  pararPresentes();
  abaInterna = "entrada";
  const resultados = el("div", { class: "resultados-checkin", "aria-live": "polite" });
  const entrada = el("input", { type: "search", id: "busca-checkin", autocomplete: "off", inputmode: "search",
    placeholder: "Criança, responsável ou final do telefone", value: termoAtual });
  let espera;
  let pedido = 0;

  async function buscar() {
    const termo = entrada.value.trim();
    termoAtual = termo;
    const so4 = /^\d{4}$/.test(termo.replace(/\D/g, "")) && !/[a-zA-ZÀ-ú]/.test(termo);
    if (!so4 && termo.replace(/[^a-zA-ZÀ-ú]/g, "").length < 2) {
      montar(resultados, el("p", { class: "suave mt-3", text: "Digite ao menos 2 letras do nome ou os 4 últimos números do telefone." }));
      return;
    }
    const meu = ++pedido;
    montar(resultados, carregando("Buscando…"));
    const r = await buscarParaCheckin(cultoAtual().id, termo);
    if (meu !== pedido) return; // chegou resposta de uma busca antiga
    if (!r.ok) { montar(resultados, aviso("erro", r.erro)); return; }
    if (!r.lista.length) {
      montar(resultados, aviso("info", "Nenhuma família encontrada. Confira o nome ou tente pelo responsável."));
      return;
    }
    montar(resultados, r.lista.map((f) => cartaoFamilia(f, buscar)));
    preencherFotos(resultados);
  }

  entrada.addEventListener("input", () => { clearTimeout(espera); espera = setTimeout(buscar, 400); });
  entrada.addEventListener("keydown", (e) => { if (e.key === "Enter") { e.preventDefault(); clearTimeout(espera); buscar(); } });

  montar(alvoTela, ...cabecalho(),
    el("div", { class: "busca" },
      el("label", { class: "busca__campo" }, icone("busca"),
        el("span", { class: "so-leitor", text: "Buscar criança, responsável ou final do telefone" }), entrada)),
    resultados);

  if (termoAtual) buscar();
  else montar(resultados, el("p", { class: "suave mt-3", text: "Busque pela criança, pelo responsável ou pelos 4 últimos números do telefone." }));
  entrada.focus();
}

// ---------- Cartão da família ----------

function cartaoFamilia(f, refazer) {
  const principal = f.responsaveis.find((r) => r.principal) || f.responsaveis[0];
  const outros = f.responsaveis.filter((r) => r !== principal).map((r) => r.nome);
  const marcadas = new Set();
  const botao = el("button", { class: "botao botao--primario botao--largo mt-3", type: "button" });

  function atualizarBotao() {
    botao.disabled = marcadas.size === 0;
    botao.textContent = marcadas.size ? `Fazer check-in (${marcadas.size})` : "Fazer check-in";
  }

  const itens = f.criancas.map((c) => linhaCrianca(c, marcadas, atualizarBotao, refazer));
  const aptas = f.criancas.filter((c) => !c.checkin && c.sala_id);
  atualizarBotao();

  botao.addEventListener("click", async () => {
    if (!marcadas.size) return;
    botao.disabled = true;
    botao.textContent = "Fazendo check-in…";
    const r = await fazerCheckin(cultoAtual().id, [...marcadas]);
    if (!r.ok) { toast("erro", r.erro, 6000); atualizarBotao(); return; }
    mostrarCodigos(r.lista);
  });

  return el("section", { class: "cartao cartao--familia-checkin" },
    el("div", { class: "familia-checkin__topo" },
      el("strong", { class: "familia-checkin__nome", text: principal ? `Família de ${principal.nome}` : "Família" }),
      outros.length ? el("span", { class: "suave", text: outros.join(" · ") }) : null),
    f.pendencias.length ? blocoPendencias(f, refazer) : null,
    el("ul", { class: "lista-checkin" }, itens),
    aptas.length ? botao : el("p", { class: "suave mt-3 sem-margem", text: "Nenhuma criança para check-in nesta família agora." }));
}

function linhaCrianca(c, marcadas, aoMudar, refazer) {
  const etiquetas = [];
  if (c.aniversario) etiquetas.push(el("span", { class: "etiqueta etiqueta--laranja", text: "🎂 Aniversário" }));
  if (c.checkin) {
    etiquetas.push(el("span", { class: "etiqueta etiqueta--sucesso" }, icone("check"),
      `Check-in feito · ${salaCurta(c.checkin.sala_nome)}`));
  } else if (c.sala_id) {
    etiquetas.push(el("span", { class: "etiqueta etiqueta--azul", text: `Sala ${salaCurta(c.sala_nome)}` }));
  } else {
    etiquetas.push(el("span", { class: "etiqueta", text: `Sem sala: ${MOTIVOS[c.sem_sala] || "conferir"}` }));
  }

  const texto = el("span", { class: "item-compacto__texto" },
    el("span", { class: "item-compacto__nome", text: c.nome }),
    el("span", { class: "linha mt-1" }, etiquetas));

  const alergia = c.alergias
    ? el("div", { class: "checkin-alergia" }, icone("alergia"), el("span", {}, el("strong", { text: "Alergia/cuidados: " }), c.alergias))
    : null;

  // Já tem check-in: mostra o código e o menu ⋯ (desfazer)
  if (c.checkin) {
    return el("li", { class: "checkin-crianca" },
      el("div", { class: "checkin-crianca__linha" },
        avatarLista("crianca", c.id, c.nome), texto,
        el("span", { class: "codigo-mini", "aria-label": `Código ${c.checkin.codigo}`, text: c.checkin.codigo }),
        menuAcoes([{ texto: "Desfazer check-in", perigo: true, acao: () => janelaDesfazer(c.checkin.id, c.nome, refazer) }],
          `Mais ações para ${c.nome}`)),
      alergia);
  }

  // Sem sala: corrigir os dados na hora (decisão 76)
  if (!c.sala_id) {
    const podeCorrigir = c.sem_sala !== "sala_fechada" && c.sem_sala !== "acima_idade";
    return el("li", { class: "checkin-crianca" },
      el("div", { class: "checkin-crianca__linha" },
        avatarLista("crianca", c.id, c.nome), texto,
        podeCorrigir ? el("button", { class: "botao botao--secundario botao--pequeno", type: "button", text: "Corrigir dados",
          onclick: () => janelaCorrigir(c, refazer) }) : null),
      c.sem_sala === "sala_fechada" ? el("p", { class: "suave sem-margem mt-1", text: "A sala desta idade está fechada neste culto. Fale com a liderança." }) : null,
      c.sem_sala === "acima_idade" ? el("p", { class: "suave sem-margem mt-1", text: "Acima da idade das salas. Fale com a liderança se precisar de uma exceção." }) : null,
      alergia);
  }

  // Apta: caixa de marcar (já vem marcada)
  const caixa = el("input", { type: "checkbox", class: "checkin-crianca__caixa", checked: true });
  marcadas.add(c.id);
  caixa.addEventListener("change", () => { if (caixa.checked) marcadas.add(c.id); else marcadas.delete(c.id); aoMudar(); });
  return el("li", { class: "checkin-crianca" },
    el("label", { class: "checkin-crianca__linha checkin-crianca__linha--marcavel" },
      caixa, avatarLista("crianca", c.id, c.nome), texto,
      el("button", { class: "botao-icone", type: "button", "aria-label": `Corrigir dados de ${c.nome}`,
        onclick: (e) => { e.preventDefault(); janelaCorrigir(c, refazer); } }, icone("editar"))),
    alergia);
}

function blocoPendencias(f, refazer) {
  return el("div", { class: "checkin-pendencias" },
    el("strong", { class: "linha" }, icone("pendencias"), `Para completar (${f.pendencias.length})`),
    el("ul", { class: "lista-pendencias" }, f.pendencias.map((p) => {
      const crianca = f.criancas.find((c) => c.id === p.crianca_id);
      const acao = p.automatica
        ? (crianca ? el("button", { class: "botao botao--secundario botao--pequeno", type: "button", text: "Corrigir dados",
            onclick: () => janelaCorrigir(crianca, refazer) }) : null)
        : el("button", { class: "botao botao--secundario botao--pequeno", type: "button", text: "Resolver",
            onclick: async (e) => {
              e.currentTarget.disabled = true;
              const r = await confirmarPendencia(p.id);
              if (!r.ok) { toast("erro", r.erro); e.currentTarget.disabled = false; return; }
              toast("sucesso", "Pendência resolvida.");
              refazer();
            } });
      return el("li", { class: "pendencia" },
        el("div", { class: "pendencia__linha" },
          el("div", { class: "flex-1" },
            el("strong", { text: nomePendencia(p.tipo) }),
            p.mensagem ? el("p", { class: "notif__corpo", text: p.mensagem }) : null),
          acao));
    })));
}

// ---------- Presentes (5C) ----------

async function desenharPresentes() {
  pararPresentes();
  abaInterna = "presentes";
  const c = cultoAtual();
  const area = el("div", { class: "presentes", "aria-live": "polite" });
  montar(alvoTela, ...cabecalho(), area);
  montar(area, carregando());
  await carregarPresentes(area, c.id);
  if (!area.isConnected) return;
  // tempo real: qualquer check-in, saída ou chamada deste culto atualiza a lista
  desligarTempoReal = ouvirCulto(c.id, () => {
    clearTimeout(esperaPresentes);
    esperaPresentes = setTimeout(() => carregarPresentes(area, c.id), 500);
  });
  // a cada minuto: garante a lista certa mesmo se a conexão em tempo real cair
  relogio = setInterval(() => carregarPresentes(area, c.id), 60000);
}

async function carregarPresentes(area, cultoId) {
  if (!area.isConnected) { pararPresentes(); return; }
  const r = await presentesDoCulto(cultoId);
  if (!area.isConnected) return;
  if (!r.ok) {
    if (!area.querySelector(".presentes__sala")) montar(area, aviso("erro", r.erro));
    else toast("erro", r.erro);
    return;
  }
  desenharListaPresentes(area, r.dados, cultoId);
}

function desenharListaPresentes(area, d, cultoId) {
  const todas = d.salas || [];
  const abertos = todas.reduce((n, s) => n + s.criancas.filter((k) => !k.saiu).length, 0);
  const total = todas.reduce((n, s) => n + s.criancas.length, 0);
  const c = cultoAtual();
  if (c) c.presentes = abertos;
  if (linhaResumo) linhaResumo.textContent = textoPresentes(abertos);

  const encerrado = !!d.culto?.encerrado;
  const salas = todas.filter((s) => s.criancas.length || !s.cancelada);
  if (filtroSala && !salas.some((s) => s.sala_id === filtroSala)) filtroSala = null;
  const recarregar = () => carregarPresentes(area, cultoId);

  if (!total) {
    montar(area,
      aviso("info", encerrado ? "Este culto já terminou e não teve check-in." : "Ainda não há check-in neste culto."),
      encerrado ? null : el("button", { class: "botao botao--primario botao--largo mt-3", type: "button", text: "Fazer check-in",
        onclick: () => { history.replaceState(null, "", "#/checkin"); desenharBusca(); } }));
    return;
  }

  const contar = (s) => s.criancas.filter((k) => !k.saiu).length;
  const chips = salas.length > 1
    ? el("div", { class: "chips mt-3", role: "group", "aria-label": "Filtrar por sala" },
        [{ sala_id: null, nome: "Todas", n: abertos }, ...salas.map((s) => ({ sala_id: s.sala_id, nome: salaCurta(s.nome), n: contar(s) }))]
          .map((x) => el("button", { class: "chip", type: "button", "aria-pressed": x.sala_id === filtroSala ? "true" : "false",
            text: `${x.nome} (${x.n})`,
            onclick: () => { filtroSala = x.sala_id; recarregar(); } })))
    : null;

  const visiveis = salas.filter((s) => !filtroSala || s.sala_id === filtroSala);
  montar(area,
    encerrado ? aviso("info", "Este culto já terminou: os check-ins foram fechados sozinhos.") : null,
    chips,
    visiveis.map((s) => {
      const n = contar(s);
      const sairam = s.criancas.length - n;
      return el("section", { class: "cartao presentes__sala mt-3" },
        el("div", { class: "presentes__topo" },
          el("h2", { class: "presentes__titulo", text: `Sala ${salaCurta(s.nome)}` }),
          el("span", { class: "etiqueta etiqueta--azul", text: `${n} ${n === 1 ? "presente" : "presentes"}` }),
          sairam ? el("span", { class: "etiqueta etiqueta--neutra", text: `${sairam} ${sairam === 1 ? "saiu" : "saíram"}` }) : null),
        s.criancas.length
          ? el("ul", { class: "lista-checkin" }, s.criancas.map((k) => linhaPresente(k, encerrado, recarregar)))
          : el("p", { class: "suave sem-margem mt-2", text: "Nenhuma criança com check-in nesta sala." }));
    }));
  preencherFotos(area);
}

function linhaPresente(k, encerrado, recarregar) {
  const ch = k.chamada;
  const chamando = ch && ch.situacao === "aguardando";
  const etiquetas = [];
  if (k.aniversario) etiquetas.push(el("span", { class: "etiqueta etiqueta--laranja", text: "🎂 Aniversário" }));
  if (chamando) etiquetas.push(el("span", { class: "etiqueta", text: `Chamando no telão · ${hora(ch.chamada_em)}` }));
  else if (ch && ch.situacao === "anunciada") etiquetas.push(el("span", { class: "etiqueta etiqueta--azul" }, icone("check"), `Anunciado · ${hora(ch.anunciada_em)}`));
  if (k.saiu) etiquetas.push(el("span", { class: "etiqueta etiqueta--neutra",
    text: k.saida_automatica ? "Saída automática" : `Saiu · ${hora(k.saida_em)}` }));

  const ativo = !k.saiu && !encerrado;
  async function acao(botao, fn, ok) {
    if (botao) botao.disabled = true;
    const r = await fn();
    if (!r.ok) { toast("erro", r.erro, 6000); if (botao) botao.disabled = false; return; }
    if (ok) toast("sucesso", ok);
    recarregar();
  }

  const menu = menuAcoes([
    chamando ? { texto: "Cancelar chamada", acao: () => acao(null, () => cancelarChamada(ch.id), "Chamada cancelada.") } : null,
    k.saiu && !k.saida_automatica && !encerrado ? { texto: "Desfazer saída", acao: () => acao(null, () => desfazerSaida(k.checkin_id), "Saída desfeita.") } : null,
    k.pode_desfazer && !encerrado ? { texto: "Desfazer check-in", perigo: true, acao: () => janelaDesfazer(k.checkin_id, k.nome, recarregar) } : null,
  ], `Mais ações para ${k.nome}`);

  let botoes = null;
  if (ativo) {
    const chamar = chamando ? null : el("button", { class: "botao botao--secundario botao--pequeno", type: "button" },
      icone("avisos"), ch && ch.situacao === "anunciada" ? "Chamar de novo" : "Chamar responsável");
    if (chamar) chamar.addEventListener("click", () => acao(chamar, () => chamarResponsavel(k.checkin_id), "Responsável chamado no telão."));
    const saiu = el("button", { class: "botao botao--secundario botao--pequeno", type: "button" }, icone("checkin"), "Saiu");
    saiu.addEventListener("click", () => acao(saiu, () => marcarSaida(k.checkin_id), `Saída de ${k.nome} registrada.`));
    botoes = el("div", { class: "linha mt-2 presentes__acoes" }, chamar, saiu);
  }

  return el("li", { class: k.saiu ? "checkin-crianca checkin-crianca--saiu" : "checkin-crianca" },
    el("div", { class: "checkin-crianca__linha" },
      avatarLista("crianca", k.crianca_id, k.nome),
      el("span", { class: "item-compacto__texto" },
        el("span", { class: "item-compacto__nome", text: k.nome }),
        etiquetas.length ? el("span", { class: "linha mt-1" }, etiquetas) : null),
      el("span", { class: "codigo-mini", "aria-label": `Código ${k.codigo.split("").join(" ")}`, text: k.codigo }),
      menu),
    botoes,
    k.alergias && !k.saiu
      ? el("div", { class: "checkin-alergia" }, icone("alergia"), el("span", {}, el("strong", { text: "Alergia/cuidados: " }), k.alergias))
      : null);
}

// ---------- Janelinhas ----------

async function janelaCorrigir(c, refazer) {
  const nascAtual = await nascimentoDe(c.pessoa_id);
  const nome = el("input", { class: "entrada", type: "text", maxlength: "120", autocomplete: "off", value: c.nome || "" });
  const nasc = el("input", { class: "entrada", type: "date", max: hojeIso(), value: nascAtual || "" });
  const alerg = el("textarea", { class: "entrada", maxlength: "500" });
  alerg.value = c.alergias || "";
  abrirJanela({
    titulo: "Dados da criança",
    conteudo: [
      aviso("info", "Confirme com o responsável antes de salvar."),
      campo("Nome completo", nome),
      campo("Data de nascimento", nasc, "A sala é escolhida pela idade."),
      campo("Alergias e cuidados", alerg, "Deixe em branco se não houver."),
    ],
    sucesso: "Dados salvos.",
    aoSalvar: async () => {
      if (nome.value.trim().length < 3) { nome.focus(); return "Informe o nome completo."; }
      if (!nasc.value) { nasc.focus(); return "Informe a data de nascimento."; }
      const r = await editarCrianca(c.id, nome.value, nasc.value, alerg.value);
      if (!r.ok) return r.erro;
      refazer();
      return null;
    },
  });
}

function janelaDesfazer(checkinId, nome, depois) {
  abrirJanela({
    titulo: "Desfazer check-in",
    conteudo: [el("p", { text: `Desfazer o check-in de ${nome}? Use só se foi feito por engano.` }),
      lideranca ? null : el("p", { class: "suave", text: "Depois de 30 minutos, só a liderança pode desfazer." })],
    textoSalvar: "Desfazer",
    perigo: true,
    sucesso: "Check-in desfeito.",
    aoSalvar: async () => {
      const r = await desfazerCheckin(checkinId);
      if (!r.ok) return r.erro;
      const c = cultoAtual();
      if (c && c.presentes > 0) c.presentes -= 1;
      depois();
      return null;
    },
  });
}

// ---------- Códigos depois do check-in ----------

function mostrarCodigos(lista) {
  const c = cultoAtual();
  c.presentes += lista.filter((x) => !x.ja_tinha).length;
  const restantes = [...lista];

  pararPresentes();
  function desenhar() {
    montar(alvoTela,
      el("div", { class: "saudacao" },
        el("h1", { text: "Check-in feito" }),
        el("p", { class: "suave", text: `${c.nome} · ${c.horario}` })),
      aviso("info", "Cada criança tem o seu código. Na hora de buscar, o responsável mostra o código na porta da sala."),
      restantes.length
        ? el("ul", { class: "lista-codigos" }, restantes.map((x) => el("li", { class: "cartao cartao--codigo" },
            el("div", { class: "flex-1" },
              el("strong", { class: "cartao-codigo__nome", text: x.nome }),
              el("span", { class: "etiqueta etiqueta--azul mt-1", text: `Sala ${salaCurta(x.sala_nome)}` }),
              x.ja_tinha ? el("p", { class: "suave sem-margem mt-1", text: "Já estava com check-in neste culto." }) : null),
            el("span", { class: "codigo-grande", "aria-label": `Código ${x.codigo.split("").join(" ")}`, text: x.codigo }),
            menuAcoes([{ texto: "Desfazer check-in", perigo: true,
              acao: () => janelaDesfazer(x.checkin_id, x.nome, () => {
                restantes.splice(restantes.indexOf(x), 1);
                desenhar();
              }) }], `Mais ações para ${x.nome}`))))
        : aviso("info", "Nenhum check-in nesta lista."),
      el("button", { class: "botao botao--primario botao--largo mt-5", type: "button", text: "Novo check-in",
        onclick: () => { termoAtual = ""; desenharBusca(); } }),
      el("button", { class: "botao botao--secundario botao--largo mt-3", type: "button", text: "Ver presentes",
        onclick: () => { abaInterna = "presentes"; history.replaceState(null, "", "#/checkin?aba=presentes"); desenharPresentes(); } }));
  }
  desenhar();
  window.scrollTo(0, 0);
}
