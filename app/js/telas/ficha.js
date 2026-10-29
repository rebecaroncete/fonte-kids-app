// =====================================================================
// Tela: Ficha (Fase 10 · Etapa 5B) – só leitura
//   #/ficha?tipo=crianca&id=…   criança (foto, sala, cuidados, responsáveis,
//                               autorizados, irmãos, histórico – Fase 5 · 5E)
//   #/ficha?tipo=familia&id=…   família (responsáveis, autorizados, crianças)
//   #/ficha?tipo=voluntaria&id=… voluntária (só liderança ou ela mesma)
//                               Fase 8: a liderança edita (função, contato,
//                               faixas e cultos) e desativa/reativa.
//                               0.28.0: "Trocar telefone" (contato e login
//                               juntos, pela Edge Function gerenciar-login).
// O banco (RLS) decide o que cada login pode ver. Foto pela Edge Function
// foto-assinada (link de 5 min). Telefones com botão de WhatsApp (wa.me).
// Foto dos responsáveis (Etapa 5C) para conferir quem retira a criança.
// =====================================================================
import { el, montar, aviso, carregando, mascararTelefone, telefoneParaLogin, iniciais, menuAcoes, toast } from "../ui.js";
import { icone } from "../icones.js";
import { fichaCrianca, fichaFamilia, fichaVoluntaria, listarSalas, meuPerfil, definirStatusVoluntaria, gerenciarLogin } from "../supabase.js";
import { abrirJanela, campo } from "../janela.js";
import { janelaPreferencias } from "../preferencias-voluntaria.js";
import { janelaNovaCrianca } from "../nova-crianca.js";
import { avatarComFoto, avatarLista, preencherFotos } from "../foto.js";
import { idade, textoIdade, salaDaCrianca } from "./cadastros.js";
import { secaoHistorico } from "../historico.js";

export const layout = "padrao";
export const titulo = "Ficha";

const RELACOES = {
  mae: "Mãe", pai: "Pai", madrasta: "Madrasta", padrasto: "Padrasto", avo: "Avô/Avó",
  tio: "Tio/Tia", irmao: "Irmão/Irmã", responsavel_legal: "Responsável legal", conjuge: "Cônjuge", outro: "Outro",
};
const NOMES_FUNCAO = { professora: "Professora", auxiliar: "Auxiliar" };
const NOMES_STATUS = { ativa: "Ativa", pendente: "Aguardando aprovação", inativa: "Inativa" };
const FUSO = "America/Sao_Paulo";

function parametro(nome) {
  return new URLSearchParams(location.hash.split("?")[1] || "").get(nome);
}

const dataBr = (iso) => {
  if (!iso) return "—";
  const [a, m, d] = iso.slice(0, 10).split("-");
  return `${d}/${m}/${a}`;
};

/** Botão redondo do WhatsApp, só para telefone no padrão 55 + DDD + número. */
function botaoWhatsapp(telefone, nome) {
  const d = String(telefone || "").replace(/\D/g, "");
  if (!/^55[1-9][0-9]9?[0-9]{8}$/.test(d)) return null;
  return el("a", {
    class: "botao-icone botao-icone--whatsapp", href: `https://wa.me/${d}`,
    target: "_blank", rel: "noopener noreferrer", "aria-label": `Chamar ${nome || "contato"} no WhatsApp`,
  }, icone("conversa"));
}

/** Linha de uma pessoa de contato (responsável ou autorizada): foto, nome, 1 linha, WhatsApp. */
function contato(nome, detalhes, telefone, etiquetas = [], avatar = null) {
  return el("li", {}, el("div", { class: "item-compacto" },
    avatar || el("div", { class: "avatar", "aria-hidden": "true", text: iniciais(nome) }),
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: nome || "Sem nome" }),
      el("span", { class: "item-compacto__linha", text: [...detalhes.filter(Boolean), telefone ? mascararTelefone(telefone) : "Sem telefone"].join(" · ") })),
    etiquetas.length ? el("span", { class: "item-compacto__etiquetas" }, etiquetas) : null,
    telefone ? botaoWhatsapp(telefone, nome) : null));
}

