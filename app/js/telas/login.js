// =====================================================================
// Tela: Entrar (Fase 10 · Etapa 2 – login real)
// Telefone → e-mail técnico; captcha obrigatório; "Manter conectado";
// mensagens de erro genéricas (nunca diz se o telefone existe).
// =====================================================================
import { el, montar, aviso, mascararTelefone, telefoneParaLogin } from "../ui.js";
import { entrar, manterConectadoAtual } from "../supabase.js";
import { criarCaptcha } from "../captcha.js";
import { irPara } from "../app.js";

export const layout = "central";
export const titulo = "Entrar";

export async function render(alvo) {
  const erroTel = el("span", { class: "campo__erro", id: "erro-tel", hidden: true });
  const tel = el("input", {
    class: "entrada", id: "tel", type: "tel", inputmode: "numeric", autocomplete: "username",
    placeholder: "(27) 90000-0000", "aria-describedby": "ajuda-tel erro-tel", required: true,
    oninput: (e) => { e.target.value = mascararTelefone(e.target.value); limparErro(); },
  });
  const senha = el("input", {
    class: "entrada", id: "senha", type: "password", autocomplete: "current-password", required: true,
    oninput: () => { caixaErro.replaceChildren(); },
  });
  const verSenha = el("button", {
    class: "botao botao--texto", type: "button", "aria-controls": "senha", text: "Mostrar",
    onclick: () => {
      const oculta = senha.type === "password";
      senha.type = oculta ? "text" : "password";
      verSenha.textContent = oculta ? "Ocultar" : "Mostrar";
    },
  });
  const manter = el("input", { type: "checkbox", id: "manter", checked: manterConectadoAtual() });
  const caixaErro = el("div", { "aria-live": "assertive" });
  const lugarCaptcha = el("div", { class: "captcha", "data-acao": "login" });
  const botao = el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Entrar", disabled: true });

  let captcha = null;
  let enviando = false;

  function limparErro() { erroTel.hidden = true; tel.removeAttribute("aria-invalid"); caixaErro.replaceChildren(); }
  function mostrarErro(t) { montar(caixaErro, aviso("erro", t)); }
  function atualizarBotao(temToken) { botao.disabled = enviando || !temToken; }

  const form = el("form", { class: "cartao", novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (enviando) return;
      limparErro();
      const t = telefoneParaLogin(tel.value);
      if (!t) {
        erroTel.textContent = "Digite o telefone com DDD.";
        erroTel.hidden = false; tel.setAttribute("aria-invalid", "true"); tel.focus();
        return;
      }
      if (!senha.value) { mostrarErro("Digite a sua senha."); senha.focus(); return; }
      const token = captcha?.token();
      if (!token) { mostrarErro("Conclua a verificação anti-robô."); return; }

      enviando = true; botao.disabled = true; botao.textContent = "Entrando…";
      const r = await entrar(t, senha.value, token, manter.checked);
      enviando = false; botao.textContent = "Entrar";
      if (r.ok) { senha.value = ""; irPara("/inicio"); return; }
      senha.value = "";
      mostrarErro(r.erro);
      captcha?.reiniciar(); // cada token vale uma vez
      senha.focus();
    } },
    el("h1", { class: "so-leitor", text: "Entrar" }),
    el("div", { class: "campo" },
      el("label", { class: "campo__rotulo", for: "tel", text: "Telefone" }),
      tel,
      el("span", { class: "campo__ajuda", id: "ajuda-tel", text: "O mesmo número cadastrado no Fonte Kids, com DDD." }),
      erroTel),
    el("div", { class: "campo" },
      el("label", { class: "campo__rotulo", for: "senha", text: "Senha" }),
      el("div", { class: "senha-box" }, senha, verSenha)),
    el("label", { class: "marcar", for: "manter" }, manter, "Manter conectado neste aparelho"),
    el("p", { class: "campo__ajuda", text: "Em aparelho de outra pessoa, deixe desmarcado: você sai ao fechar o navegador." }),
    lugarCaptcha,
    caixaErro,
    botao,
    el("p", { class: "centro" },
      el("a", { href: "#/esqueci-senha", text: "Esqueci minha senha" })));

  montar(alvo,
    el("div", { class: "marca" },
      el("img", { src: "img/logo.png", alt: "Logo do Fonte Kids" }),
      el("p", { class: "marca__titulo", text: "Fonte Kids" }),
      el("p", { class: "marca__sub", text: "Ministério infantil · Fonte de Vida Itaparica" })),
    aviso("info", "Versão de teste do app novo."),
    form);

  try {
    captcha = await criarCaptcha(lugarCaptcha, atualizarBotao);
  } catch {
    montar(lugarCaptcha, aviso("atencao", "Não foi possível carregar a verificação anti-robô. Verifique a internet e recarregue a página."));
  }
}
