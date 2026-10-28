// =====================================================================
// Tela: Notificações (Fase 10 · Etapa 4)
// Lista as notificações do próprio login (o RLS só entrega as dela),
// marca como lida (uma ou todas) e se atualiza sozinha (Realtime).
// Links só abrem telas internas conhecidas ("#/endereco").
// =====================================================================
import { el, montar, aviso, carregando, toast } from "../ui.js";
import { listarNotificacoes, marcarLida } from "../supabase.js";
import { aoMudarNotificacoes, atualizarContagem } from "../notificacoes.js";
import { irPara, rotaExiste } from "../app.js";

export const layout = "padrao";
export const titulo = "Notificações";

const FUSO = "America/Sao_Paulo";

function quando(iso) {
  const d = new Date(iso);
  const min = Math.round((Date.now() - d.getTime()) / 60000);
  if (min < 1) return "agora";
  if (min < 60) return `há ${min} min`;
  if (min < 24 * 60) return `há ${Math.round(min / 60)} h`;
  return d.toLocaleString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
}

/** "#/logins" → "/logins" se for uma tela que já existe; senão null. */
function rotaDoLink(link) {
  const m = /^#(\/[a-z0-9-]+)$/.exec(String(link || ""));
  return m && rotaExiste(m[1]) ? m[1] : null;
}

let desligar = null;

export async function render(alvo) {
  if (desligar) { desligar(); desligar = null; }
  const area = el("div", {});
  const botaoTodas = el("button", { class: "botao botao--pequeno", type: "button", text: "Ler todas", hidden: true });

  async function carregar() {
    const r = await listarNotificacoes();
    if (!document.body.contains(area)) return;
    if (!r.ok) { montar(area, aviso("erro", r.erro)); return; }
    const novas = r.lista.filter((n) => !n.lida_em).length;
    botaoTodas.hidden = novas === 0;
    if (!r.lista.length) { montar(area, aviso("info", "Você não tem notificações.")); return; }
    montar(area, el("ul", { class: "lista" }, r.lista.map(itemNotificacao)));
  }

  function itemNotificacao(n) {
    const nova = !n.lida_em;
    const rota = rotaDoLink(n.link);
    const acoes = el("div", { class: "linha" });
    if (rota) {
      acoes.append(el("button", { class: "botao botao--pequeno botao--azul", type: "button", text: "Abrir",
        onclick: async () => { if (nova) await marcarLida(n.id); atualizarContagem(); irPara(rota); } }));
    }
    if (nova) {
      acoes.append(el("button", { class: "botao botao--pequeno botao--texto", type: "button", text: "Marcar lida",
        onclick: async (e) => {
          const b = e.currentTarget;
          b.disabled = true;
          const r = await marcarLida(n.id);
          if (!r.ok) { toast("erro", r.erro); b.disabled = false; return; }
          await atualizarContagem(); carregar();
        } }));
    }
    return el("li", { class: nova ? "notif notif--nova" : "notif" },
      el("div", { class: "notif__topo" },
        el("p", { class: "notif__titulo", text: n.titulo || "Aviso" }),
        nova ? el("span", { class: "etiqueta etiqueta--laranja", text: "Novo" }) : null),
      n.corpo ? el("p", { class: "notif__corpo", text: n.corpo }) : null,
      el("p", { class: "notif__quando", text: quando(n.criado_em) }),
      acoes.childElementCount ? acoes : null);
  }

  botaoTodas.addEventListener("click", async () => {
    botaoTodas.disabled = true;
    const r = await marcarLida();
    botaoTodas.disabled = false;
    if (!r.ok) { toast("erro", r.erro); return; }
    await atualizarContagem(); carregar();
  });

  montar(alvo,
    el("div", { class: "cabecalho-tela" }, el("h1", { text: "Avisos" }), botaoTodas),
    area);
  montar(area, carregando());
  await carregar();

  // Atualiza sozinha quando chega notificação nova (enquanto a tela estiver aberta)
  desligar = aoMudarNotificacoes(() => { if (document.body.contains(area)) carregar(); else if (desligar) { desligar(); desligar = null; } });
}
