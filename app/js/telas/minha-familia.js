// =====================================================================
// Tela: Minha família (Fase 10 · Etapa 5C) – papel responsável
//   #/minha-familia
// Mostra só as famílias em que o próprio login é responsável (mesmo que a
// pessoa também seja da liderança ou da recepção): crianças (foto, idade,
// sala pela idade, alergias/cuidados, último check-in, relação informada),
// responsáveis e autorizados a retirar. Só leitura, exceto a relação com
// cada criança, que pode ser informada ou corrigida numa janelinha
// (função informar_relacao). Edição do cadastro chega na Fase 5.
// O banco (RLS) garante que o responsável veja só a própria família.
// =====================================================================
import { el, montar, aviso, carregando, mascararTelefone, toast } from "../ui.js";
import { minhaFamilia, informarRelacao, listarSalas } from "../supabase.js";
import { avatarComFoto } from "../foto.js";
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

let alvoTela = null;

export async function render(alvo) {
  alvoTela = alvo;
  await desenhar();
}

async function desenhar() {
  montar(alvoTela, carregando());
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
    el("p", { class: "suave", text: "Para mudar algum dado do cadastro, fale com a liderança do Fonte Kids." }));
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
    secao("Autorizados a retirar", listaAutorizadas(f.autorizadas)));
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
    el("p", {}, el("button", {
      class: rel ? "botao botao--pequeno" : "botao botao--pequeno botao--secundario", type: "button",
      text: rel ? "Corrigir relação" : "Informar relação",
      onclick: () => abrirRelacao(c.id, nome, rel),
    })));
}

function contato(nome, detalhes, telefone, etiquetas = []) {
  return el("li", { class: "notif" },
    el("p", { class: "notif__titulo", text: nome || "Sem nome" }),
    ...detalhes.filter(Boolean).map((t) => el("p", { class: "notif__quando", text: t })),
    etiquetas.length ? el("div", { class: "linha" }, etiquetas) : null,
    el("p", { class: "notif__corpo", text: telefone ? mascararTelefone(telefone) : "Sem telefone no cadastro" }));
}

function listaResponsaveis(responsaveis) {
  if (!responsaveis.length) return el("p", { class: "suave", text: "Nenhum responsável cadastrado." });
  const ordenados = [...responsaveis].sort((a, b) => Number(b.principal) - Number(a.principal));
  return el("ul", { class: "lista" }, ordenados.map((r) => contato(r.pessoa?.nome, [], r.pessoa?.telefone,
    r.principal ? [el("span", { class: "etiqueta etiqueta--azul", text: "Principal" })] : [])));
}

function listaAutorizadas(autorizadas) {
  if (!autorizadas.length) return el("p", { class: "suave", text: "Nenhuma pessoa autorizada além dos responsáveis." });
  return el("ul", { class: "lista" }, autorizadas.map((a) => contato(a.pessoa?.nome, [a.observacao], a.pessoa?.telefone)));
}

// ---------- Janelinha: informar ou corrigir a relação ----------
function abrirRelacao(criancaId, nome, atual) {
  document.querySelector("dialog.janela")?.remove();
  const tipo = el("select", { class: "entrada", id: "rel-tipo", required: true },
    el("option", { value: "", text: "Escolha…" }),
    TIPOS_RELACAO.map(([v, t]) => el("option", { value: v, text: t })));
  if (atual?.tipo) tipo.value = atual.tipo;
  const detalhe = el("input", { class: "entrada", id: "rel-detalhe", type: "text", maxlength: "60",
    placeholder: "Ex.: madrinha", value: atual?.tipo === "outro" ? atual.detalhe || "" : "" });
  const blocoDetalhe = el("div", { class: "campo", hidden: tipo.value !== "outro" },
    el("label", { class: "campo__rotulo", for: "rel-detalhe", text: "Qual relação?" }), detalhe);
  tipo.addEventListener("change", () => { blocoDetalhe.hidden = tipo.value !== "outro"; if (!blocoDetalhe.hidden) detalhe.focus(); });
  const caixaErro = el("div", {});
  const salvar = el("button", { class: "botao", type: "submit", text: "Salvar" });
  const cancelar = el("button", { class: "botao botao--pequeno", type: "button", text: "Cancelar" });

  const form = el("form", { novalidate: true },
    el("h2", { text: `Sua relação com ${nome}` }),
    el("div", { class: "campo" }, el("label", { class: "campo__rotulo", for: "rel-tipo", text: "Você é…" }), tipo),
    blocoDetalhe, caixaErro,
    el("div", { class: "linha" }, salvar, cancelar));
  const janela = el("dialog", { class: "janela", "aria-label": `Relação com ${nome}` }, form);

  const fechar = () => { janela.close(); janela.remove(); };
  cancelar.addEventListener("click", fechar);
  janela.addEventListener("close", () => janela.remove());
  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    montar(caixaErro);
    if (!tipo.value) { montar(caixaErro, aviso("erro", "Escolha a relação.")); tipo.focus(); return; }
    const det = tipo.value === "outro" ? detalhe.value.trim() : null;
    if (tipo.value === "outro" && !det) { montar(caixaErro, aviso("erro", "Descreva a relação (ex.: madrinha).")); detalhe.focus(); return; }
    salvar.disabled = true;
    salvar.textContent = "Salvando…";
    const res = await informarRelacao(criancaId, tipo.value, det);
    if (!res.ok) {
      salvar.disabled = false;
      salvar.textContent = "Salvar";
      montar(caixaErro, aviso("erro", res.erro));
      return;
    }
    definirEtapaAcesso(null); // o app confere de novo se ainda falta alguma relação
    fechar();
    toast("sucesso", "Relação salva.");
    await desenhar();
  });

  document.body.append(janela);
  janela.showModal();
  tipo.focus();
}
