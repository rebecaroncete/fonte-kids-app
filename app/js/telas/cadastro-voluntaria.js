// =====================================================================
// Tela pública: Cadastro de voluntária(o) (Fase 5 · Etapa 5F)
//   #/cadastro-voluntaria   (o link antigo ?tela=cadastro_voluntaria vem pra cá)
// Sem login. Só esta tela; nada do resto do app.
//
// Passos: 1 Seus dados → 2 Como quer servir → 3 Foto, termo e envio.
// • Tudo fica só na memória desta aba até o envio (nada no aparelho).
// • O envio vai para a Edge Function "cadastro-publico" (captcha conferido
//   no servidor), que grava só um PEDIDO. A liderança aprova ou recusa.
// • A resposta é sempre a mesma: a tela não diz se o telefone já existe.
// • Idade mínima: 12 anos. Foto obrigatória.
// =====================================================================
import { el, montar, aviso, carregando, mascararTelefone, telefoneParaLogin } from "../ui.js";
import { criarCaptcha } from "../captcha.js";
import { prepararFoto } from "../foto.js";
import { voluntariaOpcoes, voluntariaEnviar } from "../supabase.js";

export const layout = "central";
export const titulo = "Cadastro de voluntária(o)";

const FUSO = "America/Sao_Paulo";
const TOTAL_PASSOS = 3;
const DIAS = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];
const FUNCOES = [["professora", "Professor(a)", "Conduz a lição e as atividades da sala."],
                 ["auxiliar", "Auxiliar", "Ajuda o(a) professor(a) e cuida das crianças."]];
const SEXOS = [["", "Escolha"], ["F", "Feminino"], ["M", "Masculino"]];
const ORDINAL = ["1ª opção (preferida)", "2ª opção", "3ª opção", "4ª opção"];

const hojeIso = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO });
function menos12anos() {
  const [a, m, d] = hojeIso().split("-");
  return `${Number(a) - 12}-${m}-${d}`;
}
function idadeEm(nascIso) {
  if (!nascIso) return null;
  const [a, m, d] = nascIso.split("-").map(Number);
  const [ha, hm, hd] = hojeIso().split("-").map(Number);
  let anos = ha - a;
  if (hm < m || (hm === m && hd < d)) anos--;
  return anos;
}

let alvoTela = null;
let s = null;
let opcoes = null;
const novoEstado = () => ({
  nome: "", telefone: "", nascimento: "", email: "", profissao: "", sexo: "",
  funcao: "", salas: ["", "", "", ""], cultos: ["", "", ""], foto: null,
});

export async function render(alvo) {
  alvoTela = alvo;
  s = novoEstado();
  await carregarOpcoes();
}

async function carregarOpcoes() {
  moldura(0, "", carregando());
  const r = await voluntariaOpcoes();
  if (!alvoTela?.isConnected) return;
  if (!r.ok) {
    moldura(0, "", aviso("erro", r.codigo === "conexao"
      ? "Sem conexão com o servidor. Verifique a internet."
      : "Não foi possível abrir o cadastro agora."),
      el("button", { class: "botao botao--secundario mt-3", type: "button", text: "Tentar de novo", onclick: carregarOpcoes }));
    return;
  }
  opcoes = r;
  passo1();
}

// ---------- Utilidades ----------
let contador = 0;
const novoId = (b) => `vol-${b}-${++contador}`;
function campo(rotulo, entrada, ajuda) {
  if (!entrada.id) entrada.id = novoId("campo");
  return el("div", { class: "campo" },
    el("label", { class: "campo__rotulo", for: entrada.id, text: rotulo }),
    entrada,
    ajuda ? el("span", { class: "campo__ajuda", text: ajuda }) : null);
}
const entradaTexto = (valor = "", extra = {}) =>
  el("input", { class: "entrada", type: "text", maxlength: "120", autocomplete: "off", value: valor, ...extra });
function seletor(lista, valor = "") {
  const sel = el("select", { class: "entrada" }, lista.map(([v, t]) => el("option", { value: v, text: t })));
  sel.value = valor;
  return sel;
}

function moldura(numero, tituloPasso, ...conteudo) {
  montar(alvoTela,
    el("div", { class: "marca" }, el("img", { src: "img/logo.png", alt: "Logo do Fonte Kids" }),
      el("h1", { class: "marca__titulo", text: "Voluntários(as) Fonte Kids" })),
    numero ? el("p", { class: "passo-rotulo", text: `Passo ${numero} de ${TOTAL_PASSOS} · ${tituloPasso}` }) : null,
    numero ? el("progress", { class: "progresso", max: String(TOTAL_PASSOS), value: String(numero), "aria-hidden": "true" }) : null,
    ...conteudo);
  window.scrollTo(0, 0);
}

