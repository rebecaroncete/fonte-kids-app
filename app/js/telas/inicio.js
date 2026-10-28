// =====================================================================
// Tela: Início como painel (Fase 10 · Etapa 7)
// Quem ainda não terminou o 1º acesso é levado antes para
// "#/primeiro-acesso" (js/app.js).
// Painel por papel: algo a completar (cartão amarelo, se houver),
// cartões de número, atalhos em grade e os avisos mais recentes.
//   Liderança/pastor/admin e recepção: números do departamento.
//   Responsável: números da própria família.
// Fase 5: em dia de culto, a recepção ganha o cartão "Check-in" no topo.
// =====================================================================
import { el, montar, aviso, carregando } from "../ui.js";
import { icone } from "../icones.js";
import { estadoPrimeiroAcesso, meuPerfil, contarNaoLidas, contarPendencias, contarCadastros, listarNotificacoes } from "../supabase.js";
import { tipoDeBarra } from "../casca.js";

export const layout = "padrao";
export const titulo = "Início";

const FUSO = "America/Sao_Paulo";
const hoje = () => {
  const t = new Date().toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "long", day: "numeric", month: "long" });
  return t.charAt(0).toUpperCase() + t.slice(1);
};
const quando = (iso) => {
  const d = new Date(iso);
  const dia = d.toLocaleDateString("pt-BR", { timeZone: FUSO });
  return dia === new Date().toLocaleDateString("pt-BR", { timeZone: FUSO })
    ? `Hoje, ${d.toLocaleTimeString("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" })}`
    : d.toLocaleDateString("pt-BR", { timeZone: FUSO, day: "numeric", month: "short" });
};

function numero(nomeIcone, valor, rotulo, href, variante) {
  if (valor === null || valor === undefined) return null;
  return el("a", { class: `numero${variante ? " numero--" + variante : ""}`, href },
    el("span", { class: "numero__icone" }, icone(nomeIcone)),
    el("span", {}, el("span", { class: "numero__valor", text: String(valor) }), el("span", { class: "numero__rotulo", text: rotulo })));
}

function atalho(nomeIcone, rotulo, href) {
  return el("a", { class: "atalhos__item", href }, el("span", { class: "atalhos__icone" }, icone(nomeIcone)), rotulo);
}

function completar(titulo, texto, href, botao) {
  return el("section", { class: "cartao cartao--atencao cartao--compacto" },
    el("span", { class: "numero__icone" }, icone("pendencias")),
    el("div", { class: "flex-1" }, el("strong", { text: titulo }), el("br"), el("span", { class: "suave", text: texto })),
    el("a", { class: "botao botao--primario botao--pequeno", href, text: botao }));
}

