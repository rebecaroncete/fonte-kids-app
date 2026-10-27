// =====================================================================
// Fonte Kids – conexão com o Supabase
// A biblioteca oficial (supabase-js 2.118.0) vem de app/vendor/, servida
// pelo próprio app (versão fixa, sem depender de CDN).
// =====================================================================
import { CONFIG } from "../config.js";

if (!window.supabase?.createClient) {
  throw new Error("Biblioteca do Supabase não carregou.");
}

export const sb = window.supabase.createClient(CONFIG.supabaseUrl, CONFIG.supabaseChavePublica, {
  auth: {
    persistSession: true,      // "Manter conectado" é ajustado na Etapa 2
    autoRefreshToken: true,
    detectSessionInUrl: false, // login é só por telefone + senha
    storageKey: "fk-sessao",
  },
});

/** Confere se o app alcança o Supabase (não lê nenhum dado). */
export async function verificarConexao() {
  try {
    const r = await fetch(`${CONFIG.supabaseUrl}/auth/v1/health`, {
      headers: { apikey: CONFIG.supabaseChavePublica },
      cache: "no-store",
    });
    return r.ok;
  } catch {
    return false;
  }
}
