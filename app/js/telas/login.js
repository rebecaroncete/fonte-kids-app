// =====================================================================
// Tela: Entrar (Etapa 1 = só o visual; o login de verdade entra na Etapa 2)
// =====================================================================
import { el, montar, aviso, toast, mascararTelefone, telefoneParaLogin } from "../ui.js";

export const layout = "central";
export const titulo = "Entrar";

export function render(alvo) {
  const erroTel = el("span", { class: "campo__erro", id: "erro-tel", hidden: true });
  const tel = el("input", {
    class: "entrada", id: "tel", type: "tel", inputmode: "numeric", autocomplete: "username",
    placeholder: "(27) 90000-0000", "aria-describedby": "ajuda-tel erro-tel", required: true,
    oninput: (e) => { e.target.value = mascararTelefone(e.target.value); limparErro(); },
  });
  const senha = el("input", {
    class: "entrada", id: "senha", type: "password", autocomplete: "current-password", required: true,
  });
  const verSenha = el("button", {
    class: "botao botao--texto", type: "button", "aria-controls": "senha", text: "Mostrar",
    onclick: () => {
      const oculta = senha.type === "password";
      senha.type = oculta ? "text" : "password";
      verSenha.textContent = oculta ? "Ocultar" : "Mostrar";
    },
  });
  const manter = el("input", { type: "checkbox", id: "manter", checked: true });

  function limparErro() { erroTel.hidden = true; tel.removeAttribute("aria-invalid"); }

  const form = el("form", { class: "cartao", novalidate: true, onsubmit: (e) => {
      e.preventDefault();
      if (!telefoneParaLogin(tel.value)) {
        erroTel.textContent = "Digite o telefone com DDD.";
        erroTel.hidden = false; tel.setAttribute("aria-invalid", "true"); tel.focus();
        return;
      }
      toast("info", "Prévia do visual: o login de verdade chega na próxima etapa.");
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
    el("div", { class: "aviso aviso--atencao", id: "captcha-lugar" },
      el("span", { class: "aviso__icone", "aria-hidden": "true", text: "!" }),
      el("p", { text: "Aqui vai aparecer a verificação anti-robô (Etapa 2)." })),
    el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Entrar" }),
    el("p", { class: "centro" },
      el("button", { class: "botao botao--texto", type: "button", text: "Esqueci minha senha",
        onclick: () => toast("info", "Fale com a liderança do Fonte Kids para redefinir sua senha.", 6000) })));

  montar(alvo,
    el("div", { class: "marca" },
      el("img", { src: "img/logo.png", alt: "Logo do Fonte Kids" }),
      el("p", { class: "marca__titulo", text: "Fonte Kids" }),
      el("p", { class: "marca__sub", text: "Ministério infantil · Fonte de Vida Itaparica" })),
    aviso("info", "Versão de teste do app novo. Ainda não é possível entrar."),
    form,
    el("p", { class: "centro" }, el("a", { href: "#/vitrine", text: "Ver vitrine de componentes" })));
}