/** Seção em cartão (dados) */
function secao(tituloSecao, ...conteudo) {
  return el("section", { class: "cartao" }, el("h2", { text: tituloSecao }), ...conteudo);
}
/** Seção de lista (título + lista compacta, sem cartão em volta) */
function secaoLista(tituloSecao, ...conteudo) {
  // 1º item pode ser uma ação (botão) para ficar ao lado do título
  const acao = conteudo[0] instanceof HTMLButtonElement ? conteudo.shift() : null;
  if (conteudo[0] === null) conteudo.shift();
  return el("section", { class: "secao-lista" }, el("div", { class: "secao-titulo" }, el("h2", { text: tituloSecao }), acao), ...conteudo);
}

/** Cabeçalho da ficha: foto, nome, etiquetas (alergia sempre primeiro, em vermelho). */
function cabecalho(avatar, nome, linhas, etiquetas = []) {
  return el("section", { class: "ficha-cabecalho" }, avatar,
    el("div", { class: "flex-1" },
      el("h1", { class: "perfil-cabecalho__nome", text: nome || "Sem nome" }),
      ...linhas.filter(Boolean).map((t) => el("p", { class: "item-compacto__linha", text: t })),
      etiquetas.length ? el("div", { class: "linha mt-2" }, etiquetas) : null));
}

function voltar(aba) {
  return el("p", { class: "voltar" }, el("a", { class: "botao botao--texto botao--pequeno", href: `#/cadastros?aba=${aba}` },
    icone("voltar"), "Voltar"));
}

const nomeRelacao = (rel) => (rel.tipo === "outro" && rel.detalhe ? rel.detalhe : RELACOES[rel.tipo] || rel.tipo);

/** extras (opcional): Map(pessoaId → [linhas]) – ex.: relações com cada criança e cônjuge (ficha da família). */
function listaResponsaveis(responsaveis, relacoes, extras = null) {
  if (!responsaveis.length) return el("p", { class: "suave", text: "Nenhum responsável visível." });
  const ordenados = [...responsaveis].sort((a, b) => Number(b.principal) - Number(a.principal));
  return el("ul", { class: "lista-compacta" }, ordenados.map((r) => {
    const rel = relacoes?.get(r.pessoa?.id);
    const textoRel = rel ? nomeRelacao(rel) : null;
    return contato(r.pessoa?.nome, [textoRel, ...(extras?.get(r.pessoa?.id) || [])], r.pessoa?.telefone,
      r.principal ? [el("span", { class: "etiqueta etiqueta--azul", text: "Principal" })] : [],
      r.pessoa?.id ? avatarLista("pessoa", r.pessoa.id, r.pessoa?.nome) : null);
  }));
}

function listaAutorizadas(autorizadas) {
  if (!autorizadas.length) return el("p", { class: "suave", text: "Nenhuma pessoa autorizada além dos responsáveis." });
  return el("ul", { class: "lista-compacta" }, autorizadas.map((a) => contato(a.pessoa?.nome, [a.observacao], a.pessoa?.telefone)));
}

