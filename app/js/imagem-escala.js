// =====================================================================
// Fonte Kids – imagem da escala do mês para mandar no grupo (Fase 9)
// Desenha no aparelho (canvas, nada sai do app) os cartões de cada culto:
// data e hora no topo (cor pelo horário), líder do culto, salas com
// Prof/Auxiliar/Reserva e "Vaga aberta" em vermelho. Uma linha por
// semana; uma coluna por culto da semana (domingo manhã, noite, terça…).
// Nomes como na escala impressa: primeiro nome + inicial do sobrenome.
// Sem telefones nem dados de crianças.
// =====================================================================
const ESCALA = 2;           // pixels por ponto (imagem nítida no celular)
const LARGURA = 1080;       // largura em pontos
const M = 28;               // margem
const G = 16;               // espaço entre cartões
const CORES = {
  fundo: "#eef2f7", cartao: "#ffffff", borda: "#d9e1ea", texto: "#1f2430", suave: "#5b6472",
  aberta: "#c62828", sala: "#f58941", manha: "#1fa9e1", noite: "#13294b", semana: "#1e6fb0",
};
const ROTULO = { professora: "Prof", auxiliar: "Auxiliar", reserva: "Reserva" };
const TITULO = '800 30px "Baloo 2", "Nunito", sans-serif';
const CAB = '800 19px "Nunito", sans-serif';
const SALA = '800 15px "Nunito", sans-serif';
const ROT = '600 16px "Nunito", sans-serif';
const NOME = '800 16px "Nunito", sans-serif';

/** "Maria da Silva Souza" → "Maria S." */
export function abreviarNome(nome) {
  const p = String(nome || "").trim().split(/\s+/).filter(Boolean);
  if (!p.length) return "";
  const primeiro = p[0].charAt(0).toUpperCase() + p[0].slice(1).toLowerCase();
  return p.length > 1 ? `${primeiro} ${p[p.length - 1].charAt(0).toUpperCase()}.` : primeiro;
}

const SEMANA = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"];
const diaSemana = (iso) => new Date(`${iso}T12:00:00Z`).getUTCDay();
const inicioSemana = (iso) => {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() - d.getUTCDay());
  return d.toISOString().slice(0, 10);
};

function corCulto(c) {
  const hora = Number(String(c.horario || "00").slice(0, 2));
  if (hora >= 18) return CORES.noite;
  return diaSemana(c.data) === 0 ? CORES.manha : CORES.semana;
}

/** Linhas de um culto: [{ tipo: "lider"|"sala"|"vaga"|"nota", rotulo, nome }] */
function linhasDoCulto(c) {
  if (c.cancelado) return [{ tipo: "nota", rotulo: "Sem salinha neste culto." }];
  const linhas = [];
  const itens = c.itens || [];
  for (const i of itens.filter((x) => x.funcao === "lider_culto")) {
    linhas.push({ tipo: "lider", rotulo: "Líder do culto:", nome: i.nome ? abreviarNome(i.nome) : null });
  }
  const grupos = [];
  for (const i of itens.filter((x) => x.funcao !== "lider_culto")) {
    const nomeSala = String(i.sala || "Geral");
    let g = grupos.find((x) => x.nome === nomeSala);
    if (!g) { g = { nome: nomeSala, itens: [] }; grupos.push(g); }
    g.itens.push(i);
  }
  for (const g of grupos) {
    linhas.push({ tipo: "sala", rotulo: g.nome });
    for (const i of g.itens) linhas.push({ tipo: "vaga", rotulo: `${ROTULO[i.funcao] || i.funcao}:`, nome: i.nome ? abreviarNome(i.nome) : null });
  }
  if (!linhas.length) linhas.push({ tipo: "nota", rotulo: "Sem vagas." });
  return linhas;
}

const ALTURA = { lider: 30, sala: 34, vaga: 26, nota: 28 };
const CAB_ALT = 44;
const alturaCartao = (linhas) => CAB_ALT + 14 + linhas.reduce((s, l) => s + ALTURA[l.tipo], 0) + 10;

/** Corta o texto com "…" para caber na largura. */
function caber(ctx, texto, largura) {
  if (ctx.measureText(texto).width <= largura) return texto;
  let t = texto;
  while (t.length > 1 && ctx.measureText(`${t}…`).width > largura) t = t.slice(0, -1);
  return `${t}…`;
}

