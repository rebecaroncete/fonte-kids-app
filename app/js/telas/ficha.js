// =====================================================================
// Tela: Ficha (Fase 10 · Etapa 5B) – só leitura
//   #/ficha?tipo=crianca&id=…   criança (foto, sala, cuidados, responsáveis,
//                               autorizados, irmãos, último check-in)
//   #/ficha?tipo=familia&id=…   família (responsáveis, autorizados, crianças)
//   #/ficha?tipo=voluntaria&id=… voluntária (só liderança ou ela mesma)
// O banco (RLS) decide o que cada login pode ver. Foto pela Edge Function
// foto-assinada (link de 5 min). Telefones com botão de WhatsApp (wa.me).
// Foto dos responsáveis (Etapa 5C) para conferir quem retira a criança.
// =====================================================================
import { el, montar, aviso, carregando, mascararTelefone } from "../ui.js";
import { fichaCrianca, fichaFamilia, fichaVoluntaria, listarSalas } from "../supabase.js";
import { avatarComFoto, avatarLista, preencherFotos } from "../foto.js";
import { idade, textoIdade, salaDaCrianca, textoSala } from "./cadastros.js";

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
const quandoBr = (iso) => new Date(iso).toLocaleString("pt-BR", {
  timeZone: FUSO, day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit",
});

/** Link do WhatsApp só para telefone no padrão 55 + DDD + número. */
function botaoWhatsapp(telefone, nome) {
  const d = String(telefone || "").replace(/\D/g, "");
  if (!/^55[1-9][0-9]9?[0-9]{8}$/.test(d)) return null;
  return el("a", {
    class: "botao botao--pequeno botao--whatsapp", href: `https://wa.me/${d}`,
    target: "_blank", rel: "noopener noreferrer", "aria-label": `Chamar ${nome} no WhatsApp`,
    text: "Chamar no WhatsApp",
  });
}

/** Cartão de uma pessoa de contato (responsável ou autorizada). */
function contato(nome, detalhes, telefone, etiquetas = [], avatar = null) {
  const texto = [
    el("p", { class: "notif__titulo", text: nome || "Sem nome" }),
    ...detalhes.filter(Boolean).map((t) => el("p", { class: "notif__quando", text: t })),
    etiquetas.length ? el("div", { class: "linha" }, etiquetas) : null,
    el("p", { class: "notif__corpo", text: telefone ? mascararTelefone(telefone) : "Sem telefone no cadastro" }),
  ];
  return el("li", { class: "notif" },
    avatar ? el("div", { class: "linha" }, avatar, el("div", {}, ...texto)) : texto,
    telefone ? el("div", { class: "linha" }, botaoWhatsapp(telefone, nome)) : null);
}

function secao(tituloSecao, ...conteudo) {
  return el("section", { class: "cartao" }, el("h2", { text: tituloSecao }), ...conteudo);
}

function cabecalho(avatar, nome, linhas, etiquetas = []) {
  return el("section", { class: "cartao" },
    el("div", { class: "perfil-cabecalho" }, avatar,
      el("div", {},
        el("h1", { class: "perfil-cabecalho__nome", text: nome || "Sem nome" }),
        ...linhas.filter(Boolean).map((t) => el("p", { class: "notif__quando", text: t })),
        etiquetas.length ? el("div", { class: "linha" }, etiquetas) : null)));
}

function voltar(aba) {
  return el("p", {}, el("a", {
    class: "botao botao--pequeno", href: `#/cadastros?aba=${aba}`, text: "← Voltar à lista",
  }));
}

const nomeRelacao = (rel) => (rel.tipo === "outro" && rel.detalhe ? rel.detalhe : RELACOES[rel.tipo] || rel.tipo);

/** extras (opcional): Map(pessoaId → [linhas]) – ex.: relações com cada criança e cônjuge (ficha da família). */
function listaResponsaveis(responsaveis, relacoes, extras = null) {
  if (!responsaveis.length) return el("p", { class: "suave", text: "Nenhum responsável visível." });
  const ordenados = [...responsaveis].sort((a, b) => Number(b.principal) - Number(a.principal));
  return el("ul", { class: "lista" }, ordenados.map((r) => {
    const rel = relacoes?.get(r.pessoa?.id);
    const textoRel = rel ? nomeRelacao(rel) : null;
    return contato(r.pessoa?.nome, [textoRel ? `Relação: ${textoRel}` : null, ...(extras?.get(r.pessoa?.id) || [])], r.pessoa?.telefone,
      r.principal ? [el("span", { class: "etiqueta etiqueta--azul", text: "Principal" })] : [],
      r.pessoa?.id ? avatarLista("pessoa", r.pessoa.id, r.pessoa?.nome) : null);
  }));
}

