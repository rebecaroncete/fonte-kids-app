// =====================================================================
// Fonte Kids – janelinha "Adicionar criança" (Fase 5 · Etapa 5D)
// Usada em "Minha família" (responsável) e na ficha da família
// (recepção/liderança). O banco (incluir_crianca) confere a permissão,
// liga a criança a todos os responsáveis da família e avisa a liderança
// quando quem inclui é o responsável.
// Foto: enviada logo depois, pela mesma Edge Function "enviar-foto"
// (responsável da família e liderança podem; a recepção não).
// =====================================================================
import { el, toast } from "./ui.js";
import { abrirJanela, campo } from "./janela.js";
import { prepararFoto, enviarFoto } from "./foto.js";
import { incluirCrianca } from "./supabase.js";
import { TIPOS_RELACAO } from "./telas/primeiro-acesso.js";

const hojeIso = () => new Date().toLocaleDateString("en-CA", { timeZone: "America/Sao_Paulo" });

/**
 * opcoes: { familiaId, comRelacao (quem inclui é responsável), comFoto, aoIncluir: async () => {} }
 */
export function janelaNovaCrianca({ familiaId, comRelacao = false, comFoto = true, aoIncluir }) {
  const nome = el("input", { class: "entrada", type: "text", maxlength: "120", autocomplete: "off" });
  const nasc = el("input", { class: "entrada", type: "date", max: hojeIso() });
  const perfil = el("select", { class: "entrada" },
    el("option", { value: "membro", text: "Membro da igreja" }), el("option", { value: "visitante", text: "Visitante" }));
  const alerg = el("textarea", { class: "entrada", maxlength: "500", placeholder: "Deixe em branco se não houver." });

  const rel = el("select", { class: "entrada" }, el("option", { value: "", text: "Escolha…" }),
    TIPOS_RELACAO.map(([v, t]) => el("option", { value: v, text: t })));
  const det = el("input", { class: "entrada", type: "text", maxlength: "60", placeholder: "Ex.: madrinha" });
  const blocoDet = campo("Qual relação?", det); blocoDet.hidden = true;
  rel.addEventListener("change", () => { blocoDet.hidden = rel.value !== "outro"; });

  let foto = null;
  const previa = el("div", { class: "avatar avatar--grande previa-foto", "aria-hidden": "true" });
  const situacao = el("span", { class: "campo__ajuda", text: "Só o rosto, de frente, com boa luz." });
  const arquivo = el("input", { type: "file", accept: "image/*", class: "entrada" });
  arquivo.addEventListener("change", async () => {
    const f = arquivo.files?.[0];
    if (!f) return;
    situacao.textContent = "Preparando a foto…";
    try { foto = await prepararFoto(f); previa.replaceChildren(el("img", { src: foto, alt: "" })); situacao.textContent = "Foto escolhida."; }
    catch (e) { foto = null; situacao.textContent = e.message; }
  });

  abrirJanela({
    titulo: "Adicionar criança",
    conteudo: [
      campo("Nome completo", nome),
      campo("Data de nascimento", nasc, "A sala é escolhida pela idade."),
      campo("Perfil", perfil),
      campo("Alergias e cuidados", alerg),
      comRelacao ? campo("Você é…", rel) : null,
      comRelacao ? blocoDet : null,
      comFoto ? campo("Foto", arquivo) : null,
      comFoto ? el("div", { class: "linha" }, previa, situacao) : null,
    ].filter(Boolean),
    textoSalvar: "Adicionar",
    sucesso: "Criança adicionada.",
    aoSalvar: async () => {
      if (nome.value.trim().length < 3) { nome.focus(); return "Informe o nome completo."; }
      if (!nasc.value) { nasc.focus(); return "Informe a data de nascimento."; }
      if (comRelacao && !rel.value) { rel.focus(); return "Escolha a sua relação com a criança."; }
      if (comRelacao && rel.value === "outro" && !det.value.trim()) { det.focus(); return "Descreva a relação (ex.: madrinha)."; }
      const r = await incluirCrianca(familiaId, {
        nome: nome.value, nascimento: nasc.value, alergias: alerg.value, perfil: perfil.value,
        relacao: comRelacao ? rel.value : null, detalhe: comRelacao && rel.value === "outro" ? det.value : null,
      });
      if (!r.ok) return r.erro;
      if (foto && r.resultado) {
        const f = await enviarFoto("crianca", r.resultado, foto);
        if (!f.ok) toast("atencao", `A criança foi adicionada, mas a foto não: ${f.erro} Tente de novo em "Trocar foto".`, 7000);
      }
      if (aoIncluir) await aoIncluir();
      return null;
    },
  });
}
