// =====================================================================
// Tela: Voluntárias novas (Fase 5 · Etapa 5F)   #/voluntarias-novas
// Só liderança do Fonte Kids, pastores e admin (o banco confere).
// • "Convidar voluntária(o)": copiar o link do cadastro ou enviar pelo WhatsApp.
// • Pedidos que chegaram pelo link, com foto, dados e preferências.
//   - Telefone já usado por alguém do cadastro: escolher usar o mesmo cadastro.
//   - Menor de idade: lembrete de confirmar com o responsável.
// • Aprovar: cria a voluntária ativa (papéis voluntária + recepção) e o login
//   (senha inicial = data de nascimento, troca obrigatória).
// • Recusar: apaga os dados e a foto.
// =====================================================================
import { el, montar, aviso, carregando, toast, mascararTelefone, menuAcoes } from "../ui.js";
import { icone } from "../icones.js";
import { meuPerfil, pedidosVoluntaria, decidirPedidoVoluntaria, gerenciarLogin, enderecoCadastroVoluntaria } from "../supabase.js";
import { avatarLista, preencherFotos } from "../foto.js";
import { abrirJanela } from "../janela.js";

export const layout = "padrao";
export const titulo = "Voluntárias novas";

const FUNCOES = { professora: "Professor(a)", auxiliar: "Auxiliar" };
const FUSO = "America/Sao_Paulo";
const quandoBr = (iso) => new Date(iso).toLocaleString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
const dataBr = (iso) => { const [a, m, d] = String(iso || "").slice(0, 10).split("-"); return d ? `${d}/${m}/${a}` : "—"; };

let alvoTela = null;

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

/** Cartão "Convidar voluntária(o)": copiar o link ou enviar pelo WhatsApp. */
export function cartaoConvite() {
  const link = enderecoCadastroVoluntaria();
  const texto = `Olá! Que bom que você quer servir no Fonte Kids, o ministério infantil da igreja. Para se cadastrar como voluntário(a), preencha este formulário: ${link}`;
  const campo = el("input", { class: "entrada", type: "text", readonly: true, value: link, "aria-label": "Link do cadastro de voluntária(o)" });
  const copiar = el("button", { class: "botao botao--primario", type: "button" }, icone("check"), "Copiar link");
  copiar.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(link); toast("sucesso", "Link copiado."); }
    catch { campo.select(); toast("info", "Selecione o link e copie."); }
  });
  return el("section", { class: "cartao" },
    el("h2", { text: "Convidar voluntária(o)" }),
    el("p", { class: "suave", text: "Envie o link para quem quer servir. O cadastro chega aqui para você aprovar." }),
    campo,
    el("div", { class: "linha mt-3" }, copiar,
      el("a", { class: "botao botao--secundario", href: `https://wa.me/?text=${encodeURIComponent(texto)}`,
        target: "_blank", rel: "noopener noreferrer" }, icone("conversa"), "Enviar pelo WhatsApp")));
}

async function desenhar() {
  const r = await pedidosVoluntaria();
  if (!alvoTela?.isConnected) return;
  const lista = r.ok ? r.lista : [];
  montar(alvoTela,
    el("h1", { text: titulo }),
    cartaoConvite(),
    el("div", { class: "secao-titulo mt-5" }, el("h2", { text: `Aguardando aprovação (${lista.length})` })),
    !r.ok ? aviso("erro", r.erro)
      : lista.length ? lista.map(cartaoPedido)
      : el("p", { class: "suave", text: "Nenhum cadastro aguardando aprovação." }));
  preencherFotos(alvoTela);
}

