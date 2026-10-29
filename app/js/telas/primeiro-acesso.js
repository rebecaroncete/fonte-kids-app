// =====================================================================
// Tela: 1º acesso (Fase 10 · Etapa 3)
// Passos, sempre retomando de onde a pessoa parou (estado_primeiro_acesso):
//   1. trocar_senha       → nova senha (mín. 8, diferente da inicial)
//   2. aceitar_termo      → ler e aceitar o termo LGPD vigente (sem recusa)
//   3. informar_relacoes  → relação com cada criança ("outro" exige descrição)
// Quem não tem crianças sem relação (ex.: voluntária sem filhos) pula o 3.
// Ao terminar, vai para o início.
// =====================================================================
import { el, montar, aviso, carregando, toast, digitos } from "../ui.js";
import {
  estadoPrimeiroAcesso, telefoneDoLoginAtual, trocarSenhaInicial,
  termoVigente, aceitarTermo, criancasPorId, informarRelacao,
} from "../supabase.js";
import { irPara, definirEtapaAcesso, adiarRelacoes } from "../app.js";

export const layout = "padrao";
export const titulo = "Primeiro acesso";

export const TIPOS_RELACAO = [
  ["mae", "Mãe"], ["pai", "Pai"], ["madrasta", "Madrasta"], ["padrasto", "Padrasto"],
  ["avo", "Avô ou avó"], ["tio", "Tio ou tia"], ["irmao", "Irmão ou irmã"],
  ["responsavel_legal", "Responsável legal"], ["outro", "Outro"],
];

let alvoTela = null;

export async function render(alvo) {
  alvoTela = alvo;
  await avancar();
}

/** Pergunta ao banco o passo atual e mostra a tela certa. */
async function avancar() {
  montar(alvoTela, carregando());
  const est = await estadoPrimeiroAcesso();
  if (!est.ok) {
    montar(alvoTela, aviso("erro", `${est.erro} Tente recarregar a página.`),
      el("button", { class: "botao botao--secundario", type: "button", text: "Tentar de novo", onclick: avancar }));
    return;
  }
  definirEtapaAcesso(est.etapa);
  if (est.etapa === "trocar_senha") return passoSenha();
  if (est.etapa === "aceitar_termo") return passoTermo();
  if (est.etapa === "informar_relacoes") return passoRelacoes(est.criancas_sem_relacao || []);
  if (est.etapa === "sem_acesso") {
    montar(alvoTela, aviso("erro", "Seu acesso não está ativo. Fale com a liderança do Fonte Kids."));
    return;
  }
  irPara("/inicio"); // pronto
}

function cabecalho(rotulo, tituloPasso, explicacao) {
  return [
    el("p", { class: "passo-rotulo", text: `Primeiro acesso · ${rotulo}` }),
    el("h1", { text: tituloPasso }),
    explicacao ? el("p", { text: explicacao }) : null,
  ];
}

function campoSenha(id, rotulo, autocomplete) {
  const entrada = el("input", { class: "entrada", id, type: "password", autocomplete, required: true, minlength: "8" });
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

// ---------------------------------------------------------------------
// Passo 1 – trocar a senha inicial
// ---------------------------------------------------------------------
async function passoSenha() {
  const telefone = await telefoneDoLoginAtual(); // só para recusar "senha = telefone"
  const nova = campoSenha("nova-senha", "Nova senha", "new-password");
  const conf = campoSenha("confirmar-senha", "Repita a nova senha", "new-password");
  const caixaErro = el("div", { "aria-live": "assertive" });
  const botao = el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Salvar" });
  let enviando = false;

  function problema(s) {
    if (s.length < 8) return "A senha precisa ter pelo menos 8 caracteres.";
    if (s !== conf.entrada.value) return "As duas senhas não são iguais.";
    const d = digitos(s);
    if (telefone && d === s && (d === telefone || d === telefone.slice(2))) {
      return "A nova senha não pode ser o seu telefone.";
    }
    if (/^(.)\1+$/.test(s)) return "Escolha uma senha menos óbvia (não repita o mesmo caractere).";
    return null;
  }

  const form = el("form", { class: "cartao", novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (enviando) return;
      caixaErro.replaceChildren();
      const s = nova.entrada.value;
      const p = problema(s);
      if (p) { montar(caixaErro, aviso("erro", p)); nova.entrada.focus(); return; }

      enviando = true; botao.disabled = true; botao.textContent = "Salvando…";
      const r = await trocarSenhaInicial(s);
      enviando = false; botao.disabled = false; botao.textContent = "Salvar";
      if (!r.ok) { montar(caixaErro, aviso("erro", r.erro)); return; }
      nova.entrada.value = ""; conf.entrada.value = "";
      toast("sucesso", "Senha trocada.");
      avancar();
    } },
    nova.bloco,
    el("p", { class: "campo__ajuda", text: "Pelo menos 8 caracteres. Não use a senha inicial, o seu telefone ou a sua data de nascimento." }),
    conf.bloco,
    caixaErro,
    botao);

  montar(alvoTela,
    ...cabecalho("Senha", "Crie a sua senha",
      "Por segurança, troque a senha inicial antes de continuar. Guarde a nova senha: a liderança não consegue vê-la."),
    form);
  nova.entrada.focus();
}

