// =====================================================================
// Tela pública: Cadastro de família nova (Fase 5 · Etapa 5D)   #/cadastro
// Sem login (link/QR code da igreja). Só esta tela; nada do resto do app.
//
// Passos: 1 Responsável (telefone + captcha) → 2 Segundo responsável
// (opcional) → 3 Crianças (foto obrigatória) → 4 Autorizados a retirar
// (opcional) → 5 Conferir e aceitar o termo → Enviar.
// • No passo 1 o servidor confere o captcha e o telefone. Telefone já
//   cadastrado: a família é levada a entrar no app ("Adicionar criança").
// • Tudo fica só na memória desta aba até o envio (nada no aparelho).
// • O envio vai para a Edge Function "cadastro-publico", que grava tudo de
//   uma vez, cria os logins (senha inicial = telefone) e envia as fotos.
// • Tela final: convite para o(s) grupo(s) de WhatsApp certo(s) pela idade
//   e para entrar no app (o convite de instalar aparece depois do login).
// =====================================================================
import { el, montar, aviso, mascararTelefone, telefoneParaLogin, menuAcoes } from "../ui.js";
import { icone } from "../icones.js";
import { criarCaptcha } from "../captcha.js";
import { prepararFoto } from "../foto.js";
import { cadastroVerificarTelefone, cadastroEnviar } from "../supabase.js";

export const layout = "central";
export const titulo = "Cadastro Fonte Kids";

const FUSO = "America/Sao_Paulo";
const hojeIso = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO });
const RELACOES = [
  ["mae", "Mãe"], ["pai", "Pai"], ["madrasta", "Madrasta"], ["padrasto", "Padrasto"],
  ["avo", "Avô ou avó"], ["tio", "Tio ou tia"], ["irmao", "Irmão ou irmã"],
  ["responsavel_legal", "Responsável legal"], ["outro", "Outro"],
];
const NOME_GRUPO = { "0_9": "Crianças de 0 a 9 anos", "10_12": "Crianças de 10 a 12 anos" };
const TOTAL_PASSOS = 5;

// Estado (só na memória da aba)
let alvoTela = null;
let s = null;
function novoEstado() {
  return {
    ticket: null, termo: null,
    resp1: { nome: "", telefone: "", foto: null },
    resp2: { nome: "", telefone: "" },
    criancas: [],     // { nome, nascimento, perfil, alergias, relacao, detalhe, relacao2, detalhe2, foto }
    autorizados: [],  // { nome, telefone, observacao }
  };
}

export async function render(alvo) {
  alvoTela = alvo;
  s = novoEstado();
  passo1();
}

// ---------- Utilidades ----------
let contador = 0;
const id = (b) => `cad-${b}-${++contador}`;
function campo(rotulo, entrada, ajuda) {
  if (!entrada.id) entrada.id = id("campo");
  return el("div", { class: "campo" },
    el("label", { class: "campo__rotulo", for: entrada.id, text: rotulo }),
    entrada,
    ajuda ? el("span", { class: "campo__ajuda", text: ajuda }) : null);
}
const entradaTexto = (valor = "", extra = {}) => el("input", { class: "entrada", type: "text", maxlength: "120", autocomplete: "off", value: valor, ...extra });
function entradaTelefone(valor = "") {
  const t = el("input", { class: "entrada", type: "tel", inputmode: "numeric", autocomplete: "off", placeholder: "(27) 90000-0000", value: valor });
  t.addEventListener("input", () => { t.value = mascararTelefone(t.value); });
  return t;
}
function seletorRelacao(valor = "", vazio = "Escolha…") {
  const sel = el("select", { class: "entrada" }, el("option", { value: "", text: vazio }),
    RELACOES.map(([v, t]) => el("option", { value: v, text: t })));
  sel.value = valor;
  return sel;
}
function idadeEm(nascIso) {
  if (!nascIso) return null;
  const [a, m, d] = nascIso.split("-").map(Number);
  const [ha, hm, hd] = hojeIso().split("-").map(Number);
  let anos = ha - a;
  if (hm < m || (hm === m && hd < d)) anos--;
  return anos;
}
const textoIdade = (n) => n === null ? "" : n < 1 ? "Menos de 1 ano" : n === 1 ? "1 ano" : `${n} anos`;
const primeiro = (nome) => String(nome || "").trim().split(/\s+/)[0] || "";

