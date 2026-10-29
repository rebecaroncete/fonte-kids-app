// =====================================================================
// Tela: Aniversariantes do mês (Fase 13)   #/aniversariantes
// Equipe do Fonte Kids (liderança, recepção, voluntárias; o banco confere).
// Crianças e voluntárias ativas que fazem aniversário no mês, por dia.
// Liderança e recepção (toda voluntária tem a recepção desde 27/10/2026)
// veem o botão verde de parabéns: abre o WhatsApp
// com a mensagem pronta (criança → responsável principal; voluntária →
// ela mesma). Nada é enviado sozinho; os telefones só ficam nos links.
// O aviso "Hoje tem aniversário" chega às 8h pelo banco (keep-alive).
// =====================================================================
import { el, montar, aviso, carregando } from "../ui.js";
import { icone } from "../icones.js";
import { meuPerfil, aniversariantesMes } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Aniversariantes";

const FUSO = "America/Sao_Paulo";
const MSG_CRIANCA = "Olá, {nome_responsavel}! 🎉 Passando para desejar um feliz aniversário para o(a) {nome_crianca}! Que Deus abençoe essa vida linda com muita saúde, alegria e amor. Com carinho, equipe Fonte Kids 💙🎂";
const MSG_VOLUNTARIA = "Feliz aniversário, {nome_voluntaria}! 🎉 Obrigada por servir com tanto amor no Fonte Kids. Que Deus te abençoe muito neste novo ano de vida! 💙🎂";

let alvoTela = null;
let mes = null; // "AAAA-MM"

const isoHoje = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO });
function somarMes(aaaamm, n) {
  const [a, m] = aaaamm.split("-").map(Number);
  const d = new Date(Date.UTC(a, m - 1 + n, 1));
  return `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, "0")}`;
}
function nomeMes(aaaamm) {
  const t = new Date(`${aaaamm}-15T12:00:00Z`).toLocaleDateString("pt-BR", { timeZone: "UTC", month: "long", year: "numeric" });
  return t.charAt(0).toUpperCase() + t.slice(1);
}
function diaSemana(iso) {
  const s = new Date(`${iso}T12:00:00Z`).toLocaleDateString("pt-BR", { timeZone: "UTC", weekday: "short" }).replace(".", "");
  return s.charAt(0).toUpperCase() + s.slice(1);
}
const primeiro = (nome) => String(nome || "").trim().split(/\s+/)[0];
const numero = (t) => String(t || "").replace(/\D/g, "");
const telefoneOk = (t) => /^55[1-9][0-9]9?[0-9]{8}$/.test(numero(t));

export async function render(alvo) {
  alvoTela = alvo;
  mes = isoHoje().slice(0, 7);
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: titulo }), aviso("erro", perfil.erro)); return; }
  if (!perfil.temPapel("admin", "pastor", "lider", "recepcao", "voluntaria")) {
    montar(alvo, el("h1", { text: titulo }), aviso("atencao", "Esta tela é só para a equipe do Fonte Kids."));
    return;
  }
  await desenhar();
}

async function desenhar() {
  const pedido = mes;
  const r = await aniversariantesMes(`${pedido}-01`);
  if (!alvoTela?.isConnected || pedido !== mes) return;

  const partes = [
    el("h1", { text: titulo }),
    el("div", { class: "ind-nav" },
      el("button", { class: "botao-icone", type: "button", "aria-label": "Mês anterior",
        onclick: () => { mes = somarMes(mes, -1); desenhar(); } }, icone("voltar")),
      el("strong", { class: "ind-nav__texto", text: nomeMes(pedido) }),
      el("button", { class: "botao-icone", type: "button", "aria-label": "Próximo mês",
        onclick: () => { mes = somarMes(mes, 1); desenhar(); } }, icone("seta"))),
  ];
  if (!r.ok) { montar(alvoTela, partes, aviso("erro", r.erro)); return; }

  const d = r.resultado || {};
  const criancas = d.criancas || [];
  const voluntarias = d.voluntarias || [];
  if (d.pode_whatsapp) {
    partes.push(el("p", { class: "suave", text: "Toque no botão verde para abrir o WhatsApp com a mensagem de parabéns pronta." }));
  }
  partes.push(
    secao("Crianças", criancas, (c) => itemCrianca(c, d), "Nenhuma criança faz aniversário neste mês."),
    secao("Voluntárias", voluntarias, (v) => itemVoluntaria(v, d), "Nenhuma voluntária faz aniversário neste mês."));
  montar(alvoTela, partes);
}

function secao(nome, lista, item, vazio) {
  return el("section", { class: "secao-lista" },
    el("div", { class: "secao-titulo" }, el("h2", { text: `${nome} (${lista.length})` })),
    lista.length ? el("ul", { class: "lista-compacta" }, lista.map(item)) : el("p", { class: "suave", text: vazio }));
}

function linha(p, hoje, detalhe, botao) {
  const ehHoje = p.dia === hoje;
  return el("li", {}, el("div", { class: `item-compacto${ehHoje ? " aniv-hoje" : ""}` },
    el("span", { class: "aniv-dia", "aria-hidden": "true" },
      el("span", { class: "aniv-dia__numero", text: p.dia.slice(8, 10) }),
      el("span", { class: "aniv-dia__semana", text: diaSemana(p.dia) })),
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: p.nome }),
      ehHoje || detalhe
        ? el("span", { class: "item-compacto__linha", text: [ehHoje ? "🎂 Hoje" : null, detalhe].filter(Boolean).join(" · ") })
        : null),
    botao));
}

function botaoWhatsapp(telefone, texto, rotulo) {
  return el("a", { class: "botao-icone botao-icone--whatsapp", href: `https://wa.me/${numero(telefone)}?text=${encodeURIComponent(texto)}`,
    target: "_blank", rel: "noopener noreferrer", "aria-label": rotulo }, icone("conversa"));
}

function itemCrianca(c, d) {
  const idade = `faz ${c.idade} ${c.idade === 1 ? "ano" : "anos"}`;
  let botao = null;
  if (d.pode_whatsapp) {
    const resp = c.responsavel;
    botao = resp && telefoneOk(resp.telefone)
      ? botaoWhatsapp(resp.telefone,
          (d.mensagem_crianca || MSG_CRIANCA)
            .replace(/{nome_responsavel}/g, primeiro(resp.nome))
            .replace(/{nome_crianca}/g, primeiro(c.nome))
            .replace(/{idade}/g, String(c.idade)),
          `Parabenizar ${c.nome} pelo WhatsApp de ${resp.nome}`)
      : el("span", { class: "suave", text: "Sem WhatsApp" });
  }
  const detalhe = d.pode_whatsapp && c.responsavel ? `${idade} · ${primeiro(c.responsavel.nome)}` : idade;
  return linha(c, d.hoje, detalhe, botao);
}

function itemVoluntaria(v, d) {
  let botao = null;
  if (d.pode_whatsapp) {
    botao = telefoneOk(v.telefone)
      ? botaoWhatsapp(v.telefone,
          (d.mensagem_voluntaria || MSG_VOLUNTARIA).replace(/{nome_voluntaria}/g, primeiro(v.nome)),
          `Parabenizar ${v.nome} pelo WhatsApp`)
      : el("span", { class: "suave", text: "Sem WhatsApp" });
  }
  return linha(v, d.hoje, null, botao);
}
