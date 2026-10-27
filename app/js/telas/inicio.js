// =====================================================================
// Tela: Início por papel (Fase 10 · Etapa 4)
// Quem ainda não terminou o 1º acesso é levado antes para
// "#/primeiro-acesso" (js/app.js). Aqui: saudação, papéis, aviso das
// relações (se adiadas), notificações novas e um bloco por papel.
// Os resumos de verdade (crianças, escalas, check-ins) chegam na Fase 5.
// Recepção e liderança têm atalho para "Cadastros" (Etapa 5B).
// =====================================================================
import { el, montar, aviso, carregando } from "../ui.js";
import { estadoPrimeiroAcesso, meuPerfil, contarNaoLidas } from "../supabase.js";

export const layout = "padrao";
export const titulo = "Início";

// Um bloco por papel (na ordem de ORDEM_PAPEIS, em js/supabase.js)
const BLOCOS = {
  admin:       { cor: "azul",    titulo: "Administração", texto: "Você acompanha e ajusta tudo no app: cadastros, logins e configurações." },
  pastor:      { cor: "azul",    titulo: "Pastoral",      texto: "Você acompanha todos os departamentos da igreja." },
  lider:       { cor: "laranja", titulo: "Liderança",     texto: "Você cuida do departamento: voluntárias, famílias, escalas e pedidos de nova senha.", link: { href: "#/cadastros", texto: "Ver cadastros" } },
  recepcao:    { cor: "amarelo", titulo: "Recepção",      texto: "Você consulta crianças e famílias e, em breve, faz o check-in nos cultos.", link: { href: "#/cadastros", texto: "Ver cadastros" } },
  voluntaria:  { cor: "amarelo", titulo: "Voluntária",    texto: "Aqui você vai acompanhar as suas escalas e as salas em que serve." },
  responsavel: { cor: "laranja", titulo: "Minha família", texto: "Aqui você vai acompanhar as suas crianças, os check-ins e os avisos do Fonte Kids." },
};

export async function render(alvo) {
  montar(alvo, carregando());
  const [est, perfil, notif] = await Promise.all([estadoPrimeiroAcesso(), meuPerfil(), contarNaoLidas()]);

  if (!est.ok) {
    montar(alvo, el("h1", { text: "Início" }), aviso("erro", "Não foi possível carregar seus dados agora. Tente recarregar a página."));
    return;
  }
  if (est.etapa === "sem_acesso") {
    montar(alvo, el("h1", { text: "Início" }), aviso("erro", "Seu acesso não está ativo. Fale com a liderança do Fonte Kids."));
    return;
  }

  const primeiroNome = perfil.ok && perfil.nome ? perfil.nome.trim().split(/\s+/)[0] : "";
  const papeis = perfil.ok ? perfil.papeis : [];
  const unicos = [...new Map(papeis.map((p) => [p.papel, p])).values()];

  const partes = [
    el("h1", { text: primeiroNome ? `Olá, ${primeiroNome}!` : "Olá!" }),
    unicos.length
      ? el("p", { class: "linha" }, unicos.map((p) => el("span", { class: "etiqueta", text: p.nomePapel })))
      : null,
  ];

  if (est.etapa === "informar_relacoes") {
    partes.push(
      aviso("atencao", "Falta informar a sua relação com uma ou mais crianças."),
      el("p", {}, el("a", { class: "botao botao--secundario", href: "#/primeiro-acesso", text: "Informar agora" })));
  }

  const n = notif.ok ? notif.total : 0;
  partes.push(el("section", { class: "cartao atalho" },
    el("div", {},
      el("h2", { class: "atalho__titulo", text: "Notificações" }),
      el("p", { class: "atalho__texto", text: n === 0 ? "Nenhuma notificação nova." : `Você tem ${n} ${n > 1 ? "notificações novas" : "notificação nova"}.` })),
    el("a", { class: "botao botao--pequeno", href: "#/notificacoes", text: "Ver" })));

  for (const p of unicos) {
    const b = BLOCOS[p.papel];
    if (!b) continue;
    const dep = p.departamento && !["admin", "pastor"].includes(p.papel) ? ` · ${p.departamento}` : "";
    partes.push(el("section", { class: `cartao cartao--${b.cor}` },
      el("h2", { text: b.titulo + dep }),
      el("p", { class: "atalho__texto", text: b.texto }),
      b.link ? el("p", {}, el("a", { class: "botao botao--pequeno", href: b.link.href, text: b.link.texto })) : null));
  }

  partes.push(
    el("p", { class: "linha" },
      el("a", { class: "botao botao--pequeno", href: "#/perfil", text: "Meu perfil" }),
      el("a", { class: "botao botao--pequeno", href: "#/trocar-senha", text: "Trocar senha" })),
    el("p", { class: "suave", text: "Versão de teste: cadastro, check-in e escalas chegam nas próximas etapas." }));

  montar(alvo, partes);
}
