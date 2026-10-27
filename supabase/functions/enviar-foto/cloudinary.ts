// Envio e exclusão de fotos PRIVADAS ("authenticated") no Cloudinary,
// com assinatura SHA-1 (parâmetros em ordem alfabética + API Secret).
// Nunca registra dados pessoais em log.

export interface CredenciaisCloudinary {
  cloudName: string;
  apiKey: string;
  apiSecret: string;
}

async function sha1Hex(texto: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-1", new TextEncoder().encode(texto));
  return Array.from(new Uint8Array(hash)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function assinar(params: Record<string, string>, secret: string): Promise<string> {
  const texto = Object.keys(params).sort().map((k) => `${k}=${params[k]}`).join("&");
  return await sha1Hex(texto + secret);
}

/** Envia a imagem (data URL) como foto privada, limitada a 400 px. Retorna o public_id. */
export async function enviarPrivada(dataUrl: string, publicId: string, cred: CredenciaisCloudinary): Promise<string> {
  const params: Record<string, string> = {
    format: "jpg",
    public_id: publicId,
    timestamp: String(Math.floor(Date.now() / 1000)),
    transformation: "c_limit,h_400,w_400/q_auto:good",
    type: "authenticated",
  };
  const form = new FormData();
  for (const [k, v] of Object.entries(params)) form.append(k, v);
  form.append("api_key", cred.apiKey);
  form.append("signature", await assinar(params, cred.apiSecret));
  form.append("file", dataUrl);
  const r = await fetch(`https://api.cloudinary.com/v1_1/${encodeURIComponent(cred.cloudName)}/image/upload`, {
    method: "POST",
    body: form,
  });
  if (!r.ok) throw new Error(`upload ${r.status}`);
  const j = await r.json();
  if (typeof j.public_id !== "string") throw new Error("upload sem public_id");
  return j.public_id;
}

/** Apaga uma foto privada (melhor esforço: erro aqui não desfaz a troca). */
export async function apagarPrivada(publicId: string, cred: CredenciaisCloudinary): Promise<void> {
  const params: Record<string, string> = {
    invalidate: "true",
    public_id: publicId,
    timestamp: String(Math.floor(Date.now() / 1000)),
    type: "authenticated",
  };
  const form = new FormData();
  for (const [k, v] of Object.entries(params)) form.append(k, v);
  form.append("api_key", cred.apiKey);
  form.append("signature", await assinar(params, cred.apiSecret));
  await fetch(`https://api.cloudinary.com/v1_1/${encodeURIComponent(cred.cloudName)}/image/destroy`, {
    method: "POST",
    body: form,
  });
}
