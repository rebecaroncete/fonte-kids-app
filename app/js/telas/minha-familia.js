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
// Pendências (Etapa 5D): quadro "Para completar" no topo de cada família.
//   • relação não informada → botão para informar (some sozinha quando
//     todos os responsáveis informarem);
//   • sem data de nascimento → "Editar dados" (some sozinha);
//   • manuais (ex.: conferir nascimento) → o responsável marca como
//     resolvida; a liderança recebe aviso no sino.
// Relação de OUTRO responsável (complemento da 5D): na seção Responsáveis,
// "Informar relação" abre uma janelinha com uma linha por criança e a
// opção "É meu cônjuge/parceiro(a)". O que a própria pessoa já informou
// no login dela não é alterado (aparece como "informada por ele(a)").
// O banco (RLS + funções) garante que o responsável mexa só na própria família.
// =====================================================================
import { el, montar, aviso, carregando, mascararTelefone, telefoneParaLogin } from "../ui.js";
import { minhaFamilia, informarRelacao, listarSalas, editarCrianca, incluirAutorizado, removerAutorizado,
  listarPendencias, confirmarPendencia, nomePendencia, informarRelacoesDe, informarConjuge } from "../supabase.js";
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
let eu = null; // pessoa do próprio login

export async function render(alvo) {
  alvoTela = alvo;
  await desenhar(true);
}

async function desenhar(mostrarCarregando = false) {
  if (mostrarCarregando) montar(alvoTela, carregando());
  const [r, rs, rp] = await Promise.all([minhaFamilia(), listarSalas(), listarPendencias("abertas")]);
  const salas = rs.ok ? rs.lista : [];
  const pendencias = rp.ok ? rp.lista : [];

  if (!r.ok) {
    montar(alvoTela, el("h1", { text: "Minha família" }), aviso("erro", r.erro));
    return;
  }
  if (!r.familias.length) {
    montar(alvoTela, el("h1", { text: "Minha família" }),
      aviso("info", "Não encontramos uma família ligada ao seu login. Se você é responsável por uma criança do Fonte Kids, fale com a liderança."));
    return;
  }

  eu = r.eu;
  const varias = r.familias.length > 1;
  montar(alvoTela,
    el("h1", { text: varias ? "Minhas famílias" : "Minha família" }),
    r.familias.map((f) => blocoFamilia(f, salas, varias, pendencias.filter((x) => x.familia_id === f.id))),
    el("p", { class: "suave", text: "As alterações valem na hora e a liderança do Fonte Kids é avisada." }));
  preencherFotos(alvoTela);
}

function blocoFamilia(f, salas, mostrarTitulo, pendencias = []) {
  const principal = f.responsaveis.find((x) => x.principal) || f.responsaveis[0];
  const criancas = [...f.criancas].sort((a, b) => Number(b.ativo) - Number(a.ativo));
  return el("div", {},
    mostrarTitulo ? el("h2", { text: principal?.pessoa?.nome ? `Família de ${principal.pessoa.nome}` : "Família" }) : null,
    pendencias.length ? quadroPendencias(pendencias, f) : null,
    criancas.length
      ? criancas.map((c) => cartaoCrianca(c, f, salas))
      : el("p", { class: "suave", text: "Nenhuma criança nesta família." }),
    secao("Responsáveis", listaResponsaveis(f)),
    secao("Autorizados a retirar", listaAutorizadas(f.autorizadas),
      el("p", { class: "acoes-cartao" }, el("button", {
        class: "botao botao--pequeno botao--secundario", type: "button", text: "Incluir autorizado",
        onclick: () => janelaIncluirAutorizado(f.id),
      }))));
}

// ---------- Para completar (pendências da família) ----------

function quadroPendencias(pendencias, f) {
  const criancaPorId = new Map(f.criancas.map((c) => [c.id, c]));
  return el("section", { class: "cartao cartao--amarelo para-completar" },
    el("h2", { text: "Para completar" }),
    el("p", { class: "atalho__texto", text: "Ajude a manter o cadastro em dia. Estes avisos somem quando o dado é preenchido ou conferido." }),
    el("ul", { class: "lista" }, pendencias.map((p) => itemPendencia(p, criancaPorId.get(p.crianca_id), f))));
}

