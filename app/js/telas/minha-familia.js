// =====================================================================
// Tela: Minha família (Fase 10 · Etapa 5C) – papel responsável
//   #/minha-familia
// Mostra só as famílias em que o próprio login é responsável (mesmo que a
// pessoa também seja da liderança ou da recepção): crianças (foto, idade,
// sala pela idade, alergias/cuidados, último check-in, relação informada),
// responsáveis (com foto) e autorizados a retirar.
// Edição (decidida em 27/10/2026; vale na hora, fica na auditoria e a
// liderança recebe aviso no sino):
//   • criança: nome, data de nascimento, alergias/cuidados e foto;
//   • relação com cada criança (informar_relacao);
//   • autorizados a retirar: incluir e remover.
// O banco (RLS + funções) garante que o responsável mexa só na própria família.
// =====================================================================
import { el, montar, aviso, carregando, mascararTelefone, telefoneParaLogin } from "../ui.js";
import { minhaFamilia, informarRelacao, listarSalas, editarCrianca, incluirAutorizado, removerAutorizado } from "../supabase.js";
import { avatarComFoto, avatarLista, preencherFotos } from "../foto.js";
import { abrirJanela, janelaFoto, campo } from "../janela.js";
import { idade, textoIdade, salaDaCrianca, textoSala } from "./cadastros.js";
import { TIPOS_RELACAO } from "./primeiro-acesso.js";
import { definirEtapaAcesso } from "../app.js";

export const layout = "padrao";
export const titulo = "Minha família";

const FUSO = "America/Sao_Paulo";
const NOME_RELACAO = new Map(TIPOS_RELACAO);
const quandoBr = (iso) => new Date(iso).toLocaleString("pt-BR", {
  timeZone: FUSO, day: "2-digit", month: "2-digit", year: "numeric", hour: "2-digit", minute: "2-digit",
});
const hojeIso = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO }); // AAAA-MM-DD

let alvoTela = null;

export async function render(alvo) {
  alvoTela = alvo;
  await desenhar(true);
}

async function desenhar(mostrarCarregando = false) {
  if (mostrarCarregando) montar(alvoTela, carregando());
  const [r, rs] = await Promise.all([minhaFamilia(), listarSalas()]);
  const salas = rs.ok ? rs.lista : [];

  if (!r.ok) {
    montar(alvoTela, el("h1", { text: "Minha família" }), aviso("erro", r.erro));
    return;
  }
  if (!r.familias.length) {
    montar(alvoTela, el("h1", { text: "Minha família" }),
      aviso("info", "Não encontramos uma família ligada ao seu login. Se você é responsável por uma criança do Fonte Kids, fale com a liderança."));
    return;
  }

  const varias = r.familias.length > 1;
  montar(alvoTela,
    el("h1", { text: varias ? "Minhas famílias" : "Minha família" }),
    r.familias.map((f) => blocoFamilia(f, salas, varias)),
    el("p", { class: "suave", text: "As alterações valem na hora e a liderança do Fonte Kids é avisada." }));
  preencherFotos(alvoTela);
}

function blocoFamilia(f, salas, mostrarTitulo) {
  const principal = f.responsaveis.find((x) => x.principal) || f.responsaveis[0];
  const criancas = [...f.criancas].sort((a, b) => Number(b.ativo) - Number(a.ativo));
  return el("div", {},
    mostrarTitulo ? el("h2", { text: principal?.pessoa?.nome ? `Família de ${principal.pessoa.nome}` : "Família" }) : null,
    criancas.length
      ? criancas.map((c) => cartaoCrianca(c, f, salas))
      : el("p", { class: "suave", text: "Nenhuma criança nesta família." }),
    secao("Responsáveis", listaResponsaveis(f.responsaveis)),
    secao("Autorizados a retirar", listaAutorizadas(f.autorizadas),
      el("p", { class: "acoes-cartao" }, el("button", {
        class: "botao botao--pequeno botao--secundario", type: "button", text: "Incluir autorizado",
        onclick: () => janelaIncluirAutorizado(f.id),
      }))));
}

function secao(tituloSecao, ...conteudo) {
  return el("section", { class: "cartao" }, el("h2", { text: tituloSecao }), ...conteudo);
}

function textoRelacao(rel) {
  if (!rel) return null;
  return rel.tipo === "outro" && rel.detalhe ? rel.detalhe : NOME_RELACAO.get(rel.tipo) || rel.tipo;
}