// ---------- Passo 1: dados ----------
function passo1() {
  const nome = entradaTexto(s.nome, { autocomplete: "name" });
  const tel = el("input", { class: "entrada", type: "tel", inputmode: "numeric", autocomplete: "off",
    placeholder: "(27) 90000-0000", value: s.telefone });
  tel.addEventListener("input", () => { tel.value = mascararTelefone(tel.value); });
  const nasc = el("input", { class: "entrada", type: "date", max: menos12anos(), min: "1920-01-01", value: s.nascimento });
  const email = el("input", { class: "entrada", type: "email", maxlength: "120", autocomplete: "email",
    placeholder: "exemplo@email.com", value: s.email });
  const prof = entradaTexto(s.profissao, { maxlength: "80", placeholder: "Ex.: pedagoga" });
  const sexo = seletor(SEXOS, s.sexo);
  const caixaErro = el("div", { "aria-live": "assertive" });

  const form = el("form", { class: "cartao", novalidate: true, onsubmit: (e) => {
      e.preventDefault();
      montar(caixaErro);
      const erro = (campoErr, texto) => { campoErr.focus(); montar(caixaErro, aviso("erro", texto)); };
      s.nome = nome.value.trim(); s.telefone = tel.value; s.nascimento = nasc.value;
      s.email = email.value.trim(); s.profissao = prof.value.trim(); s.sexo = sexo.value;
      if (s.nome.length < 3) return erro(nome, "Informe o seu nome completo.");
      if (!telefoneParaLogin(s.telefone)) return erro(tel, "Digite o WhatsApp com DDD.");
      const anos = idadeEm(s.nascimento);
      if (anos === null || s.nascimento < "1920-01-01") return erro(nasc, "Informe a sua data de nascimento.");
      if (anos < 12) return erro(nasc, "O voluntariado no Fonte Kids é a partir de 12 anos.");
      if (s.email && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s.email)) return erro(email, "E-mail inválido. Confira ou deixe em branco.");
      if (!s.sexo) return erro(sexo, "Escolha o sexo: feminino ou masculino.");
      passo2();
    } },
    campo("Nome completo", nome),
    campo("WhatsApp (com DDD)", tel, "A liderança vai falar com você por aqui. Depois da aprovação, também é o seu login no app."),
    campo("Data de nascimento", nasc),
    campo("E-mail (opcional)", email, "Para receber a escala na agenda."),
    campo("Profissão (opcional)", prof),
    campo("Sexo", sexo),
    caixaErro,
    el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Continuar" }));

  moldura(1, "Seus dados",
    el("p", { text: "Quer servir no ministério infantil? Preencha o cadastro. A liderança confere e fala com você." }),
    form);
}

