// =====================================================================
// Tela: Avisos (Fase 10 · Etapa 4; Fase 7: envio, push e enquetes)
// Abas internas: Recebidos · Enviados (só liderança) · Enquetes (#/enquetes).
// Recebidos: as notificações do próprio login (o RLS só entrega as dela),
// marca como lida (uma ou todas) e se atualiza sozinha (Realtime).
// Liderança: "Novo aviso" com escolha de público (todos, equipe, só líderes,
// só responsáveis) – o banco monta a lista (enviar_aviso) – e "Enviados"
// com quantas pessoas leram + botão para mandar o texto no grupo (wa.me).
// Cartão "Receber no celular": liga o push só quando a pessoa toca.
// Links só abrem telas internas conhecidas ("#/endereco").
// =====================================================================
import { el, montar, aviso, carregando, toast } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela, campo } from "../janela.js";
import { listarNotificacoes, marcarLida, meuPerfil, enviarAviso, avisosEnviados, enquetesPendentes, enderecoApp } from "../supabase.js";
import { aoMudarNotificacoes, atualizarContagem } from "../notificacoes.js";
import { situacaoPush, ativarPush } from "../push.js";
import { irPara, rotaExiste } from "../app.js";

export const layout = "padrao";
export const titulo = "Avisos";

const FUSO = "America/Sao_Paulo";
const LIDERANCA = ["admin", "pastor", "lider"];
export const PUBLICOS_AVISO = [
  ["todos", "Todos (equipe e responsáveis)"],
  ["equipe", "Equipe (voluntárias, recepção e líderes)"],
  ["lideres", "Só líderes"],
  ["responsaveis", "Só responsáveis"],
];
const NOME_PUBLICO = { todos: "Todos", equipe: "Equipe", lideres: "Só líderes", responsaveis: "Só responsáveis" };
const CHAVE_ADIAR_PUSH = "fk_push_adiado_ate"; // guarda só uma data
const ADIAR_PUSH_MS = 7 * 24 * 60 * 60 * 1000;

export function quando(iso) {
  const d = new Date(iso);
  const min = Math.round((Date.now() - d.getTime()) / 60000);
  if (min < 1) return "agora";
  if (min < 60) return `há ${min} min`;
  if (min < 24 * 60) return `há ${Math.round(min / 60)} h`;
  return d.toLocaleString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
}

/** "#/logins" → "/logins" (ou "#/eventos?id=…" → "/eventos?id=…") se for uma tela que já existe; senão null. */
function rotaDoLink(link) {
  const m = /^#(\/[a-z0-9-]+)(\?[a-z0-9=&_-]*)?$/i.exec(String(link || ""));
  return m && rotaExiste(m[1]) ? m[1] + (m[2] || "") : null;
}

/** Abas internas de Avisos (também usadas em #/enquetes). atual: recebidos | enviados | enquetes */
export function abasAvisos(atual, lider, aoTrocar) {
  const abas = [["recebidos", "Recebidos"], lider ? ["enviados", "Enviados"] : null, ["enquetes", "Enquetes"]].filter(Boolean);
  return el("div", { class: "abas", role: "tablist", "aria-label": "Avisos" }, abas.map(([id, texto]) => el("button", {
    class: "aba", type: "button", role: "tab", "aria-selected": String(id === atual), text: texto,
    onclick: () => {
      if (id === atual) return;
      if (id === "enquetes") { irPara("/enquetes"); return; }
      if (atual === "enquetes") { location.hash = id === "enviados" ? "#/notificacoes?aba=enviados" : "#/notificacoes"; return; }
      aoTrocar(id);
    },
  })));
}

/** Botão de WhatsApp com o texto pronto (o envio é feito por quem toca). */
export function botaoWhatsapp(texto, rotulo = "Mandar no grupo") {
  return el("a", { class: "botao botao--pequeno botao--whatsapp", href: `https://wa.me/?text=${encodeURIComponent(texto)}`,
    target: "_blank", rel: "noopener noreferrer" }, icone("conversa"), rotulo);
}

// ---------- Cartão "Receber no celular" ----------
function adiadoAte() { try { return Number(localStorage.getItem(CHAVE_ADIAR_PUSH)) || 0; } catch { return 0; } }
function adiar() { try { localStorage.setItem(CHAVE_ADIAR_PUSH, String(Date.now() + ADIAR_PUSH_MS)); } catch { /* ignore */ } }