/** Moldura comum de cada passo. */
function moldura(numero, tituloPasso, ...conteudo) {
  montar(alvoTela,
    el("div", { class: "marca" }, el("img", { src: "img/logo.png", alt: "Logo do Fonte Kids" }),
      el("h1", { class: "marca__titulo", text: "Cadastro Fonte Kids" })),
    numero ? el("p", { class: "passo-rotulo", text: `Passo ${numero} de ${TOTAL_PASSOS} · ${tituloPasso}` }) : null,
    numero ? el("progress", { class: "progresso", max: String(TOTAL_PASSOS), value: String(numero), "aria-hidden": "true" }) : null,
    ...conteudo);
  window.scrollTo(0, 0);
}

// ---------- Passo 1: responsável principal ----------
function passo1(mensagem) {
  const nome = entradaTexto(s.resp1.nome, { autocomplete: "name" });
  const tel = entradaTelefone(s.resp1.telefone);
  const caixaFoto = blocoFoto(s.resp1.foto, (f) => { s.resp1.foto = f; }, false);
  const lugarCaptcha = el("div", { class: "captcha", "data-acao": "cadastro" });
  const caixaErro = el("div", { "aria-live": "assertive" });
  const botao = el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Continuar", disabled: true });
  let captcha = null;
  let enviando = false;

  const form = el("form", { class: "cartao", novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (enviando) return;
      montar(caixaErro);
      s.resp1.nome = nome.value.trim();
      s.resp1.telefone = tel.value;
      if (s.resp1.nome.length < 3) { nome.focus(); montar(caixaErro, aviso("erro", "Informe o seu nome completo.")); return; }
      const t = telefoneParaLogin(tel.value);
      if (!t) { tel.focus(); montar(caixaErro, aviso("erro", "Digite o WhatsApp com DDD.")); return; }
      const token = captcha?.token();
      if (!token) { montar(caixaErro, aviso("erro", "Conclua a verificação anti-robô.")); return; }

      enviando = true; botao.disabled = true; botao.textContent = "Conferindo…";
      const r = await cadastroVerificarTelefone(t, token);
      enviando = false; botao.textContent = "Continuar";
      if (!r.ok) {
        montar(caixaErro, aviso("erro", r.codigo === "captcha" ? "Não foi possível confirmar a verificação anti-robô. Tente de novo."
          : r.codigo === "telefone" ? "Telefone inválido: use DDD + número."
          : r.codigo === "conexao" ? "Sem conexão com o servidor. Verifique a internet e tente de novo."
          : "Não foi possível continuar agora. Tente de novo em alguns minutos."));
        captcha?.reiniciar();
        return;
      }
      if (r.existe) { telaJaCadastrado(); return; }
      s.ticket = r.ticket;
      s.termo = r.termo;
      passo2();
    } },
    campo("Seu nome completo", nome),
    campo("Seu WhatsApp (com DDD)", tel, "Vai ser o seu login no app do Fonte Kids."),
    caixaFoto,
    lugarCaptcha,
    caixaErro,
    botao);

  moldura(1, "Responsável",
    el("p", { text: "Cadastre a sua família para o check-in das crianças no Fonte Kids." }),
    mensagem ? aviso("atencao", mensagem) : null,
    form);

  criarCaptcha(lugarCaptcha, (ok) => { botao.disabled = enviando || !ok; })
    .then((c) => { captcha = c; })
    .catch(() => montar(lugarCaptcha, aviso("atencao", "Não foi possível carregar a verificação anti-robô. Verifique a internet e recarregue a página.")));
}

function telaJaCadastrado() {
  moldura(0, "",
    aviso("atencao", "Este telefone já está cadastrado no Fonte Kids."),
    el("div", { class: "cartao" },
      el("h2", { text: "Quer adicionar uma criança?" }),
      el("p", { text: "Entre no app com este telefone e toque em Família → Adicionar criança." }),
      el("p", { class: "suave", text: "No primeiro acesso, a senha é 55 + DDD + o número, só os dígitos (ex.: 5527900000000). Depois você cria uma senha nova." }),
      el("p", { class: "suave", text: "Não consegue entrar? Fale com a recepção do Fonte Kids." }),
      el("div", { class: "linha mt-3" },
        el("a", { class: "botao botao--primario", href: "#/entrar", text: "Entrar no app" }),
        el("button", { class: "botao botao--secundario", type: "button", text: "Usar outro telefone",
          onclick: () => { s.resp1.telefone = ""; passo1(); } }))));
}