export async function render(alvo) {
  montar(alvo, carregando());
  const [est, perfil, notif, pend, cad, lista] = await Promise.all([
    estadoPrimeiroAcesso(), meuPerfil(), contarNaoLidas(), contarPendencias(), contarCadastros(), listarNotificacoes()]);

  if (!est.ok) {
    montar(alvo, el("h1", { text: "Início" }), aviso("erro", "Não foi possível carregar seus dados agora. Tente recarregar a página."));
    return;
  }
  if (est.etapa === "sem_acesso") {
    montar(alvo, el("h1", { text: "Início" }), aviso("erro", "Seu acesso não está ativo. Fale com a liderança do Fonte Kids."));
    return;
  }

  const tipo = tipoDeBarra(perfil);
  const equipe = tipo === "lideranca" || tipo === "equipe";
  const lideranca = tipo === "lideranca";
  const primeiroNome = perfil.ok && perfil.nome ? perfil.nome.trim().split(/\s+/)[0] : "";
  const nNotif = notif.ok ? notif.total : null;
  const nPend = pend.ok ? pend.total : null;

  const partes = [
    el("div", { class: "saudacao" },
      el("h1", { text: primeiroNome ? `Olá, ${primeiroNome}` : "Olá" }),
      el("p", { class: "suave", text: hoje() })),
  ];

  // Algo a completar (amarelo, com a ação principal da tela)
  if (est.etapa === "informar_relacoes") {
    partes.push(completar("Relação com as crianças", "Falta informar", "#/primeiro-acesso", "Informar"));
  } else if (!equipe && nPend > 0) {
    partes.push(completar(`${nPend} ${nPend > 1 ? "itens" : "item"} para completar`, "No cadastro da família", "#/minha-familia", "Completar"));
  }

  // Números
  const numeros = equipe
    ? [numero("crianca", cad.criancas, "Crianças", "#/cadastros?aba=criancas", "destaque"),
       perfil.temPapel("admin", "pastor", "lider", "recepcao") ? numero("inicio", cad.familias, "Famílias", "#/cadastros?aba=familias") : null,
       perfil.temPapel("admin", "pastor", "lider", "recepcao") ? numero("pendencias", nPend, "Pendências", "#/pendencias", nPend > 0 ? "atencao" : null) : null,
       numero("avisos", nNotif, nNotif === 1 ? "Aviso novo" : "Avisos novos", "#/notificacoes")]
    : [numero("crianca", cad.criancas, cad.criancas === 1 ? "Criança" : "Crianças", "#/minha-familia", "destaque"),
       numero("autorizados", cad.autorizados, cad.autorizados === 1 ? "Autorizado" : "Autorizados", "#/minha-familia"),
       numero("avisos", nNotif, nNotif === 1 ? "Aviso novo" : "Avisos novos", "#/notificacoes")];
  const visiveis = numeros.filter(Boolean);
  partes.push(el("div", { class: visiveis.length === 3 ? "numeros numeros--tres" : "numeros" }, visiveis));

  // Atalhos
  const atalhos = lideranca
    ? [atalho("crianca", "Crianças", "#/cadastros?aba=criancas"), atalho("inicio", "Famílias", "#/cadastros?aba=familias"),
       atalho("familia", "Voluntárias", "#/cadastros?aba=voluntarias"), atalho("logins", "Logins", "#/logins")]
    : equipe
      ? [atalho("crianca", "Crianças", "#/cadastros?aba=criancas"),
         perfil.temPapel("recepcao") ? atalho("inicio", "Famílias", "#/cadastros?aba=familias") : null,
         perfil.temPapel("recepcao") ? atalho("pendencias", "Pendências", "#/pendencias") : null,
         atalho("perfil", "Perfil", "#/perfil")]
      : [atalho("familia", "Família", "#/minha-familia"), atalho("autorizados", "Autorizados", "#/minha-familia"),
         atalho("perfil", "Perfil", "#/perfil"), atalho("senha", "Senha", "#/trocar-senha")];
  partes.push(
    el("div", { class: "secao-titulo" }, el("h2", { text: "Atalhos" })),
    el("div", { class: "atalhos" }, atalhos.filter(Boolean)));

  // Avisos recentes
  const recentes = lista.ok ? lista.lista.slice(0, 3) : [];
  if (recentes.length) {
    partes.push(
      el("div", { class: "secao-titulo" }, el("h2", { text: "Avisos recentes" }), el("a", { href: "#/notificacoes", text: "Ver todos" })),
      el("ul", { class: "lista-compacta" }, recentes.map((n) => el("li", {},
        el("a", { class: "item-compacto", href: "#/notificacoes" },
          el("span", { class: n.lida_em ? "item-compacto__ponto item-compacto__ponto--lido" : "item-compacto__ponto", "aria-hidden": "true" }),
          el("span", { class: "item-compacto__texto" },
            el("span", { class: "item-compacto__nome", text: n.titulo || "Aviso" }),
            el("span", { class: "item-compacto__linha", text: (n.lida_em ? "" : "Novo · ") + quando(n.criado_em) })),
          icone("seta", null, "item-compacto__seta"))))));
  }

  montar(alvo, partes);
}