/** Cartão para ligar o push (ou null se já está ligado / não dá). */
export async function cartaoPush({ sempre = false } = {}) {
  const s = await situacaoPush();
  if (s === "ativo" || s === "sem_suporte") return null;
  if (!sempre && Date.now() < adiadoAte()) return null;
  const cartao = el("section", { class: "cartao cartao--azul" });
  const textos = {
    desligado: "Ative para o celular avisar quando chegar escala, enquete ou aviso da liderança.",
    bloqueado: "As notificações estão bloqueadas para este site. Libere nas configurações do navegador (cadeado ao lado do endereço → Notificações).",
    instalar: "No iPhone, os avisos só chegam com o app instalado: toque em Compartilhar → \"Adicionar à Tela de Início\" e abra o app pelo ícone.",
  };
  const acoes = el("div", { class: "linha mt-2" });
  if (s === "desligado") {
    const ativar = el("button", { class: "botao botao--primario botao--pequeno", type: "button", text: "Ativar" });
    ativar.addEventListener("click", async () => {
      ativar.disabled = true; ativar.textContent = "Ativando…";
      const r = await ativarPush();
      if (!r.ok) { toast("erro", r.erro, 6000); ativar.disabled = false; ativar.textContent = "Ativar"; return; }
      toast("sucesso", "Pronto! Os avisos vão chegar neste celular.");
      cartao.remove();
    });
    acoes.append(ativar);
  }
  if (!sempre) {
    acoes.append(el("button", { class: "botao botao--texto botao--pequeno", type: "button", text: "Agora não",
      onclick: () => { adiar(); cartao.remove(); } }));
  }
  montar(cartao,
    el("h2", { text: "Receber no celular" }),
    el("p", { class: "suave", text: textos[s] }),
    acoes.childElementCount ? acoes : null);
  return cartao;
}

// ---------- Tela ----------
let desligar = null;

