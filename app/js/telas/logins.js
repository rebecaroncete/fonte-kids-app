// =====================================================================
// Tela: Gestão de logins (Fase 10 · Etapa 5A)
// Para liderança do Fonte Kids, pastores e admin (o banco confere).
//   • Pedidos: pedidos de nova senha pendentes → redefinir ou encerrar.
//   • Pessoas: busca e situação de cada login → criar ou redefinir.
//   • Criar em lote (só admin): simular (contagens) e criar todos.
// Telefone aparece sempre mascarado. Nenhuma senha passa por esta tela:
// ela só informa QUAL regra de senha inicial vale para a pessoa.
// =====================================================================
import { el, montar, aviso, carregando, toast } from "../ui.js";
import { meuPerfil, listarPedidosRedefinicao, situacaoLogins, encerrarPedido, gerenciarLogin } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Gestão de logins";

const FUSO = "America/Sao_Paulo";
const AVISO_FIXO = "Confirme com a pessoa antes de redefinir e peça que entre logo em seguida.";
const MAX_LISTA = 50;
const POR_CHAMADA = 25;

const SITUACOES = {
  ativo: { texto: "Login ativo", cor: "azul" },
  primeiro_acesso: { texto: "Aguardando 1º acesso", cor: "" },
  inativo: { texto: "Login desativado", cor: "" },
  sem_login: { texto: "Sem login", cor: "laranja" },
  sem_telefone: { texto: "Sem telefone no cadastro", cor: "laranja" },
  telefone_invalido: { texto: "Telefone fora do padrão", cor: "laranja" },
  telefone_em_uso: { texto: "Telefone já usado por outro login", cor: "laranja" },
  telefone_compartilhado: { texto: "Telefone compartilhado: o login fica com outra pessoa", cor: "" },
};

const FILTROS = [
  { valor: "todos", texto: "Todas as pessoas", teste: () => true },
  { valor: "sem_login", texto: "Sem login", teste: (s) => s === "sem_login" },
  { valor: "primeiro_acesso", texto: "Aguardando 1º acesso", teste: (s) => s === "primeiro_acesso" },
  { valor: "ativo", texto: "Login ativo", teste: (s) => s === "ativo" },
  { valor: "compartilhado", texto: "Telefone compartilhado", teste: (s) => s === "telefone_compartilhado" },
  { valor: "problema", texto: "Com problema no cadastro", teste: (s) => ["sem_telefone", "telefone_invalido", "telefone_em_uso", "inativo"].includes(s) },
];

// Quem já falhou no lote nesta aba (para não tentar de novo a cada rodada)
const ignorarNoLote = new Set();
let loteRodando = false;

