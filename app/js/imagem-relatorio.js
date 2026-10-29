// =====================================================================
// Fonte Kids – imagem do Relatório do mês (Fase 9)
// Desenha no aparelho (canvas) as mesmas tabelas da página do relatório,
// para mandar ao pastor ou no grupo onde "Imprimir" não funciona (ex.:
// app instalado no iPhone). Só números: recebe as seções já montadas.
// secoes: [{ titulo, cabecas: [...], linhas: [[...]], texto }]
// =====================================================================
const ESCALA = 2;
const LARGURA = 820;
const M = 32;
const CORES = { fundo: "#ffffff", texto: "#1f2430", suave: "#5b6472", linha: "#e7e3df", faixa: "#f58941" };
const TITULO = '800 30px "Baloo 2", "Nunito", sans-serif';
const H2 = '800 21px "Baloo 2", "Nunito", sans-serif';
const CAB = '700 14px "Nunito", sans-serif';
const CEL = '600 17px "Nunito", sans-serif';
const NUM = '800 17px "Nunito", sans-serif';
const TXT = '600 16px "Nunito", sans-serif';
const ALT_LINHA = 34;

function carregarLogo() {
  return new Promise((ok) => {
    const img = new Image();
    img.onload = () => ok(img);
    img.onerror = () => ok(null);
    img.src = "img/logo.png";
  });
}

/** Quebra o texto em linhas que cabem na largura. */
function quebrar(ctx, texto, largura) {
  const linhas = []; let atual = "";
  for (const p of String(texto).split(/\s+/)) {
    const t = atual ? `${atual} ${p}` : p;
    if (ctx.measureText(t).width > largura && atual) { linhas.push(atual); atual = p; } else atual = t;
  }
  if (atual) linhas.push(atual);
  return linhas;
}

function caber(ctx, texto, largura) {
  if (ctx.measureText(texto).width <= largura) return texto;
  let t = texto;
  while (t.length > 1 && ctx.measureText(`${t}…`).width > largura) t = t.slice(0, -1);
  return `${t}…`;
}

/** Larguras das colunas: a 1ª fica com o que sobra; as outras, pelo conteúdo. */
function colunas(ctx, s, largura) {
  const n = Math.max(s.cabecas.length, ...s.linhas.map((l) => l.length));
  const ws = [0];
  for (let i = 1; i < n; i++) {
    ctx.font = CAB; let w = ctx.measureText(s.cabecas[i] || "").width;
    ctx.font = NUM; for (const l of s.linhas) w = Math.max(w, ctx.measureText(String(l[i] ?? "")).width);
    ws.push(w + 22);
  }
  ws[0] = Math.max(140, largura - ws.slice(1).reduce((a, b) => a + b, 0));
  return ws;
}

export async function imagemDoRelatorio(titulo, subtitulo, secoes, rodape) {
  try { await Promise.all([document.fonts.load(TITULO), document.fonts.load(CEL), document.fonts.load(NUM)]); } catch { /* fonte do sistema */ }
  const largura = LARGURA - 2 * M;
  const medir = document.createElement("canvas").getContext("2d");

  // altura total
  let altura = 120;
  for (const s of secoes) {
    altura += 48;
    if (s.texto) { medir.font = TXT; altura += quebrar(medir, s.texto, largura).length * 24 + 8; }
    if (s.linhas?.length) altura += (s.cabecas.some(Boolean) ? 30 : 0) + s.linhas.length * ALT_LINHA + 8;
  }
  medir.font = '600 13px "Nunito", sans-serif';
  const linhasRodape = rodape ? quebrar(medir, rodape, largura) : [];
  altura += 16 + linhasRodape.length * 20 + M;

  const canvas = document.createElement("canvas");
  canvas.width = LARGURA * ESCALA; canvas.height = Math.ceil(altura * ESCALA);
  const ctx = canvas.getContext("2d");
  ctx.scale(ESCALA, ESCALA);
  ctx.fillStyle = CORES.fundo; ctx.fillRect(0, 0, LARGURA, altura);
  ctx.fillStyle = CORES.faixa; ctx.fillRect(0, 0, LARGURA, 6);

  const logo = await carregarLogo();
  let xt = M;
  if (logo) {
    const lado = 64, prop = Math.min(logo.width / logo.height || 1, 1.6);
    ctx.drawImage(logo, M, 28, lado * prop, lado); xt = M + lado * prop + 16;
  }
  ctx.textBaseline = "alphabetic";
  ctx.fillStyle = CORES.texto; ctx.font = TITULO; ctx.fillText(caber(ctx, titulo, LARGURA - xt - M), xt, 62);
  ctx.fillStyle = CORES.suave; ctx.font = '600 16px "Nunito", sans-serif'; ctx.fillText(subtitulo, xt, 88);

  let y = 120;
  for (const s of secoes) {
    y += 34;
    ctx.fillStyle = CORES.texto; ctx.font = H2; ctx.fillText(s.titulo, M, y);
    y += 14;
    if (s.texto) {
      ctx.font = TXT; ctx.fillStyle = CORES.texto;
      for (const l of quebrar(ctx, s.texto, largura)) { y += 24; ctx.fillText(l, M, y - 6); }
      y += 8;
    }
    if (s.linhas?.length) {
      const ws = colunas(ctx, s, largura);
      const xs = ws.map((_, i) => M + ws.slice(0, i + 1).reduce((a, b) => a + b, 0)); // borda direita de cada coluna
      if (s.cabecas.some(Boolean)) {
        y += 30;
        ctx.font = CAB; ctx.fillStyle = CORES.suave;
        s.cabecas.forEach((c, i) => {
          if (!c) return;
          ctx.textAlign = i ? "right" : "left";
          ctx.fillText(i ? c : caber(ctx, c, ws[0] - 8), i ? xs[i] - 4 : M + 4, y - 10);
        });
        ctx.textAlign = "left";
        ctx.fillStyle = CORES.linha; ctx.fillRect(M, y - 1, largura, 1);
      }
      for (const l of s.linhas) {
        y += ALT_LINHA;
        l.forEach((c, i) => {
          ctx.textAlign = i ? "right" : "left";
          ctx.font = i ? NUM : CEL; ctx.fillStyle = CORES.texto;
          ctx.fillText(i ? String(c) : caber(ctx, String(c), ws[0] - 12), i ? xs[i] - 4 : M + 4, y - 11);
        });
        ctx.textAlign = "left";
        ctx.fillStyle = CORES.linha; ctx.fillRect(M, y - 1, largura, 1);
      }
      y += 8;
    }
  }
  y += 16;
  ctx.fillStyle = CORES.suave; ctx.font = '600 13px "Nunito", sans-serif';
  for (const l of linhasRodape) { y += 20; ctx.fillText(l, M, y - 4); }

  return new Promise((ok, falha) => canvas.toBlob((b) => (b ? ok(b) : falha(new Error("Não foi possível gerar a imagem."))), "image/png"));
}
