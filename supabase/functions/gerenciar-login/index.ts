// =====================================================================
// Edge Function "gerenciar-login" – Fase 4 · Etapa 3
// Cria e redefine logins (Supabase Auth, sem SMS).
//
// Login = telefone. O app converte o telefone num e-mail técnico
// "<telefone>@<LOGIN_DOMINIO>" (domínio que não recebe e-mail).
// Senha inicial (decisão da Rebeca, 26/10/2026):
//   • voluntária ativa com data de nascimento → DDMMAAAA
//   • demais → o próprio telefone de login (só dígitos, com 55)
// Todo login nasce com troca de senha obrigatória: até trocar, a pessoa
// não vê nenhum dado (regra no banco). A senha NUNCA aparece na resposta
// nem nos logs; a resposta diz só QUAL regra foi usada.
//
// Quem pode chamar:
//   • o painel do Supabase (Edge Functions → gerenciar-login → Test, com
//     o papel "service role"), ou
//   • um usuário logado que já trocou a senha e pode dar TODOS os papéis
//     envolvidos (o banco decide: posso_dar_papeis / posso_redefinir_senha).
//     "lote" e "autoteste": só o painel ou admin.
//
// Ações (POST, JSON):
//   { "acao": "autoteste" }
//       cria e apaga na hora um login fictício (confere o domínio técnico).
//   { "acao": "criar", "pessoa_id": "<uuid>", "telefone_login": "55DDD9XXXXXXXX" (opcional),
//     "papeis": [{ "papel": "admin" }, { "papel": "lider", "departamento": "kids" }] }
//       papéis de voluntária/responsável são acrescentados sozinhos
//       conforme o cadastro da pessoa.
//   { "acao": "redefinir", "pessoa_id": "<uuid>" }
//       volta para a senha inicial e exige nova troca.
//   { "acao": "lote", "departamento": "kids", "confirmar": false, "limite": 50 }
//       sem "confirmar": true só mostra as contagens. Com true, cria até
//       "limite" logins por chamada (repita até "restantes" = 0).
//
// Variáveis de ambiente (já fornecidas pelo Supabase):
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
// Opcional: LOGIN_DOMINIO (padrão login.fonteitaparica.invalid) –
//   tem de ser o MESMO usado pelo app na tela de login.
// =====================================================================
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TELEFONE = /^55[1-9][0-9]9?[0-9]{8}$/;
const PAPEIS = ["admin", "pastor", "lider", "recepcao", "voluntaria", "responsavel"];
const PAPEIS_DEPT = ["lider", "recepcao", "voluntaria"];

type Papel = { papel: string; departamento_id: string | null };
type Dados = {
  igreja_id: string; telefone_contato: string | null; data_nascimento: string | null;
  depts_voluntaria: string[]; e_responsavel: boolean; ja_tem_login: boolean;
};