// ---------------------------------------------------------------------
// Passo 2 – termo LGPD (sem botão de recusa)
// ---------------------------------------------------------------------
async function passoTermo() {
  montar(alvoTela, carregando("Carregando o termo…"));
  const t = await termoVigente();
  if (!t.ok) {
    montar(alvoTela, aviso("erro", t.erro),
      el("button", { class: "botao botao--secundario", type: "button", text: "Tentar de novo", onclick: passoTermo }));
    return;
  }

  const marcar = el("input", { type: "checkbox", id: "li-termo",
    onchange: () => { botao.disabled = !marcar.checked; } });
  const caixaErro = el("div", { "aria-live": "assertive" });
  const botao = el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Aceitar", disabled: true });
  let enviando = false;

  const form = el("form", { class: "cartao", novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (enviando || !marcar.checked) return;
      caixaErro.replaceChildren();
      enviando = true; botao.disabled = true; botao.textContent = "Registrando…";
      const r = await aceitarTermo(t.versao);
      enviando = false; botao.disabled = !marcar.checked; botao.textContent = "Aceitar";
      if (!r.ok) { montar(caixaErro, aviso("erro", r.erro)); return; }
      toast("sucesso", "Termo aceito. Obrigado!");
      avancar();
    } },
    el("div", { class: "termo-texto", tabindex: "0", role: "document", "aria-label": "Texto do termo", text: t.texto }),
    el("p", { class: "campo__ajuda", text: `Versão ${t.versao}` }),
    el("label", { class: "marcar", for: "li-termo" }, marcar, "Li e concordo com o termo"),
    caixaErro,
    botao,
    el("p", { class: "centro suave", text: "Não concorda? Fale com a liderança do Fonte Kids." }));

  montar(alvoTela,
    ...cabecalho("Termo", "Termo de uso de dados (LGPD)",
      "Leia com atenção. O aceite é registrado no seu nome, para as crianças da sua família."),
    form);
}

// ---------------------------------------------------------------------
// Passo 3 – relação com cada criança
// ---------------------------------------------------------------------
async function passoRelacoes(ids) {
  montar(alvoTela, carregando());
  const r = await criancasPorId(ids);
  if (!r.ok) {
    montar(alvoTela, aviso("erro", r.erro),
      el("button", { class: "botao botao--secundario", type: "button", text: "Tentar de novo", onclick: () => passoRelacoes(ids) }));
    return;
  }

  const linhas = r.lista.map((c, i) => {
    const idSel = `rel-${i}`, idDet = `det-${i}`;
    const detalhe = el("input", { class: "entrada", id: idDet, type: "text", maxlength: "60",
      placeholder: "Ex.: madrinha", autocomplete: "off" });
    const blocoDetalhe = el("div", { class: "campo", hidden: true },
      el("label", { class: "campo__rotulo", for: idDet, text: "Qual relação?" }), detalhe);
    const tipo = el("select", { class: "entrada", id: idSel, required: true,
      onchange: () => { blocoDetalhe.hidden = tipo.value !== "outro"; if (!blocoDetalhe.hidden) detalhe.focus(); } },
      el("option", { value: "", text: "Escolha…" }),
      TIPOS_RELACAO.map(([v, t]) => el("option", { value: v, text: t })));
    const cartao = el("div", { class: "cartao cartao--azul crianca-rel" },
      el("p", { class: "crianca-rel__nome", text: c.nome }),
      el("div", { class: "campo" },
        el("label", { class: "campo__rotulo", for: idSel, text: "Você é…" }), tipo),
      blocoDetalhe);
    return { c, tipo, detalhe, cartao, feito: false };
  });

  const caixaErro = el("div", { "aria-live": "assertive" });
  const botao = el("button", { class: "botao botao--primario botao--largo", type: "submit", text: "Continuar" });
  let enviando = false;

  const form = el("form", { novalidate: true, onsubmit: async (e) => {
      e.preventDefault();
      if (enviando) return;
      caixaErro.replaceChildren();
      for (const l of linhas) {
        if (l.feito) continue;
        if (!l.tipo.value) { montar(caixaErro, aviso("erro", `Escolha a relação com ${l.c.nome}.`)); l.tipo.focus(); return; }
        if (l.tipo.value === "outro" && !l.detalhe.value.trim()) {
          montar(caixaErro, aviso("erro", `Descreva a relação com ${l.c.nome} (ex.: madrinha).`)); l.detalhe.focus(); return;
        }
      }
      enviando = true; botao.disabled = true; botao.textContent = "Salvando…";
      for (const l of linhas) {
        if (l.feito) continue;
        const det = l.tipo.value === "outro" ? l.detalhe.value.trim() : null;
        const res = await informarRelacao(l.c.id, l.tipo.value, det);
        if (!res.ok) {
          enviando = false; botao.disabled = false; botao.textContent = "Continuar";
          montar(caixaErro, aviso("erro", `${l.c.nome}: ${res.erro}`));
          return;
        }
        l.feito = true; // se outra falhar, esta não é enviada de novo
      }
      toast("sucesso", "Tudo pronto! Bem-vindo(a) ao app.");
      avancar();
    } },
    linhas.map((l) => l.cartao),
    caixaErro,
    botao,
    el("p", { class: "centro" },
      el("button", { class: "botao botao--texto", type: "button", text: "Depois",
        onclick: () => { adiarRelacoes(); irPara("/inicio"); } })));

  montar(alvoTela,
    ...cabecalho("Crianças", "Sua relação com as crianças",
      linhas.length === 1 ? "Conte para nós qual é a sua relação com esta criança." :
        "Conte para nós qual é a sua relação com cada criança."),
    form);
}
