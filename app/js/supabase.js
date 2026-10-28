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

// =====================================================================
// Casca por papel (Fase 10 · Etapa 4): meu perfil, trocar senha,
// notificações. Mesmo formato: { ok: true, ... } ou { ok: false, erro }.
// =====================================================================

export const NOMES_PAPEIS = {
  admin: "Administração",
  pastor: "Pastor(a)",
  lider: "Liderança",
  recepcao: "Recepção",
  voluntaria: "Voluntária",
  responsavel: "Responsável",
};
const ORDEM_PAPEIS = ["admin", "pastor", "lider", "recepcao", "voluntaria", "responsavel"];

let perfilGuardado = null; // { uid, dados } – só na memória desta aba

/** Esquece o perfil guardado (ao sair ou trocar de login). */
export function limparPerfilGuardado() { perfilGuardado = null; }

/**
 * Dados do próprio login: nome, telefone e papéis (com o departamento).
 * Retorna { ok, uid, nome, telefone, papeis: [{ papel, nomePapel, departamento }], temPapel(p) }.
 */
export async function meuPerfil(forcar = false) {
  const s = await sessaoAtual();
  if (!s) return { ok: false, erro: "Você não está conectado." };
  const uid = s.user.id;
  if (!forcar && perfilGuardado?.uid === uid) return perfilGuardado.dados;
  try {
    const [rPerfil, rPapeis] = await Promise.all([
      sb.from("perfis").select("telefone, pessoa_id").eq("id", uid).maybeSingle(),
      sb.from("papeis_usuario").select("papel, departamento_id").eq("perfil_id", uid),
    ]);
    if (rPerfil.error || rPapeis.error) throw new Error("leitura");
    const perfil = rPerfil.data || {};

    let nome = "";
    if (perfil.pessoa_id) {
      const { data } = await sb.from("pessoas").select("nome").eq("id", perfil.pessoa_id).maybeSingle();
      nome = data?.nome || "";
    }

    const depIds = [...new Set((rPapeis.data || []).map((p) => p.departamento_id).filter(Boolean))];
    let deps = new Map();
    if (depIds.length) {
      const { data } = await sb.from("departamentos").select("id, nome").in("id", depIds);
      deps = new Map((data || []).map((d) => [d.id, d.nome]));
    }

    const papeis = (rPapeis.data || [])
      .map((p) => ({ papel: p.papel, nomePapel: NOMES_PAPEIS[p.papel] || p.papel, departamento: deps.get(p.departamento_id) || "" }))
      .sort((a, b) => ORDEM_PAPEIS.indexOf(a.papel) - ORDEM_PAPEIS.indexOf(b.papel));

    const dados = {
      ok: true, uid, nome,
      pessoaId: perfil.pessoa_id || null,
      telefone: perfil.telefone || (await telefoneDoLoginAtual()),
      papeis,
      temPapel: (...lista) => papeis.some((p) => lista.includes(p.papel)),
    };
    perfilGuardado = { uid, dados };
    return dados;
  } catch {
    return { ok: false, erro: "Não foi possível carregar o seu perfil agora." };
  }
}

/**
 * Trocar senha (pessoa já conectada).
 * 1) confere a senha atual (entrando de novo, com captcha);
 * 2) grava a nova senha;
 * 3) desconecta os outros aparelhos deste login.
 */