function cartaoCrianca(c, f, salas) {
  const nome = c.pessoa?.nome || "Sem nome";
  const anos = idade(c.pessoa?.data_nascimento);
  const rel = f.minhasRelacoes.get(c.pessoa?.id);
  const uc = f.ultimosCheckins.get(c.id);
  const etiquetas = [
    c.perfil === "visitante" ? el("span", { class: "etiqueta etiqueta--azul", text: "Visitante" }) : null,
    !c.ativo ? el("span", { class: "etiqueta", text: "Inativa" }) : null,
  ].filter(Boolean);

  return el("section", { class: "cartao" },
    el("div", { class: "perfil-cabecalho" }, avatarComFoto("crianca", c.id, nome),
      el("div", {},
        el("h2", { class: "perfil-cabecalho__nome", text: nome }),
        el("p", { class: "notif__quando", text: textoIdade(anos) }),
        el("p", { class: "notif__quando", text: textoSala(salaDaCrianca(c.sala_fixa_id, anos, salas)) }),
        etiquetas.length ? el("div", { class: "linha" }, etiquetas) : null)),
    c.alergias_observacoes
      ? aviso("atencao", `Alergias e cuidados: ${c.alergias_observacoes}`)
      : el("p", { class: "suave", text: "Nenhuma alergia ou cuidado especial informado." }),
    el("dl", { class: "dados" },
      el("dt", { text: "Último check-in" }),
      el("dd", { text: uc
        ? `${quandoBr(uc.entrada_em)}${uc.sala?.nome ? ` · ${uc.sala.nome}` : ""}${uc.saida_em ? " · já saiu" : " · ainda sem check-out"}`
        : "Nenhum check-in registrado." }),
      el("dt", { text: "Sua relação" }),
      el("dd", { text: textoRelacao(rel) || "Ainda não informada" })),
    el("div", { class: "linha acoes-cartao" },
      el("button", { class: "botao botao--pequeno", type: "button", text: "Editar dados", onclick: () => janelaEditarCrianca(c) }),
      el("button", { class: "botao botao--pequeno", type: "button", text: "Trocar foto",
        onclick: () => janelaFoto({ tipo: "crianca", id: c.id, nome, tipoFoto: "crianca", idFoto: c.id, aoTrocar: () => desenhar() }) }),
      el("button", {
        class: rel ? "botao botao--pequeno" : "botao botao--pequeno botao--secundario", type: "button",
        text: rel ? "Corrigir relação" : "Informar relação",
        onclick: () => janelaRelacao(c.id, nome, rel),
      })));
}

function contato(avatar, nome, detalhes, telefone, etiquetas = [], acao = null) {
  return el("li", { class: "notif" },
    el("div", { class: "lista__item-simples linha" },
      avatar,
      el("div", {},
        el("p", { class: "notif__titulo", text: nome || "Sem nome" }),
        ...detalhes.filter(Boolean).map((t) => el("p", { class: "notif__quando", text: t })),
        etiquetas.length ? el("div", { class: "linha" }, etiquetas) : null,
        el("p", { class: "notif__corpo", text: telefone ? mascararTelefone(telefone) : "Sem telefone no cadastro" }))),
    acao ? el("div", { class: "linha" }, acao) : null);
}

function listaResponsaveis(responsaveis) {
  if (!responsaveis.length) return el("p", { class: "suave", text: "Nenhum responsável cadastrado." });
  const ordenados = [...responsaveis].sort((a, b) => Number(b.principal) - Number(a.principal));
  return el("ul", { class: "lista" }, ordenados.map((r) => contato(
    r.pessoa?.id ? avatarLista("pessoa", r.pessoa.id, r.pessoa?.nome) : null,
    r.pessoa?.nome, [], r.pessoa?.telefone,
    r.principal ? [el("span", { class: "etiqueta etiqueta--azul", text: "Principal" })] : [])));
}

function listaAutorizadas(autorizadas) {
  if (!autorizadas.length) return el("p", { class: "suave", text: "Nenhuma pessoa autorizada além dos responsáveis." });
  return el("ul", { class: "lista" }, autorizadas.map((a) => contato(null, a.pessoa?.nome, [a.observacao], a.pessoa?.telefone, [],
    el("button", { class: "botao botao--pequeno", type: "button", text: "Remover", onclick: () => janelaRemoverAutorizado(a) }))));
}

// ---------- Janelinhas ----------