function cartaoPedido(p) {
  const tel = String(p.telefone || "").replace(/\D/g, "");
  const menor = p.idade < 18;
  const outros = p.mesmo_telefone || [];
  const jaVoluntaria = outros.find((x) => x.voluntaria);

  // telefone já usado: escolher o cadastro (quem tem login vem primeiro)
  let escolha = null;
  if (outros.length && !jaVoluntaria) {
    const ordenados = [...outros].sort((a, b) => Number(b.tem_login) - Number(a.tem_login));
    const algumLogin = ordenados.some((x) => x.tem_login);
    escolha = el("select", { class: "entrada", "aria-label": "Qual cadastro usar" },
      ordenados.map((x) => el("option", { value: x.pessoa_id, text: `Usar o cadastro de ${x.nome}${x.tem_login ? " (já tem login)" : ""}` })),
      algumLogin ? null : el("option", { value: "", text: "Criar um cadastro novo" }));
  }

  const etiquetas = [
    el("span", { class: "etiqueta etiqueta--azul", text: FUNCOES[p.funcao] || p.funcao }),
    menor ? el("span", { class: "etiqueta etiqueta--laranja", text: "Menor de idade" }) : null,
    p.tem_foto ? null : el("span", { class: "etiqueta", text: "Sem foto" }),
  ].filter(Boolean);

  const aprovar = el("button", { class: "botao botao--primario", type: "button", text: "Aprovar", disabled: !!jaVoluntaria,
    onclick: () => confirmarAprovar(p, escolha ? escolha.value || null : null) });

  return el("section", { class: "cartao mt-3" },
    el("div", { class: "ficha-cabecalho" }, avatarLista("pedido_voluntaria", p.id, p.nome),
      el("div", { class: "flex-1" },
        el("h3", { class: "perfil-cabecalho__nome", text: p.nome }),
        el("p", { class: "item-compacto__linha", text: `${p.idade} anos · enviado em ${quandoBr(p.criado_em)}` }),
        el("div", { class: "linha mt-2" }, etiquetas)),
      menuAcoes([{ texto: "Recusar", perigo: true, acao: () => confirmarRecusar(p) }], `Mais ações para ${p.nome}`)),
    el("dl", { class: "dados mt-3" },
      el("dt", { text: "WhatsApp" }), el("dd", {},
        mascararTelefone(tel),
        tel ? el("a", { class: "botao-icone botao-icone--whatsapp", href: `https://wa.me/${tel}`, target: "_blank",
          rel: "noopener noreferrer", "aria-label": `Chamar ${p.nome} no WhatsApp` }, icone("conversa")) : null),
      el("dt", { text: "Nascimento" }), el("dd", { text: dataBr(p.nascimento) }),
      el("dt", { text: "Faixas de idade" }), el("dd", { text: (p.salas || []).join(", ") || "—" }),
      el("dt", { text: "Cultos" }), el("dd", { text: (p.cultos || []).join(", ") || "—" }),
      el("dt", { text: "E-mail" }), el("dd", { text: p.email || "—" }),
      el("dt", { text: "Profissão" }), el("dd", { text: p.profissao || "—" }),
      el("dt", { text: "Termo" }), el("dd", { text: `Aceito (versão ${p.termo_versao})` })),
    menor ? aviso("atencao", "Menor de idade: confirme com o pai, a mãe ou o responsável antes de aprovar.") : null,
    jaVoluntaria ? aviso("atencao", `Este telefone já é de ${jaVoluntaria.nome}, que já é voluntária. Recuse este pedido.`) : null,
    escolha ? el("div", { class: "mt-3" },
      aviso("info", "Este telefone já está no cadastro da igreja. Escolha qual cadastro usar (os dados existentes não são alterados)."),
      el("div", { class: "mt-2" }, escolha)) : null,
    el("div", { class: "linha mt-3" }, aprovar));
}

function confirmarAprovar(p, pessoaId) {
  abrirJanela({
    titulo: "Aprovar voluntária(o)",
    textoSalvar: "Aprovar",
    conteudo: [el("p", { text: `${p.nome} passa a ser voluntária(o) do Fonte Kids, com acesso ao check-in. Se ainda não tiver login, ele é criado agora (senha inicial = data de nascimento, só os números).` })],
    aoSalvar: async () => {
      const r = await decidirPedidoVoluntaria(p.id, "aprovar", pessoaId);
      if (!r.ok) return r.erro;
      if (!r.tem_login && r.pessoa_id) {
        const l = await gerenciarLogin({ acao: "criar", pessoa_id: r.pessoa_id });
        if (!l.ok) toast("atencao", `Aprovada(o), mas o login não foi criado: ${l.erro} Crie em Gestão de logins.`, 9000);
        else toast("sucesso", `${p.nome} aprovada(o). Login criado: a senha inicial é a data de nascimento (DDMMAAAA).`, 7000);
      } else {
        toast("sucesso", `${p.nome} aprovada(o). Já tinha login: agora tem acesso de voluntária(o).`, 7000);
      }
      await desenhar();
      return null;
    },
  });
}

function confirmarRecusar(p) {
  abrirJanela({
    titulo: "Recusar cadastro",
    textoSalvar: "Recusar e apagar",
    perigo: true,
    sucesso: "Cadastro recusado. Os dados e a foto foram apagados.",
    conteudo: [el("p", { text: `Os dados e a foto de ${p.nome} serão apagados. Se for o caso, avise a pessoa pelo WhatsApp.` })],
    aoSalvar: async () => {
      const r = await decidirPedidoVoluntaria(p.id, "recusar");
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}
