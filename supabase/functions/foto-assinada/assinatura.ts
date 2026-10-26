// Gera o link temporário de download de uma foto PRIVADA ("authenticated")
// no Cloudinary. É o mesmo formato do private_download_url do SDK oficial:
//   https://api.cloudinary.com/v1_1/<cloud>/image/download?api_key=...&expires_at=...
//     &format=jpg&public_id=...&signature=...&timestamp=...&type=authenticated
// A assinatura é SHA-1 dos parâmetros (em ordem alfabética, sem api_key)
// seguidos do API Secret. O link deixa de funcionar depois de expires_at.

export interface CredenciaisCloudinary {
  cloudName: string;
  apiKey: string;
  apiSecret: string;
}

async function sha1Hex(texto: string): Promise<string> {
  const dados = new TextEncoder().encode(texto);
  const hash = await crypto.subtle.digest("SHA-1", dados);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function linkTemporario(
  publicId: string,
  cred: CredenciaisCloudinary,
  segundos: number,
  agora: number = Math.floor(Date.now() / 1000),
): Promise<string> {
  const params: Record<string, string> = {
    expires_at: String(agora + segundos),
    format: "jpg",
    public_id: publicId,
    timestamp: String(agora),
    type: "authenticated",
  };
  const paraAssinar = Object.keys(params)
    .sort()
    .map((k) => `${k}=${params[k]}`)
    .join("&");
  const signature = await sha1Hex(paraAssinar + cred.apiSecret);

  const query = new URLSearchParams({
    api_key: cred.apiKey,
    ...params,
    signature,
  });
  return `https://api.cloudinary.com/v1_1/${encodeURIComponent(cred.cloudName)}/image/download?${query.toString()}`;
}
