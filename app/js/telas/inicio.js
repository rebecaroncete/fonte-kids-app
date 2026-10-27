// =====================================================================
// Tela: Início (PROVISÓRIA – Fase 10 · Etapa 2)
// Só confirma que o login funcionou e mostra em que etapa do 1º acesso a
// pessoa está. As telas de troca de senha, termo e relações chegam na
// Etapa 3; o início por papel, na Etapa 4.
// =====================================================================
import { el, montar, aviso, carregando } from "../ui.js";
import { sb } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Início";
export const privada = true;

const ETAPAS = {
  trocar_senha:      ["atencao", "Próximo passo: trocar a senha inicial. (Tela disponível na próxima etapa do app.)"],
  aceitar_termo:     ["atencao", "Próximo passo: ler e aceitar o termo de uso de dados (LGPD). (Tela disponível na próxima etapa do app.)"],
  informar_relacoes: ["atencao", "Próximo passo: informar a sua relação com cada criança. (Tela disponível na próxima etapa do app.)"],
  pronto:            ["sucesso", "Tudo certo com o seu acesso."],
  sem_acesso:        ["erro", "Seu acesso não está ativo. Fale com a liderança do Fonte Kids."],
};

export async function render(alvo) {
  montar(alvo, carregando());
  let etapa = null;
  try {
    const { data, error } = await sb.rpc("estado_primeiro_acesso");
    if (!error) etapa = data?.etapa ?? null;
  } catch { /* segue com etapa nula */ }

  const [tipo, texto] = ETAPAS[etapa] || ["erro", "Não foi possível carregar seus dados agora. Tente recarregar a página."];
  montar(alvo,
    el("h1", { text: "Você entrou 🎉" }),
    aviso(tipo, texto),
    el("p", { class: "suave", text: "Versão de teste: as demais telas chegam nas próximas etapas." }));
}