// ---------- Foto (prévia) ----------
function blocoFoto(atual, aoEscolher, obrigatoria) {
  const previa = el("div", { class: "avatar avatar--grande previa-foto", "aria-hidden": "true" });
  if (atual) previa.append(el("img", { src: atual, alt: "" }));
  const situacao = el("span", { class: "campo__ajuda", text: atual ? "Foto escolhida. Toque para trocar." :
    obrigatoria ? "Só o rosto, de frente, com boa luz." : "Opcional. Só o rosto, de frente." });
  const arquivo = el("input", { type: "file", accept: "image/*", class: "entrada" });
  arquivo.addEventListener("change", async () => {
    const f = arquivo.files?.[0];
    if (!f) return;
    situacao.textContent = "Preparando a foto…";
    try {
      const pronta = await prepararFoto(f);
      aoEscolher(pronta);
      previa.replaceChildren(el("img", { src: pronta, alt: "" }));
      situacao.textContent = "Foto escolhida.";
    } catch (e) {
      situacao.textContent = e.message;
    }
  });
  arquivo.id = id("foto");
  return el("div", { class: "campo" },
    el("label", { class: "campo__rotulo", for: arquivo.id, text: obrigatoria ? "Foto (obrigatória)" : "Sua foto (opcional)" }),
    el("div", { class: "linha" }, previa, el("div", { class: "flex-1" }, arquivo, situacao)));
}

// ---------- Passo 2: segundo responsável ----------
function passo2() {
  const nome = entradaTexto(s.resp2.nome);
  const tel = entradaTelefone(s.resp2.telefone);
  const caixaErro = el("div", { "aria-live": "assertive" });
  const form = el("form", { class: "cartao", novalidate: true, onsubmit: (e) => {
      e.preventDefault();
      montar(caixaErro);
      const n = nome.value.trim();
      const t = tel.value.trim();
      if (!n && !t) { s.resp2 = { nome: "", telefone: "" }; limparRelacoes2(); passo3(); return; }
      if (n.length < 3) { nome.focus(); montar(caixaErro, aviso("erro", "Informe o nome completo do segundo responsável.")); return; }
      if (t && !telefoneParaLogin(t)) { tel.focus(); montar(caixaErro, aviso("erro", "Telefone inválido: use DDD + número.")); return; }
      s.resp2 = { nome: n, telefone: t };
      passo3();
    } },
    campo("Nome completo", nome),
    campo("WhatsApp (com DDD)", tel, "Se tiver um WhatsApp diferente do seu, ele(a) também ganha acesso ao app."),
    caixaErro,
    el("div", { class: "linha" },
      el("button", { class: "botao botao--primario", type: "submit", text: "Continuar" }),
      el("button", { class: "botao botao--secundario", type: "button", text: "Pular",
        onclick: () => { s.resp2 = { nome: "", telefone: "" }; limparRelacoes2(); passo3(); } })),
    el("p", { class: "mt-3" }, el("button", { class: "botao botao--texto", type: "button", text: "Voltar", onclick: () => passo1() })));
  moldura(2, "Segundo responsável",
    el("p", { text: "Outra pessoa responsável pelas crianças (ex.: pai, mãe, avó). É opcional." }),
    form);
}
function limparRelacoes2() { for (const c of s.criancas) { c.relacao2 = ""; c.detalhe2 = ""; } }