function retangulo(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function desenharCartao(ctx, c, linhas, x, y, w, h) {
  // cartão
  ctx.save();
  ctx.shadowColor = "rgba(20, 30, 50, .10)"; ctx.shadowBlur = 8; ctx.shadowOffsetY = 2;
  retangulo(ctx, x, y, w, h, 12); ctx.fillStyle = CORES.cartao; ctx.fill();
  ctx.restore();
  retangulo(ctx, x, y, w, h, 12); ctx.strokeStyle = CORES.borda; ctx.lineWidth = 1; ctx.stroke();
  // topo colorido
  ctx.save();
  retangulo(ctx, x, y, w, h, 12); ctx.clip();
  ctx.fillStyle = corCulto(c); ctx.fillRect(x, y, w, CAB_ALT);
  ctx.restore();
  ctx.fillStyle = "#ffffff"; ctx.font = CAB; ctx.textBaseline = "middle";
  const cab = `${SEMANA[diaSemana(c.data)]}, ${c.data.slice(8, 10)}/${c.data.slice(5, 7)} · ${c.hora}`;
  ctx.fillText(caber(ctx, cab, w - 28), x + 14, y + CAB_ALT / 2 + 1);

  let yy = y + CAB_ALT + 14;
  const xi = x + 14, wi = w - 28;
  for (const l of linhas) {
    const meio = yy + ALTURA[l.tipo] / 2;
    if (l.tipo === "sala") {
      ctx.font = SALA; ctx.fillStyle = CORES.texto;
      ctx.fillText(caber(ctx, l.rotulo, wi), xi, meio);
      ctx.fillStyle = CORES.sala; ctx.fillRect(xi, yy + ALTURA.sala - 6, wi, 2);
    } else if (l.tipo === "nota") {
      ctx.font = ROT; ctx.fillStyle = CORES.suave;
      ctx.fillText(caber(ctx, l.rotulo, wi), xi, meio);
    } else {
      ctx.font = ROT; ctx.fillStyle = CORES.suave;
      ctx.fillText(l.rotulo, xi, meio);
      const xr = xi + ctx.measureText(l.rotulo).width + 6;
      ctx.font = NOME;
      if (l.nome) { ctx.fillStyle = CORES.texto; ctx.fillText(caber(ctx, l.nome, xi + wi - xr), xr, meio); }
      else { ctx.fillStyle = CORES.aberta; ctx.fillText(caber(ctx, "⚠ Vaga aberta", xi + wi - xr), xr, meio); }
    }
    yy += ALTURA[l.tipo];
  }
}

function carregarLogo() {
  return new Promise((ok) => {
    const img = new Image();
    img.onload = () => ok(img);
    img.onerror = () => ok(null);
    img.src = "img/logo.png";
  });
}

/**
 * Desenha a escala (resultado de escala_do_mes) e devolve um Blob PNG.
 * titulo: ex. "Escala Fonte Kids"; subtitulo: ex. "Novembro de 2026".
 */
export async function imagemDaEscala(dados, titulo, subtitulo) {
  const cultos = (dados.cultos || []).filter((c) => c.cancelado || (c.itens || []).length);
  if (!cultos.length) throw new Error("A escala deste mês ainda não tem cultos.");
  try {
    await Promise.all([document.fonts.load(TITULO), document.fonts.load(CAB), document.fonts.load(ROT), document.fonts.load(NOME)]);
  } catch { /* usa a fonte do sistema */ }

  // Colunas: um tipo de culto (dia da semana + horário) por coluna, se forem até 4;
  // senão, os cultos de cada semana em sequência.
  const chave = (c) => `${diaSemana(c.data)}|${c.horario}`;
  const tipos = [...new Set(cultos.map(chave))].sort((a, b) => {
    const [da, ha] = a.split("|"); const [db, hb] = b.split("|");
    return Number(da) - Number(db) || ha.localeCompare(hb);
  });
  const semanas = [...new Set(cultos.map((c) => inicioSemana(c.data)))].sort();
  const porTipo = tipos.length <= 4;
  const linhasGrade = semanas.map((s) => {
    const daSemana = cultos.filter((c) => inicioSemana(c.data) === s).sort((a, b) => (a.data + a.horario).localeCompare(b.data + b.horario));
    if (!porTipo) return daSemana;
    return tipos.map((t) => daSemana.find((c) => chave(c) === t) || null);
  });
  const colunas = Math.max(1, ...linhasGrade.map((l) => l.length));
  const w = (LARGURA - 2 * M - (colunas - 1) * G) / colunas;

  const preparadas = linhasGrade.map((l) => l.map((c) => (c ? { c, linhas: linhasDoCulto(c) } : null)));
  const alturas = preparadas.map((l) => Math.max(...l.map((x) => (x ? alturaCartao(x.linhas) : 0))));
  const TOPO = 112, RODAPE = 40;
  const altura = TOPO + alturas.reduce((s, h) => s + h + G, 0) - G + RODAPE + M;

  const canvas = document.createElement("canvas");
  canvas.width = LARGURA * ESCALA;
  canvas.height = Math.ceil(altura * ESCALA);
  const ctx = canvas.getContext("2d");
  ctx.scale(ESCALA, ESCALA);
  ctx.fillStyle = CORES.fundo; ctx.fillRect(0, 0, LARGURA, altura);

  // Cabeçalho
  const logo = await carregarLogo();
  let xt = M;
  if (logo) {
    const lado = 64, prop = logo.width / logo.height || 1;
    ctx.drawImage(logo, M, 24, lado * Math.min(prop, 1.6), lado);
    xt = M + lado * Math.min(prop, 1.6) + 16;
  }
  ctx.textBaseline = "alphabetic";
  ctx.fillStyle = CORES.texto; ctx.font = TITULO; ctx.fillText(titulo, xt, 54);
  ctx.fillStyle = CORES.suave; ctx.font = '700 20px "Nunito", sans-serif'; ctx.fillText(subtitulo, xt, 84);

  // Cartões
  let y = TOPO;
  preparadas.forEach((linha, i) => {
    linha.forEach((x, k) => { if (x) desenharCartao(ctx, x.c, x.linhas, M + k * (w + G), y, w, alturas[i]); });
    y += alturas[i] + G;
  });

  ctx.textBaseline = "alphabetic";
  ctx.fillStyle = CORES.suave; ctx.font = '600 14px "Nunito", sans-serif';
  ctx.fillText("Confirme a sua vaga no app: toque em Ciente ou Não poderei.", M, altura - M + 6);

  return new Promise((ok, falha) => canvas.toBlob((b) => (b ? ok(b) : falha(new Error("Não foi possível gerar a imagem."))), "image/png"));
}