export async function trocarSenha(atual, nova, captchaToken) {
  const tel = await telefoneDoLoginAtual();
  if (!tel) return { ok: false, erro: "Você não está conectado. Entre de novo." };
  try {
    const { error } = await sb.auth.signInWithPassword({
      email: emailDoLogin(tel), password: atual, options: { captchaToken },
    });
    if (error) {
      const m = mensagemDeErro(error);
      return { ok: false, erro: m === "Telefone ou senha incorretos." ? "A senha atual está incorreta." : m, refazerCaptcha: true };
    }
  } catch {
    return { ok: false, erro: SEM_CONEXAO, refazerCaptcha: true };
  }
  try {
    const { error } = await sb.auth.updateUser({ password: nova });
    if (error) {
      const cod = String(error.code || "");
      const msg = String(error.message || "").toLowerCase();
      if (cod === "same_password" || msg.includes("different from the old")) return { ok: false, erro: "A nova senha precisa ser diferente da atual.", refazerCaptcha: true };
      if (cod === "weak_password" || msg.includes("weak")) return { ok: false, erro: "Senha fraca. Use pelo menos 8 caracteres, misturando letras e números.", refazerCaptcha: true };
      if (error.status === 429) return { ok: false, erro: "Muitas tentativas seguidas. Aguarde alguns minutos e tente de novo.", refazerCaptcha: true };
      return { ok: false, erro: "Não foi possível trocar a senha agora. Tente de novo.", refazerCaptcha: true };
    }
  } catch {
    return { ok: false, erro: SEM_CONEXAO, refazerCaptcha: true };
  }
  try { await sb.auth.signOut({ scope: "others" }); } catch { /* a troca já valeu */ }
  return { ok: true };
}

/** Quantas notificações ainda não lidas (só as do próprio login, pelo RLS). */
export async function contarNaoLidas() {
  try {
    const { count, error } = await sb.from("notificacoes")
      .select("id", { count: "exact", head: true }).is("lida_em", null);
    if (error) return { ok: false };
    return { ok: true, total: count || 0 };
  } catch {
    return { ok: false };
  }
}