function listaAutorizadas(autorizadas) {
  if (!autorizadas.length) return el("p", { class: "suave", text: "Nenhuma pessoa autorizada além dos responsáveis." });
  return el("ul", { class: "lista" }, autorizadas.map((a) => contato(a.pessoa?.nome, [a.observacao], a.pessoa?.telefone)));
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

  const etiquetas = [
    c.perfil === "visitante" ? el("span", { class: "etiqueta etiqueta--azul", text: "Visitante" }) : null,
    !c.ativo ? el("span", { class: "etiqueta", text: "Inativa" }) : null,
  ].filter(Boolean);

  const uc = r.ultimoCheckin;
  montar(alvo,
    voltar("criancas"),
    cabecalho(avatarComFoto("crianca", c.id, nome), nome,
      [`${textoIdade(idade(c.pessoa?.data_nascimento))} · nasc. ${dataBr(c.pessoa?.data_nascimento)}`,
       textoSala(salaDaCrianca(c.sala_fixa_id, idade(c.pessoa?.data_nascimento), salas))], etiquetas),
    c.alergias_observacoes
      ? aviso("atencao", `Alergias e cuidados: ${c.alergias_observacoes}`)
      : el("p", { class: "suave", text: "Nenhuma alergia ou cuidado especial informado." }),
    secao("Responsáveis", listaResponsaveis(mostrar, r.relacoes),
      ligados.length && outros.length ? el("p", { class: "suave", text: `Outros responsáveis da família: ${outros.map((o) => o.pessoa?.nome).filter(Boolean).join(", ")}.` }) : null),
    secao("Autorizados a retirar", listaAutorizadas(r.autorizadas)),
    r.irmaos.length ? secao("Irmãos no Fonte Kids", el("ul", { class: "lista-simples" }, r.irmaos.map((i) =>
      el("li", {}, el("a", { href: `#/ficha?tipo=crianca&id=${encodeURIComponent(i.id)}`, text: i.pessoa?.nome || "Sem nome" }),
        i.ativo ? null : " (inativa)")))) : null,
    secao("Último check-in", el("p", { text: uc
      ? `${quandoBr(uc.entrada_em)}${uc.sala?.nome ? ` · ${uc.sala.nome}` : ""}${uc.saida_em ? " · já saiu" : " · ainda sem check-out"}`
      : "Nenhum check-in registrado." })),
    el("p", {}, el("a", { class: "botao botao--secundario", href: `#/ficha?tipo=familia&id=${encodeURIComponent(c.familia_id)}`, text: "Ver a família" })));
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

  montar(alvo,
    voltar("familias"),
    el("h1", { text: nome }),
    secao("Crianças", criancas.length
      ? el("ul", { class: "lista" }, criancas.map((c) => el("li", {},
          el("a", { class: "lista__item lista__item--link", href: `#/ficha?tipo=crianca&id=${encodeURIComponent(c.id)}` },
            el("div", { class: "lista__texto" },
              el("p", { class: "notif__titulo", text: c.pessoa?.nome || "Sem nome" }),
              el("p", { class: "notif__quando", text: `${textoIdade(idade(c.pessoa?.data_nascimento))} · ${textoSala(salaDaCrianca(c.sala_fixa_id, idade(c.pessoa?.data_nascimento), salas))}${c.ativo ? "" : " · inativa"}` }))))))
      : el("p", { class: "suave", text: "Nenhuma criança visível." })),
    secao("Responsáveis", listaResponsaveis(r.responsaveis, null, linhasDaFamilia(r))),
    secao("Autorizados a retirar", listaAutorizadas(r.autorizadas)),
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
      comCriancas.length ? `Relação: ${comCriancas.join(" · ")}` : "Relação com as crianças: não informada",
      conjuges.length ? `Cônjuge/parceiro(a) de ${conjuges.join(", ")}` : null,
    ]);
  }
  return mapa;
}

// ---------------- Voluntária ----------------
async function desenharVoluntaria(alvo, id) {
  const [r, rs] = await Promise.all([fichaVoluntaria(id), listarSalas()]);
  if (!r.ok) { montar(alvo, voltar("voluntarias"), aviso(r.naoEncontrada ? "atencao" : "erro", r.erro)); return; }
  const v = r.voluntaria;
  const nome = v.pessoa?.nome || "Sem nome";
  document.title = `${nome} · Fonte Kids`;
  const anos = idade(v.pessoa?.data_nascimento);
  const nomeSala = new Map((rs.ok ? rs.lista : []).map((s) => [s.id, s.nome]));
  const salas = (v.salas_preferidas || []).map((s) => nomeSala.get(s)).filter(Boolean);

  montar(alvo,
    voltar("voluntarias"),
    cabecalho(avatarComFoto("voluntaria", v.id, nome), nome,
      [NOMES_FUNCAO[v.funcao] || null, `${textoIdade(anos)} · nasc. ${dataBr(v.pessoa?.data_nascimento)}`],
      [el("span", { class: v.status === "ativa" ? "etiqueta etiqueta--azul" : "etiqueta etiqueta--laranja", text: NOMES_STATUS[v.status] || v.status }),
       anos !== null && anos < 18 ? el("span", { class: "etiqueta", text: "Menor de idade" }) : null].filter(Boolean)),
    secao("Contato", el("ul", { class: "lista" }, contato(nome, [v.email ? `E-mail: ${v.email}` : null], v.pessoa?.telefone))),
    secao("Dados", el("dl", { class: "dados" },
      el("dt", { text: "Profissão" }), el("dd", { text: v.profissao || "—" }),
      el("dt", { text: "Salas preferidas" }), el("dd", { text: salas.length ? salas.join(", ") : "—" }),
      el("dt", { text: "Cultos preferidos" }), el("dd", { text: r.cultos.length ? r.cultos.join(", ") : "—" }),
      el("dt", { text: "Máximo de escalas por mês" }), el("dd", { text: v.teto_mensal ? String(v.teto_mensal) : "Padrão do departamento" }),
      el("dt", { text: "Aprovada em" }), el("dd", { text: v.aprovada_em ? dataBr(v.aprovada_em) : "—" }))));
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
