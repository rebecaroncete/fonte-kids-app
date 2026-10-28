// =====================================================================
// Fonte Kids – ícones de linha fina (Fase 10 · Etapa 7)
// Desenhos baseados no Lucide (https://lucide.dev), licença ISC:
//   Copyright (c) for portions of Lucide are held by Cole Bemis 2013-2022
//   as part of Feather (MIT). All other copyright (c) for Lucide are held
//   by Lucide Contributors 2022. Permission to use, copy, modify, and/or
//   distribute this software for any purpose with or without fee is hereby
//   granted, provided that the above copyright notice and this permission
//   notice appear in all copies.
// Servidos pelo próprio app (nada de fora; a CSP não muda).
// Criados com createElementNS (sem innerHTML).
//
// Uso: icone("avisos")  →  <svg class="icone-linha" aria-hidden="true">
//      icone("avisos", "Avisos") → com nome para leitor de tela.
// =====================================================================
const SVG = "http://www.w3.org/2000/svg";

// Cada ícone: lista de [elemento, atributos] num quadro 24×24.
const P = (d) => ["path", { d }];
const C = (cx, cy, r) => ["circle", { cx, cy, r }];

const DESENHOS = {
  inicio:      [P("M3 10.5 12 3l9 7.5"), P("M5 9.5V21h14V9.5"), P("M10 21v-6h4v6")],
  familia:     [C(9, 8, 3.5), P("M2.5 20c0-3.6 2.9-6 6.5-6s6.5 2.4 6.5 6"), P("M16 4.5a3.5 3.5 0 0 1 0 7"), P("M18 14.3c2.1.7 3.5 2.8 3.5 5.7")],
  avisos:      [P("M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"), P("M10.3 21a1.94 1.94 0 0 0 3.4 0")],
  perfil:      [C(12, 8, 4), P("M4 21c0-4 3.6-7 8-7s8 3 8 7")],
  recepcao:    [["rect", { x: 8, y: 2, width: 8, height: 4, rx: 1 }], P("M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"), P("m9 14 2 2 4-4")],
  pendencias:  [C(12, 12, 9), P("M12 8v4"), P("M12 16h.01")],
  mais:        [C(5, 12, 1), C(12, 12, 1), C(19, 12, 1)],
  menu:        [P("M4 6h16"), P("M4 12h16"), P("M4 18h16")],
  crianca:     [C(12, 12, 9), P("M8.5 14s1.3 2 3.5 2 3.5-2 3.5-2"), P("M9 9.5h.01"), P("M15 9.5h.01")],
  cadastros:   [P("M16 3H8a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h8a2 2 0 0 0 2-2V5a2 2 0 0 0-2-2"), C(12, 10, 2.5), P("M8.5 17c.6-1.8 1.9-3 3.5-3s2.9 1.2 3.5 3")],
  autorizados: [P("M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z"), P("m9 12 2 2 4-4")],
  senha:       [C(7.5, 15.5, 3.5), P("m10 13 9-9"), P("m16 7 2 2"), P("m19 4 2 2")],
  logins:      [C(9, 8, 4), P("M2 21c0-4 3.1-7 7-7 1.3 0 2.5.3 3.5.9"), C(18, 17, 2), P("M18 13v2"), P("M18 19v2"), P("m21.5 15-1.7 1"), P("m16.2 18-1.7 1"), P("m21.5 19-1.7-1"), P("m16.2 16-1.7-1")],
  busca:       [C(11, 11, 7), P("m20 20-3.5-3.5")],
  seta:        [P("m9 6 6 6-6 6")],
  voltar:      [P("m15 6-6 6 6 6")],
  abaixo:      [P("m6 9 6 6 6-6")],
  sair:        [P("M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"), P("m16 17 5-5-5-5"), P("M21 12H9")],
  editar:      [P("M12 20h9"), P("M16.4 3.6a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4z")],
  excluir:     [P("M3 6h18"), P("M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"), P("M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2")],
  adicionar:   [P("M12 5v14"), P("M5 12h14")],
  fechar:      [P("M18 6 6 18"), P("m6 6 12 12")],
  check:       [P("M20 6 9 17l-5-5")],
  telefone:    [P("M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.9.7 2.8a2 2 0 0 1-.5 2.1L8 9.9a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.8.7a2 2 0 0 1 1.8 2")],
  conversa:    [P("M7.9 20A9 9 0 1 0 4 16.1L2 22z")],
  alergia:     [P("m21.7 18-8-14a2 2 0 0 0-3.4 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.7-3"), P("M12 9v4"), P("M12 17h.01")],
  camera:      [P("M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3z"), C(12, 13, 3)],
  atualizar:   [P("M3 12a9 9 0 0 1 15-6.7L21 8"), P("M21 3v5h-5"), P("M21 12a9 9 0 0 1-15 6.7L3 16"), P("M8 16H3v5")],
  checkin:     [P("M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"), P("m10 17 5-5-5-5"), P("M15 12H3")],
  calendario:  [["rect", { x: 3, y: 4, width: 18, height: 18, rx: 2 }], P("M16 2v4"), P("M8 2v4"), P("M3 10h18")],
  telao:       [["rect", { x: 2, y: 3, width: 20, height: 14, rx: 2 }], P("M8 21h8"), P("M12 17v4")],
};

export const NOMES_ICONES = Object.keys(DESENHOS);

/** Cria o ícone. Sem `rotulo`, fica escondido do leitor de tela (decorativo). */
export function icone(nome, rotulo, classeExtra) {
  const s = document.createElementNS(SVG, "svg");
  s.setAttribute("viewBox", "0 0 24 24");
  s.setAttribute("class", classeExtra ? `icone-linha ${classeExtra}` : "icone-linha");
  if (rotulo) { s.setAttribute("role", "img"); s.setAttribute("aria-label", rotulo); }
  else s.setAttribute("aria-hidden", "true");
  for (const [tag, attrs] of DESENHOS[nome] || DESENHOS.pendencias) {
    const n = document.createElementNS(SVG, tag);
    for (const [k, v] of Object.entries(attrs)) n.setAttribute(k, String(v));
    s.append(n);
  }
  return s;
}