// ---------- Passo 3: crianças ----------
function passo3(editando = null) {
  const lista = el("ul", { class: "lista-compacta" }, s.criancas.map((c, i) => el("li", {},
    el("div", { class: "item-compacto" },
      c.foto ? el("span", { class: "avatar avatar--foto", "aria-hidden": "true" }, el("img", { src: c.foto, alt: "" }))
             : el("span", { class: "avatar", "aria-hidden": "true", text: primeiro(c.nome)[0] || "?" }),
      el("span", { class: "item-compacto__texto" },
        el("span", { class: "item-compacto__nome", text: c.nome }),
        el("span", { class: "item-compacto__linha", text: [textoIdade(idadeEm(c.nascimento)), c.alergias ? "Alergia / cuidados" : null].filter(Boolean).join(" · ") })),
      menuAcoes([
        { texto: "Editar", acao: () => passo3(i) },
        { texto: "Remover", perigo: true, acao: () => { s.criancas.splice(i, 1); passo3(); } },
      ], `Mais ações para ${c.nome}`)))));

  const mostrarForm = editando !== null || !s.criancas.length;
  const caixaErro = el("div", { "aria-live": "assertive" });
  const continuar = el("button", { class: "botao botao--primario botao--largo", type: "button", text: "Continuar",
    onclick: () => {
      if (!s.criancas.length) { montar(caixaErro, aviso("erro", "Cadastre pelo menos uma criança.")); return; }
      passo4();
    } });

  moldura(3, "Crianças",
    s.criancas.length ? lista : null,
    mostrarForm ? formCrianca(editando) : el("button", { class: "botao botao--secundario botao--largo mt-3", type: "button",
      onclick: () => passo3(-1), disabled: s.criancas.length >= 10 }, icone("adicionar"), "Adicionar outra criança"),
    caixaErro,
    !mostrarForm ? el("div", { class: "mt-3" }, continuar) : null,
    el("p", { class: "mt-3" }, el("button", { class: "botao botao--texto", type: "button", text: "Voltar", onclick: () => passo2() })));
}

function formCrianca(indice) {
  const atual = indice !== null && indice >= 0 ? s.criancas[indice] : null;
  const c = atual ? { ...atual } : { nome: "", nascimento: "", perfil: "visitante", alergias: "", relacao: "", detalhe: "", relacao2: "", detalhe2: "", foto: null };
  const nome = entradaTexto(c.nome);
  const nasc = el("input", { class: "entrada", type: "date", max: hojeIso(), value: c.nascimento });
  const perfil = el("select", { class: "entrada" },
    el("option", { value: "visitante", text: "Visitante" }), el("option", { value: "membro", text: "Membro da igreja" }));
  perfil.value = c.perfil;
  const alerg = el("textarea", { class: "entrada", maxlength: "500", placeholder: "Ex.: alergia a amendoim. Deixe em branco se não houver." });
  alerg.value = c.alergias;
  const rel = seletorRelacao(c.relacao);
  const det = entradaTexto(c.detalhe, { maxlength: "60", placeholder: "Ex.: madrinha" });
  const blocoDet = campo("Qual relação?", det); blocoDet.hidden = rel.value !== "outro";
  rel.addEventListener("change", () => { blocoDet.hidden = rel.value !== "outro"; });
  const tem2 = !!s.resp2.nome;
  const rel2 = seletorRelacao(c.relacao2, "Não informar");
  const det2 = entradaTexto(c.detalhe2, { maxlength: "60", placeholder: "Ex.: padrinho" });
  const blocoDet2 = campo(`Qual relação de ${primeiro(s.resp2.nome)}?`, det2); blocoDet2.hidden = rel2.value !== "outro";
  rel2.addEventListener("change", () => { blocoDet2.hidden = rel2.value !== "outro"; });
  const caixaFoto = blocoFoto(c.foto, (f) => { c.foto = f; }, true);
  const caixaErro = el("div", { "aria-live": "assertive" });
  const erro = (texto, foco) => { montar(caixaErro, aviso("erro", texto)); foco?.focus(); };

  return el("form", { class: "cartao", novalidate: true, onsubmit: (e) => {
      e.preventDefault();
      c.nome = nome.value.trim().replace(/\s+/g, " ");
      c.nascimento = nasc.value;
      c.perfil = perfil.value;
      c.alergias = alerg.value.trim();
      c.relacao = rel.value; c.detalhe = rel.value === "outro" ? det.value.trim() : "";
      c.relacao2 = tem2 ? rel2.value : ""; c.detalhe2 = tem2 && rel2.value === "outro" ? det2.value.trim() : "";
      if (c.nome.length < 3) return erro("Informe o nome completo da criança.", nome);
      if (!c.nascimento) return erro("Informe a data de nascimento.", nasc);
      const anos = idadeEm(c.nascimento);
      if (c.nascimento > hojeIso() || anos === null || anos < 0) return erro("Data de nascimento inválida.", nasc);
      if (anos > 12) return erro("O Fonte Kids atende crianças de 0 a 12 anos.", nasc);
      if (!c.relacao) return erro("Escolha a sua relação com a criança.", rel);
      if (c.relacao === "outro" && !c.detalhe) return erro("Descreva a sua relação (ex.: madrinha).", det);
      if (c.relacao2 === "outro" && !c.detalhe2) return erro("Descreva a relação do segundo responsável.", det2);
      if (!c.foto) return erro("Escolha uma foto da criança.");
      if (atual) s.criancas[indice] = c; else s.criancas.push(c);
      passo3();
    } },
    el("h2", { text: atual ? "Editar criança" : "Dados da criança" }),
    campo("Nome completo", nome),
    campo("Data de nascimento", nasc, "A sala é escolhida pela idade."),
    campo("Perfil", perfil),
    campo("Alergias ou cuidados", alerg),
    campo("Você é…", rel), blocoDet,
    tem2 ? campo(`${primeiro(s.resp2.nome)} é…`, rel2) : null, tem2 ? blocoDet2 : null,
    caixaFoto,
    caixaErro,
    el("div", { class: "linha" },
      el("button", { class: "botao botao--primario", type: "submit", text: "Salvar criança" }),
      s.criancas.length ? el("button", { class: "botao botao--secundario", type: "button", text: "Cancelar", onclick: () => passo3() }) : null));
}

