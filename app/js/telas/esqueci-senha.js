// =====================================================================
// Tela: Esqueci minha senha (Fase 10 · Etapa 2 – plano, seção 4.2)
// Telefone + captcha → pedido para a liderança. Não redefine nada sozinho.
// A resposta é sempre a mesma, exista o telefone ou não.
// =====================================================================
import { el, montar, aviso, mascararTelefone, telefoneParaLogin } from "../ui.js";
import { pedirNovaSenha } from "../supabase.js";
import { criarCaptcha } from "../captcha.js";

export const layout = "central";
export const titulo = "Esqueci minha senha";

export async function render(alvo) {
  const erroTel = el("span", { class: "campo__erro", id: "erro-tel-rec", hidden: true });
  const tel = el("input", {
    class: "entrada", id: "tel-rec", type: "tel", inputmode: "numeric", autocomplete: "username",
    placeholder: "(27) 90000-0000", "aria-describedby": "erro-tel-rec", required: true,
    oninput: (e) => { e.target.value = mascararTelefone(e.target.value); limpar(); },
  });
  const caixaErro = el("div", { "aria-live": "assertive" });
  const lugarCaptcha = el("div", { class: "captcha", "data-acao": "pedido-senha" });
  const botao = el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Enviar pedido", disabled: true });
  let captcha = null;
  let enviando = false;

  function limpar() { erroTel.hidden = true; tel.removeAttribute("aria-invalid"); caixaErro.replaceChildren(); }

  const form = el("form", { class: "cartao", novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (enviando) return;
      limpar();
      const t = telefoneParaLogin(tel.value);
      if (!t) {
        erroTel.textContent = "Digite o telefone com DDD.";
        erroTel.hidden = false; tel.setAttribute("aria-invalid", "true"); tel.focus();
        return;
      }
      const token = captcha?.token();
      if (!token) { montar(caixaErro, aviso("erro", "Conclua a verificação anti-robô.")); return; }

      enviando = true; botao.disabled = true; botao.textContent = "Enviando…";
      const r = await pedirNovaSenha(t, token);
      enviando = false; botao.textContent = "Enviar pedido";
      if (r.ok) {
        montar(conteudo,
          aviso("sucesso", r.mensagem),
          el("p", { class: "centro", text: "Quando a liderança redefinir, entre com a senha inicial e troque por uma nova logo em seguida." }),
          el("p", { class: "centro" }, el("a", { class: "botao botao--secundario", href: "#/entrar", text: "Voltar" })));
        return;
      }
      montar(caixaErro, aviso("erro", r.erro));
      captcha?.reiniciar();
    } },
    el("div", { class: "campo" },
      el("label", { class: "campo__rotulo", for: "tel-rec", text: "Telefone" }),
      tel, erroTel),
    lugarCaptcha,
    caixaErro,
    botao,
    el("p", { class: "centro" }, el("a", { href: "#/entrar", text: "Voltar" })));

  const conteudo = el("div", {},
    el("h1", { class: "marca__titulo", text: "Esqueci minha senha" }),
    el("p", { text: "A liderança recebe o pedido e fala com você antes de redefinir." }),
    form);

  montar(alvo,
    el("div", { class: "marca" }, el("img", { src: "img/logo.png", alt: "Logo do Fonte Kids" })),
    conteudo);

  try {
    captcha = await criarCaptcha(lugarCaptcha, (ok) => { botao.disabled = enviando || !ok; });
  } catch {
    montar(lugarCaptcha, aviso("atencao", "Não foi possível carregar a verificação anti-robô. Verifique a internet e recarregue a página."));
  }
}