function itemPendencia(p, c, f) {
  const nomeCri = c?.pessoa?.nome || p.crianca_nome || "";
  const primeiro = nomeCri ? nomeCri.trim().split(/\s+/)[0] : "";
  let texto = p.mensagem;
  const acoes = [];

  if (p.tipo === "relacao_nao_informada") {
    const minha = c ? f.minhasRelacoes.get(c.pessoa?.id) : null;
    if (minha) {
      // responsáveis ligados a esta criança que ainda estão sem relação
      const faltam = c ? f.responsaveis.filter((r) => r.pessoa?.id && r.pessoa.id !== eu
        && criancasDe(f, r).some((x) => x.id === c.id) && !relacaoDe(f, r.pessoa.id, c.pessoa?.id)) : [];
      if (faltam.length) {
        texto = `Falta a relação de ${faltam.map((r) => primeiroNome(r.pessoa.nome)).join(" e ")} com ${primeiro || "a criança"}. Você pode informar por ${faltam.length > 1 ? "eles" : "ele(a)"}.`;
        for (const r of faltam) {
          acoes.push(el("button", { class: "botao botao--pequeno botao--secundario", type: "button",
            text: `Informar por ${primeiroNome(r.pessoa.nome)}`, onclick: () => janelaRelacoesDe(r, f) }));
        }
      } else {
        texto = `Você já informou a sua relação${primeiro ? ` com ${primeiro}` : ""}. Falta outro responsável informar a dele(a).`;
      }
    } else if (c) {
      texto = `Informe a sua relação${primeiro ? ` com ${primeiro}` : " com a criança"} (ex.: mãe, pai, avó).`;
      acoes.push(el("button", { class: "botao botao--pequeno botao--secundario", type: "button", text: "Informar relação",
        onclick: () => janelaRelacao(c.id, nomeCri, null) }));
    }
  } else if (p.tipo === "nascimento_vazio" && c) {
    texto = `Falta a data de nascimento${primeiro ? ` de ${primeiro}` : ""}.`;
    acoes.push(el("button", { class: "botao botao--pequeno botao--secundario", type: "button", text: "Editar dados",
      onclick: () => janelaEditarCrianca(c) }));
  } else if (!p.automatica) {
    if (c && p.tipo === "conferir_nascimento") {
      acoes.push(el("button", { class: "botao botao--pequeno", type: "button", text: "Editar dados",
        onclick: () => janelaEditarCrianca(c) }));
    }
    acoes.push(el("button", { class: "botao botao--pequeno botao--secundario", type: "button", text: "Marcar como resolvida",
      onclick: () => janelaResolverPendencia(p) }));
  }

  return el("li", { class: "notif pendencia" },
    el("div", { class: "linha" },
      el("span", { class: "etiqueta etiqueta--laranja", text: nomePendencia(p.tipo) }),
      nomeCri ? el("span", { class: "notif__titulo", text: nomeCri }) : null),
    el("p", { class: "notif__corpo", text: texto }),
    acoes.length ? el("div", { class: "linha acoes-cartao" }, acoes) : null);
}

