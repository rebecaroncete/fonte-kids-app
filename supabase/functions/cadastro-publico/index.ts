// =====================================================================
// Edge Function "cadastro-publico" – Fase 5 · Etapa 5D
// Cadastro de família nova pelo link público (sem login).
//
// É a ÚNICA porta do cadastro sem login: as funções do banco que gravam o
// cadastro só podem ser chamadas com a chave de serviço, que fica só aqui.
//
// Passo 1 – POST { "acao": "verificar", "telefone": "...", "captchaToken": "..." }
//   • confere o captcha (Turnstile) NO SERVIDOR;
//   • telefone já cadastrado (de um responsável ou de um login) →
//     { ok: true, existe: true } (a família entra no app e usa "Adicionar criança");
//   • senão → { ok: true, existe: false, ticket, termo: { versao, texto } }.
//     O "ticket" vale 60 min, só para aquele telefone (assinado com HMAC).
//
// Passo 2 – POST { "acao": "cadastrar", "ticket": "...", "dados": {...},
//                  "fotos": { "criancas": [dataUrl|null, ...], "responsavel": dataUrl|null } }
//   • confere o ticket (mesmo telefone do responsável principal);
//   • grava tudo no banco de uma vez (cadastrar_familia_link: valida tudo,
//     limite de 100 cadastros a cada 24 h, aviso à liderança);
//   • cria o login de cada responsável com telefone (senha inicial = o
//     telefone; troca obrigatória no 1º acesso) e liga o aceite do termo;
//   • envia as fotos ao Cloudinary (privadas, até 400 px);
//   • devolve só: links dos grupos certos pela idade, se o 2º responsável
//     ganhou login e quantas fotos falharam. Nenhum dado do banco volta.
//
// Fase 5 · 5F – cadastro de VOLUNTÁRIA pelo link (aprovação pela liderança):
// POST { "acao": "voluntaria_opcoes" }
//   • devolve o termo vigente da voluntária, as salas e os cultos da agenda
//     (nada pessoal; sem captcha).
// POST { "acao": "voluntaria", "captchaToken": "...", "dados": {...}, "foto": dataUrl }
//   • confere o captcha NO SERVIDOR; foto obrigatória;
//   • grava só um PEDIDO (pedido_voluntaria_criar: valida tudo, 12 anos ou mais,
//     limite de 30 a cada 24 h, aviso à liderança e aos pastores);
//   • envia a foto (privada, até 400 px) e liga ao pedido;
//   • resposta SEMPRE igual ({ ok: true }), exista o telefone ou não.
//
// Pública (sem login): publicar com verify_jwt = false.
// Segredos (os mesmos já usados por outras funções):
//   TURNSTILE_SECRET_KEY, ORIGENS_PERMITIDAS (opcional),
//   CLOUDINARY_API_KEY, CLOUDINARY_API_SECRET, CLOUDINARY_CLOUD_NAME (opcional),
//   LOGIN_DOMINIO (opcional; padrão login.fonteitaparica.invalid).
// SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY já existem por padrão.
// Nada de dado pessoal nos logs.
// =====================================================================
import { createClient, SupabaseClient } from "npm:@supabase/supabase-js@2";
import { apagarPrivada, enviarPrivada } from "./cloudinary.ts";

const ORIGENS = (Deno.env.get("ORIGENS_PERMITIDAS") || "https://rebecaroncete.github.io")
  .split(",").map((s) => s.trim()).filter(Boolean);
const TELEFONE = /^55[1-9][0-9]9?[0-9]{8}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const IMAGEM = /^data:image\/(jpeg|png|webp);base64,[A-Za-z0-9+/]+=*$/;
const MAX_FOTO = 3_000_000;        // caracteres por foto (~2,2 MB)
const MAX_CORPO = 25_000_000;      // corpo inteiro
const VALIDADE_TICKET = 60 * 60;   // segundos

