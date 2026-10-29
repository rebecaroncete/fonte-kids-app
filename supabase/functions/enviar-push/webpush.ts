// =====================================================================
// Web Push sem biblioteca externa (só Web Crypto do Deno):
//   • criptografia do conteúdo "aes128gcm" (RFC 8291 + RFC 8188);
//   • assinatura VAPID (RFC 8292, JWT ES256).
// As chaves VAPID chegam por parâmetro (vêm dos segredos da função).
// =====================================================================

const enc = new TextEncoder();

export function b64urlParaBytes(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function bytesParaB64url(b: Uint8Array): string {
  let bin = "";
  for (let i = 0; i < b.length; i++) bin += String.fromCharCode(b[i]);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function juntar(...partes: Uint8Array[]): Uint8Array {
  const total = partes.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  let i = 0;
  for (const p of partes) { out.set(p, i); i += p.length; }
  return out;
}

async function hkdf(sal: Uint8Array, ikm: Uint8Array, info: Uint8Array, bytes: number): Promise<Uint8Array> {
  const chave = await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]);
  const bits = await crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt: sal, info }, chave, bytes * 8);
  return new Uint8Array(bits);
}

/** Criptografa o conteúdo para um aparelho (p256dh e auth em base64url). */
export async function criptografar(conteudo: Uint8Array, p256dh: string, auth: string): Promise<Uint8Array> {
  const uaPublica = b64urlParaBytes(p256dh);
  const segredoAuth = b64urlParaBytes(auth);
  if (uaPublica.length !== 65 || segredoAuth.length !== 16) throw new Error("inscrição inválida");

  const local = await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
  const localPublica = new Uint8Array(await crypto.subtle.exportKey("raw", local.publicKey));
  const chaveUa = await crypto.subtle.importKey("raw", uaPublica, { name: "ECDH", namedCurve: "P-256" }, false, []);
  const ecdh = new Uint8Array(await crypto.subtle.deriveBits({ name: "ECDH", public: chaveUa }, local.privateKey, 256));

  const ikm = await hkdf(segredoAuth, ecdh, juntar(enc.encode("WebPush: info\0"), uaPublica, localPublica), 32);
  const sal = crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(sal, ikm, enc.encode("Content-Encoding: aes128gcm\0"), 16);
  const nonce = await hkdf(sal, ikm, enc.encode("Content-Encoding: nonce\0"), 12);

  const chaveAes = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
  const texto = juntar(conteudo, new Uint8Array([2])); // 0x02 = último (e único) bloco
  const cifrado = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, chaveAes, texto));

  const rs = new Uint8Array(4);
  new DataView(rs.buffer).setUint32(0, 4096);
  return juntar(sal, rs, new Uint8Array([localPublica.length]), localPublica, cifrado);
}

/** Cabeçalho Authorization VAPID para o serviço de push do endpoint. */
export async function cabecalhoVapid(endpoint: string, publica: string, privada: string, assunto: string): Promise<string> {
  const pub = b64urlParaBytes(publica);
  if (pub.length !== 65) throw new Error("VAPID_PUBLIC_KEY inválida");
  const jwk = { kty: "EC", crv: "P-256", d: privada, x: bytesParaB64url(pub.slice(1, 33)), y: bytesParaB64url(pub.slice(33, 65)), ext: true };
  const chave = await crypto.subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const cab = bytesParaB64url(enc.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
  const corpo = bytesParaB64url(enc.encode(JSON.stringify({
    aud: new URL(endpoint).origin,
    exp: Math.floor(Date.now() / 1000) + 12 * 60 * 60,
    sub: assunto,
  })));
  const assinatura = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, chave, enc.encode(`${cab}.${corpo}`)));
  return `vapid t=${cab}.${corpo}.${bytesParaB64url(assinatura)}, k=${publica}`;
}

export type Inscricao = { endpoint: string; p256dh: string; auth: string };

/** Envia um push. Devolve o status HTTP do serviço (201 = entregue ao serviço). */
export async function enviarPush(insc: Inscricao, conteudo: unknown, vapid: { publica: string; privada: string; assunto: string },
                                 ttlSegundos = 24 * 60 * 60): Promise<number> {
  const corpo = await criptografar(enc.encode(JSON.stringify(conteudo)), insc.p256dh, insc.auth);
  const r = await fetch(insc.endpoint, {
    method: "POST",
    headers: {
      "Authorization": await cabecalhoVapid(insc.endpoint, vapid.publica, vapid.privada, vapid.assunto),
      "Content-Encoding": "aes128gcm",
      "Content-Type": "application/octet-stream",
      "TTL": String(ttlSegundos),
      "Urgency": "high",
    },
    body: corpo,
  });
  try { await r.body?.cancel(); } catch { /* ignore */ }
  return r.status;
}