export async function render(alvo) {
  if (desligar) { desligar(); desligar = null; }
  const perfil = await meuPerfil();
  const lider = perfil.ok && perfil.temPapel(...LIDERANCA);
  let abaAtual = lider && new URLSearchParams(location.hash.split("?")[1] || "").get("aba") === "enviados" ? "enviados" : "recebidos";

  const area = el("div", {});
  const extras = el("div", {});
  const botaoTodas = el("button", { class: "botao botao--pequeno", type: "button", text: "Ler todas", hidden: true });
  const botaoNovo = lider ? el("button", { class: "botao botao--primario botao--pequeno", type: "button",
    onclick: () => janelaNovoAviso(() => trocar("enviados")) }, icone("adicionar"), "Novo aviso") : null;
  const abas = el("div", {});

  function trocar(id) {
    abaAtual = id;
    history.replaceState(null, "", id === "enviados" ? "#/notificacoes?aba=enviados" : "#/notificacoes");
    desenharAbas();
    carregar();
  }
  function desenharAbas() { montar(abas, abasAvisos(abaAtual, lider, trocar)); }

  async function carregar() {
    if (abaAtual === "enviados") return carregarEnviados();
    const r = await listarNotificacoes();
    if (!document.body.contains(area) || abaAtual !== "recebidos") return;
    if (!r.ok) { montar(area, aviso("erro", r.erro)); return; }
    const novas = r.lista.filter((n) => !n.lida_em).length;
    botaoTodas.hidden = novas === 0;
    if (!r.lista.length) { montar(area, aviso("info", "Você não tem avisos.")); return; }
    montar(area, el("ul", { class: "lista" }, r.lista.map(itemNotificacao)));
  }

  async function carregarEnviados() {
    botaoTodas.hidden = true;
    montar(area, carregando());
    const r = await avisosEnviados(30);
    if (!document.body.contains(area) || abaAtual !== "enviados") return;
    if (!r.ok) { montar(area, aviso("erro", r.erro)); return; }
    const lista = r.resultado || [];
    if (!lista.length) { montar(area, aviso("info", "Nenhum aviso enviado ainda. Toque em \"Novo aviso\".")); return; }
    montar(area, el("ul", { class: "lista" }, lista.map(itemEnviado)));
  }

  function itemEnviado(a) {
    const texto = `*${a.titulo}*\n${a.texto}\n\nVeja no app do Fonte Kids: ${enderecoApp()}`;
    return el("li", { class: "notif" },
      el("div", { class: "notif__topo" },
        el("p", { class: "notif__titulo", text: a.titulo }),
        el("span", { class: "etiqueta etiqueta--azul", text: NOME_PUBLICO[a.publico] || a.publico })),
      el("p", { class: "notif__corpo", text: a.texto }),
      el("p", { class: "notif__quando", text: `${a.autor} · ${quando(a.criado_em)} · ${a.lidas} de ${a.destinatarios} leram` }),
      el("div", { class: "linha" }, botaoWhatsapp(texto)));
  }

  function itemNotificacao(n) {
    const nova = !n.lida_em;
    const rota = rotaDoLink(n.link);
    const acoes = el("div", { class: "linha" });
    if (rota) {
      acoes.append(el("button", { class: "botao botao--pequeno botao--azul", type: "button", text: "Abrir",
        onclick: async () => { if (nova) await marcarLida(n.id); atualizarContagem(); irPara(rota); } }));
    }
    if (nova) {
      acoes.append(el("button", { class: "botao botao--pequeno botao--texto", type: "button", text: "Marcar lida",
        onclick: async (e) => {
          const b = e.currentTarget;
          b.disabled = true;
          const r = await marcarLida(n.id);
          if (!r.ok) { toast("erro", r.erro); b.disabled = false; return; }
          await atualizarContagem(); carregar();
        } }));
    }
    return el("li", { class: nova ? "notif notif--nova" : "notif" },
      el("div", { class: "notif__topo" },
        el("p", { class: "notif__titulo", text: n.titulo || "Aviso" }),
        nova ? el("span", { class: "etiqueta etiqueta--laranja", text: "Novo" }) : null),
      n.corpo ? el("p", { class: "notif__corpo", text: n.corpo }) : null,
      el("p", { class: "notif__quando", text: quando(n.criado_em) }),
      acoes.childElementCount ? acoes : null);
  }

  botaoTodas.addEventListener("click", async () => {
    botaoTodas.disabled = true;
    const r = await marcarLida();
    botaoTodas.disabled = false;
    if (!r.ok) { toast("erro", r.erro); return; }
    await atualizarContagem(); carregar();
  });

  desenharAbas();
  montar(alvo,
    el("div", { class: "cabecalho-tela" }, el("h1", { text: "Avisos" }),
      el("div", { class: "linha" }, botaoTodas, botaoNovo)),
    abas, extras, area);
  montar(area, carregando());

  // Cartões de cima: push e enquetes por responder (não atrasam a lista)
  Promise.all([cartaoPush(), enquetesPendentes()]).then(([cp, ep]) => {
    if (!extras.isConnected) return;
    const n = ep.ok ? Number(ep.resultado) || 0 : 0;
    montar(extras, cp, n > 0 ? el("a", { class: "cartao cartao--laranja item-compacto", href: "#/enquetes" },
      el("span", { class: "numero__icone" }, icone("check")),
      el("span", { class: "item-compacto__texto" },
        el("span", { class: "item-compacto__nome", text: n === 1 ? "1 enquete para responder" : `${n} enquetes para responder` })),
      icone("seta", null, "item-compacto__seta")) : null);
  });

  await carregar();

  // Atualiza sozinha quando chega notificação nova (enquanto a tela estiver aberta)
  desligar = aoMudarNotificacoes(() => {
    if (document.body.contains(area)) { if (abaAtual === "recebidos") carregar(); }
    else if (desligar) { desligar(); desligar = null; }
  });
}

/** Janela "Novo aviso" (liderança). depois(): o que fazer quando enviar. */
function janelaNovoAviso(depois) {
  const publico = el("select", { class: "entrada" },
    el("option", { value: "", text: "Escolha…" }),
    PUBLICOS_AVISO.map(([v, t]) => el("option", { value: v, text: t })));
  const tit = el("input", { class: "entrada", type: "text", maxlength: "80", placeholder: "Ex.: Reunião da equipe" });
  const texto = el("textarea", { class: "entrada", maxlength: "1000", rows: "5" });
  abrirJanela({
    titulo: "Novo aviso",
    conteudo: [
      campo("Para quem", publico),
      campo("Título", tit),
      campo("Texto", texto, "Chega na aba Avisos e, para quem ativou, no celular."),
    ],
    textoSalvar: "Enviar",
    aoSalvar: async () => {
      if (!publico.value) { publico.focus(); return "Escolha para quem é o aviso."; }
      if (tit.value.trim().length < 3) { tit.focus(); return "Escreva um título (3 letras ou mais)."; }
      if (!texto.value.trim()) { texto.focus(); return "Escreva o texto do aviso."; }
      const r = await enviarAviso(publico.value, tit.value.trim(), texto.value.trim());
      if (!r.ok) return r.erro;
      const n = r.resultado?.destinatarios ?? 0;
      toast("sucesso", n === 1 ? "Aviso enviado para 1 pessoa." : `Aviso enviado para ${n} pessoas.`);
      depois();
      return null;
    },
  });
}
