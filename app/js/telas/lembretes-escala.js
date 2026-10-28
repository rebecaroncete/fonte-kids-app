// =====================================================================
// Tela: Lembretes da escala (Fase 6 · 6D)   #/lembretes-escala
// Só liderança (o banco confere). Para cada culto dos próximos dias:
//   • um botão de WhatsApp por voluntária, com a mensagem das regras
//     da escala já preenchida (o envio é feito por quem toca, no WhatsApp);
//   • "Texto para o grupo": a escala do culto pronta para colar.
// Os telefones só aparecem aqui, dentro dos links; nada é enviado sozinho.
// =====================================================================
import { el, montar, aviso, carregando, toast } from "../ui.js";
import { icone } from "../icones.js";
import { abrirJanela } from "../janela.js";
import { meuPerfil, lembretesEscala, escalaDoMes } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Lembretes da escala";

const FUSO = "America/Sao_Paulo";
const FUNCOES = { professora: "Professora(o)", auxiliar: "Auxiliar", reserva: "Reserva", lider_culto: "Líder do culto" };
const EMOJI = { professora: "👩‍🏫", auxiliar: "🤝", reserva: "🔄", lider_culto: "🎤" };
const PERIODOS = [[7, "Próximos 7 dias"], [14, "Próximos 14 dias"], [31, "Próximos 31 dias"]];

let alvoTela = null;
let dias = 7;

const isoHoje = () => new Date().toLocaleDateString("en-CA", { timeZone: FUSO });
function somarDias(iso, n) {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + n);
  return d.toISOString().slice(0, 10);
}
function dataBr(iso) {
  const d = new Date(`${iso}T12:00:00`);
  const semana = d.toLocaleDateString("pt-BR", { timeZone: FUSO, weekday: "short" }).replace(".", "");
  const dia = d.toLocaleDateString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit" });
  return `${semana.charAt(0).toUpperCase()}${semana.slice(1)} ${dia}`;
}
const ddmm = (iso) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;
const primeiro = (nome) => String(nome || "").trim().split(/\s+/)[0];

export async function render(alvo) {
  alvoTela = alvo;
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: titulo }), aviso("erro", perfil.erro)); return; }
  if (!perfil.temPapel("admin", "pastor", "lider")) {
    montar(alvo, el("h1", { text: titulo }), aviso("atencao", "Esta tela é só para a liderança do Fonte Kids."));
    return;
  }
  await desenhar();
}

async function desenhar() {
  const de = isoHoje();
  const ate = somarDias(de, dias);
  const meses = [...new Set([de.slice(0, 7), ate.slice(0, 7)])];
  const [rl, ...re] = await Promise.all([lembretesEscala(de, ate), ...meses.map((m) => escalaDoMes(`${m}-01`))]);
  if (!alvoTela?.isConnected) return;
  const erro = [rl, ...re].find((r) => !r.ok);
  if (erro) { montar(alvoTela, el("h1", { text: titulo }), aviso("erro", erro.erro)); return; }

  const modelo = rl.resultado?.mensagem || "";
  const pessoas = rl.resultado?.itens || [];
  const cultos = re.flatMap((r) => (r.resultado?.escala?.status === "publicada" ? r.resultado.cultos : []))
    .filter((c) => c.data >= de && c.data <= ate && !c.cancelado);

  const partes = [
    el("h1", { text: titulo }),
    el("p", { class: "voltar" }, el("a", { class: "botao botao--texto botao--pequeno", href: "#/escala" }, icone("voltar"), "Escala")),
    el("div", { class: "chips mt-2" }, PERIODOS.map(([n, texto]) => el("button", {
      class: "chip", type: "button", "aria-pressed": String(n === dias), text: texto,
      onclick: () => { dias = n; desenhar(); } }))),
    el("p", { class: "suave mt-2", text: "Toque no botão verde para abrir o WhatsApp com a mensagem pronta. Dá para mudar o texto em Escala → ⋯ → Regras da escala." }),
  ];
  if (!cultos.length) {
    partes.push(aviso("info", "Nenhum culto com escala publicada neste período."));
    montar(alvoTela, partes);
    return;
  }
  for (const c of cultos) {
    const daqui = pessoas.filter((p) => p.data === c.data && p.hora === c.hora);
    const vazias = c.itens.filter((i) => !i.nome && i.funcao !== "reserva");
    partes.push(el("section", { class: "secao-lista" },
      el("div", { class: "secao-titulo" },
        el("h2", { text: `${dataBr(c.data)} · ${c.hora} · ${c.nome}` }),
        el("button", { class: "botao botao--secundario botao--pequeno", type: "button", onclick: () => janelaGrupo(c) }, "Texto para o grupo")),
      vazias.length ? el("p", { class: "resumo-lista", text: `${vazias.length} vaga(s) aberta(s)` }) : null,
      daqui.length
        ? el("ul", { class: "lista-compacta" }, daqui.map((p) => itemPessoa(p, modelo)))
        : el("p", { class: "suave", text: "Ninguém escalado com cadastro." })));
  }
  montar(alvoTela, partes);
}

