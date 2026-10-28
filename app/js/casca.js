// =====================================================================
// Fonte Kids – casca do app (Fase 10 · Etapa 7: navegação nova)
// Topo enxuto (logo, departamento, foto) + barra de ícones embaixo, por
// papel. No computador, a barra vira uma coluna à esquerda (só CSS).
//
// Abas por papel (4 ou 5):
//   Responsável: Início · Família · Avisos · Perfil
//   Recepção/voluntária: Início · Check-in · Pendências · Avisos · Mais
//   Liderança/pastor/admin: Início · Cadastros · Pendências · Avisos · Mais
// Quem tem papel de equipe E de responsável fica com a barra da equipe;
// "Minha família" aparece no "Mais".
// Fase 5 · 5B: a aba "Recepção" virou "Check-in"; a lista de crianças e
// famílias da recepção foi para o "Mais". A liderança acha o Check-in no
// "Mais" e no cartão do Início em dia de culto.
//
// Tela nova? Se for aba, acrescente em ABAS e em abasDo(); se não, em
// ITENS_MAIS (com "papeis" quando for só para alguns papéis) e, para a
// aba ficar marcada, em abaDaRota().
// =====================================================================
import { CONFIG } from "../config.js";
import { el, iniciais } from "./ui.js";
import { icone } from "./icones.js";
import { meuPerfil, contarPendencias } from "./supabase.js";
import { aoMudarContagem } from "./notificacoes.js";
import { linkFoto } from "./foto.js";

const LIDERANCA = ["admin", "pastor", "lider"];
const EQUIPE = [...LIDERANCA, "recepcao", "voluntaria"];

const ABAS = {
  inicio:     { rota: "/inicio", texto: "Início", icone: "inicio" },
  familia:    { rota: "/minha-familia", texto: "Família", icone: "familia" },
  checkin:    { rota: "/checkin", texto: "Check-in", icone: "checkin" },
  cadastros:  { rota: "/cadastros", texto: "Cadastros", icone: "cadastros" },
  pendencias: { rota: "/pendencias", texto: "Pendências", icone: "pendencias", contagem: "pendencias" },
  avisos:     { rota: "/notificacoes", texto: "Avisos", icone: "avisos", contagem: "avisos" },
  perfil:     { rota: "/perfil", texto: "Perfil", icone: "perfil" },
  mais:       { rota: "/mais", texto: "Mais", icone: "mais" },
};

// Itens da tela "Mais" (papeis: admin | pastor | lider | recepcao | voluntaria | responsavel)
export const ITENS_MAIS = [
  { rota: "/checkin", texto: "Check-in", icone: "checkin", papeis: [...LIDERANCA, "recepcao"] },
  { rota: "/cadastros", texto: "Crianças e famílias", icone: "cadastros", papeis: [...LIDERANCA, "recepcao"] },
  { rota: "/historico", texto: "Histórico", icone: "historico", papeis: [...LIDERANCA, "recepcao"] },
  { rota: "/minha-familia", texto: "Minha família", icone: "familia", papeis: ["responsavel"] },
  { rota: "/perfil", texto: "Meu perfil", icone: "perfil" },
  { rota: "/trocar-senha", texto: "Trocar senha", icone: "senha" },
  { rota: "/logins", texto: "Gestão de logins", icone: "logins", papeis: LIDERANCA },
  { rota: "/acessos", texto: "Acessos da equipe", icone: "autorizados", papeis: LIDERANCA },
  { rota: "/cultos", texto: "Cultos e salas", icone: "calendario", papeis: LIDERANCA },
  { rota: "/telao-link", texto: "Link do telão", icone: "telao", papeis: LIDERANCA },
  { rota: "/grupos-whatsapp", texto: "Grupos de WhatsApp", icone: "conversa", papeis: LIDERANCA },
];

/** "lideranca" | "equipe" | "responsavel" | "basico" */
export function tipoDeBarra(perfil) {
  if (!perfil?.ok) return "basico";
  if (perfil.temPapel(...LIDERANCA)) return "lideranca";
  if (perfil.temPapel("recepcao", "voluntaria")) return "equipe";
  if (perfil.temPapel("responsavel")) return "responsavel";
  return "basico";
}

function abasDo(perfil) {
  const tipo = tipoDeBarra(perfil);
  if (tipo === "lideranca") return ["inicio", "cadastros", "pendencias", "avisos", "mais"];
  if (tipo === "equipe") {
    return perfil.temPapel("recepcao")
      ? ["inicio", "checkin", "pendencias", "avisos", "mais"]
      : ["inicio", "avisos", "mais"];
  }
  if (tipo === "responsavel") return ["inicio", "familia", "avisos", "perfil"];
  return ["inicio", "avisos", "perfil"];
}

