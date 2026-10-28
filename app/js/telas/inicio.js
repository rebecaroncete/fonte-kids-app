// =====================================================================
// Tela: Início como painel (Fase 10 · Etapa 7)
// Quem ainda não terminou o 1º acesso é levado antes para
// "#/primeiro-acesso" (js/app.js).
// Painel por papel: algo a completar (cartão amarelo, se houver),
// cartões de número, atalhos em grade e os avisos mais recentes.
//   Liderança/pastor/admin e recepção: números do departamento.
//   Responsável: números da própria família.
// Fase 5 · 5B: em dia de culto, recepção/liderança ganham o cartão "Check-in"
// no topo; o responsável vê o check-in de hoje dos filhos (sala e código).
// Fase 6: quem serve na escala vê a próxima vaga e a indisponibilidade a marcar.
// Fase 8: cartão "Próximos eventos" para todos (até 3, com link para o evento).
// Fase 9: liderança vê o "Último culto" (crianças, visitantes, primeira vez) → Indicadores.
// =====================================================================
import { el, montar, aviso, carregando } from "../ui.js";
import { icone } from "../icones.js";
import { estadoPrimeiroAcesso, meuPerfil, contarNaoLidas, contarPendencias, contarCadastros, listarNotificacoes,
  cultosDeHoje, meusCheckinsHoje, minhaEscala, proximosEventos, ultimoCulto } from "../supabase.js";
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

