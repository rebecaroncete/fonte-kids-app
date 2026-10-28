// =====================================================================
// Fonte Kids – configuração do app novo
// Só valores PÚBLICOS. Nunca coloque aqui chave secreta, service_role,
// senha ou a chave secreta do captcha (essa fica só no painel do Supabase).
// =====================================================================
export const CONFIG = {
  // Projeto Supabase "fonte-itaparica-app" (São Paulo)
  supabaseUrl: "https://pnujayydfuimfhcgrxjo.supabase.co",
  // Chave publicável (pública por natureza; quem protege os dados é o RLS)
  supabaseChavePublica: "sb_publishable_Hbpkkdl7J1rWtumH563CVw_F3FSA9RF",

  // Cloudflare Turnstile – chave PÚBLICA (site key). A secreta fica só no Supabase.
  turnstileChavePublica: "0x4AAAAAAFoTpgDXDn8Xyp9P",

  // Domínio técnico dos logins: telefone → <telefone>@login.fonteitaparica.invalid
  dominioLogin: "login.fonteitaparica.invalid",

  nomeApp: "Fonte Kids",
  // Ao mudar a versão, mude também VERSAO em sw.js (o mesmo número).
  versao: "0.14.0 (Fase 5 · 5A – cultos, salas e acessos)",
};
