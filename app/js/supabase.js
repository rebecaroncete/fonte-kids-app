// =====================================================================
// Fonte Kids – conexão com o Supabase e sessão
// A biblioteca oficial (supabase-js 2.118.0) vem de app/vendor/, servida
// pelo próprio app (versão fixa, sem depender de CDN).
//
// "Manter conectado":
//   marcado    → sessão salva no aparelho (localStorage)
//   desmarcado → sessão só nesta aba (sessionStorage): some ao fechar a aba
//                ou o navegador.
// =====================================================================
import { CONFIG } from "../config.js";

if (!window.supabase?.createClient) {
  throw new Error("Biblioteca do Supabase não carregou.");
}

const CHAVE_MANTER = "fk-manter-conectado"; // guarda só "1" ou "0"

function lerManter() {
  try { return localStorage.getItem(CHAVE_MANTER) !== "0"; } catch { return false; }
}

/** Define onde a próxima sessão será guardada (chamar ANTES de entrar). */
export function definirManterConectado(manter) {
  try { localStorage.setItem(CHAVE_MANTER, manter ? "1" : "0"); } catch { /* sem armazenamento */ }
}

export function manterConectadoAtual() { return lerManter(); }

// Armazenamento que escolhe entre aparelho (local) e aba (session).
const memoria = new Map();
const armazenamento = {
  getItem(k) {
    try { return localStorage.getItem(k) ?? sessionStorage.getItem(k) ?? memoria.get(k) ?? null; }
    catch { return memoria.get(k) ?? null; }
  },
  setItem(k, v) {
    try {
      if (lerManter()) { localStorage.setItem(k, v); sessionStorage.removeItem(k); }
      else { sessionStorage.setItem(k, v); localStorage.removeItem(k); }
    } catch { memoria.set(k, v); }
  },
  removeItem(k) {
    memoria.delete(k);
    try { localStorage.removeItem(k); } catch { /* ignore */ }
    try { sessionStorage.removeItem(k); } catch { /* ignore */ }
  },
};

export const sb = window.supabase.createClient(CONFIG.supabaseUrl, CONFIG.supabaseChavePublica, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false, // login é só por telefone + senha
    storageKey: "fk-sessao",
    storage: armazenamento,
  },
});

/** Telefone (55DDDnúmero) → e-mail técnico do login. */
export const emailDoLogin = (telefone55) => `${telefone55}@${CONFIG.dominioLogin}`;

/** Sessão atual ou null (sem lançar erro). */
export async function sessaoAtual() {
  try {
    const { data } = await sb.auth.getSession();
    return data?.session ?? null;
  } catch {
    return null;
  }
}

/**
 * Entrar. Retorna { ok: true } ou { ok: false, erro: "<mensagem genérica>" }.
 * Nunca diz se o telefone existe ou não.
 */
export async function entrar(telefone55, senha, captchaToken, manter) {
  definirManterConectado(manter);
  try {
    const { error } = await sb.auth.signInWithPassword({
      email: emailDoLogin(telefone55),
      password: senha,
      options: { captchaToken },
    });
    if (!error) return { ok: true };
    return { ok: false, erro: mensagemDeErro(error) };
  } catch {
    return { ok: false, erro: "Sem conexão com o servidor. Verifique a internet e tente de novo." };
  }
}

function mensagemDeErro(error) {
  const cod = String(error?.code || "");
  const msg = String(error?.message || "").toLowerCase();
  if (cod.includes("captcha") || msg.includes("captcha")) {
    return "Não foi possível confirmar a verificação anti-robô. Tente de novo.";
  }
  if (error?.status === 429 || cod.includes("rate_limit")) {
    return "Muitas tentativas seguidas. Aguarde alguns minutos e tente de novo.";
  }
  if (error?.status === 0 || msg.includes("fetch")) {
    return "Sem conexão com o servidor. Verifique a internet e tente de novo.";
  }
  // invalid_credentials, usuário inexistente, desativado etc.: mesma mensagem
  return "Telefone ou senha incorretos.";
}

/** Sair (só deste aparelho). */
export async function sair() {
  try { await sb.auth.signOut({ scope: "local" }); } catch { /* segue limpando */ }
  armazenamento.removeItem("fk-sessao");
}

/** Pedido de nova senha (Edge Function pedir-redefinicao). */
export async function pedirNovaSenha(telefone55, captchaToken) {
  try {
    const r = await fetch(`${CONFIG.supabaseUrl}/functions/v1/pedir-redefinicao`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: CONFIG.supabaseChavePublica },
      body: JSON.stringify({ telefone: telefone55, captchaToken }),
    });
    const j = await r.json().catch(() => ({}));
    if (r.ok && j.ok) return { ok: true, mensagem: j.mensagem };
    if (j.erro === "captcha") return { ok: false, erro: "Não foi possível confirmar a verificação anti-robô. Tente de novo." };
    return { ok: false, erro: "Não foi possível enviar agora. Tente de novo mais tarde." };
  } catch {
    return { ok: false, erro: "Sem conexão com o servidor. Verifique a internet e tente de novo." };
  }
}

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