function janelaEditarCrianca(c) {
  const nome = el("input", { class: "entrada", type: "text", maxlength: "120", autocomplete: "off", value: c.pessoa?.nome || "" });
  const nasc = el("input", { class: "entrada", type: "date", max: hojeIso(), value: c.pessoa?.data_nascimento || "" });
  const alerg = el("textarea", { class: "entrada", maxlength: "500" });
  alerg.value = c.alergias_observacoes || "";
  abrirJanela({
    titulo: "Dados da criança",
    conteudo: [
      campo("Nome completo", nome),
      campo("Data de nascimento", nasc, "A sala muda sozinha conforme a idade."),
      campo("Alergias e cuidados", alerg, "Ex.: alergia a amendoim, usa bombinha. Deixe em branco se não houver."),
    ],
    sucesso: "Dados salvos.",
    aoSalvar: async () => {
      if (nome.value.trim().length < 3) { nome.focus(); return "Informe o nome completo."; }
      if (!nasc.value) { nasc.focus(); return "Informe a data de nascimento."; }
      const r = await editarCrianca(c.id, nome.value, nasc.value, alerg.value);
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

function janelaRelacao(criancaId, nome, atual) {
  const tipo = el("select", { class: "entrada", required: true },
    el("option", { value: "", text: "Escolha…" }),
    TIPOS_RELACAO.map(([v, t]) => el("option", { value: v, text: t })));
  if (atual?.tipo) tipo.value = atual.tipo;
  const detalhe = el("input", { class: "entrada", type: "text", maxlength: "60", placeholder: "Ex.: madrinha",
    value: atual?.tipo === "outro" ? atual.detalhe || "" : "" });
  const blocoDetalhe = campo("Qual relação?", detalhe);
  blocoDetalhe.hidden = tipo.value !== "outro";
  tipo.addEventListener("change", () => { blocoDetalhe.hidden = tipo.value !== "outro"; if (!blocoDetalhe.hidden) detalhe.focus(); });

  abrirJanela({
    titulo: `Sua relação com ${nome}`,
    conteudo: [campo("Você é…", tipo), blocoDetalhe],
    sucesso: "Relação salva.",
    aoSalvar: async () => {
      if (!tipo.value) { tipo.focus(); return "Escolha a relação."; }
      const det = tipo.value === "outro" ? detalhe.value.trim() : null;
      if (tipo.value === "outro" && !det) { detalhe.focus(); return "Descreva a relação (ex.: madrinha)."; }
      const res = await informarRelacao(criancaId, tipo.value, det);
      if (!res.ok) return res.erro;
      definirEtapaAcesso(null); // o app confere de novo se ainda falta alguma relação
      await desenhar();
      return null;
    },
  });
}

function janelaIncluirAutorizado(familiaId) {
  const nome = el("input", { class: "entrada", type: "text", maxlength: "120", autocomplete: "off" });
  const tel = el("input", { class: "entrada", type: "tel", inputmode: "numeric", autocomplete: "off", placeholder: "(27) 99999-9999" });
  tel.addEventListener("input", () => { tel.value = mascararTelefone(tel.value); });
  const obs = el("input", { class: "entrada", type: "text", maxlength: "120", placeholder: "Ex.: avó, vizinha, babá" });
  abrirJanela({
    titulo: "Incluir autorizado a retirar",
    conteudo: [
      aviso("atencao", "Esta pessoa poderá retirar as crianças da família no fim do culto, a partir de agora."),
      campo("Nome completo", nome),
      campo("Telefone (com DDD)", tel),
      campo("Quem é (opcional)", obs),
    ],
    textoSalvar: "Incluir",
    sucesso: "Autorizado incluído.",
    aoSalvar: async () => {
      if (nome.value.trim().length < 3) { nome.focus(); return "Informe o nome completo."; }
      const t = telefoneParaLogin(tel.value);
      if (!t) { tel.focus(); return "Telefone inválido: use DDD + número."; }
      const r = await incluirAutorizado(familiaId, nome.value, t, obs.value);
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}

function janelaRemoverAutorizado(a) {
  const nome = a.pessoa?.nome || "esta pessoa";
  abrirJanela({
    titulo: "Remover autorizado",
    conteudo: [el("p", { text: `${nome} não poderá mais retirar as crianças da família. Deseja remover?` })],
    textoSalvar: "Remover",
    perigo: true,
    sucesso: "Autorizado removido.",
    aoSalvar: async () => {
      const r = await removerAutorizado(a.id);
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
}
