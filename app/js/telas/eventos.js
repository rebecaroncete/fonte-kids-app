// =====================================================================
// Tela: Eventos (Fase 8)   #/eventos   #/eventos?id=…   #/eventos?id=…&ver=inscritos
// Todos com login veem os eventos publicados do Fonte Kids (cartão no
// Início; Mais → "Eventos").
//   • Responsável: inscreve as próprias crianças (dentro da idade, do prazo
//     e das vagas), marca "Autorizo a participação" quando o evento pede,
//     tira a inscrição até o prazo e convida outra família pelo WhatsApp.
//   • Voluntária ativa: "Quero ajudar" quando o evento pede ajuda.
//   • Liderança: "Novo evento" (fica em rascunho), Publicar (aviso + push
//     para o público escolhido), Editar, Avisar inscritos, Cancelar (avisa
//     os inscritos), Apagar (sem inscrições), "Mandar no grupo" e a lista
//     de inscritos (alergias, autorização, WhatsApp do responsável,
//     "Presente", inscrever/tirar qualquer criança, quem vai ajudar).
// O banco confere tudo; nenhuma tela grava direto nas tabelas.
// =====================================================================
import { el, montar, aviso, carregando, toast, menuAcoes, mascararTelefone } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela, campo } from "../janela.js";
import {
  meuPerfil, eventosLista, salvarEvento, publicarEvento, cancelarEvento, apagarEvento, avisarInscritos,
  inscreverCrianca, cancelarInscricao, marcarPresencaEvento, ajudarEvento, eventoInscritos, listarCriancas,
  enderecoApp, enderecoCadastroFamilia,
} from "../supabase.js";
import { botaoWhatsapp } from "./notificacoes.js";
import { normalizar, idade, textoIdade } from "./cadastros.js";

export const layout = "padrao";
export const titulo = "Eventos";

const FUSO = "America/Sao_Paulo";
const LIDERANCA = ["admin", "pastor", "lider"];
const PUBLICOS = [
  ["responsaveis", "Só responsáveis"],
  ["todos", "Todos (equipe e responsáveis)"],
  ["equipe", "Equipe (voluntárias, recepção e líderes)"],
  ["lideres", "Só líderes (bom para testar)"],
];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

let alvoTela = null;
let lider = false;

function parametro(nome) {
  return new URLSearchParams(location.hash.split("?")[1] || "").get(nome);
}

// ---------- datas (horário de Brasília) ----------
const isoHoje = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO });
const diaIso = (iso) => new Date(iso).toLocaleDateString("en-CA", { timeZone: FUSO });
const hora = (iso) => new Date(iso).toLocaleTimeString("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" });
function dia(iso) {
  const t = new Date(iso).toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short", day: "2-digit", month: "2-digit" }).replace(".", "");
  return t.charAt(0).toUpperCase() + t.slice(1);
}
const diaMes = (dataIso) => `${dataIso.slice(8, 10)}/${dataIso.slice(5, 7)}`;
/** "Sáb, 15/11 · 09:00–12:00" */
export function quandoEvento(e) {
  if (!e.inicio) return "";
  let t = `${dia(e.inicio)} · ${hora(e.inicio)}`;
  if (e.fim) t += diaIso(e.fim) === diaIso(e.inicio) ? `–${hora(e.fim)}` : ` até ${dia(e.fim)} ${hora(e.fim)}`;
  return t;
}
/** São Paulo não tem horário de verão desde 2019: UTC−3 */
const paraIso = (data, horaTxt) => new Date(`${data}T${horaTxt}:00-03:00`).toISOString();

function faixa(e) {
  if (e.idade_min == null && e.idade_max == null) return null;
  const min = e.idade_min ?? 0;
  const max = e.idade_max ?? 12;
  return min === max ? `Crianças de ${min} ${min === 1 ? "ano" : "anos"}` : `Crianças de ${min} a ${max} anos`;
}
const esgotado = (e) => e.vagas != null && Number(e.inscritos) >= Number(e.vagas);