const normalizar = (s) => String(s || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().trim();

function quando(iso) {
  const d = new Date(iso);
  const min = Math.round((Date.now() - d.getTime()) / 60000);
  if (min < 60) return `há ${Math.max(min, 1)} min`;
  if (min < 24 * 60) return `há ${Math.round(min / 60)} h`;
  return d.toLocaleString("pt-BR", { timeZone: FUSO, day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
}

function textoSenhaInicial(regra) {
  const qual = regra === "data_de_nascimento"
    ? "a data de nascimento (DDMMAAAA, só números)"
    : "o telefone com 55 + DDD (só números)";
  return `A senha inicial é ${qual}. Peça que entre logo em seguida e troque a senha.`;
}

/** Troca a linha de botões por uma confirmação; volta ao cancelar. */
function pedirConfirmacao(linha, texto, rotulo, aoConfirmar, perigo = false) {
  const original = [...linha.childNodes];
  const ok = el("button", { class: perigo ? "botao botao--pequeno botao--perigo" : "botao botao--pequeno botao--primario", type: "button", text: rotulo });
  const cancelar = el("button", { class: "botao botao--pequeno", type: "button", text: "Cancelar" });
  const caixa = el("div", { class: "confirmacao" }, el("p", { text: texto }), el("div", { class: "linha" }, ok, cancelar));
  linha.replaceChildren(caixa);
  ok.focus();
  cancelar.addEventListener("click", () => linha.replaceChildren(...original));
  ok.addEventListener("click", async () => {
    ok.disabled = true; cancelar.disabled = true;
    ok.textContent = "Aguarde…";
    const fim = await aoConfirmar();
    if (fim === false) linha.replaceChildren(...original);
  });
}

export async function render(alvo) {
  montar(alvo, carregando());
  const perfil = await meuPerfil();
  if (!perfil.ok) { montar(alvo, el("h1", { text: titulo }), aviso("erro", perfil.erro)); return; }
  if (!perfil.temPapel("admin", "pastor", "lider")) {
    montar(alvo, el("h1", { text: titulo }), aviso("atencao", "Esta tela é só para a liderança do Fonte Kids."));
    return;
  }
  const eAdmin = perfil.temPapel("admin");

  const abas = [
    { id: "pedidos", texto: "Pedidos", desenhar: abaPedidos },
    { id: "pessoas", texto: "Pessoas", desenhar: abaPessoas },
    ...(eAdmin ? [{ id: "lote", texto: "Criar em lote", desenhar: abaLote }] : []),
  ];
  const area = el("section", { id: "logins-area", role: "tabpanel" });
  const botoes = abas.map((a) => el("button", {
    class: "aba", type: "button", role: "tab", id: `aba-${a.id}`, "aria-controls": "logins-area",
    text: a.texto, onclick: () => abrir(a.id),
  }));
  const contadorPedidos = el("span", { class: "sino__contagem aba__contagem", hidden: true });
  botoes[0].append(contadorPedidos);

  function abrir(id) {
    if (loteRodando) { toast("atencao", "Espere a criação em lote terminar."); return; }
    abas.forEach((a, i) => botoes[i].setAttribute("aria-selected", a.id === id ? "true" : "false"));
    area.setAttribute("aria-labelledby", `aba-${id}`);
    abas.find((a) => a.id === id).desenhar(area);
  }

  // ---------------- Aba: Pedidos ----------------
  async function abaPedidos(painel) {
    montar(painel, carregando());
    const r = await listarPedidosRedefinicao();
    if (!painel.isConnected) return;
    if (!r.ok) { montar(painel, aviso("erro", r.erro)); return; }
    contadorPedidos.hidden = r.lista.length === 0;
    contadorPedidos.textContent = String(r.lista.length);
    if (!r.lista.length) { montar(painel, aviso("sucesso", "Nenhum pedido de nova senha pendente.")); return; }
    montar(painel,
      el("p", { class: "suave", text: `${r.lista.length} pedido${r.lista.length > 1 ? "s" : ""} pendente${r.lista.length > 1 ? "s" : ""}.` }),
      el("ul", { class: "lista" }, r.lista.map((p) => itemPedido(p, () => abaPedidos(painel)))));
  }

  function itemPedido(p, recarregar) {
    const linha = el("div", { class: "linha" });
    if (p.pode_redefinir) {
      linha.append(el("button", { class: "botao botao--pequeno botao--azul", type: "button", text: "Redefinir senha",
        onclick: () => pedirConfirmacao(linha, `${AVISO_FIXO} A senha de ${p.nome} volta para a senha inicial.`, "Confirmar redefinição",
          async () => {
            const r = await gerenciarLogin({ acao: "redefinir", pessoa_id: p.pessoa_id });
            if (!r.ok) { toast("erro", r.erro); return false; }
            toast("sucesso", textoSenhaInicial(r.senha_inicial), 9000);
            recarregar();
          }) }));
    }
    linha.append(el("button", { class: "botao botao--pequeno", type: "button", text: "Encerrar sem redefinir",
      onclick: () => pedirConfirmacao(linha, "Use quando a pessoa já lembrou a senha ou não reconhece o pedido. A senha não muda.", "Encerrar pedido",
        async () => {
          const r = await encerrarPedido(p.id);
          if (!r.ok) { toast("erro", r.erro); return false; }
          toast("info", r.encerrado ? "Pedido encerrado." : "Este pedido já tinha sido resolvido.");
          recarregar();
        }) }));
    return el("li", { class: "notif" },
      el("p", { class: "notif__titulo", text: p.nome }),
      el("p", { class: "notif__corpo", text: p.telefone_mascarado || "Telefone não disponível" }),
      el("p", { class: "notif__quando", text: `Pedido ${quando(p.criado_em)}` }),
      p.pode_redefinir ? null : el("p", { class: "suave", text: "Este login tem papéis que só a administração ou os pastores podem redefinir." }),
      linha);
  }

  // ---------------- Aba: Pessoas ----------------
  let pessoasCache = null;
  async function abaPessoas(painel, forcar = false) {
    montar(painel, carregando());
    if (!pessoasCache || forcar) {
      const r = await situacaoLogins();
      if (!painel.isConnected) return;
      if (!r.ok) { montar(painel, aviso("erro", r.erro)); return; }
      pessoasCache = r.lista.map((p) => ({ ...p, busca: normalizar(p.nome) }));
    }
    const todos = pessoasCache;
    const recarregar = () => abaPessoas(painel, true);

    const contagem = {};
    for (const p of todos) contagem[p.situacao] = (contagem[p.situacao] || 0) + 1;
    const resumo = el("p", { class: "suave", text:
      `${todos.length} pessoas · ${contagem.ativo || 0} com login ativo · ${contagem.primeiro_acesso || 0} aguardando 1º acesso · ${contagem.sem_login || 0} sem login` });

    const busca = el("input", { class: "entrada", type: "search", id: "busca-logins", placeholder: "Digite parte do nome", autocomplete: "off" });
    const filtro = el("select", { class: "entrada", id: "filtro-logins" },
      FILTROS.map((f) => el("option", { value: f.valor, text: f.texto })));
    const resultado = el("div", {});

    function atualizar() {
      const termo = normalizar(busca.value);
      const f = FILTROS.find((x) => x.valor === filtro.value) || FILTROS[0];
      const achados = todos.filter((p) => f.teste(p.situacao) && (!termo || p.busca.includes(termo)));
      if (!achados.length) { montar(resultado, aviso("info", "Ninguém encontrado com esse filtro.")); return; }
      montar(resultado,
        achados.length > MAX_LISTA ? el("p", { class: "suave", text: `Mostrando ${MAX_LISTA} de ${achados.length}. Digite parte do nome para encontrar mais rápido.` }) : null,
        el("ul", { class: "lista" }, achados.slice(0, MAX_LISTA).map((p) => itemPessoa(p, recarregar))));
    }
    let espera = null;
    busca.addEventListener("input", () => { clearTimeout(espera); espera = setTimeout(atualizar, 200); });
    filtro.addEventListener("change", atualizar);

    montar(painel,
      resumo,
      el("div", { class: "campo" }, el("label", { class: "campo__rotulo", for: "busca-logins", text: "Buscar pelo nome" }), busca),
      el("div", { class: "campo" }, el("label", { class: "campo__rotulo", for: "filtro-logins", text: "Mostrar" }), filtro),
      resultado);
    atualizar();
  }

  function itemPessoa(p, recarregar) {
    const sit = SITUACOES[p.situacao] || { texto: p.situacao, cor: "" };
    const etiquetas = el("div", { class: "linha" },
      el("span", { class: sit.cor ? `etiqueta etiqueta--${sit.cor}` : "etiqueta", text: sit.texto }),
      p.e_voluntaria ? el("span", { class: "etiqueta", text: "Voluntária" }) : null,
      p.e_responsavel ? el("span", { class: "etiqueta", text: "Responsável" }) : null);
    const linha = el("div", { class: "linha" });

    if (p.situacao === "sem_login") {
      linha.append(el("button", { class: "botao botao--pequeno botao--primario", type: "button", text: "Criar login",
        onclick: () => pedirConfirmacao(linha, `Criar o login de ${p.nome} com o telefone ${p.telefone_mascarado || ""}? No 1º acesso a pessoa troca a senha e (se for responsável) aceita o termo.`, "Criar login",
          async () => {
            const r = await gerenciarLogin({ acao: "criar", pessoa_id: p.pessoa_id });
            if (!r.ok) { toast("erro", r.erro); return false; }
            toast("sucesso", `Login criado. ${textoSenhaInicial(r.senha_inicial)}`, 9000);
            recarregar();
          }) }));
    } else if (p.pode_redefinir && (p.situacao === "ativo" || p.situacao === "primeiro_acesso")) {
      linha.append(el("button", { class: "botao botao--pequeno botao--azul", type: "button", text: "Redefinir senha",
        onclick: () => pedirConfirmacao(linha, `${AVISO_FIXO} A senha de ${p.nome} volta para a senha inicial.`, "Confirmar redefinição",
          async () => {
            const r = await gerenciarLogin({ acao: "redefinir", pessoa_id: p.pessoa_id });
            if (!r.ok) { toast("erro", r.erro); return false; }
            toast("sucesso", textoSenhaInicial(r.senha_inicial), 9000);
            recarregar();
          }) }));
    } else if (["sem_telefone", "telefone_invalido", "telefone_em_uso"].includes(p.situacao)) {
      linha.append(el("p", { class: "suave", text: "Corrija o telefone no cadastro antes de criar o login." }));
    }

    return el("li", { class: "notif" },
      el("p", { class: "notif__titulo", text: p.nome }),
      p.telefone_mascarado ? el("p", { class: "notif__corpo", text: p.telefone_mascarado }) : null,
      etiquetas,
      linha.childElementCount ? linha : null);
  }

  // ---------------- Aba: Criar em lote (admin) ----------------
  async function abaLote(painel) {
    montar(painel, carregando("Contando…"));
    const s = await gerenciarLogin({ acao: "lote", departamento: "kids", confirmar: false, ignorar: [...ignorarNoLote] });
    if (!painel.isConnected) return;
    if (!s.ok) { montar(painel, aviso("erro", s.erro)); return; }
    const sit = s.por_situacao || {};
    const aCriar = Math.max((sit.criar || 0) - ignorarNoLote.size, 0);

    const dados = el("dl", { class: "dados" },
      el("dt", { text: "Logins a criar" }), el("dd", { text: String(aCriar) }),
      el("dt", { text: "…voluntárias" }), el("dd", { text: String(s.a_criar_voluntarias || 0) }),
      el("dt", { text: "…responsáveis" }), el("dd", { text: String(s.a_criar_responsaveis || 0) }),
      el("dt", { text: "…com os dois papéis" }), el("dd", { text: String(s.a_criar_os_dois_papeis || 0) }),
      el("dt", { text: "Já têm login" }), el("dd", { text: String(sit.ja_tem_login || 0) }),
      el("dt", { text: "Sem telefone / telefone fora do padrão" }), el("dd", { text: String((sit.sem_telefone || 0) + (sit.telefone_invalido || 0)) }),
      el("dt", { text: "Telefone compartilhado ou já em uso" }), el("dd", { text: String((sit.telefone_compartilhado || 0) + (sit.telefone_em_uso || 0)) }),
      ignorarNoLote.size ? el("dt", { text: "Falharam antes nesta aba (não serão tentados)" }) : null,
      ignorarNoLote.size ? el("dd", { text: String(ignorarNoLote.size) }) : null);

    const saida = el("div", {});
    const botao = el("button", { class: "botao botao--primario", type: "button", text: `Criar ${aCriar} logins`, disabled: aCriar === 0 });
    const linha = el("div", { class: "linha" }, botao);
    botao.addEventListener("click", () => pedirConfirmacao(linha,
      `Isso cria ${aCriar} logins de uma vez. Cada pessoa troca a senha no 1º acesso. Não feche esta tela até terminar.`,
      "Criar todos", async () => { await rodarLote(painel, saida, aCriar); }));

    montar(painel,
      el("section", { class: "cartao" }, el("h2", { text: "Simulação (Fonte Kids)" }), dados),
      aviso("atencao", "A senha inicial é previsível. Avise as pessoas para entrarem e trocarem a senha assim que possível."),
      aCriar === 0 ? aviso("sucesso", "Não há logins para criar.") : linha,
      saida);
  }

  async function rodarLote(painel, saida, total) {
    loteRodando = true;
    const sairDaPagina = (e) => { e.preventDefault(); e.returnValue = ""; };
    window.addEventListener("beforeunload", sairDaPagina);
    const barra = el("progress", { class: "progresso", max: String(Math.max(total, 1)), value: "0" });
    const texto = el("p", { role: "status", text: "Criando…" });
    montar(saida, el("section", { class: "cartao" }, texto, barra));

    let criados = 0, falhas = 0, erro = "";
    const motivos = {};
    for (let rodada = 0; rodada < 40; rodada++) {
      const r = await gerenciarLogin({ acao: "lote", departamento: "kids", confirmar: true, limite: POR_CHAMADA, ignorar: [...ignorarNoLote] });
      if (!r.ok) { erro = r.erro; break; }
      criados += r.criados || 0;
      falhas += r.falhas || 0;
      (r.falhas_ids || []).forEach((id) => ignorarNoLote.add(id));
      for (const [m, n] of Object.entries(r.motivos || {})) motivos[m] = (motivos[m] || 0) + n;
      barra.value = String(Math.min(criados + falhas, total));
      texto.textContent = `Criados: ${criados} · Falhas: ${falhas} · Faltam: ${r.restantes}`;
      if (!r.restantes || (!r.criados && !r.falhas)) break;
    }

    window.removeEventListener("beforeunload", sairDaPagina);
    loteRodando = false;
    pessoasCache = null;
    const lista = Object.entries(motivos).map(([m, n]) => el("li", { text: `${m} (${n})` }));
    montar(saida,
      aviso(erro ? "erro" : (falhas ? "atencao" : "sucesso"),
        `${erro ? `Parou antes do fim: ${erro} ` : "Terminado. "}Criados: ${criados}. Falhas: ${falhas}.`),
      lista.length ? el("section", { class: "cartao" }, el("h2", { text: "Motivos das falhas" }), el("ul", { class: "lista-simples" }, lista),
        el("p", { class: "suave", text: "Confira essas pessoas na aba Pessoas (filtro “Sem login”)." })) : null,
      el("div", { class: "linha" }, el("button", { class: "botao", type: "button", text: "Atualizar contagens", onclick: () => abaLote(painel) })));
  }

  montar(alvo,
    el("h1", { text: titulo }),
    aviso("atencao", AVISO_FIXO),
    el("div", { class: "abas", role: "tablist", "aria-label": "Gestão de logins" }, botoes),
    area);
  abrir("pedidos");
}