// ---------- Passo 2: como quer servir ----------
function passo2() {
  const caixaErro = el("div", { "aria-live": "assertive" });
  const grupoFuncao = novoId("funcao");
  const funcoes = FUNCOES.map(([v, t, ajuda]) => {
    const r = el("input", { type: "radio", name: grupoFuncao, value: v, id: novoId("f"), checked: s.funcao === v });
    return el("div", { class: "linha" }, r, el("label", { for: r.id },
      el("strong", { text: t }), el("span", { class: "campo__ajuda", text: ` – ${ajuda}` })));
  });
  const opcoesSalas = [["", "Escolha…"], ...opcoes.salas.map((x) => [x.id, x.nome])];
  const opcoesCultos = [["", "Escolha…"], ...opcoes.cultos.map((x) => [x.id, `${x.nome} (${DIAS[x.dia_semana] || ""} ${x.horario})`])];
  const selSalas = s.salas.map((v) => seletor(opcoesSalas, v));
  const selCultos = s.cultos.map((v) => seletor(opcoesCultos, v));

  function lerLista(sels, nomeLista) {
    const lista = sels.map((x) => x.value).filter(Boolean);
    if (!sels[0].value) return { erro: `Escolha a 1ª opção de ${nomeLista}.`, foco: sels[0] };
    if (new Set(lista).size !== lista.length) return { erro: `Não repita a mesma opção de ${nomeLista}.`, foco: sels[0] };
    return { lista };
  }

  const form = el("form", { class: "cartao", novalidate: true, onsubmit: (e) => {
      e.preventDefault();
      montar(caixaErro);
      s.funcao = form.querySelector(`input[name="${grupoFuncao}"]:checked`)?.value || "";
      s.salas = selSalas.map((x) => x.value);
      s.cultos = selCultos.map((x) => x.value);
      if (!s.funcao) { montar(caixaErro, aviso("erro", "Escolha como quer servir.")); return; }
      const a = lerLista(selSalas, "faixa de idade");
      if (a.erro) { a.foco.focus(); montar(caixaErro, aviso("erro", a.erro)); return; }
      const b = lerLista(selCultos, "culto");
      if (b.erro) { b.foco.focus(); montar(caixaErro, aviso("erro", b.erro)); return; }
      passo3();
    } },
    el("fieldset", { class: "campo" }, el("legend", { class: "campo__rotulo", text: "Como quer servir" }), funcoes),
    el("h2", { class: "mt-3", text: "Faixas de idade" }),
    el("p", { class: "suave", text: "Em quais salas prefere servir? Só a 1ª é obrigatória." }),
    selSalas.slice(0, Math.max(1, opcoes.salas.length)).map((x, i) => campo(ORDINAL[i], x)),
    el("h2", { class: "mt-3", text: "Cultos" }),
    el("p", { class: "suave", text: "Em quais cultos prefere servir? Só o 1º é obrigatório." }),
    selCultos.slice(0, Math.max(1, Math.min(3, opcoes.cultos.length))).map((x, i) => campo(ORDINAL[i], x)),
    caixaErro,
    el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Continuar" }),
    el("p", { class: "mt-3" }, el("button", { class: "botao botao--texto", type: "button", text: "Voltar", onclick: () => passo1() })));

  moldura(2, "Como quer servir", form);
}

// ---------- Passo 3: foto, termo e envio ----------
function passo3() {
  const previa = el("div", { class: "avatar avatar--grande previa-foto", "aria-hidden": "true" });
  if (s.foto) previa.append(el("img", { src: s.foto, alt: "" }));
  const situacaoFoto = el("span", { class: "campo__ajuda", text: s.foto ? "Foto escolhida." : "Só o rosto, de frente, com boa luz." });
  const arquivo = el("input", { type: "file", accept: "image/*", class: "entrada", id: novoId("foto") });
  arquivo.addEventListener("change", async () => {
    const f = arquivo.files?.[0];
    if (!f) return;
    situacaoFoto.textContent = "Preparando a foto…";
    try {
      s.foto = await prepararFoto(f);
      previa.replaceChildren(el("img", { src: s.foto, alt: "" }));
      situacaoFoto.textContent = "Foto escolhida.";
    } catch (e) { situacaoFoto.textContent = e.message; }
  });

  const nomeSala = new Map(opcoes.salas.map((x) => [x.id, x.nome]));
  const nomeCulto = new Map(opcoes.cultos.map((x) => [x.id, x.nome]));
  const resumo = el("dl", { class: "dados" },
    el("dt", { text: "Nome" }), el("dd", { text: s.nome }),
    el("dt", { text: "WhatsApp" }), el("dd", { text: s.telefone }),
    el("dt", { text: "Idade" }), el("dd", { text: `${idadeEm(s.nascimento)} anos` }),
    el("dt", { text: "Função" }), el("dd", { text: FUNCOES.find(([v]) => v === s.funcao)?.[1] || "" }),
    el("dt", { text: "Faixas de idade" }), el("dd", { text: s.salas.filter(Boolean).map((x) => nomeSala.get(x)).join(", ") }),
    el("dt", { text: "Cultos" }), el("dd", { text: s.cultos.filter(Boolean).map((x) => nomeCulto.get(x)).join(", ") }));

  const aceite = el("input", { type: "checkbox", id: novoId("aceite") });
  const lugarCaptcha = el("div", { class: "captcha", "data-acao": "cadastro_voluntaria" });
  const caixaErro = el("div", { "aria-live": "assertive" });
  const enviar = el("button", { class: "botao botao--primario botao--largo", type: "button", text: "Enviar cadastro", disabled: true });
  let captcha = null;
  let enviando = false;

  enviar.addEventListener("click", async () => {
    if (enviando) return;
    montar(caixaErro);
    if (!s.foto) { arquivo.focus(); montar(caixaErro, aviso("erro", "A foto é obrigatória.")); return; }
    if (!aceite.checked) { aceite.focus(); montar(caixaErro, aviso("erro", "Para enviar, marque que leu e aceita o termo.")); return; }
    const token = captcha?.token();
    if (!token) { montar(caixaErro, aviso("erro", "Conclua a verificação anti-robô.")); return; }
    enviando = true; enviar.disabled = true; enviar.textContent = "Enviando…";
    const r = await voluntariaEnviar(token, {
      nome: s.nome, telefone: telefoneParaLogin(s.telefone), nascimento: s.nascimento,
      email: s.email || null, profissao: s.profissao || null, sexo: s.sexo || null, funcao: s.funcao,
      salas: s.salas.filter(Boolean), cultos: s.cultos.filter(Boolean), termo_versao: opcoes.termo?.versao,
    }, s.foto);
    enviando = false;
    if (r.ok) { telaSucesso(r); return; }
    enviar.textContent = "Enviar cadastro";
    captcha?.reiniciar();
    montar(caixaErro, aviso("erro", textoErro(r)));
  });

  moldura(3, "Foto e termo",
    el("section", { class: "cartao" },
      el("div", { class: "campo" },
        el("label", { class: "campo__rotulo", for: arquivo.id, text: "Sua foto (obrigatória)" }),
        el("div", { class: "linha" }, previa, el("div", { class: "flex-1" }, arquivo, situacaoFoto)))),
    el("section", { class: "cartao" }, el("h2", { text: "Confira os dados" }), resumo,
      el("button", { class: "botao botao--texto", type: "button", text: "Corrigir", onclick: () => passo1() })),
    el("section", { class: "cartao" },
      el("h2", { text: "Termo de uso de dados e imagem" }),
      el("div", { class: "termo-texto", tabindex: "0", role: "document", "aria-label": "Texto do termo", text: opcoes.termo?.texto || "" }),
      el("div", { class: "linha mt-3" }, aceite, el("label", { for: aceite.id, text: "Li e aceito o termo." }))),
    lugarCaptcha,
    caixaErro,
    enviar,
    el("p", { class: "mt-3" }, el("button", { class: "botao botao--texto", type: "button", text: "Voltar", onclick: () => passo2() })));

  criarCaptcha(lugarCaptcha, (ok) => { enviar.disabled = enviando || !ok; })
    .then((c) => { captcha = c; })
    .catch(() => montar(lugarCaptcha, aviso("atencao", "Não foi possível carregar a verificação anti-robô. Verifique a internet e recarregue a página.")));
}