/** Botão redondo do WhatsApp para um telefone (55 + DDD + número). */
function zapPessoa(telefone, nome) {
  const d = String(telefone || "").replace(/\D/g, "");
  if (!/^55[1-9][0-9]9?[0-9]{8}$/.test(d)) return null;
  return el("a", { class: "botao-icone botao-icone--whatsapp", href: `https://wa.me/${d}`, target: "_blank",
    rel: "noopener noreferrer", "aria-label": `Chamar ${nome || "contato"} no WhatsApp` }, icone("conversa"));
}

// =====================================================================
export async function render(alvo) {
  alvoTela = alvo;
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  lider = perfil.ok && perfil.temPapel(...LIDERANCA);
  await desenhar();
}

async function desenhar() {
  const id = parametro("id");
  if (id && UUID.test(id) && parametro("ver") === "inscritos" && lider) await desenharInscritos(id);
  else await desenharLista(id && UUID.test(id) ? id : null);
}

// ---------------- Lista de eventos ----------------
async function desenharLista(idFoco) {
  const r = await eventosLista();
  if (!alvoTela?.isConnected) return;
  const cabecalho = el("div", { class: "cabecalho-tela" }, el("h1", { text: "Eventos" }),
    lider ? el("button", { class: "botao botao--primario botao--pequeno", type: "button", onclick: () => janelaEvento(null) },
      icone("adicionar"), "Novo evento") : null);
  if (!r.ok) { montar(alvoTela, cabecalho, aviso("erro", r.erro)); return; }
  const lista = r.resultado || [];
  const partes = [cabecalho];

  if (idFoco) {
    const e = lista.find((x) => x.id === idFoco);
    partes.push(e ? cartaoEvento(e) : aviso("atencao", "Evento não encontrado (pode ter sido apagado ou já passou)."),
      el("p", { class: "mt-3" }, el("a", { class: "botao botao--texto botao--pequeno", href: "#/eventos" }, icone("voltar"), "Ver todos os eventos")));
    montar(alvoTela, partes);
    return;
  }

  const proximos = lista.filter((e) => !e.passado);
  const passados = lista.filter((e) => e.passado);
  if (!proximos.length) {
    partes.push(aviso("info", lider ? "Nenhum evento por vir. Toque em \"Novo evento\"." : "Nenhum evento por enquanto. Quando a liderança publicar, aparece aqui."));
  } else {
    partes.push(el("div", {}, proximos.map(cartaoEvento)));
  }
  if (lider && passados.length) {
    partes.push(el("div", { class: "secao-titulo" }, el("h2", { text: "Passados" })),
      el("div", {}, passados.map(cartaoEvento)));
  }
  montar(alvoTela, partes);
}