const quandoEvento = (iso) => {
  const d = new Date(iso);
  const t = d.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short", day: "2-digit", month: "2-digit" }).replace(".", "");
  return `${t.charAt(0).toUpperCase()}${t.slice(1)} · ${d.toLocaleTimeString("pt-BR", { timeZone: FUSO, hour: "2-digit", minute: "2-digit" })}`;
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

  // Check-in (Fase 5 · 5B)
  const fazCheckin = perfil.ok && perfil.temPapel("admin", "pastor", "lider", "recepcao");
  const ehResponsavel = perfil.ok && perfil.temPapel("responsavel");
  const serve = perfil.ok && perfil.temPapel("voluntaria");
  const [hojeCultos, meusHoje, escala, eventos, ultimo] = await Promise.all([
    fazCheckin ? cultosDeHoje() : null, ehResponsavel ? meusCheckinsHoje() : null, serve ? minhaEscala() : null,
    proximosEventos(), lideranca ? ultimoCulto() : null]);
  if (hojeCultos?.ok && hojeCultos.lista.length) {
    const c = hojeCultos.lista.find((x) => x.sugerido) || hojeCultos.lista[0];
    partes.push(el("section", { class: "cartao cartao--checkin-hoje" },
      el("span", { class: "numero__icone" }, icone("checkin")),
      el("div", { class: "flex-1" }, el("strong", { text: "Check-in" }), el("br"),
        el("span", { class: "suave", text: `${c.nome} · ${c.horario} · ${c.presentes} com check-in` })),
      el("a", { class: "botao botao--primario", href: "#/checkin", text: "Abrir" })));
  }
  if (meusHoje?.ok && meusHoje.lista.length) {
    partes.push(el("section", { class: "cartao" },
      el("div", { class: "secao-titulo sem-margem" }, el("h2", { text: "Check-in de hoje" })),
      el("ul", { class: "codigos-hoje mt-2" }, meusHoje.lista.map((k) => el("li", {},
        el("span", { class: "item-compacto__texto" },
          el("span", { class: "item-compacto__nome", text: k.nome }),
          el("span", { class: "item-compacto__linha", text: [`Sala ${String(k.sala_nome || "").replace(/ anos$/, "")}`, `${k.culto} ${k.horario}`, k.saiu ? "Saiu" : null].filter(Boolean).join(" · ") })),
        el("span", { class: "codigo-mini", "aria-label": `Código ${k.codigo}`, text: k.codigo }))))
      ,
      el("p", { class: "suave sem-margem mt-2", text: "Mostre o código na porta da sala na hora de buscar." })));
  }

  // Último culto (Fase 9, liderança)
  const u = ultimo?.ok ? ultimo.resultado : null;
  if (u) {
    const dia = new Date(`${u.data}T12:00:00`).toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short", day: "2-digit", month: "2-digit" }).replace(".", "");
    const linha = [`${u.presencas} ${u.presencas === 1 ? "criança" : "crianças"}`, `${u.visitantes} ${u.visitantes === 1 ? "visitante" : "visitantes"}`,
      u.primeira_vez ? `${u.primeira_vez} primeira vez` : null].filter(Boolean).join(" · ");
    partes.push(el("section", { class: "cartao cartao--compacto cartao--indicador" },
      el("span", { class: "numero__icone" }, icone("grafico")),
      el("div", { class: "flex-1" }, el("strong", { text: `Último culto · ${dia.charAt(0).toUpperCase()}${dia.slice(1)} ${u.hora}` }), el("br"),
        el("span", { class: "suave", text: linha })),
      el("a", { class: "botao botao--secundario botao--pequeno", href: "#/indicadores", text: "Indicadores" })));
  }

  // Escala (Fase 6)
  if (escala?.ok) {
    const { minhas = [], pedidos = [] } = escala.resultado || {};
    const prox = minhas.find((m) => !m.cancelado);
    if (prox) {
      const dia = new Date(`${prox.data}T12:00:00`).toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short", day: "2-digit", month: "2-digit" });
      const ciente = prox.resposta === "ciente";
      partes.push(el("section", { class: ciente ? "cartao cartao--compacto" : "cartao cartao--atencao cartao--compacto" },
        el("span", { class: "numero__icone" }, icone("calendario")),
        el("div", { class: "flex-1" }, el("strong", { text: "Sua próxima escala" }), el("br"),
          el("span", { class: "suave", text: `${dia} · ${prox.hora} · ${prox.sala}` })),
        el("a", { class: ciente ? "botao botao--secundario botao--pequeno" : "botao botao--primario botao--pequeno",
          href: "#/minha-escala", text: ciente ? "Ver" : "Confirmar" })));
    }
    for (const p of pedidos.filter((x) => !x.respondeu && (!x.prazo || x.prazo >= new Date().toLocaleDateString("en-CA", { timeZone: FUSO })))) {
      const prazo = p.prazo ? ` até ${p.prazo.slice(8, 10)}/${p.prazo.slice(5, 7)}` : "";
      partes.push(completar(`Indisponibilidade de ${p.nome_mes}`, `Só se tiver culto em que não pode${prazo}`, "#/minha-escala", "Marcar"));
    }
  }

  // Algo a completar (amarelo, com a ação principal da tela)
  if (est.etapa === "informar_relacoes") {
    partes.push(completar("Relação com as crianças", "Falta informar", "#/primeiro-acesso", "Informar"));
  } else if (!equipe && nPend > 0) {
    partes.push(completar(`${nPend} ${nPend > 1 ? "itens" : "item"} para completar`, "No cadastro da família", "#/minha-familia", "Completar"));
  }

  // Próximos eventos (Fase 8)
  const proximos = eventos?.ok ? eventos.resultado || [] : [];
  if (proximos.length) {
    partes.push(
      el("div", { class: "secao-titulo" }, el("h2", { text: "Próximos eventos" }), el("a", { href: "#/eventos", text: "Ver todos" })),
      el("ul", { class: "lista-compacta" }, proximos.map((e) => el("li", {},
        el("a", { class: "item-compacto", href: `#/eventos?id=${encodeURIComponent(e.id)}` },
          el("span", { class: "numero__icone" }, icone("calendario")),
          el("span", { class: "item-compacto__texto" },
            el("span", { class: "item-compacto__nome", text: e.titulo }),
            el("span", { class: "item-compacto__linha", text: [quandoEvento(e.inicio), e.local, e.aberta ? "Inscrições abertas" : null].filter(Boolean).join(" · ") })),
          icone("seta", null, "item-compacto__seta"))))));
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
       atalho("familia", "Voluntárias", "#/cadastros?aba=voluntarias"), atalho("calendario", "Escala", "#/escala")]
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
