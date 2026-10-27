// =====================================================================
// Fonte Kids – sino de notificações (Fase 10 · Etapa 4)
// Guarda a contagem de não lidas e escuta, em tempo real (Realtime),
// as notificações do próprio login. O RLS do banco garante que cada
// pessoa só recebe as suas. O push no celular chega na Fase 7.
// =====================================================================
import { sb, sessaoAtual, contarNaoLidas } from "./supabase.js";
import { toast } from "./ui.js";

let canal = null;
let uidAtual = null;
let naoLidas = 0;
const ouvintesContagem = new Set();
const ouvintesMudanca = new Set();

function avisarContagem() {
  for (const f of ouvintesContagem) { try { f(naoLidas); } catch { /* ignore */ } }
}

/** Chama fn(total) agora e a cada mudança. Retorna a função para desligar. */
export function aoMudarContagem(fn) {
  ouvintesContagem.add(fn);
  try { fn(naoLidas); } catch { /* ignore */ }
  return () => ouvintesContagem.delete(fn);
}

/** Chama fn() quando chega ou muda alguma notificação. Retorna a função para desligar. */
export function aoMudarNotificacoes(fn) {
  ouvintesMudanca.add(fn);
  return () => ouvintesMudanca.delete(fn);
}

/** Relê a contagem no banco. */
export async function atualizarContagem() {
  const r = await contarNaoLidas();
  if (r.ok) { naoLidas = r.total; avisarContagem(); }
}

/** Liga o sino para o login atual (pode ser chamada várias vezes). */
export async function iniciarNotificacoes() {
  const s = await sessaoAtual();
  if (!s) { await pararNotificacoes(); return; }
  if (canal && uidAtual === s.user.id) return;
  await pararNotificacoes();
  uidAtual = s.user.id;
  await atualizarContagem();
  canal = sb.channel(`notificacoes-${uidAtual}`)
    .on("postgres_changes",
      { event: "*", schema: "public", table: "notificacoes", filter: `destinatario_id=eq.${uidAtual}` },
      (msg) => {
        atualizarContagem();
        if (msg.eventType === "INSERT" && msg.new?.titulo) toast("info", `Nova notificação: ${msg.new.titulo}`);
        for (const f of ouvintesMudanca) { try { f(); } catch { /* ignore */ } }
      })
    .subscribe();
}

/** Desliga o sino (ao sair). */
export async function pararNotificacoes() {
  if (canal) { try { await sb.removeChannel(canal); } catch { /* ignore */ } }
  canal = null; uidAtual = null; naoLidas = 0;
  avisarContagem();
}