// ---------- Passo 4: autorizados a retirar ----------
function passo4(mostrarForm = false) {
  const lista = el("ul", { class: "lista-compacta" }, s.autorizados.map((a, i) => el("li", {},
    el("div", { class: "item-compacto" },
      el("span", { class: "item-compacto__texto" },
        el("span", { class: "item-compacto__nome", text: a.nome }),
        el("span", { class: "item-compacto__linha", text: [a.telefone, a.observacao].filter(Boolean).join(" · ") })),
      menuAcoes([{ texto: "Remover", perigo: true, acao: () => { s.autorizados.splice(i, 1); passo4(); } }], `Mais ações para ${a.nome}`)))));

  let conteudo;
  if (mostrarForm) {
    const nome = entradaTexto();
    const tel = entradaTelefone();
    const obs = entradaTexto("", { placeholder: "Ex.: avó, vizinha, babá" });
    const caixaErro = el("div", { "aria-live": "assertive" });
    conteudo = el("form", { class: "cartao", novalidate: true, onsubmit: (e) => {
        e.preventDefault();
        const n = nome.value.trim().replace(/\s+/g, " ");
        if (n.length < 3) { nome.focus(); montar(caixaErro, aviso("erro", "Informe o nome completo.")); return; }
        if (!telefoneParaLogin(tel.value)) { tel.focus(); montar(caixaErro, aviso("erro", "Telefone inválido: use DDD + número.")); return; }
        s.autorizados.push({ nome: n, telefone: tel.value, observacao: obs.value.trim() });
        passo4();
      } },
      el("h2", { text: "Pessoa autorizada" }),
      campo("Nome completo", nome),
      campo("Telefone (com DDD)", tel),
      campo("Quem é (opcional)", obs),
      caixaErro,
      el("div", { class: "linha" },
        el("button", { class: "botao botao--primario", type: "submit", text: "Salvar" }),
        el("button", { class: "botao botao--secundario", type: "button", text: "Cancelar", onclick: () => passo4() })));
  } else {
    conteudo = el("div", {},
      s.autorizados.length < 10 ? el("button", { class: "botao botao--secundario botao--largo", type: "button", onclick: () => passo4(true) },
        icone("adicionar"), "Adicionar pessoa autorizada") : null,
      el("div", { class: "mt-3" }, el("button", { class: "botao botao--primario botao--largo", type: "button",
        text: s.autorizados.length ? "Continuar" : "Pular", onclick: () => passo5() })));
  }

  moldura(4, "Autorizados a retirar",
    el("p", { text: "Outras pessoas que podem buscar as crianças no fim do culto (opcional). Os responsáveis já podem." }),
    s.autorizados.length ? lista : null,
    conteudo,
    el("p", { class: "mt-3" }, el("button", { class: "botao botao--texto", type: "button", text: "Voltar", onclick: () => passo3() })));
}