/** Notificações mais recentes (até 50). */
export async function listarNotificacoes() {
  try {
    const { data, error } = await sb.from("notificacoes")
      .select("id, titulo, corpo, link, tipo, lida_em, criado_em")
      .order("criado_em", { ascending: false }).limit(50);
    if (error) return { ok: false, erro: "Não foi possível carregar as notificações agora." };
    return { ok: true, lista: data || [] };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Marca uma notificação (ou todas, sem id) como lida. */
export async function marcarLida(id) {
  try {
    let q = sb.from("notificacoes").update({ lida_em: new Date().toISOString() }).is("lida_em", null);
    if (id) q = q.eq("id", id);
    const { error } = await q;
    if (error) return { ok: false, erro: "Não foi possível marcar como lida agora." };
    return { ok: true };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

// =====================================================================
// Gestão de logins (Fase 10 · Etapa 5A) – liderança do Fonte Kids,
// pastores e admin. O banco confere a permissão em cada chamada; o
// telefone já vem mascarado do banco. Nenhuma senha passa por aqui.
// =====================================================================

/** Pedidos de nova senha pendentes. */
export async function listarPedidosRedefinicao() {
  try {
    const { data, error } = await sb.rpc("listar_pedidos_redefinicao");
    if (error) return { ok: false, erro: error.code === "42501" ? "Você não tem acesso à gestão de logins." : "Não foi possível carregar os pedidos agora." };
    return { ok: true, lista: data || [] };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Situação de login de cada pessoa (com e sem login). */
export async function situacaoLogins() {
  try {
    const { data, error } = await sb.rpc("situacao_logins");
    if (error) return { ok: false, erro: error.code === "42501" ? "Você não tem acesso à gestão de logins." : "Não foi possível carregar a lista agora." };
    return { ok: true, lista: data || [] };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Encerra um pedido de nova senha sem redefinir. */
export async function encerrarPedido(id) {
  try {
    const { data, error } = await sb.rpc("encerrar_pedido_redefinicao", { p_pedido: id });
    if (error) return { ok: false, erro: "Não foi possível encerrar o pedido agora." };
    return { ok: true, encerrado: data === true };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Chama a Edge Function gerenciar-login com a sessão atual. */
export async function gerenciarLogin(corpo) {
  const s = await sessaoAtual();
  if (!s) return { ok: false, erro: "Você não está conectado. Entre de novo." };
  try {
    const r = await fetch(`${CONFIG.supabaseUrl}/functions/v1/gerenciar-login`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: CONFIG.supabaseChavePublica,
        Authorization: `Bearer ${s.access_token}`,
      },
      body: JSON.stringify(corpo),
    });
    const j = await r.json().catch(() => ({}));
    if (!r.ok || j.erro) return { ok: false, erro: j.erro || "Não foi possível concluir agora. Tente de novo." };
    return { ok: true, ...j };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

// =====================================================================
// Cadastros: lista, busca e ficha (Fase 10 · Etapa 5B) – só leitura.
// Quem decide o que cada papel vê é o RLS do banco: aqui só pedimos;
// o que não for permitido simplesmente não volta (ou volta vazio).
// =====================================================================

const ERRO_LISTA = "Não foi possível carregar a lista agora.";
const ERRO_FICHA = "Não foi possível carregar a ficha agora.";

/**
 * A data de nascimento não pode ser lida direto da tabela "pessoas"
 * (coluna protegida). Ela vem pela função nascimentos(), que confere a
 * permissão de cada pessoa. Preenche p.data_nascimento nos objetos.
 */
async function preencherNascimentos(pessoas) {
  const lista = pessoas.filter((p) => p?.id);
  if (!lista.length) return;
  try {
    const { data, error } = await sb.rpc("nascimentos", { p_ids: [...new Set(lista.map((p) => p.id))] });
    if (error) return;
    const mapa = new Map((data || []).map((x) => [x.id, x.data_nascimento]));
    for (const p of lista) p.data_nascimento = mapa.get(p.id) || null;
  } catch { /* sem idade: a tela mostra "Idade não informada" */ }
}

/** Salas do Fonte Kids (para filtro e nomes). */
export async function listarSalas() {
  try {
    const { data, error } = await sb.from("salas").select("id, nome, ordem, ativa, idade_min, idade_max").order("ordem");
    if (error) return { ok: false, erro: ERRO_LISTA };
    return { ok: true, lista: data || [] };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Crianças visíveis para o login (nome, idade, sala, família). */
export async function listarCriancas() {
  try {
    const { data, error } = await sb.from("criancas")
      .select("id, familia_id, ativo, perfil, sala_fixa_id, pessoa:pessoas(id, nome, nome_busca)")
      .limit(2000);
    if (error) return { ok: false, erro: ERRO_LISTA };
    await preencherNascimentos((data || []).map((c) => c.pessoa));
    return { ok: true, lista: data || [] };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/**
 * Contagens para o Início (Etapa 7). O RLS decide o que entra:
 * equipe = o departamento; responsável = a própria família.
 * Retorna { criancas, familias, autorizados } (null quando não deu para contar).
 */
export async function contarCadastros() {
  const contar = async (tabela, filtro) => {
    try {
      let q = sb.from(tabela).select("id", { count: "exact", head: true });
      if (filtro) q = filtro(q);
      const { count, error } = await q;
      return error ? null : count || 0;
    } catch { return null; }
  };
  const [criancas, familias, autorizados] = await Promise.all([
    contar("criancas", (q) => q.eq("ativo", true)),
    contar("familias"),
    contar("pessoas_autorizadas"),
  ]);
  return { criancas, familias, autorizados };
}

/** Famílias visíveis (responsáveis e crianças com nome). */
export async function listarFamilias() {
  try {
    const { data, error } = await sb.from("familias")
      .select("id, responsaveis(principal, pessoa:pessoas(nome, nome_busca)), criancas(id, ativo, pessoa:pessoas(nome, nome_busca))")
      .limit(2000);
    if (error) return { ok: false, erro: ERRO_LISTA };
    return { ok: true, lista: data || [] };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Voluntárias (o banco só mostra para a liderança; cada uma vê só a própria). */
export async function listarVoluntarias() {
  try {
    const { data, error } = await sb.from("voluntarias")
      .select("id, status, funcao, pessoa:pessoas(id, nome, nome_busca)")
      .limit(2000);
    if (error) return { ok: false, erro: ERRO_LISTA };
    await preencherNascimentos((data || []).map((v) => v.pessoa));
    return { ok: true, lista: data || [] };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Pessoas da família: responsáveis (com quais crianças) e autorizadas. */
async function pessoasDaFamilia(familiaId) {
  const [rResp, rAut] = await Promise.all([
    sb.from("responsaveis").select("id, principal, pessoa:pessoas(id, nome, telefone), responsaveis_criancas(crianca_id)").eq("familia_id", familiaId),
    sb.from("pessoas_autorizadas").select("id, observacao, pessoa:pessoas(id, nome, telefone)").eq("familia_id", familiaId),
  ]);
  if (rResp.error || rAut.error) throw new Error("leitura");
  return { responsaveis: rResp.data || [], autorizadas: rAut.data || [] };
}

/** Ficha da criança. */
export async function fichaCrianca(id) {
  try {
    const { data: c, error } = await sb.from("criancas")
      .select("id, familia_id, ativo, perfil, alergias_observacoes, sala_fixa_id, pessoa:pessoas(id, nome, sexo)")
      .eq("id", id).maybeSingle();
    if (error) return { ok: false, erro: ERRO_FICHA };
    if (!c) return { ok: false, naoEncontrada: true, erro: "Ficha não encontrada ou sem permissão para ver." };
    await preencherNascimentos([c.pessoa]);

    const [fam, rIrmaos, rRel, rCheck] = await Promise.all([
      pessoasDaFamilia(c.familia_id),
      sb.from("criancas").select("id, ativo, pessoa:pessoas(nome)").eq("familia_id", c.familia_id).neq("id", id),
      c.pessoa?.id
        ? sb.from("relacoes_pessoas").select("pessoa_id, tipo, detalhe").eq("relacionada_id", c.pessoa.id)
        : Promise.resolve({ data: [] }),
      sb.from("checkins").select("entrada_em, saida_em, sala:salas(nome)").eq("crianca_id", id)
        .order("entrada_em", { ascending: false }).limit(1),
    ]);
    const relacoes = new Map((rRel.data || []).map((r) => [r.pessoa_id, r]));
    return {
      ok: true, crianca: c, ...fam, relacoes,
      irmaos: rIrmaos.data || [],
      ultimoCheckin: (rCheck.data || [])[0] || null,
    };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Ficha da família. */
export async function fichaFamilia(id) {
  try {
    const { data: f, error } = await sb.from("familias").select("id, observacoes").eq("id", id).maybeSingle();
    if (error) return { ok: false, erro: ERRO_FICHA };
    if (!f) return { ok: false, naoEncontrada: true, erro: "Ficha não encontrada ou sem permissão para ver." };
    const [fam, rCri, rRel] = await Promise.all([
      pessoasDaFamilia(id),
      sb.from("criancas").select("id, ativo, sala_fixa_id, pessoa:pessoas(id, nome)").eq("familia_id", id),
      relacoesDaFamilia(id),
    ]);
    await preencherNascimentos((rCri.data || []).map((c) => c.pessoa));
    return { ok: true, familia: f, ...fam, criancas: rCri.data || [], relacoes: rRel.ok ? rRel.lista : [] };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Ficha da voluntária (o banco só libera para a liderança e para ela mesma). */
export async function fichaVoluntaria(id) {
  try {
    const { data: v, error } = await sb.from("voluntarias")
      .select("id, status, funcao, email, profissao, salas_preferidas, cultos_preferidos, teto_mensal, aprovada_em, pessoa:pessoas(id, nome, telefone)")
      .eq("id", id).maybeSingle();
    if (error) return { ok: false, erro: ERRO_FICHA };
    if (!v) return { ok: false, naoEncontrada: true, erro: "Ficha não encontrada ou sem permissão para ver." };
    await preencherNascimentos([v.pessoa]);
    let cultos = [];
    if (v.cultos_preferidos?.length) {
      const { data } = await sb.from("cultos_recorrentes").select("id, nome").in("id", v.cultos_preferidos);
      cultos = (data || []).map((x) => x.nome);
    }
    return { ok: true, voluntaria: v, cultos };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

// =====================================================================
// Minha família (Fase 10 · Etapa 5C) – responsável
// Só as famílias em que o próprio login é responsável (filtra pela pessoa
// do login, então liderança/recepção não recebem as famílias dos outros).
// =====================================================================

/**
 * { ok, familias: [{ id, responsaveis, autorizadas, criancas,
 *   minhasRelacoes: Map(pessoaCriancaId → {tipo, detalhe}),
 *   ultimosCheckins: Map(criancaId → checkin) }] }
 */
export async function minhaFamilia() {
  const perfil = await meuPerfil();
  if (!perfil.ok) return { ok: false, erro: perfil.erro };
  if (!perfil.pessoaId) return { ok: true, familias: [] };
  try {
    const { data: minhas, error } = await sb.from("responsaveis").select("familia_id").eq("pessoa_id", perfil.pessoaId);
    if (error) return { ok: false, erro: "Não foi possível carregar a sua família agora." };
    const ids = [...new Set((minhas || []).map((m) => m.familia_id))];
    if (!ids.length) return { ok: true, familias: [] };

    const { data: cri, error: e2 } = await sb.from("criancas")
      .select("id, familia_id, ativo, perfil, alergias_observacoes, sala_fixa_id, pessoa:pessoas(id, nome)")
      .in("familia_id", ids);
    if (e2) return { ok: false, erro: "Não foi possível carregar a sua família agora." };
    const criancas = cri || [];
    const pessoasCri = criancas.map((c) => c.pessoa).filter(Boolean);
    const criIds = criancas.map((c) => c.id);

    const [fams, , rRel, rChk, relsFam] = await Promise.all([
      Promise.all(ids.map((id) => pessoasDaFamilia(id))),
      preencherNascimentos(pessoasCri),
      pessoasCri.length
        ? sb.from("relacoes_pessoas").select("relacionada_id, tipo, detalhe")
            .eq("pessoa_id", perfil.pessoaId).in("relacionada_id", pessoasCri.map((p) => p.id))
        : Promise.resolve({ data: [] }),
      criIds.length
        ? sb.from("checkins").select("crianca_id, entrada_em, saida_em, sala:salas(nome)")
            .in("crianca_id", criIds).order("entrada_em", { ascending: false }).limit(500)
        : Promise.resolve({ data: [] }),
      Promise.all(ids.map((id) => relacoesDaFamilia(id))),
    ]);
    const minhasRelacoes = new Map((rRel.data || []).map((r) => [r.relacionada_id, r]));
    const ultimosCheckins = new Map();
    for (const ck of rChk.data || []) if (!ultimosCheckins.has(ck.crianca_id)) ultimosCheckins.set(ck.crianca_id, ck);

    const familias = ids.map((id, i) => ({
      id, ...fams[i],
      criancas: criancas.filter((c) => c.familia_id === id),
      minhasRelacoes, ultimosCheckins,
      relacoes: relsFam[i].ok ? relsFam[i].lista : [],
    }));
    return { ok: true, familias, eu: perfil.pessoaId };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

// =====================================================================
// Edição pelo responsável (Etapa 5C). A alteração vale na hora; o banco
// confere a família, registra na auditoria e avisa a liderança.
// =====================================================================

// Mensagens do banco que podem ser mostradas como estão (todas escritas por nós).
const ERRO_LEGIVEL = /^(Informe o nome|Data de nascimento inválida|Alergias e cuidados|Telefone inválido|Observação|Limite de 10|Conclua o primeiro acesso|Descreva a relação|Tipo de relação inválido)/;

async function chamarEdicao(funcao, args) {
  try {
    const { data, error } = await sb.rpc(funcao, args);
    if (!error) return { ok: true, resultado: data };
    const msg = String(error.message || "");
    if (ERRO_LEGIVEL.test(msg)) return { ok: false, erro: msg };
    if (msg.includes("sem permissão") || msg.includes("não encontrad")) return { ok: false, erro: "Sem permissão para alterar este cadastro." };
    return { ok: false, erro: "Não foi possível salvar agora. Tente de novo." };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Data de nascimento de uma pessoa (pela função nascimentos(), que confere a permissão). */
export async function nascimentoDe(pessoaId) {
  if (!pessoaId) return null;
  const p = { id: pessoaId };
  await preencherNascimentos([p]);
  return p.data_nascimento || null;
}

export async function editarMeuPerfil(nome, nascimento) {
  const r = await chamarEdicao("editar_meu_perfil", { p_nome: nome, p_nascimento: nascimento || null });
  if (r.ok) limparPerfilGuardado();
  return r;
}

export function editarCrianca(criancaId, nome, nascimento, alergias) {
  return chamarEdicao("editar_crianca", { p_crianca: criancaId, p_nome: nome, p_nascimento: nascimento || null, p_alergias: alergias || null });
}

export function incluirAutorizado(familiaId, nome, telefone, observacao) {
  return chamarEdicao("incluir_autorizado", { p_familia: familiaId, p_nome: nome, p_telefone: telefone, p_observacao: observacao || null });
}

export function removerAutorizado(autorizadoId) {
  return chamarEdicao("remover_autorizado", { p_autorizado: autorizadoId });
}

// =====================================================================
// Pendências de cadastro (Etapa 5D). O banco decide o que cada login vê:
// recepção/liderança/pastores/admin → o departamento; responsável → só a
// própria família. Resolver é sempre pela confirmar_pendencia() (só as
// manuais; as automáticas somem sozinhas quando o dado é preenchido).
// =====================================================================

/** Nomes legíveis dos tipos de pendência. */
export const NOMES_PENDENCIA = {
  relacao_nao_informada: "Relação não informada",
  nascimento_vazio: "Sem data de nascimento",
  conferir_nascimento: "Conferir data de nascimento",
  nome_responsavel: "Conferir nome do responsável",
};
export const nomePendencia = (tipo) =>
  NOMES_PENDENCIA[tipo] || String(tipo || "Pendência").replace(/_/g, " ").replace(/^./, (x) => x.toUpperCase());

/** situacao: "abertas" | "resolvidas" (resolvidas: as 300 mais recentes). */
export async function listarPendencias(situacao = "abertas") {
  try {
    const { data, error } = await sb.rpc("listar_pendencias", { p_situacao: situacao });
    if (error) return { ok: false, erro: ERRO_LISTA };
    return { ok: true, lista: data || [] };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/** Quantas pendências abertas o login enxerga (para o início). */
export async function contarPendencias() {
  try {
    const [{ count, error }, vol] = await Promise.all([
      sb.from("pendencias_cadastro").select("id", { count: "exact", head: true }).is("resolvida_em", null),
      voluntariasSemAcesso(),
    ]);
    if (error) return { ok: false };
    return { ok: true, total: (count || 0) + (vol.ok ? vol.lista.length : 0), cadastro: count || 0, voluntarias: vol.ok ? vol.lista.length : 0 };
  } catch {
    return { ok: false };
  }
}

/**
 * Voluntárias que ainda não entraram no app (Etapa 7, decidido em 27/10/2026).
 * Só para a liderança do Fonte Kids, pastores e admin (situacao_logins confere
 * no banco); para os outros logins volta lista vazia, sem consultar.
 * Guardada por 1 minuto para não repetir a consulta a cada troca de tela.
 */
const MOTIVOS_SEM_ACESSO = {
  primeiro_acesso: "Ainda não entrou no app",
  sem_login: "Sem login",
  sem_telefone: "Sem telefone no cadastro",
  telefone_invalido: "Telefone fora do padrão",
  telefone_em_uso: "Telefone já usado por outro login",
  telefone_compartilhado: "Telefone compartilhado",
};
let volGuardadas = null;
export async function voluntariasSemAcesso(forcar = false) {
  const perfil = await meuPerfil();
  if (!perfil.ok || !perfil.temPapel("admin", "pastor", "lider")) return { ok: true, lista: [] };
  if (!forcar && volGuardadas && volGuardadas.uid === perfil.uid && Date.now() - volGuardadas.em < 60000) return volGuardadas.r;
  try {
    const { data, error } = await sb.rpc("situacao_logins");
    if (error) return { ok: false, lista: [] };
    const lista = (data || [])
      .filter((x) => x.e_voluntaria && MOTIVOS_SEM_ACESSO[x.situacao])
      .map((x) => ({ pessoaId: x.pessoa_id, nome: x.nome, situacao: x.situacao, motivo: MOTIVOS_SEM_ACESSO[x.situacao], telefone: x.telefone_mascarado }));
    const r = { ok: true, lista };
    volGuardadas = { uid: perfil.uid, em: Date.now(), r };
    return r;
  } catch {
    return { ok: false, lista: [] };
  }
}

/** Marca uma pendência manual como resolvida. */
export async function confirmarPendencia(id) {
  try {
    const { error } = await sb.rpc("confirmar_pendencia", { p_pendencia: id });
    if (!error) return { ok: true };
    const msg = String(error.message || "");
    if (msg.startsWith("Este aviso some sozinho")) return { ok: false, erro: "Este aviso some sozinho quando o dado for preenchido." };
    if (msg.includes("sem permissão") || msg.includes("não encontrad")) return { ok: false, erro: "Esta pendência já foi resolvida ou você não tem permissão." };
    return { ok: false, erro: "Não foi possível salvar agora. Tente de novo." };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

// =====================================================================
// Relações informadas por outro responsável da família e cônjuge
// (Etapa 5D, complemento). Vale na hora; a liderança é avisada.
// O que a própria pessoa informou no login dela não é sobrescrito.
// =====================================================================

/** Relações da família: [{ pessoa_id, relacionada_id, tipo, detalhe, pelo_proprio }]. */
export async function relacoesDaFamilia(familiaId) {
  try {
    const { data, error } = await sb.rpc("relacoes_da_familia", { p_familia: familiaId });
    if (error) return { ok: false, lista: [] };
    return { ok: true, lista: data || [] };
  } catch {
    return { ok: false, lista: [] };
  }
}

/** lista: [{ crianca, tipo, detalhe }] → { ok, resultado: { gravadas, mantidas } } */
export function informarRelacoesDe(responsavelId, lista) {
  return chamarEdicao("informar_relacoes_de", { p_responsavel: responsavelId, p_relacoes: lista });
}

/** Marca (sim = true) ou desmarca cônjuge/parceiro(a) com outro responsável da família. */
export function informarConjuge(responsavelId, sim) {
  return chamarEdicao("informar_conjuge", { p_responsavel: responsavelId, p_conjuge: !!sim });
}

// =====================================================================
// Fase 5 · Etapa 5A – agenda de cultos, salas por culto e acessos da equipe.
// Tudo passa por funções do banco (que conferem a permissão e registram
// na auditoria). As mensagens de erro dessas funções foram escritas por
// nós (código P0001) e podem ser mostradas como estão.
// =====================================================================

async function chamarRpc(funcao, args) {
  try {
    const { data, error } = await sb.rpc(funcao, args);
    if (!error) return { ok: true, resultado: data };
    if (error.code === "P0001" && error.message) return { ok: false, erro: error.message };
    return { ok: false, erro: "Não foi possível concluir agora. Tente de novo." };
  } catch {
    return { ok: false, erro: SEM_CONEXAO };
  }
}

/**
 * Cultos dos próximos dias (criados sozinhos a partir da agenda).
 * [{ id, data, horario, nome, cancelado, extra, personalizado,
 *    salas: [{ sala_id, nome, idade_min, idade_max, salas: [ids], cancelada }] }]
 */
export async function cultosProximos(dias = 14) {
  const r = await chamarRpc("cultos_proximos", { p_dias: dias });
  return r.ok ? { ok: true, lista: r.resultado || [] } : r;
}

/** Agenda: [{ id, nome, dia_semana, horario, ativo, salas: [...] }] */
export async function agendaCultos() {
  const r = await chamarRpc("agenda_cultos", {});
  return r.ok ? { ok: true, lista: r.resultado || [] } : r;
}

export function salvarCultoAgenda(id, nome, diaSemana, horario, ativo = true) {
  return chamarRpc("salvar_culto_agenda", { p_id: id || null, p_nome: nome, p_dia_semana: diaSemana, p_horario: horario, p_ativo: ativo });
}

/** salas: [{ sala_id, cancelada, junto_com }] – só as exceções (sala aberta não entra). */
export function definirSalasAgenda(recorrenteId, salas) {
  return chamarRpc("definir_salas_agenda", { p_recorrente: recorrenteId, p_salas: salas });
}

/** salas = null → volta ao padrão da agenda. */
export function definirSalasDia(cultoId, salas) {
  return chamarRpc("definir_salas_dia", { p_culto: cultoId, p_salas: salas });
}

export function cancelarCulto(cultoId, cancelar = true) {
  return chamarRpc("cancelar_culto", { p_culto: cultoId, p_cancelar: cancelar });
}

export function criarCultoExtra(data, horario, nome, salas = []) {
  return chamarRpc("criar_culto_extra", { p_data: data, p_horario: horario, p_nome: nome, p_salas: salas });
}

/** Voluntárias com login e seus acessos: [{ perfil_id, nome, lider, recepcao, sou_eu }] */
export async function papeisVoluntarias() {
  const r = await chamarRpc("papeis_voluntarias", {});
  return r.ok ? { ok: true, lista: r.resultado || [] } : r;
}

/** papel: "lider" | "recepcao"; ativo: dar (true) ou tirar (false). */
export async function definirPapel(perfilId, papel, ativo) {
  const r = await chamarRpc("definir_papel", { p_perfil: perfilId, p_papel: papel, p_ativo: !!ativo });
  if (r.ok) limparPerfilGuardado();
  return r;
}

// =====================================================================
// Fase 5 · Etapa 5B – Entrada do check-in. Tudo pelas funções do banco
// (a gravação direta na tabela checkins foi fechada). A sala vem do banco
// (faixa de idade na data do culto, respeitando as salas juntas do dia).
// =====================================================================

/** Cultos de hoje: [{ id, nome, horario, extra, sugerido, presentes, salas }] */
export async function cultosDeHoje() {
  const r = await chamarRpc("cultos_de_hoje", {});
  return r.ok ? { ok: true, lista: r.resultado || [] } : r;
}

/**
 * Busca para o check-in (nome da criança/responsável ou 4 últimos números do telefone).
 * [{ familia_id, responsaveis: [{ nome, principal }],
 *    criancas: [{ id, pessoa_id, nome, alergias, aniversario, sala_id, sala_nome, sem_sala,
 *                 checkin: { id, codigo, sala_nome, entrada_em, saiu } | null }],
 *    pendencias: [{ id, tipo, mensagem, automatica, crianca_id }] }]
 */
export async function buscarParaCheckin(cultoId, texto) {
  const r = await chamarRpc("buscar_para_checkin", { p_culto: cultoId, p_texto: texto });
  return r.ok ? { ok: true, lista: r.resultado || [] } : r;
}

/** → [{ crianca_id, nome, checkin_id, codigo, sala_nome, ja_tinha }] */
export async function fazerCheckin(cultoId, criancaIds) {
  const r = await chamarRpc("fazer_checkin", { p_culto: cultoId, p_criancas: criancaIds });
  return r.ok ? { ok: true, lista: r.resultado || [] } : r;
}

export function desfazerCheckin(checkinId) {
  return chamarRpc("desfazer_checkin", { p_checkin: checkinId });
}

/** Responsável: check-ins de hoje dos filhos [{ nome, culto, horario, sala_nome, codigo, entrada_em, saiu }] */
export async function meusCheckinsHoje() {
  const r = await chamarRpc("meus_checkins_hoje", {});
  return r.ok ? { ok: true, lista: r.resultado || [] } : r;
}