// ---------------- Criança ----------------
async function desenharCrianca(alvo, id) {
  const [r, rs] = await Promise.all([fichaCrianca(id), listarSalas()]);
  const salas = rs.ok ? rs.lista : [];
  if (!r.ok) { montar(alvo, voltar("criancas"), aviso(r.naoEncontrada ? "atencao" : "erro", r.erro)); return; }
  const c = r.crianca;
  const nome = c.pessoa?.nome || "Sem nome";
  document.title = `${nome} · Fonte Kids`;

  // Responsáveis ligados a esta criança primeiro; se nenhum estiver ligado, mostra os da família.
  const ligados = r.responsaveis.filter((x) => (x.responsaveis_criancas || []).some((rc) => rc.crianca_id === id));
  const outros = r.responsaveis.filter((x) => !ligados.includes(x));
  const mostrar = ligados.length ? ligados : r.responsaveis;

  const anos = idade(c.pessoa?.data_nascimento);
  const sala = salaDaCrianca(c.sala_fixa_id, anos, salas);
  const etiquetas = [
    c.alergias_observacoes ? el("span", { class: "etiqueta etiqueta--alergia" }, icone("alergia"), "Alergia / cuidados") : null,
    el("span", { class: sala.sala ? "etiqueta etiqueta--azul" : "etiqueta", text: sala.sala ? `Sala ${sala.sala.nome}` : "Sem sala" }),
    c.perfil === "visitante" ? el("span", { class: "etiqueta etiqueta--laranja", text: "Visitante" }) : null,
    !c.ativo ? el("span", { class: "etiqueta etiqueta--neutra", text: "Inativa" }) : null,
  ].filter(Boolean);

  montar(alvo,
    voltar("criancas"),
    cabecalho(avatarComFoto("crianca", c.id, nome), nome,
      [`${textoIdade(anos)} · nasc. ${dataBr(c.pessoa?.data_nascimento)}`,
       sala.sala && !sala.porIdade ? "Sala definida pela liderança" : (sala.sala ? null : sala.motivo)], etiquetas),
    c.alergias_observacoes
      ? el("div", { class: "cuidados", role: "note" },
          icone("alergia"), el("div", {}, el("strong", { text: "Alergias e cuidados" }), el("p", { text: c.alergias_observacoes })))
      : null,
    secaoLista("Responsáveis", listaResponsaveis(mostrar, r.relacoes),
      ligados.length && outros.length ? el("p", { class: "suave mt-2", text: `Outros da família: ${outros.map((o) => o.pessoa?.nome).filter(Boolean).join(", ")}` }) : null),
    secaoLista("Autorizados a retirar", listaAutorizadas(r.autorizadas)),
    r.irmaos.length ? secaoLista("Irmãos", el("ul", { class: "lista-compacta" }, r.irmaos.map((i) => el("li", {},
      el("a", { class: "item-compacto", href: `#/ficha?tipo=crianca&id=${encodeURIComponent(i.id)}` },
        avatarLista("crianca", i.id, i.pessoa?.nome),
        el("span", { class: "item-compacto__texto" },
          el("span", { class: "item-compacto__nome", text: i.pessoa?.nome || "Sem nome" }),
          i.ativo ? null : el("span", { class: "item-compacto__linha", text: "Inativa" })),
        icone("seta", null, "item-compacto__seta")))))) : null,
    secaoHistorico(c.id, nome),
    el("p", { class: "mt-5" }, el("a", { class: "botao botao--secundario", href: `#/ficha?tipo=familia&id=${encodeURIComponent(c.familia_id)}`, text: "Ver família" })));
  preencherFotos(alvo);
}

// ---------------- Família ----------------
async function desenharFamilia(alvo, id) {
  const [r, rs] = await Promise.all([fichaFamilia(id), listarSalas()]);
  const salas = rs.ok ? rs.lista : [];
  if (!r.ok) { montar(alvo, voltar("familias"), aviso(r.naoEncontrada ? "atencao" : "erro", r.erro)); return; }
  const principal = r.responsaveis.find((x) => x.principal) || r.responsaveis[0];
  const nome = principal?.pessoa?.nome ? `Família de ${principal.pessoa.nome}` : "Família";
  document.title = `${nome} · Fonte Kids`;
  const criancas = [...r.criancas].sort((a, b) => Number(b.ativo) - Number(a.ativo));
  const perfil = await meuPerfil();
  const podeIncluir = perfil.ok && perfil.temPapel("admin", "pastor", "lider", "recepcao");
  const podeFoto = perfil.ok && perfil.temPapel("admin", "pastor", "lider");

  montar(alvo,
    voltar("familias"),
    el("h1", { text: nome }),
    secaoLista("Crianças", podeIncluir ? el("button", {
        class: "botao botao--secundario botao--pequeno", type: "button",
        onclick: () => janelaNovaCrianca({ familiaId: id, comRelacao: false, comFoto: podeFoto, aoIncluir: () => desenharFamilia(alvo, id) }),
      }, icone("adicionar"), "Adicionar") : null, criancas.length
      ? el("ul", { class: "lista-compacta" }, criancas.map((c) => {
          const anos = idade(c.pessoa?.data_nascimento);
          const sala = salaDaCrianca(c.sala_fixa_id, anos, salas);
          return el("li", {}, el("a", { class: "item-compacto", href: `#/ficha?tipo=crianca&id=${encodeURIComponent(c.id)}` },
            avatarLista("crianca", c.id, c.pessoa?.nome),
            el("span", { class: "item-compacto__texto" },
              el("span", { class: "item-compacto__nome", text: c.pessoa?.nome || "Sem nome" }),
              el("span", { class: "item-compacto__linha", text: [textoIdade(anos), sala.sala ? `Sala ${sala.sala.nome}` : "Sem sala", c.ativo ? null : "Inativa"].filter(Boolean).join(" · ") })),
            icone("seta", null, "item-compacto__seta")));
        }))
      : el("p", { class: "suave", text: "Nenhuma criança visível." })),
    secaoLista("Responsáveis", listaResponsaveis(r.responsaveis, null, linhasDaFamilia(r))),
    secaoLista("Autorizados a retirar", listaAutorizadas(r.autorizadas)),
    r.familia.observacoes ? secao("Observações", el("p", { text: r.familia.observacoes })) : null);
  preencherFotos(alvo);
}