function textoErro(r) {
  if (r.codigo === "captcha") return "Não foi possível confirmar a verificação anti-robô. Tente de novo.";
  if (r.codigo === "conexao") return "Sem conexão com o servidor. Verifique a internet e tente de novo.";
  if (r.codigo === "limite_diario") return "Muitos cadastros hoje. Tente de novo amanhã ou fale com a liderança.";
  if (r.codigo === "termo_desatualizado") return "O termo foi atualizado. Recarregue a página e confira de novo.";
  if (r.codigo === "foto" || r.codigo === "grande") return "Foto inválida ou grande demais. Escolha outra.";
  if (r.codigo === "dados") {
    const campos = { nome: "o nome", telefone: "o WhatsApp", nascimento: "a data de nascimento (a partir de 12 anos)",
      email: "o e-mail", profissao: "a profissão", sexo: "o sexo", funcao: "a função",
      salas: "as faixas de idade", cultos: "os cultos", preferencias: "as preferências" };
    return `Confira ${campos[r.campo] || "os dados"} e tente de novo.`;
  }
  return "Não foi possível enviar agora. Tente de novo em alguns minutos.";
}

function telaSucesso(r) {
  const nome = s.nome.split(/\s+/)[0] || "";
  s = novoEstado(); // nada fica guardado na tela
  moldura(0, "",
    aviso("sucesso", "Cadastro enviado!"),
    el("div", { class: "cartao" },
      el("h2", { text: `Obrigado, ${nome}!` }),
      el("p", { text: "A liderança do Fonte Kids vai conferir o seu cadastro e falar com você pelo WhatsApp." }),
      el("p", { class: "suave", text: "Depois da aprovação, você entra no app com o seu WhatsApp. No primeiro acesso, a senha é a sua data de nascimento, só os números (ex.: 01022000), e você cria uma senha nova." }),
      r.foto_falhou ? aviso("atencao", "A foto não chegou. Envie uma foto para a liderança pelo WhatsApp.") : null));
}