function itemPessoa(p, modelo) {
  const tel = String(p.telefone || "").replace(/\D/g, "");
  const texto = modelo
    .replace(/{nome_voluntaria}/g, primeiro(p.nome))
    .replace(/{data_culto}/g, ddmm(p.data))
    .replace(/{horario_culto}/g, p.hora)
    .replace(/{sala}/g, p.sala)
    .replace(/{papel}/g, p.papel);
  const funcao = FUNCOES[p.funcao] || p.funcao;
  return el("li", {}, el("div", { class: "item-compacto" },
    el("span", { class: "item-compacto__texto" },
      el("span", { class: "item-compacto__nome", text: p.nome }),
      el("span", { class: "item-compacto__linha", text: p.funcao === "lider_culto" ? funcao : `${p.sala} · ${funcao}` })),
    p.resposta === "ciente" ? el("span", { class: "item-compacto__etiquetas" }, el("span", { class: "etiqueta etiqueta--sucesso", text: "Ciente" })) : null,
    /^55[1-9][0-9]9?[0-9]{8}$/.test(tel)
      ? el("a", { class: "botao-icone botao-icone--whatsapp", href: `https://wa.me/${tel}?text=${encodeURIComponent(texto)}`,
          target: "_blank", rel: "noopener noreferrer", "aria-label": `Enviar lembrete para ${p.nome} no WhatsApp` }, icone("conversa"))
      : el("span", { class: "suave", text: "Sem WhatsApp" })));
}

/** Escala do culto em texto, para colar no grupo da equipe (só nomes). */
function textoGrupo(c) {
  const linhas = ["🔔 *LEMBRETE DE ESCALA - FONTE KIDS* 🔔", "", `📅 *${dataBr(c.data)} · ${c.hora} · ${c.nome}*`];
  for (const i of c.itens.filter((x) => x.funcao === "lider_culto")) {
    linhas.push(`🎤 Líder do culto: ${i.nome ? `*${i.nome}*` : "⚠️ Vaga aberta"}`);
  }
  const salas = [...new Set(c.itens.filter((x) => x.funcao !== "lider_culto").map((x) => x.sala))];
  for (const s of salas) {
    const itens = c.itens.filter((x) => x.sala === s && x.funcao !== "lider_culto" && (x.nome || x.funcao !== "reserva"));
    if (!itens.length) continue;
    linhas.push("", `*${s}:*`);
    for (const i of itens) {
      linhas.push(`  ${EMOJI[i.funcao] || "•"} ${FUNCOES[i.funcao] || i.funcao}: ${i.nome ? `*${i.nome}*` : "⚠️ Vaga aberta"}`);
    }
  }
  return linhas.join("\n");
}

function janelaGrupo(c) {
  const caixa = el("textarea", { class: "entrada", rows: "12", readonly: true });
  caixa.value = textoGrupo(c);
  abrirJanela({
    titulo: "Texto para o grupo",
    textoSalvar: "Copiar",
    conteudo: [caixa],
    aoSalvar: async () => {
      try {
        await navigator.clipboard.writeText(caixa.value);
        toast("sucesso", "Texto copiado. Cole no grupo do WhatsApp.");
        return null;
      } catch {
        caixa.select();
        return "Não deu para copiar sozinho. Segure no texto e escolha Copiar.";
      }
    },
  });
}