/** Para cada responsável: "Pai de Ana · Pai de Bia" e "Cônjuge/parceiro(a) de …". */
function linhasDaFamilia(r) {
  const primeiro = (n) => (n || "").trim().split(/\s+/)[0] || "";
  const nomePorPessoa = new Map([
    ...r.responsaveis.map((x) => [x.pessoa?.id, x.pessoa?.nome]),
    ...r.criancas.map((c) => [c.pessoa?.id, c.pessoa?.nome]),
  ]);
  const criancasPessoa = new Set(r.criancas.map((c) => c.pessoa?.id));
  const mapa = new Map();
  for (const x of r.responsaveis) {
    const pid = x.pessoa?.id;
    if (!pid) continue;
    const comCriancas = (r.relacoes || []).filter((y) => y.tipo !== "conjuge" &&
      ((y.pessoa_id === pid && criancasPessoa.has(y.relacionada_id)) || (y.relacionada_id === pid && criancasPessoa.has(y.pessoa_id))))
      .map((y) => `${nomeRelacao(y)} de ${primeiro(nomePorPessoa.get(y.pessoa_id === pid ? y.relacionada_id : y.pessoa_id))}`);
    const conjuges = (r.relacoes || []).filter((y) => y.tipo === "conjuge" && (y.pessoa_id === pid || y.relacionada_id === pid))
      .map((y) => nomePorPessoa.get(y.pessoa_id === pid ? y.relacionada_id : y.pessoa_id)).filter(Boolean);
    mapa.set(pid, [
      comCriancas.length ? comCriancas.join(" · ") : "Relação não informada",
      conjuges.length ? `Cônjuge de ${conjuges.map(primeiro).join(", ")}` : null,
    ]);
  }
  return mapa;
}

// ---------------- Voluntária ----------------
async function desenharVoluntaria(alvo, id) {
  const [r, rs, perfil] = await Promise.all([fichaVoluntaria(id), listarSalas(), meuPerfil()]);
  if (!r.ok) { montar(alvo, voltar("voluntarias"), aviso(r.naoEncontrada ? "atencao" : "erro", r.erro)); return; }
  const v = r.voluntaria;
  const nome = v.pessoa?.nome || "Sem nome";
  document.title = `${nome} · Fonte Kids`;
  const anos = idade(v.pessoa?.data_nascimento);
  const nomeSala = new Map((rs.ok ? rs.lista : []).map((s) => [s.id, s.nome]));
  const salas = (v.salas_preferidas || []).map((s) => nomeSala.get(s)).filter(Boolean);

  const lider = perfil.ok && perfil.temPapel("admin", "pastor", "lider");
  const redesenhar = () => desenharVoluntaria(alvo, id);
  const acoes = lider ? el("div", { class: "cartao-topo mt-3" },
    el("div", { class: "flex-1 linha" },
      el("button", { class: "botao botao--secundario botao--pequeno", type: "button", onclick: () => janelaPreferencias(v.id, redesenhar) },
        icone("editar"), "Editar")),
    menuAcoes([
      { texto: "Trocar telefone", acao: () => janelaTelefone(v, nome, redesenhar) },
      v.status === "ativa"
        ? { texto: "Desativar voluntária", perigo: true, acao: () => confirmarStatus(v, nome, false, redesenhar) }
        : { texto: "Reativar voluntária", acao: () => confirmarStatus(v, nome, true, redesenhar) },
    ], `Mais ações para ${nome}`)) : null;

  montar(alvo,
    voltar("voluntarias"),
    acoes,
    cabecalho(avatarComFoto("voluntaria", v.id, nome), nome,
      [NOMES_FUNCAO[v.funcao] || null, `${textoIdade(anos)} · nasc. ${dataBr(v.pessoa?.data_nascimento)}`],
      [el("span", { class: v.status === "ativa" ? "etiqueta etiqueta--sucesso" : "etiqueta etiqueta--laranja", text: NOMES_STATUS[v.status] || v.status }),
       anos !== null && anos < 18 ? el("span", { class: "etiqueta", text: "Menor de idade" }) : null].filter(Boolean)),
    secaoLista("Contato", el("ul", { class: "lista-compacta" }, contato(nome, [v.email || null], v.pessoa?.telefone))),
    secao("Dados", el("dl", { class: "dados" },
      el("dt", { text: "Profissão" }), el("dd", { text: v.profissao || "—" }),
      el("dt", { text: "Salas preferidas" }), el("dd", { text: salas.length ? salas.join(", ") : "—" }),
      el("dt", { text: "Cultos preferidos" }), el("dd", { text: r.cultos.length ? r.cultos.join(", ") : "—" }),
      el("dt", { text: "Máximo de escalas por mês" }), el("dd", { text: v.teto_mensal ? String(v.teto_mensal) : "Padrão do departamento" }),
      el("dt", { text: "Aprovada em" }), el("dd", { text: v.aprovada_em ? dataBr(v.aprovada_em) : "—" }))));
}

