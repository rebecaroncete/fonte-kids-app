// =====================================================================
// Tela: Grupos de WhatsApp (Fase 5 · Etapa 5D)   #/grupos-whatsapp
// Só liderança, pastores e admin (o banco confere).
// Dois grupos: crianças de 0 a 9 anos e de 10 a 12 anos (pela idade de hoje).
// Lista os responsáveis com criança na faixa e quem já está no grupo.
// • "Convidar": abre o WhatsApp da pessoa com a mensagem e o link do grupo
//   (o link vem do banco; nunca fica no código).
// • "Está no grupo": marca/desmarca (fica registrado quem marcou).
// • "Saiu da faixa": marcado no grupo, mas sem criança na faixa hoje.
// =====================================================================
import { el, montar, aviso, carregando, toast, mascararTelefone } from "../ui.js";
import { icone } from "../icones.js";
import { meuPerfil, gruposWhatsapp, marcarGrupoWhatsapp } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Grupos de WhatsApp";

const GRUPOS = [["0_9", "0 a 9 anos"], ["10_12", "10 a 12 anos"]];
const LINK_OK = /^https:\/\/chat\.whatsapp\.com\/[A-Za-z0-9]+$/;
const normalizar = (s) => String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();
const primeiro = (nome) => String(nome || "").trim().split(/\s+/)[0] || "";

let alvoTela = null;
const escolhas = { grupo: "0_9", filtro: "falta", busca: "" };

export async function render(alvo) {
  alvoTela = alvo;
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: titulo }), aviso("erro", perfil.erro)); return; }
  if (!perfil.temPapel("admin", "pastor", "lider")) {
    montar(alvo, el("h1", { text: titulo }), aviso("atencao", "Esta tela é só para a liderança do Fonte Kids."));
    return;
  }
  await desenhar();
}

async function desenhar() {
  const r = await gruposWhatsapp();
  if (!alvoTela?.isConnected) return;
  if (!r.ok) { montar(alvoTela, el("h1", { text: titulo }), aviso("erro", r.erro)); return; }
  const todos = r.responsaveis.map((p) => ({ ...p, busca: normalizar(p.nome) }));
  const links = r.links || {};

  const busca = el("input", { type: "search", class: "entrada", placeholder: "Buscar responsável", autocomplete: "off",
    "aria-label": "Buscar responsável", value: escolhas.busca });
  busca.addEventListener("input", () => { escolhas.busca = busca.value; atualizar(); });
  const chipsGrupo = el("div", { class: "chips" });
  const chipsFiltro = el("div", { class: "chips mt-2" });
  const avisoLink = el("div", {});
  const resumo = el("p", { class: "resumo-lista", role: "status" });
  const lista = el("ul", { class: "lista-compacta" });

  function doGrupo(p, g) {
    const faixa = g === "0_9" ? p.faixa_0_9 : p.faixa_10_12;
    const no = g === "0_9" ? p.no_0_9 : p.no_10_12;
    return { faixa, no };
  }

  function atualizar() {
    const g = escolhas.grupo;
    const conta = (f) => todos.filter((p) => f(doGrupo(p, g))).length;
    const FILTROS = [
      ["falta", `Falta convite (${conta((x) => x.faixa && !x.no)})`, (x) => x.faixa && !x.no],
      ["no", `No grupo (${conta((x) => x.no)})`, (x) => x.no],
      ["saiu", `Saiu da faixa (${conta((x) => x.no && !x.faixa)})`, (x) => x.no && !x.faixa],
    ];
    montar(chipsGrupo, GRUPOS.map(([v, t]) => el("button", { class: "chip", type: "button", text: t,
      "aria-pressed": String(g === v), onclick: () => { escolhas.grupo = v; atualizar(); } })));
    montar(chipsFiltro, FILTROS.map(([v, t]) => el("button", { class: "chip", type: "button", text: t,
      "aria-pressed": String(escolhas.filtro === v), onclick: () => { escolhas.filtro = v; atualizar(); } })));
    const link = links[g];
    montar(avisoLink, LINK_OK.test(link || "") ? null
      : aviso("atencao", "O link deste grupo não está configurado. O convite abre o WhatsApp sem o link."));

    const teste = FILTROS.find(([v]) => v === escolhas.filtro)?.[2] || (() => true);
    const termo = normalizar(escolhas.busca);
    const vis = todos.filter((p) => teste(doGrupo(p, g)) && (!termo || p.busca.includes(termo)));
    resumo.textContent = vis.length === 1 ? "1 responsável" : `${vis.length} responsáveis`;
    montar(lista, vis.length ? vis.map((p) => item(p, g, LINK_OK.test(link || "") ? link : null))
      : el("li", { class: "suave", text: "Ninguém nesta lista." }));
  }

  function item(p, g, link) {
    const { faixa, no } = doGrupo(p, g);
    const nomeGrupo = GRUPOS.find(([v]) => v === g)[1];
    const tel = String(p.telefone || "").replace(/\D/g, "");
    const texto = `Olá, ${primeiro(p.nome)}! Este é o convite para o grupo de WhatsApp dos responsáveis do Fonte Kids (crianças de ${nomeGrupo}).`
      + (link ? ` Para entrar, toque no link: ${link}` : "");
    const convidar = tel
      ? el("a", { class: "botao-icone botao-icone--whatsapp", href: `https://wa.me/${tel}?text=${encodeURIComponent(texto)}`,
          target: "_blank", rel: "noopener noreferrer", "aria-label": `Convidar ${p.nome} pelo WhatsApp` }, icone("conversa"))
      : null;
    const marcar = el("button", { class: "chip", type: "button", text: "No grupo", "aria-pressed": String(no),
      "aria-label": `${p.nome} está no grupo de ${nomeGrupo}: ${no ? "sim" : "não"}`,
      onclick: async () => {
        marcar.disabled = true;
        const r = await marcarGrupoWhatsapp(p.pessoa_id, g, !no);
        if (!r.ok) { marcar.disabled = false; toast("erro", r.erro); return; }
        if (g === "0_9") p.no_0_9 = !no; else p.no_10_12 = !no;
        toast("sucesso", !no ? `${primeiro(p.nome)} marcado(a) no grupo.` : `${primeiro(p.nome)} desmarcado(a) do grupo.`);
        atualizar();
      } });
    const linha = [
      tel ? mascararTelefone(tel) : "Sem telefone",
      !faixa && no ? "Sem criança nesta faixa" : null,
      p.tem_login ? null : "Sem login",
    ].filter(Boolean).join(" · ");
    return el("li", {}, el("div", { class: "item-compacto" },
      el("a", { class: "item-compacto__texto", href: p.familia_id ? `#/ficha?tipo=familia&id=${encodeURIComponent(p.familia_id)}` : null },
        el("span", { class: "item-compacto__nome", text: p.nome }),
        el("span", { class: "item-compacto__linha", text: linha })),
      el("span", { class: "item-compacto__etiquetas" }, marcar, convidar)));
  }

  montar(alvoTela,
    el("h1", { text: titulo }),
    el("p", { class: "suave", text: "Convide quem ainda não está no grupo e marque quem já entrou. O grupo certo depende da idade das crianças hoje." }),
    chipsGrupo, busca, chipsFiltro, avisoLink,
    el("div", { class: "mt-3" }, resumo, lista));
  atualizar();
}