function cartaoEvento(e) {
  const ativo = e.publicado && !e.cancelado && !e.passado;
  const etiquetas = el("div", { class: "linha" },
    !e.publicado ? el("span", { class: "etiqueta etiqueta--neutra", text: "Rascunho" }) : null,
    e.cancelado ? el("span", { class: "etiqueta etiqueta--alergia", text: "Cancelado" }) : null,
    e.passado && !e.cancelado ? el("span", { class: "etiqueta etiqueta--neutra", text: "Já aconteceu" }) : null,
    ativo && e.aberta && !esgotado(e) ? el("span", { class: "etiqueta etiqueta--sucesso", text: "Inscrições abertas" }) : null,
    ativo && e.aberta && esgotado(e) ? el("span", { class: "etiqueta etiqueta--laranja", text: "Vagas esgotadas" }) : null,
    ativo && !e.aberta ? el("span", { class: "etiqueta etiqueta--neutra", text: "Inscrições fechadas" }) : null,
    e.autorizacao ? el("span", { class: "etiqueta etiqueta--azul", text: "Pede autorização" }) : null);

  const info = [
    quandoEvento(e),
    e.local,
    faixa(e),
    e.vagas != null ? (lider ? `${e.inscritos} de ${e.vagas} vagas` : `${e.vagas} vagas`) : (lider ? `${e.inscritos} inscritos` : null),
    e.inscricoes_ate && ativo ? `Inscrições até ${diaMes(e.inscricoes_ate)}` : null,
  ].filter(Boolean);

  const menu = lider ? menuAcoes([
    !e.cancelado && !e.passado ? { texto: "Editar", acao: () => janelaEvento(e) } : null,
    ativo && Number(e.inscritos) > 0 ? { texto: "Avisar inscritos", acao: () => janelaAvisar(e) } : null,
    e.publicado && !e.cancelado ? { texto: "Cancelar evento", perigo: true, acao: () => confirmar("Cancelar o evento?",
      "O evento fica marcado como cancelado e os responsáveis das crianças inscritas (e quem ia ajudar) recebem um aviso.",
      "Cancelar evento", () => cancelarEvento(e.id), "Evento cancelado.", true) } : null,
    Number(e.inscritos) === 0 && Number(e.ajudantes) === 0 ? { texto: "Apagar", perigo: true, acao: () => confirmar("Apagar o evento?",
      "O evento some para todos. Não dá para desfazer.", "Apagar", () => apagarEvento(e.id), "Evento apagado.", true) } : null,
  ], `Mais ações do evento ${e.titulo}`) : null;

  const corpo = [];
  if (e.descricao) corpo.push(el("p", { class: "texto-livre mt-2", text: e.descricao }));
  if (ativo && Array.isArray(e.minhas_criancas) && e.minhas_criancas.length) corpo.push(blocoMinhasCriancas(e));
  if (ativo && e.aceita_ajuda && (e.pode_ajudar || lider)) corpo.push(blocoAjuda(e));

  const linkApp = enderecoApp(`/eventos?id=${e.id}`);
  const acoes = el("div", { class: "linha mt-3" });
  if (lider && !e.publicado && !e.cancelado && !e.passado) {
    acoes.append(el("button", { class: "botao botao--primario botao--pequeno", type: "button", onclick: () => janelaPublicar(e) },
      icone("avisos"), "Publicar"));
  }
  if (lider && e.publicado) {
    acoes.append(el("a", { class: "botao botao--secundario botao--pequeno", href: `#/eventos?id=${e.id}&ver=inscritos` },
      icone("crianca"), `Inscritos (${e.inscritos})`));
  }
  if (ativo && lider) acoes.append(botaoWhatsapp(textoGrupo(e, linkApp)));
  if (ativo && e.aberta && !esgotado(e)) acoes.append(botaoWhatsapp(textoConvite(e, linkApp), "Convidar uma família"));

  return el("section", { class: "cartao" },
    el("div", { class: "cartao-topo" },
      el("div", { class: "flex-1" }, el("h2", { text: e.titulo }), etiquetas),
      menu),
    el("p", { class: "suave mt-2", text: info.join(" · ") }),
    corpo,
    acoes.childNodes.length ? acoes : null);
}

function textoGrupo(e, link) {
  return [`🎉 *${e.titulo}* – Fonte Kids`, `📅 ${quandoEvento(e)}`, e.local ? `📍 ${e.local}` : null, faixa(e) ? `👧 ${faixa(e)}` : null,
    e.descricao ? `\n${e.descricao}` : null,
    e.aberta ? `\nInscrições pelo app${e.inscricoes_ate ? ` até ${diaMes(e.inscricoes_ate)}` : ""}: ${link}` : `\nMais detalhes no app: ${link}`]
    .filter(Boolean).join("\n");
}

function textoConvite(e, link) {
  return [`Oi! Vai ter *${e.titulo}* no Fonte Kids: ${quandoEvento(e)}${e.local ? `, ${e.local}` : ""}.`,
    faixa(e) ? `${faixa(e)}.` : null,
    "",
    `Se a sua família já tem cadastro, faça a inscrição pelo app: ${link}`,
    `Ainda não tem cadastro? É rapidinho: ${enderecoCadastroFamilia()}`]
    .filter((x) => x !== null).join("\n");
}

