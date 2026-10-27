// =====================================================================
// Tela: Início (PROVISÓRIA – Fase 10 · Etapa 3)
// Quem ainda não terminou o 1º acesso é levado antes para
// "#/primeiro-acesso" (js/app.js). Aqui chega quem já terminou, ou quem
// deixou as relações para depois. O início por papel chega na Etapa 4.
// =====================================================================
import { el, montar, aviso, carregando } from "../ui.js";
import { estadoPrimeiroAcesso } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Início";
export const privada = true;

export async function render(alvo) {
  montar(alvo, carregando());
  const est = await estadoPrimeiroAcesso();

  let conteudo;
  if (!est.ok) {
    conteudo = aviso("erro", "Não foi possível carregar seus dados agora. Tente recarregar a página.");
  } else if (est.etapa === "sem_acesso") {
    conteudo = aviso("erro", "Seu acesso não está ativo. Fale com a liderança do Fonte Kids.");
  } else if (est.etapa === "informar_relacoes") {
    conteudo = [
      aviso("atencao", "Falta informar a sua relação com uma ou mais crianças."),
      el("p", {}, el("a", { class: "botao botao--secundario", href: "#/primeiro-acesso", text: "Informar agora" })),
    ];
  } else {
    conteudo = aviso("sucesso", "Tudo certo com o seu acesso.");
  }

  montar(alvo,
    el("h1", { text: "Você entrou 🎉" }),
    conteudo,
    el("p", { class: "suave", text: "Versão de teste: as demais telas chegam nas próximas etapas." }));
}