// ---------- Passo 5: conferir, aceitar o termo e enviar ----------
function passo5(mensagem) {
  const aceite = el("input", { type: "checkbox", id: id("aceite") });
  const caixaErro = el("div", { "aria-live": "assertive" });
  const enviar = el("button", { class: "botao botao--primario botao--largo", type: "button", text: "Enviar cadastro" });
  const resumo = el("dl", { class: "dados" },
    el("dt", { text: "Responsável" }), el("dd", { text: `${s.resp1.nome} · ${s.resp1.telefone}` }),
    s.resp2.nome ? [el("dt", { text: "Segundo responsável" }), el("dd", { text: [s.resp2.nome, s.resp2.telefone].filter(Boolean).join(" · ") })] : null,
    el("dt", { text: s.criancas.length === 1 ? "Criança" : "Crianças" }),
    el("dd", { text: s.criancas.map((c) => `${c.nome} (${textoIdade(idadeEm(c.nascimento))})`).join(", ") }),
    el("dt", { text: "Autorizados a retirar" }), el("dd", { text: s.autorizados.length ? s.autorizados.map((a) => a.nome).join(", ") : "Nenhum" }));

  enviar.addEventListener("click", async () => {
    montar(caixaErro);
    if (!aceite.checked) { montar(caixaErro, aviso("erro", "Para concluir, marque que leu e aceita o termo.")); aceite.focus(); return; }
    enviar.disabled = true; enviar.textContent = "Enviando… (pode levar até 1 minuto)";
    const dados = {
      termo_versao: s.termo?.versao,
      responsaveis: [
        { nome: s.resp1.nome, telefone: telefoneParaLogin(s.resp1.telefone) },
        ...(s.resp2.nome ? [{ nome: s.resp2.nome, telefone: telefoneParaLogin(s.resp2.telefone) || null }] : []),
      ],
      criancas: s.criancas.map((c) => ({
        nome: c.nome, nascimento: c.nascimento, perfil: c.perfil, alergias: c.alergias || null,
        relacao: c.relacao, relacao_detalhe: c.detalhe || null,
        relacao2: c.relacao2 || null, relacao2_detalhe: c.detalhe2 || null,
      })),
      autorizados: s.autorizados.map((a) => ({ nome: a.nome, telefone: telefoneParaLogin(a.telefone), observacao: a.observacao || null })),
    };
    const fotos = { criancas: s.criancas.map((c) => c.foto || null), responsavel: s.resp1.foto || null };
    const r = await cadastroEnviar(s.ticket, dados, fotos);
    if (r.ok) { telaSucesso(r); return; }
    enviar.disabled = false; enviar.textContent = "Enviar cadastro";
    tratarErro(r, caixaErro);
  });

  moldura(5, "Conferir e aceitar",
    mensagem ? aviso("atencao", mensagem) : null,
    el("section", { class: "cartao" }, el("h2", { text: "Confira os dados" }), resumo,
      el("button", { class: "botao botao--texto", type: "button", text: "Corrigir", onclick: () => passo1() })),
    el("section", { class: "cartao" },
      el("h2", { text: "Termo de uso de dados e imagem" }),
      el("div", { class: "termo-texto", tabindex: "0", role: "document", "aria-label": "Texto do termo", text: s.termo?.texto || "" }),
      el("div", { class: "linha mt-3" }, aceite,
        el("label", { for: aceite.id, text: "Li e aceito o termo, em nome da família." }))),
    caixaErro,
    enviar,
    el("p", { class: "mt-3" }, el("button", { class: "botao botao--texto", type: "button", text: "Voltar", onclick: () => passo4() })));
}