function resposta(corpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(corpo), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

function papelDoToken(token: string): string | null {
  try {
    const p = JSON.parse(atob(token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")));
    return typeof p.role === "string" ? p.role : null;
  } catch {
    return null;
  }
}

// DDMMAAAA (voluntária) ou telefone de login
function senhaInicial(telefone: string, nascimento: string | null, voluntaria: boolean) {
  if (voluntaria && nascimento && /^\d{4}-\d{2}-\d{2}$/.test(nascimento)) {
    const [a, m, d] = nascimento.split("-");
    return { senha: `${d}${m}${a}`, regra: "data_de_nascimento" };
  }
  return { senha: telefone, regra: "telefone" };
}

function papeisDaPessoa(d: Dados, extras: Papel[]): Papel[] {
  const lista: Papel[] = [...extras];
  for (const dept of d.depts_voluntaria) lista.push({ papel: "voluntaria", departamento_id: dept });
  if (d.e_responsavel) lista.push({ papel: "responsavel", departamento_id: null });
  const vistos = new Set<string>();
  return lista.filter((p) => {
    const k = `${p.papel}|${p.departamento_id ?? ""}`;
    if (vistos.has(k)) return false;
    vistos.add(k);
    return true;
  });
}

async function criarLogin(
  admin: SupabaseClient, dominio: string, pessoaId: string, telefone: string,
  d: Dados, papeis: Papel[], concedidoPor: string | null,
) {
  const { senha, regra } = senhaInicial(telefone, d.data_nascimento, d.depts_voluntaria.length > 0);
  const { data, error } = await admin.auth.admin.createUser({
    email: `${telefone}@${dominio}`,
    password: senha,
    email_confirm: true,
    app_metadata: { pessoa_id: pessoaId, telefone },
  });
  if (error || !data.user) {
    return { ok: false as const, erro: traduzErro(error?.message ?? "") };
  }
  const uid = data.user.id;
  const { data: perfil } = await admin.from("perfis").select("pessoa_id").eq("id", uid).single();
  if (!perfil || perfil.pessoa_id !== pessoaId) {
    await admin.auth.admin.deleteUser(uid);
    return { ok: false as const, erro: "O perfil não foi ligado à pessoa. Nada foi criado." };
  }
  if (papeis.length) {
    const { error: e2 } = await admin.from("papeis_usuario").insert(
      papeis.map((p) => ({ perfil_id: uid, departamento_id: p.departamento_id, papel: p.papel, concedido_por: concedidoPor })),
    );
    if (e2) {
      await admin.auth.admin.deleteUser(uid);
      return { ok: false as const, erro: "Não foi possível dar os papéis. Nada foi criado." };
    }
  }
  return { ok: true as const, perfil_id: uid, regra };
}

function traduzErro(msg: string): string {
  const m = msg.toLowerCase();
  if (m.includes("already") || m.includes("registered") || m.includes("exists")) return "Este telefone já tem login.";
  if (m.includes("password")) return "A senha inicial não atende à política de senha do Auth (veja o tamanho mínimo).";
  if (m.includes("email")) return "O Auth recusou o e-mail técnico. Confira LOGIN_DOMINIO.";
  return "Erro do Auth ao criar o login.";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return resposta({ erro: "Use POST." }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const dominio = Deno.env.get("LOGIN_DOMINIO") || "login.fonteitaparica.invalid";
  if (!url || !anonKey || !serviceKey) return resposta({ erro: "Configuração incompleta no servidor." }, 500);

  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  // ----- Quem está chamando -----
  // Painel/servidor: chave secreta (sb_secret_…) ou service_role, no
  // cabeçalho Authorization ou apikey. A chave é CONFERIDA no próprio Auth
  // (endpoint de administração), não só lida.
  const auth = req.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7).trim() : "";
  const apikey = (req.headers.get("apikey") ?? "").trim();
  const chaveDeServico = async (k: string) => {
    if (!k) return false;
    if (k === serviceKey) return true;
    if (!k.startsWith("sb_secret_") && papelDoToken(k) !== "service_role") return false;
    const r = await fetch(`${url}/auth/v1/admin/users?page=1&per_page=1`, {
      headers: { apikey: k, Authorization: `Bearer ${k}` },
    });
    await r.body?.cancel();
    return r.ok;
  };
  const doPainel = (await chaveDeServico(token)) || (await chaveDeServico(apikey));
  if (!doPainel && (!token || token.startsWith("sb_") || token === anonKey)) {
    return resposta({ erro: "Faça login (ou, no painel, use a chave secreta / service role)." }, 401);
  }
  let usuario: SupabaseClient | null = null;
  let quem: string | null = null;
  if (!doPainel) {
    const { data, error } = await admin.auth.getUser(token);
    if (error || !data.user) return resposta({ erro: "Sessão inválida ou expirada." }, 401);
    quem = data.user.id;
    usuario = createClient(url, anonKey, {
      global: { headers: { Authorization: auth } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
  }
  const eAdmin = async () => {
    if (doPainel) return true;
    const { data } = await usuario!.rpc("posso_dar_papeis", { p_papeis: [{ papel: "admin" }] });
    return data === true;
  };

  let corpo: Record<string, unknown>;
  try {
    corpo = await req.json();
  } catch {
    return resposta({ erro: "Corpo da requisição inválido." }, 400);
  }
  const acao = corpo.acao;

  // ----- autoteste -----
  if (acao === "autoteste") {
    if (!(await eAdmin())) return resposta({ erro: "Só a administração." }, 403);
    const fake = "5500" + String(Math.floor(Math.random() * 1e9)).padStart(9, "0");
    const { data, error } = await admin.auth.admin.createUser({
      email: `${fake}@${dominio}`,
      password: crypto.randomUUID(),
      email_confirm: true,
      app_metadata: {},
    });
    if (error || !data.user) return resposta({ ok: false, dominio, erro: traduzErro(error?.message ?? "") });
    const { data: perfil } = await admin.from("perfis").select("troca_senha_obrigatoria").eq("id", data.user.id).single();
    await admin.auth.admin.deleteUser(data.user.id);
    return resposta({ ok: true, dominio, perfil_criado: !!perfil, troca_obrigatoria: perfil?.troca_senha_obrigatoria === true, apagado: true });
  }

  // ----- criar -----
  if (acao === "criar") {
    const pessoaId = String(corpo.pessoa_id ?? "");
    if (!UUID.test(pessoaId)) return resposta({ erro: "pessoa_id inválido." }, 400);
    const { data: linhas } = await admin.rpc("dados_login", { p_pessoa: pessoaId });
    const d = (linhas as Dados[] | null)?.[0];
    if (!d) return resposta({ erro: "Pessoa não encontrada." }, 404);
    if (d.ja_tem_login) return resposta({ erro: "Esta pessoa já tem login." }, 409);
    const telefone = String(corpo.telefone_login ?? d.telefone_contato ?? "").replace(/\D/g, "");
    if (!TELEFONE.test(telefone)) return resposta({ erro: "Telefone de login ausente ou fora do padrão 55 + DDD + número." }, 400);

    const extras: Papel[] = [];
    for (const p of (Array.isArray(corpo.papeis) ? corpo.papeis : []) as Record<string, unknown>[]) {
      const papel = String(p.papel ?? "");
      if (!PAPEIS.includes(papel)) return resposta({ erro: `Papel desconhecido: ${papel}` }, 400);
      let dept: string | null = null;
      if (PAPEIS_DEPT.includes(papel)) {
        const slug = String(p.departamento ?? "");
        const { data: dep } = await admin.from("departamentos").select("id").eq("slug", slug).single();
        if (!dep) return resposta({ erro: `Departamento não encontrado para o papel ${papel}.` }, 400);
        dept = dep.id;
      }
      extras.push({ papel, departamento_id: dept });
    }
    const papeis = papeisDaPessoa(d, extras);
    if (!papeis.length) return resposta({ erro: "Informe ao menos um papel." }, 400);
    if (!doPainel) {
      const { data: pode } = await usuario!.rpc("posso_dar_papeis", { p_papeis: papeis });
      if (pode !== true) return resposta({ erro: "Você não pode criar um login com estes papéis." }, 403);
    }
    const r = await criarLogin(admin, dominio, pessoaId, telefone, d, papeis, quem);
    if (!r.ok) return resposta({ erro: r.erro }, 409);
    return resposta({
      ok: true, perfil_id: r.perfil_id, senha_inicial: r.regra,
      papeis: papeis.map((p) => p.papel), troca_obrigatoria: true,
    });
  }

  // ----- redefinir -----
  if (acao === "redefinir") {
    const pessoaId = String(corpo.pessoa_id ?? "");
    if (!UUID.test(pessoaId)) return resposta({ erro: "pessoa_id inválido." }, 400);
    const { data: perfil } = await admin.from("perfis").select("id, telefone").eq("pessoa_id", pessoaId).single();
    if (!perfil?.telefone) return resposta({ erro: "Esta pessoa não tem login." }, 404);
    if (!doPainel) {
      const { data: pode } = await usuario!.rpc("posso_redefinir_senha", { p_perfil: perfil.id });
      if (pode !== true) return resposta({ erro: "Você não pode redefinir a senha deste login." }, 403);
    }
    const { data: linhas } = await admin.rpc("dados_login", { p_pessoa: pessoaId });
    const d = (linhas as Dados[] | null)?.[0];
    if (!d) return resposta({ erro: "Pessoa não encontrada." }, 404);
    const { senha, regra } = senhaInicial(perfil.telefone, d.data_nascimento, d.depts_voluntaria.length > 0);
    const { error } = await admin.auth.admin.updateUserById(perfil.id, { password: senha });
    if (error) return resposta({ erro: traduzErro(error.message) }, 409);
    await admin.rpc("marcar_senha_inicial", { p_perfil: perfil.id });
    return resposta({ ok: true, senha_inicial: regra, troca_obrigatoria: true });
  }

  // ----- lote -----
  if (acao === "lote") {
    if (!(await eAdmin())) return resposta({ erro: "Só a administração." }, 403);
    const slug = String(corpo.departamento ?? "kids");
    const { data: dep } = await admin.from("departamentos").select("id").eq("slug", slug).single();
    if (!dep) return resposta({ erro: "Departamento não encontrado." }, 404);
    const { data: cands, error } = await admin.rpc("candidatos_login", { p_departamento: dep.id });
    if (error || !cands) return resposta({ erro: "Não foi possível listar os candidatos." }, 500);
    type C = { pessoa_id: string; telefone_login: string; data_nascimento: string | null; e_voluntaria: boolean; e_responsavel: boolean; situacao: string };
    const lista = cands as C[];
    const contagem: Record<string, number> = {};
    for (const c of lista) contagem[c.situacao] = (contagem[c.situacao] ?? 0) + 1;
    const aCriar = lista.filter((c) => c.situacao === "criar");
    const resumo = {
      por_situacao: contagem,
      a_criar_voluntarias: aCriar.filter((c) => c.e_voluntaria).length,
      a_criar_responsaveis: aCriar.filter((c) => c.e_responsavel).length,
      a_criar_os_dois_papeis: aCriar.filter((c) => c.e_voluntaria && c.e_responsavel).length,
    };
    if (corpo.confirmar !== true) return resposta({ simulacao: true, ...resumo });

    const limite = Math.min(Math.max(Number(corpo.limite) || 50, 1), 100);
    let criados = 0, falhas = 0;
    for (const c of aCriar.slice(0, limite)) {
      const { data: linhas } = await admin.rpc("dados_login", { p_pessoa: c.pessoa_id });
      const d = (linhas as Dados[] | null)?.[0];
      if (!d || d.ja_tem_login) { falhas++; continue; }
      const papeis = papeisDaPessoa({ ...d, depts_voluntaria: d.depts_voluntaria.filter((x) => x === dep.id) }, []);
      const r = await criarLogin(admin, dominio, c.pessoa_id, c.telefone_login, d, papeis, quem);
      if (r.ok) criados++; else falhas++;
    }
    return resposta({ simulacao: false, criados, falhas, restantes: Math.max(aCriar.length - criados - falhas, 0) });
  }

  return resposta({ erro: 'acao deve ser "autoteste", "criar", "redefinir" ou "lote".' }, 400);
});