/** Trocar o telefone: muda o contato e, se ela tiver login, o login junto (a senha não muda). */
function janelaTelefone(v, nome, redesenhar) {
  const atual = v.pessoa?.telefone ? mascararTelefone(v.pessoa.telefone) : "";
  const tel = el("input", { class: "entrada", type: "tel", inputmode: "numeric", autocomplete: "off",
    placeholder: "(27) 90000-0000", value: atual });
  tel.addEventListener("input", () => { tel.value = mascararTelefone(tel.value); });
  abrirJanela({
    titulo: "Trocar telefone",
    conteudo: [
      campo("WhatsApp com DDD", tel),
      aviso("info", `Se ${nome} já tiver login, ela passa a entrar com o número novo e a mesma senha.`),
    ],
    aoSalvar: async () => {
      const novo = telefoneParaLogin(tel.value);
      if (!novo) return "Digite o WhatsApp com DDD.";
      const r = await gerenciarLogin({ acao: "trocar_telefone", pessoa_id: v.pessoa?.id, telefone: novo });
      if (!r.ok) return r.erro;
      toast("sucesso", r.sem_mudanca ? "O telefone já era esse." : r.tem_login ? "Telefone e login trocados." : "Telefone trocado.");
      await redesenhar();
      return null;
    },
  });
}

/** Desativar (sai dos rascunhos de escala e perde os papéis) ou reativar. */
function confirmarStatus(v, nome, ativar, redesenhar) {
  abrirJanela({
    titulo: ativar ? "Reativar voluntária?" : "Desativar voluntária?",
    conteudo: [el("p", { text: ativar
      ? `${nome} volta a entrar nas próximas escalas e recebe de volta o acesso de voluntária e recepção.`
      : `${nome} sai das vagas dos meses ainda em rascunho, das ajudas em eventos e perde o acesso de voluntária e recepção. As escalas já publicadas não mudam (troque as vagas dela em "Escala do mês"). O login continua.` })],
    textoSalvar: ativar ? "Reativar" : "Desativar",
    perigo: !ativar,
    aoSalvar: async () => {
      const r = await definirStatusVoluntaria(v.id, ativar);
      if (!r.ok) return r.erro;
      const vagas = r.resultado?.vagas || 0;
      const extra = !ativar && vagas ? ` ${vagas === 1 ? "1 vaga ficou aberta" : `${vagas} vagas ficaram abertas`} no rascunho.` : "";
      toast("sucesso", `${ativar ? "Voluntária reativada." : "Voluntária desativada."}${extra}`);
      await redesenhar();
      return null;
    },
  });
}

const TIPOS = { crianca: desenharCrianca, familia: desenharFamilia, voluntaria: desenharVoluntaria };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function render(alvo) {
  const tipo = parametro("tipo");
  const id = parametro("id");
  const desenhar = TIPOS[tipo];
  if (!desenhar || !UUID.test(id || "")) {
    montar(alvo, el("h1", { text: "Ficha" }), aviso("atencao", "Endereço de ficha inválido."), voltar("criancas"));
    return;
  }
  montar(alvo, carregando());
  await desenhar(alvo, id);
}