// ---------- Responsável: as próprias crianças ----------
function blocoMinhasCriancas(e) {
  return el("div", { class: "mt-3" },
    el("h3", { class: "sem-margem", text: "Suas crianças" }),
    el("ul", { class: "lista-compacta mt-2" }, e.minhas_criancas.map((c) => {
      const ins = c.inscricao;
      const linha = [textoIdade(c.idade ?? null) + " no dia"];
      const acoes = el("div", { class: "linha acoes-crianca" });
      if (ins) {
        if (e.autorizacao) linha.push(ins.autorizado ? "Autorizada" : "Falta a sua autorização");
        if (e.autorizacao && !ins.autorizado) {
          acoes.append(el("button", { class: "botao botao--primario botao--pequeno", type: "button", text: "Autorizar",
            onclick: () => janelaInscrever(e, c) }));
        }
        if (e.aberta) {
          acoes.append(el("button", { class: "botao botao--texto botao--pequeno", type: "button", text: "Tirar inscrição",
            onclick: () => confirmar(`Tirar a inscrição de ${c.nome}?`, "A vaga fica livre para outra criança.", "Tirar inscrição",
              () => cancelarInscricao(ins.id), "Inscrição retirada.") }));
        }
      } else if (!c.cabe) {
        linha.push("Fora da faixa de idade");
      } else if (!e.aberta) {
        linha.push("Inscrições fechadas");
      } else if (esgotado(e)) {
        linha.push("Vagas esgotadas");
      } else {
        acoes.append(el("button", { class: "botao botao--primario botao--pequeno", type: "button", text: "Inscrever",
          onclick: () => janelaInscrever(e, c) }));
      }
      return el("li", {}, el("div", { class: "item-compacto" },
        el("span", { class: "item-compacto__texto" },
          el("span", { class: "item-compacto__nome", text: c.nome }),
          el("span", { class: "item-compacto__linha item-compacto__linha--quebra", text: linha.join(" · ") })),
        ins ? el("span", { class: "item-compacto__etiquetas" }, el("span", { class: "etiqueta etiqueta--sucesso", text: "Inscrita" })) : null),
        acoes.childNodes.length ? acoes : null);
    })));
}

