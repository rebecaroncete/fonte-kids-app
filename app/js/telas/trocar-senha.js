// =====================================================================
// Tela: Trocar senha (Fase 10 · Etapa 4)
// Pede a senha atual + verificação anti-robô (assim, quem pegar um
// aparelho com o app aberto não troca a senha), a nova e a repetição.
// Depois da troca, os outros aparelhos deste login são desconectados.
// =====================================================================
import { el, montar, aviso, toast, digitos } from "../ui.js";
import { trocarSenha, telefoneDoLoginAtual } from "../supabase.js";
import { criarCaptcha } from "../captcha.js";
import { irPara } from "../app.js";

export const layout = "padrao";
export const titulo = "Trocar senha";

function campoSenha(id, rotulo, autocomplete) {
  const entrada = el("input", { class: "entrada", id, type: "password", autocomplete, required: true });
  const ver = el("button", {
    class: "botao botao--texto", type: "button", "aria-controls": id, text: "Mostrar",
    onclick: () => {
      const oculta = entrada.type === "password";
      entrada.type = oculta ? "text" : "password";
      ver.textContent = oculta ? "Ocultar" : "Mostrar";
    },
  });
  const bloco = el("div", { class: "campo" },
    el("label", { class: "campo__rotulo", for: id, text: rotulo }),
    el("div", { class: "senha-box" }, entrada, ver));
  return { entrada, bloco };
}

export async function render(alvo) {
  const telefone = await telefoneDoLoginAtual(); // só para recusar "senha = telefone"
  const atual = campoSenha("senha-atual", "Senha atual", "current-password");
  const nova = campoSenha("nova-senha", "Nova senha", "new-password");
  const conf = campoSenha("confirmar-senha", "Repita a nova senha", "new-password");
  const caixaErro = el("div", { "aria-live": "assertive" });
  const lugarCaptcha = el("div", { class: "captcha", "data-acao": "trocar_senha" });
  const botao = el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Salvar", disabled: true });
  let captcha = null;
  let enviando = false;

  function problema() {
    const s = nova.entrada.value;
    if (!atual.entrada.value) return ["Digite a sua senha atual.", atual];
    if (s.length < 8) return ["A nova senha precisa ter pelo menos 8 caracteres.", nova];
    if (s !== conf.entrada.value) return ["As duas senhas novas não são iguais.", conf];
    if (s === atual.entrada.value) return ["A nova senha precisa ser diferente da atual.", nova];
    const d = digitos(s);
    if (telefone && d === s && (d === telefone || d === telefone.slice(2))) return ["A nova senha não pode ser o seu telefone.", nova];
    if (/^(.)\1+$/.test(s)) return ["Escolha uma senha menos óbvia (não repita o mesmo caractere).", nova];
    return null;
  }

  const form = el("form", { class: "cartao", novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (enviando) return;
      caixaErro.replaceChildren();
      const p = problema();
      if (p) { montar(caixaErro, aviso("erro", p[0])); p[1].entrada.focus(); return; }
      const token = captcha?.token();
      if (!token) { montar(caixaErro, aviso("erro", "Conclua a verificação anti-robô.")); return; }

      enviando = true; botao.disabled = true; botao.textContent = "Trocando…";
      const r = await trocarSenha(atual.entrada.value, nova.entrada.value, token);
      enviando = false; botao.textContent = "Salvar";
      atual.entrada.value = "";
      if (!r.ok) {
        montar(caixaErro, aviso("erro", r.erro));
        captcha?.reiniciar(); // cada verificação vale uma vez
        atual.entrada.focus();
        return;
      }
      nova.entrada.value = ""; conf.entrada.value = "";
      toast("sucesso", "Senha trocada. Os outros aparelhos foram desconectados.");
      irPara("/perfil");
    } },
    atual.bloco,
    nova.bloco,
    el("p", { class: "campo__ajuda", text: "Pelo menos 8 caracteres. Não use o seu telefone nem a sua data de nascimento." }),
    conf.bloco,
    lugarCaptcha,
    caixaErro,
    botao);

  montar(alvo,
    el("h1", { text: "Trocar senha" }),
    el("p", { text: "Depois da troca, o app desconecta os outros aparelhos em que você entrou." }),
    form,
    el("p", { class: "centro" }, el("a", { href: "#/perfil", text: "Voltar" })));
  atual.entrada.focus();

  try {
    captcha = await criarCaptcha(lugarCaptcha, (temToken) => { botao.disabled = enviando || !temToken; });
  } catch {
    montar(lugarCaptcha, aviso("atencao", "Não foi possível carregar a verificação anti-robô. Verifique a internet e recarregue a página."));
  }
}