// =====================================================================
// 1º acesso (Fase 10 · Etapa 3)
// Todas as funções retornam { ok: true, ... } ou { ok: false, erro } com
// mensagem simples (sem detalhe técnico).
// =====================================================================

const SEM_CONEXAO = "Sem conexão com o servidor. Verifique a internet e tente de novo.";

/** Em que passo do 1º acesso a pessoa está (função estado_primeiro_acesso). */
export async function estadoPrimeiroAcesso() {
  try {
    const { data, error } = await sb.rpc("estado_primeiro_acesso");
    if (error || !data?.etapa) return { ok: false, erro: "Não foi possível carregar seus dados agora." };
    return { ok: true, ...data };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Telefone do login atual (só dígitos, com 55), lido do e-mail técnico. */
export async function telefoneDoLoginAtual() {
  const s = await sessaoAtual();
  const email = s?.user?.email || "";
  return email.endsWith(`@${CONFIG.dominioLogin}`) ? email.split("@")[0] : "";
}

/**
 * Troca a senha inicial e libera o perfil (concluir_troca_senha).
 * Se a senha já tinha sido trocada mas a confirmação falhou (internet caiu),
 * tentar de novo com a mesma senha também conclui.
 */
export async function trocarSenhaInicial(novaSenha) {
  let mesmaSenha = false;
  try {
    const { error } = await sb.auth.updateUser({ password: novaSenha });
    if (error) {
      const cod = String(error.code || "");
      const msg = String(error.message || "").toLowerCase();
      if (cod === "same_password" || msg.includes("different from the old")) mesmaSenha = true;
      else if (cod === "weak_password" || msg.includes("weak")) return { ok: false, erro: "Senha fraca. Use pelo menos 8 caracteres, misturando letras e números." };
      else if (cod === "reauthentication_needed") return { ok: false, erro: "Por segurança, saia, entre de novo com a senha inicial e troque a senha logo em seguida." };
      else if (error.status === 429) return { ok: false, erro: "Muitas tentativas seguidas. Aguarde alguns minutos e tente de novo." };
      else return { ok: false, erro: "Não foi possível trocar a senha agora. Tente de novo." };
    }
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
  try {
    const { error } = await sb.rpc("concluir_troca_senha");
    if (!error) return { ok: true };
    if (mesmaSenha) return { ok: false, erro: "A nova senha precisa ser diferente da senha inicial." };
    return { ok: false, erro: "A senha foi trocada, mas não conseguimos confirmar. Tente de novo com a mesma nova senha." };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Termo LGPD vigente: { ok, versao, texto }. */
export async function termoVigente() {
  try {
    const { data, error } = await sb.from("termos_lgpd_versoes")
      .select("versao, texto").eq("vigente", true).maybeSingle();
    if (error || !data) return { ok: false, erro: "Não foi possível carregar o termo agora." };
    return { ok: true, versao: data.versao, texto: data.texto };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Aceite do termo na versão mostrada na tela. */
export async function aceitarTermo(versao) {
  try {
    const { error } = await sb.rpc("aceitar_termo_lgpd", { p_versao: versao });
    if (!error) return { ok: true };
    if (String(error.message || "").includes("desatualizada")) {
      return { ok: false, erro: "O termo foi atualizado. Recarregue a página para ler a versão nova." };
    }
    return { ok: false, erro: "Não foi possível registrar o aceite agora. Tente de novo." };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Nomes das crianças (ids vindos de estado_primeiro_acesso). */
export async function criancasPorId(ids) {
  if (!ids?.length) return { ok: true, lista: [] };
  try {
    const { data: cri, error: e1 } = await sb.from("criancas").select("id, pessoa_id").in("id", ids);
    if (e1) throw e1;
    const pessoaIds = (cri || []).map((c) => c.pessoa_id).filter(Boolean);
    let nomes = new Map();
    if (pessoaIds.length) {
      const { data: pes, error: e2 } = await sb.from("pessoas").select("id, nome").in("id", pessoaIds);
      if (e2) throw e2;
      nomes = new Map((pes || []).map((p) => [p.id, p.nome]));
    }
    const lista = ids.map((id, i) => {
      const c = (cri || []).find((x) => x.id === id);
      return { id, nome: (c && nomes.get(c.pessoa_id)) || `Criança ${i + 1}` };
    });
    return { ok: true, lista };
  } catch {
    return { ok: false, erro: "Não foi possível carregar as crianças agora." };
  }
}

/** Relação do responsável com uma criança (informar_relacao). */
export async function informarRelacao(criancaId, tipo, detalhe) {
  try {
    const { error } = await sb.rpc("informar_relacao", {
      p_crianca: criancaId, p_tipo: tipo, p_detalhe: detalhe || null,
    });
    if (!error) return { ok: true };
    if (String(error.message || "").includes("Descreva")) return { ok: false, erro: "Descreva a relação (ex.: madrinha)." };
    return { ok: false, erro: "Não foi possível salvar agora. Tente de novo." };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}