/** Erros do envio → mensagem e, quando der, volta ao passo certo. */
function tratarErro(r, caixaErro) {
  const c = r.codigo;
  if (c === "telefone_ja_cadastrado") { telaJaCadastrado(); return; }
  if (c === "ticket") { passo1("O tempo para concluir o cadastro acabou. Confirme o telefone de novo; os dados preenchidos continuam aqui."); return; }
  if (c === "telefone2_ja_cadastrado") {
    passo2(); montarAvisoTopo("O WhatsApp do segundo responsável já está cadastrado no Fonte Kids. Deixe o telefone dele(a) em branco; depois ele(a) entra no app com o próprio telefone.");
    return;
  }
  if (c === "termo_desatualizado") { montar(caixaErro, aviso("erro", "O termo foi atualizado. Recarregue a página e confirme o telefone de novo.")); return; }
  if (c === "limite_diario") { montar(caixaErro, aviso("erro", "Muitos cadastros hoje. Tente de novo amanhã ou fale com a recepção do Fonte Kids.")); return; }
  if (c === "grande" || c === "foto") { montar(caixaErro, aviso("erro", "Alguma foto não pôde ser usada. Troque a foto da criança e tente de novo.")); return; }
  if (c === "conexao") { montar(caixaErro, aviso("erro", "Sem conexão com o servidor. Verifique a internet e toque em Enviar de novo.")); return; }
  if (c === "dados" && r.campo) {
    const m = /^([a-z0-9_]+?)_(\d+)$/.exec(r.campo);
    const n = m ? Number(m[2]) : 0;
    const qual = m ? m[1] : r.campo;
    const textos = {
      nome_responsavel: "Confira o nome do responsável.", telefone_responsavel: "Confira o telefone do responsável.",
      nome_crianca: `Confira o nome da ${n}ª criança.`, nascimento_crianca: `Confira a data de nascimento da ${n}ª criança (0 a 12 anos).`,
      alergias_crianca: `Alergias da ${n}ª criança: use no máximo 500 caracteres.`, relacao_crianca: `Confira a sua relação com a ${n}ª criança.`,
      relacao2_crianca: `Confira a relação do segundo responsável com a ${n}ª criança.`,
      nome_autorizado: `Confira o nome do ${n}º autorizado.`, telefone_autorizado: `Confira o telefone do ${n}º autorizado.`,
      observacao_autorizado: `"Quem é" do ${n}º autorizado: use no máximo 120 caracteres.`,
    };
    montar(caixaErro, aviso("erro", textos[qual] || "Confira os dados e tente de novo."));
    return;
  }
  montar(caixaErro, aviso("erro", "Não foi possível enviar agora. Tente de novo em alguns minutos. Seus dados continuam aqui."));
}
function montarAvisoTopo(texto) {
  const p = alvoTela.querySelector(".progresso");
  if (p) p.after(aviso("atencao", texto));
}

// ---------- Tela final ----------
function telaSucesso(r) {
  const nomes = s.criancas.map((c) => primeiro(c.nome)).join(", ");
  const links = (r.links || []).filter((l) => /^https:\/\/chat\.whatsapp\.com\/[A-Za-z0-9]+$/.test(l.link));
  const segundo = r.segundo_login && s.resp2.nome ? primeiro(s.resp2.nome) : null;
  const fotosFalharam = Number(r.fotos_falharam) || 0;
  s.ticket = null; // o cadastro acabou; nada fica guardado

  moldura(0, "",
    aviso("sucesso", `Cadastro concluído! ${nomes ? `${nomes} já ${s.criancas.length > 1 ? "podem" : "pode"} fazer check-in.` : ""}`),
    fotosFalharam ? aviso("atencao", `${fotosFalharam === 1 ? "Uma foto não foi enviada" : `${fotosFalharam} fotos não foram enviadas`}. Coloque depois pelo app, em Família.`) : null,
    links.length ? el("section", { class: "cartao" },
      el("h2", { text: "Grupo de WhatsApp dos responsáveis" }),
      el("p", { text: "Avisos do Fonte Kids chegam por lá. Toque para entrar:" }),
      links.map((l) => el("p", {}, el("a", { class: "botao botao--whatsapp botao--largo", href: l.link, target: "_blank", rel: "noopener noreferrer" },
        icone("conversa"), `Entrar no grupo · ${NOME_GRUPO[l.grupo] || "Responsáveis"}`)))) : null,
    el("section", { class: "cartao" },
      el("h2", { text: "Entre no app do Fonte Kids" }),
      el("p", { text: "Veja o check-in e o código das crianças, atualize dados e fotos." }),
      el("ol", { class: "lista-passos" },
        el("li", { text: "Login: o seu WhatsApp com DDD." }),
        el("li", { text: "Senha no primeiro acesso: 55 + DDD + o número, só os dígitos (ex.: 5527900000000)." }),
        el("li", { text: "Depois você cria uma senha nova e pode instalar o app na tela inicial." })),
      segundo ? el("p", { class: "suave mt-2", text: `${segundo} também pode entrar com o WhatsApp dele(a), do mesmo jeito.` }) : null,
      el("p", { class: "mt-3" }, el("a", { class: "botao botao--primario botao--largo", href: "#/entrar", text: "Entrar no app" }))));
}