function janelaResolverPendencia(p) {
  abrirJanela({
    titulo: "Marcar como resolvida",
    conteudo: [
      el("p", { class: "notif__titulo", text: nomePendencia(p.tipo) }),
      el("p", { text: p.mensagem }),
      el("p", { class: "suave", text: "Confirme que o dado está certo (ou que já corrigiu). A liderança do Fonte Kids é avisada." }),
    ],
    textoSalvar: "Está certo, resolver",
    sucesso: "Pendência resolvida. Obrigado!",
    aoSalvar: async () => {
      const r = await confirmarPendencia(p.id);
      if (!r.ok) return r.erro;
      await desenhar();
      return null;
    },
  });
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

// ---------- Relações dos responsáveis ----------

const primeiroNome = (nome) => (nome || "").trim().split(/\s+/)[0] || "";

/** Relação de um adulto com uma criança (pessoa_id de cada um), em qualquer direção. */
function relacaoDe(f, adultoId, criancaPessoaId) {
  return f.relacoes.find((x) => x.tipo !== "conjuge" &&
    ((x.pessoa_id === adultoId && x.relacionada_id === criancaPessoaId) ||
     (x.pessoa_id === criancaPessoaId && x.relacionada_id === adultoId))) || null;
}
function saoConjuges(f, a, b) {
  return f.relacoes.some((x) => x.tipo === "conjuge" &&
    ((x.pessoa_id === a && x.relacionada_id === b) || (x.pessoa_id === b && x.relacionada_id === a)));
}
/** Crianças ligadas a um responsável (se nenhuma estiver ligada, as ativas da família). */
function criancasDe(f, resp) {
  const ids = new Set((resp.responsaveis_criancas || []).map((x) => x.crianca_id));
  const ligadas = f.criancas.filter((c) => ids.has(c.id));
  return ligadas.length ? ligadas : f.criancas.filter((c) => c.ativo);
}

function listaResponsaveis(f) {
  const responsaveis = f.responsaveis;
  if (!responsaveis.length) return el("p", { class: "suave", text: "Nenhum responsável cadastrado." });
  const ordenados = [...responsaveis].sort((a, b) =>
    Number(b.pessoa?.id === eu) - Number(a.pessoa?.id === eu) || Number(b.principal) - Number(a.principal));
  return el("ul", { class: "lista" }, ordenados.map((r) => {
    const pid = r.pessoa?.id;
    const souEu = pid && pid === eu;
    const etiquetas = [
      souEu ? el("span", { class: "etiqueta", text: "Você" }) : null,
      r.principal ? el("span", { class: "etiqueta etiqueta--azul", text: "Principal" }) : null,
      !souEu && pid && eu && saoConjuges(f, eu, pid) ? el("span", { class: "etiqueta etiqueta--laranja", text: "Seu cônjuge/parceiro(a)" }) : null,
    ].filter(Boolean);

    let detalhe = null;
    let acao = null;
    if (!souEu && pid) {
      const cri = criancasDe(f, r);
      const partes = cri.map((c) => {
        const rel = relacaoDe(f, pid, c.pessoa?.id);
        return rel ? `${textoRelacao(rel)} de ${primeiroNome(c.pessoa?.nome)}` : null;
      }).filter(Boolean);
      const falta = cri.length - partes.length;
      detalhe = partes.length
        ? `Relação: ${partes.join(" · ")}${falta ? ` · falta ${falta}` : ""}`
        : "Relação com as crianças: ainda não informada";
      acao = el("button", {
        class: falta ? "botao botao--pequeno botao--secundario" : "botao botao--pequeno", type: "button",
        text: falta ? "Informar relação" : "Corrigir relação", onclick: () => janelaRelacoesDe(r, f),
      });
    }
    return contato(pid ? avatarLista("pessoa", pid, r.pessoa?.nome) : null,
      r.pessoa?.nome, [detalhe], r.pessoa?.telefone, etiquetas, acao);
  }));
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

function janelaRelacoesDe(resp, f) {
  const pid = resp.pessoa?.id;
  const nomeResp = resp.pessoa?.nome || "este responsável";
  const linhas = criancasDe(f, resp).map((c) => {
    const nomeCri = c.pessoa?.nome || "Criança";
    const atual = relacaoDe(f, pid, c.pessoa?.id);
    if (atual?.pelo_proprio) {
      return { c, fixa: true, no: el("p", { class: "notif__corpo",
        text: `${nomeCri}: ${textoRelacao(atual)} (informada por ${primeiroNome(nomeResp)} no app)` }) };
    }
    const tipo = el("select", { class: "entrada" },
      el("option", { value: "", text: "Escolha…" }),
      TIPOS_RELACAO.map(([v, t]) => el("option", { value: v, text: t })));
    if (atual?.tipo) tipo.value = atual.tipo;
    const detalhe = el("input", { class: "entrada", type: "text", maxlength: "60", placeholder: "Ex.: padrinho",
      value: atual?.tipo === "outro" ? atual.detalhe || "" : "" });
    const blocoDet = campo(`Qual relação com ${primeiroNome(nomeCri)}?`, detalhe);
    blocoDet.hidden = tipo.value !== "outro";
    tipo.addEventListener("change", () => { blocoDet.hidden = tipo.value !== "outro"; if (!blocoDet.hidden) detalhe.focus(); });
    return { c, fixa: false, tipo, detalhe, no: el("div", {}, campo(`${primeiroNome(nomeResp)} é… de ${nomeCri}`, tipo), blocoDet) };
  });

  const eraConjuge = !!(eu && pid && saoConjuges(f, eu, pid));
  const conj = el("input", { type: "checkbox", id: `conjuge-${resp.id}` });
  conj.checked = eraConjuge;

  abrirJanela({
    titulo: `Relação de ${primeiroNome(nomeResp)}`,
    conteudo: [
      el("p", { class: "suave", text: `Informe a relação de ${nomeResp} com as crianças. Se ${primeiroNome(nomeResp)} informar diferente depois, vale o que ele(a) informar.` }),
      ...linhas.map((l) => l.no),
      el("label", { class: "linha", for: conj.id }, conj, el("span", { text: `${primeiroNome(nomeResp)} é meu cônjuge/parceiro(a)` })),
    ],
    sucesso: "Relação salva.",
    aoSalvar: async () => {
      const lista = [];
      for (const l of linhas) {
        if (l.fixa || !l.tipo.value) continue;
        const det = l.tipo.value === "outro" ? l.detalhe.value.trim() : null;
        if (l.tipo.value === "outro" && !det) { l.detalhe.focus(); return "Descreva a relação (ex.: padrinho)."; }
        lista.push({ crianca: l.c.id, tipo: l.tipo.value, detalhe: det });
      }
      if (!lista.length && conj.checked === eraConjuge) return "Escolha a relação com pelo menos uma criança.";
      if (lista.length) {
        const r = await informarRelacoesDe(resp.id, lista);
        if (!r.ok) return r.erro;
      }
      if (conj.checked !== eraConjuge) {
        const r = await informarConjuge(resp.id, conj.checked);
        if (!r.ok) return r.erro;
      }
      definirEtapaAcesso(null);
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