function cabecalhos(origem: string | null): HeadersInit {
  const h: Record<string, string> = {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
  if (origem && ORIGENS.includes(origem)) h["Access-Control-Allow-Origin"] = origem;
  return h;
}
const resposta = (corpo: unknown, status: number, origem: string | null) =>
  new Response(JSON.stringify(corpo), { status, headers: cabecalhos(origem) });

function normalizarTelefone(v: unknown): string | null {
  let d = String(v ?? "").replace(/\D/g, "");
  if (d.startsWith("55") && (d.length === 12 || d.length === 13)) d = d.slice(2);
  if (d.length !== 10 && d.length !== 11) return null;
  if (d[0] === "0") return null;
  const t = "55" + d;
  return TELEFONE.test(t) ? t : null;
}

async function captchaValido(token: string, ip: string | null): Promise<boolean> {
  const segredo = Deno.env.get("TURNSTILE_SECRET_KEY");
  if (!segredo || !token || token.length > 2048) return false;
  const form = new FormData();
  form.append("secret", segredo);
  form.append("response", token);
  if (ip) form.append("remoteip", ip); // só repassado ao Turnstile; não é guardado
  try {
    const r = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form });
    const j = await r.json();
    return j?.success === true;
  } catch {
    return false;
  }
}

// ---------- Ticket: "telefone.validade.assinatura" ----------
async function chaveHmac(): Promise<CryptoKey> {
  const segredo = "cadastro-publico:" + (Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
  return await crypto.subtle.importKey("raw", new TextEncoder().encode(segredo),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}
const hex = (b: ArrayBuffer) => Array.from(new Uint8Array(b)).map((x) => x.toString(16).padStart(2, "0")).join("");

async function gerarTicket(tel: string): Promise<string> {
  const ate = Math.floor(Date.now() / 1000) + VALIDADE_TICKET;
  const msg = `${tel}.${ate}`;
  const sig = await crypto.subtle.sign("HMAC", await chaveHmac(), new TextEncoder().encode(msg));
  return `${msg}.${hex(sig)}`;
}

async function telefoneDoTicket(ticket: unknown): Promise<string | null> {
  const partes = String(ticket ?? "").split(".");
  if (partes.length !== 3 || !TELEFONE.test(partes[0]) || !/^\d{10}$/.test(partes[1]) || !/^[0-9a-f]{64}$/.test(partes[2])) return null;
  if (Number(partes[1]) < Math.floor(Date.now() / 1000)) return null;
  const pares = partes[2].match(/../g)!.map((h) => parseInt(h, 16));
  const ok = await crypto.subtle.verify("HMAC", await chaveHmac(), new Uint8Array(pares),
    new TextEncoder().encode(`${partes[0]}.${partes[1]}`));
  return ok ? partes[0] : null;
}

// ---------- Login do responsável (mesma regra da gerenciar-login) ----------
async function criarLoginResponsavel(admin: SupabaseClient, dominio: string, pessoaId: string, tel: string): Promise<string | null> {
  const { data, error } = await admin.auth.admin.createUser({
    email: `${tel}@${dominio}`,
    password: tel, // senha inicial = telefone; troca obrigatória no 1º acesso
    email_confirm: true,
    app_metadata: { pessoa_id: pessoaId, telefone: tel },
  });
  if (error || !data.user) return null;
  const uid = data.user.id;
  const { data: perfil } = await admin.from("perfis").select("pessoa_id").eq("id", uid).single();
  if (!perfil || perfil.pessoa_id !== pessoaId) { await admin.auth.admin.deleteUser(uid); return null; }
  const { error: e2 } = await admin.from("papeis_usuario")
    .insert({ perfil_id: uid, departamento_id: null, papel: "responsavel", concedido_por: null });
  if (e2) { await admin.auth.admin.deleteUser(uid); return null; }
  return uid;
}

/** Erros do banco que a tela sabe explicar (o resto vira "dados"). */
function erroDoBanco(msg: string): { erro: string; campo?: string } {
  const m = (msg || "").trim();
  if (["telefone_ja_cadastrado", "telefone2_ja_cadastrado", "limite_diario", "termo_desatualizado"].includes(m)) return { erro: m };
  if (/^[a-z0-9_]+$/.test(m) && m.length <= 40) return { erro: "dados", campo: m };
  return { erro: "interno" };
}

Deno.serve(async (req) => {
  const origem = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cabecalhos(origem) });
  if (req.method !== "POST") return resposta({ erro: "metodo" }, 405, origem);
  if (origem && !ORIGENS.includes(origem)) return resposta({ erro: "origem" }, 403, origem);
  if (Number(req.headers.get("content-length") || 0) > MAX_CORPO) return resposta({ erro: "grande" }, 413, origem);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return resposta({ erro: "interno" }, 500, origem);
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

  let corpo: Record<string, unknown>;
  try {
    const texto = await req.text();
    if (texto.length > MAX_CORPO) return resposta({ erro: "grande" }, 413, origem);
    corpo = JSON.parse(texto);
  } catch { return resposta({ erro: "pedido" }, 400, origem); }

  // ================= Passo 1: verificar o telefone =================
  if (corpo.acao === "verificar") {
    const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || null;
    if (!(await captchaValido(String(corpo.captchaToken ?? ""), ip))) return resposta({ erro: "captcha" }, 400, origem);
    const tel = normalizarTelefone(corpo.telefone);
    if (!tel) return resposta({ erro: "telefone" }, 400, origem);
    const { data, error } = await admin.rpc("cadastro_link_verificar", { p_telefone: tel });
    if (error || !data) { console.error("verificar falhou", error?.code); return resposta({ erro: "interno" }, 500, origem); }
    if (data.existe) return resposta({ ok: true, existe: true }, 200, origem);
    if (!data.termo) return resposta({ erro: "interno" }, 500, origem);
    return resposta({ ok: true, existe: false, ticket: await gerarTicket(tel), termo: data.termo }, 200, origem);
  }

  // ================= Passo 2: cadastrar =================
  if (corpo.acao === "cadastrar") {
    const telTicket = await telefoneDoTicket(corpo.ticket);
    if (!telTicket) return resposta({ erro: "ticket" }, 400, origem);
    const dados = corpo.dados as Record<string, unknown> | undefined;
    if (!dados || typeof dados !== "object") return resposta({ erro: "pedido" }, 400, origem);
    const resps = Array.isArray(dados.responsaveis) ? dados.responsaveis as Record<string, unknown>[] : [];
    if (!resps.length || normalizarTelefone(resps[0]?.telefone) !== telTicket) return resposta({ erro: "ticket" }, 400, origem);

    // Fotos (opcionais aqui; a tela pede a da criança)
    const fotos = (corpo.fotos ?? {}) as { criancas?: unknown; responsavel?: unknown };
    const fotosCri = Array.isArray(fotos.criancas) ? fotos.criancas : [];
    const fotoValida = (f: unknown) => typeof f === "string" && f.length <= MAX_FOTO && IMAGEM.test(f);
    for (const f of [...fotosCri, fotos.responsavel]) {
      if (f !== null && f !== undefined && !fotoValida(f)) return resposta({ erro: "foto" }, 400, origem);
    }

    const { data: r, error } = await admin.rpc("cadastrar_familia_link", { p_dados: {
      responsaveis: resps, criancas: dados.criancas, autorizados: dados.autorizados ?? [], termo_versao: dados.termo_versao,
    } });
    if (error || !r) {
      const e = erroDoBanco(error?.message ?? "");
      if (e.erro === "interno") console.error("cadastrar falhou", error?.code);
      return resposta(e, e.erro === "limite_diario" ? 429 : e.erro === "interno" ? 500 : 409, origem);
    }

    const familia = String(r.familia_id);
    const dominio = Deno.env.get("LOGIN_DOMINIO") || "login.fonteitaparica.invalid";
    let segundoLogin = false;
    let loginsFalharam = 0;
    let pessoaPrincipal: string | null = null;
    for (const l of (r.logins ?? []) as { pessoa_id: string; telefone: string; principal: boolean }[]) {
      if (!UUID.test(l.pessoa_id) || !TELEFONE.test(l.telefone)) continue;
      if (l.principal) pessoaPrincipal = l.pessoa_id;
      const uid = await criarLoginResponsavel(admin, dominio, l.pessoa_id, l.telefone);
      if (!uid) { loginsFalharam++; continue; }
      if (l.principal) {
        const { error: e } = await admin.rpc("cadastro_link_ligar_login", { p_familia: familia, p_pessoa: l.pessoa_id, p_perfil: uid });
        if (e) console.error("ligar_login falhou", e.code);
      } else segundoLogin = true;
    }

    // Fotos → Cloudinary (privadas, até 400 px) → cadastro
    const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
    const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
    const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME") || "tzoi5ks7";
    const pessoasCri = (r.criancas ?? []) as string[];
    const envios: { pessoa: string; pasta: string; img: string }[] = [];
    pessoasCri.forEach((p, i) => { if (fotoValida(fotosCri[i]) && UUID.test(p)) envios.push({ pessoa: p, pasta: "pessoas/criancas", img: fotosCri[i] as string }); });
    if (fotoValida(fotos.responsavel) && pessoaPrincipal) envios.push({ pessoa: pessoaPrincipal, pasta: "pessoas/adultos", img: fotos.responsavel as string });
    let fotosFalharam = 0;
    for (const e of envios) {
      try {
        if (!apiKey || !apiSecret) throw new Error("sem chave");
        const id = await enviarPrivada(e.img, `${e.pasta}/${e.pessoa}_${Date.now()}`, { cloudName, apiKey, apiSecret });
        const { error: eg } = await admin.rpc("cadastro_link_gravar_foto", { p_familia: familia, p_pessoa: e.pessoa, p_public_id: id });
        if (eg) throw new Error("gravar");
      } catch {
        fotosFalharam++;
      }
    }

    return resposta({
      ok: true,
      links: ((r.links ?? []) as { grupo: string; link: string }[])
        .filter((x) => /^https:\/\/chat\.whatsapp\.com\/[A-Za-z0-9]+$/.test(x.link)),
      segundo_login: segundoLogin,
      logins_falharam: loginsFalharam,
      fotos_falharam: fotosFalharam,
    }, 200, origem);
  }

  // ================= 5F: opções do cadastro de voluntária =================
  if (corpo.acao === "voluntaria_opcoes") {
    const { data, error } = await admin.rpc("voluntaria_link_opcoes");
    if (error || !data?.termo) { console.error("opcoes falhou", error?.code); return resposta({ erro: "interno" }, 500, origem); }
    return resposta({ ok: true, termo: data.termo, salas: data.salas ?? [], cultos: data.cultos ?? [] }, 200, origem);
  }

  // ================= 5F: pedido de voluntária =================
  if (corpo.acao === "voluntaria") {
    const ip = req.headers.get("cf-connecting-ip") || req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() || null;
    if (!(await captchaValido(String(corpo.captchaToken ?? ""), ip))) return resposta({ erro: "captcha" }, 400, origem);
    const dados = corpo.dados as Record<string, unknown> | undefined;
    if (!dados || typeof dados !== "object") return resposta({ erro: "pedido" }, 400, origem);
    const foto = corpo.foto;
    if (typeof foto !== "string" || foto.length > MAX_FOTO || !IMAGEM.test(foto)) return resposta({ erro: "foto" }, 400, origem);
    const tel = normalizarTelefone(dados.telefone);
    if (!tel) return resposta({ erro: "dados", campo: "telefone" }, 409, origem);

    const { data: r, error } = await admin.rpc("pedido_voluntaria_criar", { p_dados: {
      nome: dados.nome, telefone: tel, nascimento: dados.nascimento, email: dados.email ?? null,
      profissao: dados.profissao ?? null, sexo: dados.sexo ?? null, funcao: dados.funcao,
      salas: dados.salas, cultos: dados.cultos, termo_versao: dados.termo_versao,
    } });
    if (error || !r?.pedido_id) {
      const e = erroDoBanco(error?.message ?? "");
      if (e.erro === "interno") console.error("pedido voluntaria falhou", error?.code);
      return resposta(e, e.erro === "limite_diario" ? 429 : e.erro === "interno" ? 500 : 409, origem);
    }

    const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
    const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
    const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME") || "tzoi5ks7";
    let fotoFalhou = false;
    if (apiKey && apiSecret && UUID.test(String(r.pedido_id))) {
      const cred = { cloudName, apiKey, apiSecret };
      try {
        const id = await enviarPrivada(foto, `pessoas/adultos/pedido_${r.pedido_id}_${Date.now()}`, cred);
        const { error: eg } = await admin.rpc("pedido_voluntaria_gravar_foto", { p_pedido: r.pedido_id, p_public_id: id });
        if (eg) { await apagarPrivada(id, cred).catch(() => {}); fotoFalhou = true; }
      } catch { fotoFalhou = true; }
      // pedido antigo do mesmo telefone foi substituído: apaga a foto dele
      if (typeof r.foto_antiga === "string" && r.foto_antiga) await apagarPrivada(r.foto_antiga, cred).catch(() => {});
    } else fotoFalhou = true;

    return resposta({ ok: true, foto_falhou: fotoFalhou }, 200, origem);
  }

  return resposta({ erro: "acao" }, 400, origem);
});