/** Qual aba fica marcada em cada tela. */
function abaDaRota(rota, abas) {
  const temMais = abas.includes("mais");
  const mapa = {
    "/ficha": abas.includes("familia") ? "/minha-familia" : abas.includes("cadastros") ? "/cadastros" : "/mais",
    "/cadastros": abas.includes("cadastros") ? "/cadastros" : "/mais",
    "/checkin": abas.includes("checkin") ? "/checkin" : "/mais",
    "/perfil": temMais ? "/mais" : "/perfil",
    "/trocar-senha": temMais ? "/mais" : "/perfil",
    "/logins": "/mais",
    "/acessos": "/mais",
    "/cultos": "/mais",
    "/telao-link": "/mais",
    "/historico": "/mais",
    "/grupos-whatsapp": "/mais",
    "/minha-familia": abas.includes("familia") ? "/minha-familia" : "/mais",
  };
  return mapa[rota] || rota;
}

/** Itens do "Mais" para o login atual. */
export function itensMaisDo(perfil) {
  const meus = perfil?.ok ? perfil.papeis.map((p) => p.papel) : [];
  const naBarra = abasDo(perfil).map((a) => ABAS[a].rota); // o que já está na barra não se repete
  return ITENS_MAIS.filter((i) => (!i.papeis || i.papeis.some((p) => meus.includes(p))) && !naBarra.includes(i.rota));
}

let desligadores = [];
function desligarTudo() { for (const f of desligadores) { try { f(); } catch { /* ignore */ } } desligadores = []; }

/** Barra do topo. opcoes: { logado, rota } */
export function montarTopo({ logado, rota }) {
  desligarTudo();

  const marca = el("a", { class: "topo__marca", href: logado ? "#/inicio" : "#/entrar", "aria-label": `${CONFIG.nomeApp} – início` },
    el("img", { class: "topo__logo", src: "img/logo.png", alt: "" }));
  const departamento = el("span", { class: "topo__nome", text: CONFIG.nomeApp });

  if (!logado) return el("header", { class: "topo" }, marca, departamento);

  // Foto (ou iniciais) → abre o perfil
  const avatar = el("a", { class: "avatar topo__avatar", href: "#/perfil", "aria-label": "Meu perfil" },
    el("span", { "aria-hidden": "true", text: "" }));
  if (rota === "/perfil") avatar.setAttribute("aria-current", "page");

  meuPerfil().then(async (p) => {
    if (!p.ok) return;
    avatar.firstChild.textContent = iniciais(p.nome);
    // Departamento: hoje todos são do Fonte Kids. O seletor (para quem serve
    // em mais de um) entra junto com o app geral da igreja.
    const deps = [...new Set(p.papeis.map((x) => x.departamento).filter(Boolean))];
    if (deps.length === 1) departamento.textContent = deps[0];
    if (p.pessoaId) {
      const url = await linkFoto("pessoa", p.pessoaId);
      if (!url || !avatar.isConnected) return;
      const img = el("img", { src: url, alt: "", referrerpolicy: "no-referrer", decoding: "async" });
      img.addEventListener("load", () => avatar.replaceChildren(img), { once: true });
    }
  });

  return el("header", { class: "topo" }, marca, departamento, avatar);
}

/** Barra de ícones (embaixo no celular; coluna à esquerda no computador). */
export function montarBarra({ rota }) {
  const nav = el("nav", { class: "barra", "aria-label": "Menu principal" });

  function desenhar(perfil) {
    const abas = abasDo(perfil);
    const ativa = abaDaRota(rota, abas);
    const contagens = {};
    nav.replaceChildren(...abas.map((chave) => {
      const a = ABAS[chave];
      const num = el("span", { class: "barra__contagem", hidden: true, "aria-hidden": "true" });
      if (a.contagem) contagens[a.contagem] = { num, link: null, texto: a.texto };
      const link = el("a", { class: "barra__aba", href: `#${a.rota}`, "aria-current": a.rota === ativa ? "page" : null },
        el("span", { class: "barra__icone" }, icone(a.icone), num),
        el("span", { class: "barra__texto", text: a.texto }));
      if (a.contagem) contagens[a.contagem].link = link;
      return link;
    }));

    const mostrar = (chave, n) => {
      const c = contagens[chave];
      if (!c) return;
      c.num.hidden = !(n > 0);
      c.num.textContent = n > 9 ? "9+" : String(n);
      c.link.setAttribute("aria-label", n > 0 ? `${c.texto}, ${n}` : c.texto);
    };
    desligadores.push(aoMudarContagem((n) => mostrar("avisos", n)));
    if (contagens.pendencias) contarPendencias().then((r) => { if (r.ok) mostrar("pendencias", r.total); });
  }

  desenhar(null); // enquanto o perfil carrega (vem da memória depois da 1ª vez)
  meuPerfil().then((p) => { if (nav.isConnected || !nav.parentNode) desenhar(p); });
  return nav;
}