function janelaInscrever(e, c) {
  const autorizo = el("input", { type: "checkbox" });
  const obs = el("textarea", { class: "entrada", rows: "3", maxlength: "300",
    placeholder: "Ex.: vai embora mais cedo; precisa de ajuda para comer…" });
  obs.value = c.inscricao?.observacao || "";
  abrirJanela({
    titulo: c.inscricao ? `Autorizar ${c.nome}` : `Inscrever ${c.nome}`,
    conteudo: [
      el("p", { class: "suave", text: `${e.titulo} · ${quandoEvento(e)}${e.local ? ` · ${e.local}` : ""}` }),
      e.autorizacao ? el("label", { class: "marcar" }, autorizo, `Autorizo a participação de ${c.nome} neste evento.`) : null,
      campo("Observação para a liderança (opcional)", obs),
    ].filter(Boolean),
    textoSalvar: c.inscricao ? "Autorizar" : "Inscrever",
    sucesso: c.inscricao ? "Autorização registrada." : "Inscrição feita!",
    aoSalvar: async () => {
      if (e.autorizacao && !autorizo.checked) { autorizo.focus(); return "Marque \"Autorizo a participação\"."; }
      const r = await inscreverCrianca(e.id, c.id, autorizo.checked, obs.value.trim());
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

// ---------- Voluntária: "Quero ajudar" ----------
function blocoAjuda(e) {
  const vagas = e.vagas_ajuda != null ? ` (${e.ajudantes} de ${e.vagas_ajuda})` : ` (${e.ajudantes})`;
  const cheio = e.vagas_ajuda != null && Number(e.ajudantes) >= Number(e.vagas_ajuda);
  const botao = !e.pode_ajudar ? null : e.eu_ajudo
    ? el("button", { class: "botao botao--texto botao--pequeno", type: "button", text: "Não vou poder ajudar",
        onclick: () => ajudar(e, false) })
    : cheio ? null
      : el("button", { class: "botao botao--primario botao--pequeno", type: "button", text: "Quero ajudar",
          onclick: () => ajudar(e, true) });
  return el("div", { class: "linha linha--entre mt-3" },
    el("span", { class: "suave", text: e.eu_ajudo ? `Você vai ajudar neste evento${vagas}.`
      : cheio ? `A equipe de ajuda já está completa${vagas}.` : `A liderança pediu ajuda da equipe${vagas}.` }),
    botao);
}

async function ajudar(e, sim) {
  const r = await ajudarEvento(e.id, sim);
  if (!r.ok) { toast("erro", r.erro); return; }
  toast("sucesso", sim ? "Obrigada! A liderança vai ver que você vai ajudar." : "Pronto, você saiu da lista de ajuda.");
  await desenhar();
}

// ---------- Liderança: criar, editar, publicar, avisar ----------
function janelaEvento(e) {
  const tituloEv = el("input", { class: "entrada", type: "text", maxlength: "80", placeholder: "Ex.: Festa da Primavera" });
  const descricao = el("textarea", { class: "entrada", rows: "4", maxlength: "2000", placeholder: "O que vai ter, o que levar, valor…" });
  const data = el("input", { class: "entrada", type: "date", min: isoHoje() });
  const inicio = el("input", { class: "entrada", type: "time" });
  const fim = el("input", { class: "entrada", type: "time" });
  const local = el("input", { class: "entrada", type: "text", maxlength: "120", placeholder: "Ex.: Salão do Fonte Kids" });
  const idadeOpcoes = (rotulo) => [el("option", { value: "", text: rotulo }),
    ...Array.from({ length: 13 }, (_, n) => el("option", { value: String(n), text: `${n} ${n === 1 ? "ano" : "anos"}` }))];
  const idadeMin = el("select", { class: "entrada" }, idadeOpcoes("Qualquer idade"));
  const idadeMax = el("select", { class: "entrada" }, idadeOpcoes("Qualquer idade"));
  const vagas = el("input", { class: "entrada", type: "number", min: "1", max: "500", inputmode: "numeric", placeholder: "Sem limite" });
  const prazo = el("input", { class: "entrada", type: "date", min: isoHoje() });
  const autorizacao = el("input", { type: "checkbox" });
  const abertas = el("input", { type: "checkbox" });
  const ajuda = el("input", { type: "checkbox" });
  const vagasAjuda = el("input", { class: "entrada", type: "number", min: "1", max: "50", inputmode: "numeric", placeholder: "Sem limite" });
  const campoVagasAjuda = campo("Quantas pessoas da equipe (opcional)", vagasAjuda);

  abertas.checked = true;
  if (e) {
    tituloEv.value = e.titulo || "";
    descricao.value = e.descricao || "";
    data.value = diaIso(e.inicio);
    data.removeAttribute("min");
    inicio.value = hora(e.inicio);
    fim.value = e.fim && diaIso(e.fim) === diaIso(e.inicio) ? hora(e.fim) : "";
    local.value = e.local || "";
    idadeMin.value = e.idade_min == null ? "" : String(e.idade_min);
    idadeMax.value = e.idade_max == null ? "" : String(e.idade_max);
    vagas.value = e.vagas == null ? "" : String(e.vagas);
    prazo.value = e.inscricoes_ate || "";
    autorizacao.checked = !!e.autorizacao;
    abertas.checked = !!e.inscricoes_abertas;
    ajuda.checked = !!e.aceita_ajuda;
    vagasAjuda.value = e.vagas_ajuda == null ? "" : String(e.vagas_ajuda);
  }
  const mostrarAjuda = () => { campoVagasAjuda.hidden = !ajuda.checked; };
  ajuda.addEventListener("change", mostrarAjuda);
  mostrarAjuda();

  abrirJanela({
    titulo: e ? "Editar evento" : "Novo evento",
    conteudo: [
      campo("Nome do evento", tituloEv),
      campo("Descrição (opcional)", descricao),
      campo("Dia", data),
      campo("Começa às", inicio),
      campo("Termina às (opcional)", fim),
      campo("Local (opcional)", local),
      campo("Idade mínima", idadeMin),
      campo("Idade máxima", idadeMax),
      campo("Vagas (opcional)", vagas),
      campo("Inscrições até (opcional)", prazo, "Sem data, ficam abertas até o evento começar."),
      el("label", { class: "marcar" }, abertas, "Inscrições abertas"),
      el("label", { class: "marcar" }, autorizacao, "Precisa de autorização dos pais"),
      el("label", { class: "marcar" }, ajuda, "Pedir ajuda da equipe (\"Quero ajudar\")"),
      campoVagasAjuda,
      e && e.publicado ? el("p", { class: "suave", text: "Editar não avisa ninguém. Se mudar data ou local, use \"Avisar inscritos\" depois." }) : null,
    ].filter(Boolean),
    textoSalvar: e ? "Salvar" : "Salvar rascunho",
    aoSalvar: async () => {
      if (tituloEv.value.trim().length < 3) { tituloEv.focus(); return "Escreva o nome do evento."; }
      if (!data.value) { data.focus(); return "Escolha o dia."; }
      if (!inicio.value) { inicio.focus(); return "Informe a hora de início."; }
      if (fim.value && fim.value <= inicio.value) { fim.focus(); return "O fim precisa ser depois do início."; }
      if (idadeMin.value && idadeMax.value && Number(idadeMin.value) > Number(idadeMax.value)) { idadeMin.focus(); return "A idade mínima passa da máxima."; }
      if (prazo.value && prazo.value > data.value) { prazo.focus(); return "O prazo de inscrição passa do dia do evento."; }
      const dados = {
        titulo: tituloEv.value.trim(), descricao: descricao.value.trim(),
        inicio: paraIso(data.value, inicio.value), fim: fim.value ? paraIso(data.value, fim.value) : "",
        local: local.value.trim(), idade_min: idadeMin.value, idade_max: idadeMax.value,
        vagas: vagas.value.trim(), inscricoes_ate: prazo.value,
        autorizacao: autorizacao.checked, inscricoes_abertas: abertas.checked,
        aceita_ajuda: ajuda.checked, vagas_ajuda: ajuda.checked ? vagasAjuda.value.trim() : "",
      };
      const r = await salvarEvento(e?.id || null, dados);
      if (!r.ok) return r.erro;
      toast("sucesso", e ? "Evento salvo." : "Rascunho salvo. Toque em \"Publicar\" para avisar as famílias.");
      await desenhar();
      return null;
    },
  });
}

function janelaPublicar(e) {
  const publico = el("select", { class: "entrada" }, PUBLICOS.map(([v, t]) => el("option", { value: v, text: t })));
  publico.value = "responsaveis";
  abrirJanela({
    titulo: "Publicar evento",
    conteudo: [
      el("p", { text: `"${e.titulo}" aparece para todos no app. Quem estiver no público escolhido recebe um aviso (e no celular, se ativou).` }),
      campo("Quem recebe o aviso", publico),
    ],
    textoSalvar: "Publicar",
    aoSalvar: async () => {
      const r = await publicarEvento(e.id, publico.value);
      if (!r.ok) return r.erro;
      const n = r.resultado?.destinatarios ?? 0;
      toast("sucesso", `Evento publicado. ${n === 1 ? "1 pessoa avisada" : `${n} pessoas avisadas`}.`);
      await desenhar();
      return null;
    },
  });
}

function janelaAvisar(e) {
  const texto = el("textarea", { class: "entrada", rows: "3", maxlength: "500",
    placeholder: `Sem texto, vai: "O evento é ${quandoEvento(e).replace(" · ", " às ")}${e.local ? ` · ${e.local}` : ""}."` });
  abrirJanela({
    titulo: "Avisar inscritos",
    conteudo: [
      el("p", { class: "suave", text: "Vai para os responsáveis das crianças inscritas (aviso no app e no celular). No máximo 1 lembrete por hora." }),
      campo("Texto (opcional)", texto),
    ],
    textoSalvar: "Enviar",
    aoSalvar: async () => {
      const r = await avisarInscritos(e.id, texto.value.trim());
      if (!r.ok) return r.erro;
      const n = r.resultado ?? 0;
      toast("sucesso", `Lembrete enviado. ${n === 1 ? "1 pessoa avisada" : `${n} pessoas avisadas`}.`);
      await desenhar();
      return null;
    },
  });
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

// ---------------- Liderança: inscritos ----------------
async function desenharInscritos(id) {
  const [rl, ri] = await Promise.all([eventosLista(), eventoInscritos(id)]);
  if (!alvoTela?.isConnected) return;
  const voltar = el("p", { class: "voltar" }, el("a", { class: "botao botao--texto botao--pequeno", href: `#/eventos?id=${id}` },
    icone("voltar"), "Voltar ao evento"));
  const e = rl.ok ? (rl.resultado || []).find((x) => x.id === id) : null;
  if (!ri.ok || !e) { montar(alvoTela, voltar, el("h1", { text: "Inscritos" }), aviso("erro", ri.ok ? "Evento não encontrado." : ri.erro)); return; }

  const inscritos = ri.resultado?.inscritos || [];
  const ajudantes = ri.resultado?.ajudantes || [];
  const autorizados = inscritos.filter((i) => i.autorizado_em).length;
  const presentes = inscritos.filter((i) => i.presente).length;
  const resumo = [`${inscritos.length} ${inscritos.length === 1 ? "inscrita" : "inscritas"}${e.vagas != null ? ` de ${e.vagas} vagas` : ""}`,
    e.autorizacao ? `${autorizados} com autorização` : null, `${presentes} ${presentes === 1 ? "presente" : "presentes"}`].filter(Boolean);

  const podeMexer = !e.cancelado && !e.passado;
  const partes = [
    voltar,
    el("div", { class: "cabecalho-tela" }, el("h1", { text: e.titulo }),
      podeMexer ? el("button", { class: "botao botao--primario botao--pequeno", type: "button", onclick: () => janelaInscreverLideranca(e, inscritos) },
        icone("adicionar"), "Inscrever criança") : null),
    el("p", { class: "suave", text: `${quandoEvento(e)}${e.local ? ` · ${e.local}` : ""}` }),
    el("p", { class: "resumo-lista", text: resumo.join(" · ") }),
  ];
  if (!inscritos.length) partes.push(aviso("info", "Nenhuma criança inscrita ainda."));
  else partes.push(el("div", {}, inscritos.map((i) => cartaoInscrito(e, i))));

  if (e.aceita_ajuda || ajudantes.length) {
    partes.push(el("div", { class: "secao-titulo" }, el("h2", { text: `Vão ajudar (${ajudantes.length}${e.vagas_ajuda != null ? ` de ${e.vagas_ajuda}` : ""})` })));
    partes.push(ajudantes.length
      ? el("ul", { class: "lista-compacta" }, ajudantes.map((a) => el("li", {}, el("div", { class: "item-compacto" },
          el("span", { class: "item-compacto__texto" },
            el("span", { class: "item-compacto__nome", text: a.nome }),
            el("span", { class: "item-compacto__linha", text: a.telefone ? mascararTelefone(a.telefone) : "Sem telefone" })),
          zapPessoa(a.telefone, a.nome)))))
      : el("p", { class: "suave", text: "Ninguém da equipe se ofereceu ainda." }));
  }
  montar(alvoTela, partes);
}

function cartaoInscrito(e, i) {
  const presente = el("input", { type: "checkbox" });
  presente.checked = !!i.presente;
  presente.addEventListener("change", async () => {
    presente.disabled = true;
    const r = await marcarPresencaEvento(i.id, presente.checked ? true : null);
    presente.disabled = false;
    if (!r.ok) { presente.checked = !presente.checked; toast("erro", r.erro); }
  });
  const etiquetas = el("div", { class: "linha" },
    i.alergias ? el("span", { class: "etiqueta etiqueta--alergia" }, icone("alergia"), i.alergias) : null,
    e.autorizacao && !i.autorizado_em ? el("span", { class: "etiqueta etiqueta--laranja", text: "Sem autorização" }) : null,
    e.autorizacao && i.autorizado_em ? el("span", { class: "etiqueta etiqueta--sucesso", text: "Autorizada" }) : null,
    i.pela_lideranca ? el("span", { class: "etiqueta etiqueta--neutra", text: "Inscrita pela liderança" }) : null);
  const menu = menuAcoes([
    { texto: "Tirar inscrição", perigo: true, acao: () => confirmar(`Tirar a inscrição de ${i.nome}?`,
      "A criança sai da lista deste evento.", "Tirar inscrição", () => cancelarInscricao(i.id), "Inscrição retirada.", true) },
  ], `Mais ações para ${i.nome}`);
  return el("section", { class: "cartao" },
    el("div", { class: "cartao-topo" },
      el("div", { class: "flex-1" },
        el("h2", { text: i.nome }),
        el("p", { class: "suave sem-margem", text: i.idade == null ? "Idade não informada" : `${textoIdade(i.idade)} no dia` })),
      menu),
    etiquetas.childNodes.length ? etiquetas : null,
    i.observacao ? el("p", { class: "texto-livre mt-2", text: `Obs.: ${i.observacao}` }) : null,
    el("ul", { class: "lista-compacta mt-2" }, (i.responsaveis || []).map((p) => el("li", {}, el("div", { class: "item-compacto" },
      el("span", { class: "item-compacto__texto" },
        el("span", { class: "item-compacto__nome", text: p.nome }),
        el("span", { class: "item-compacto__linha", text: p.telefone ? mascararTelefone(p.telefone) : "Sem telefone" })),
      zapPessoa(p.telefone, p.nome))))),
    el("label", { class: "marcar mt-2" }, presente, "Presente"));
}

async function janelaInscreverLideranca(e, inscritos) {
  const r = await listarCriancas();
  if (!r.ok) { toast("erro", r.erro); return; }
  const jaInscritas = new Set(inscritos.map((i) => i.crianca_id));
  const todas = (r.lista || []).filter((c) => c.ativo && !jaInscritas.has(c.id))
    .map((c) => ({ id: c.id, nome: c.pessoa?.nome || "Sem nome", busca: normalizar(c.pessoa?.nome), anos: idade(c.pessoa?.data_nascimento) }))
    .sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
  let escolhida = null;
  const busca = el("input", { class: "entrada", type: "search", placeholder: "Digite o nome da criança", autocomplete: "off" });
  const resultados = el("ul", { class: "lista-compacta mt-2" });
  const selecionada = el("p", { class: "suave", text: "Nenhuma criança escolhida." });
  const obs = el("textarea", { class: "entrada", rows: "2", maxlength: "300" });
  const filtrar = () => {
    const t = normalizar(busca.value);
    const achadas = t.length < 2 ? [] : todas.filter((c) => c.busca.includes(t)).slice(0, 8);
    montar(resultados, achadas.map((c) => el("li", {}, el("button", { class: "botao botao--texto botao--pequeno", type: "button",
      text: `${c.nome} · ${textoIdade(c.anos)}`,
      onclick: () => { escolhida = c; selecionada.textContent = `Escolhida: ${c.nome} (${textoIdade(c.anos)})`; } }))));
  };
  busca.addEventListener("input", filtrar);
  abrirJanela({
    titulo: "Inscrever criança",
    conteudo: [
      el("p", { class: "suave", text: "A liderança pode inscrever mesmo fora da idade, do prazo ou passando das vagas. A autorização continua sendo dos pais pelo app." }),
      campo("Buscar", busca), resultados, selecionada,
      campo("Observação (opcional)", obs),
    ],
    textoSalvar: "Inscrever",
    sucesso: "Criança inscrita.",
    aoSalvar: async () => {
      if (!escolhida) { busca.focus(); return "Escolha a criança na lista."; }
      const res = await inscreverCrianca(e.id, escolhida.id, false, obs.value.trim());
      if (!res.ok) return res.erro;
      await desenhar();
      return null;
    },
  });
}
