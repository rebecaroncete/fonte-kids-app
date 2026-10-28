// =====================================================================
// Fonte Kids – service worker (Fase 10 · Etapa 6)
// Guarda no aparelho SÓ os arquivos do próprio app (lista ARQUIVOS).
// Nunca guarda dados do Supabase, fotos do Cloudinary nem o captcha:
// pedidos para outros endereços não passam por aqui.
//
// Ao publicar uma versão nova:
//   1) suba VERSAO aqui E "versao" em config.js (o mesmo número);
//   2) arquivo novo dentro de app/? acrescente em ARQUIVOS.
//   Conferência automática: node ferramentas/conferir-pwa.mjs
// O app mostra "Versão nova disponível – Atualizar"; a troca só acontece
// quando a pessoa toca em Atualizar (nada muda no meio de um check-in).
// =====================================================================
const VERSAO = "0.11.0";
const PREFIXO = "fonte-kids-app-";
const CACHE = PREFIXO + VERSAO;

const ARQUIVOS = [
  "./",
  "index.html",
  "config.js",
  "manifest.webmanifest",
  "css/tema.css",
  "css/componentes.css",
  "fonts/baloo-2-latin-700-normal.woff2",
  "fonts/baloo-2-latin-800-normal.woff2",
  "fonts/nunito-latin-400-normal.woff2",
  "fonts/nunito-latin-600-normal.woff2",
  "fonts/nunito-latin-700-normal.woff2",
  "fonts/nunito-latin-800-normal.woff2",
  "img/logo.png",
  "img/icones/apple-touch-icon-180.png",
  "img/icones/favicon-32.png",
  "img/icones/icone-192.png",
  "img/icones/icone-512.png",
  "img/icones/icone-maskable-512.png",
  "vendor/supabase-2.118.0.js",
  "js/app.js",
  "js/captcha.js",
  "js/casca.js",
  "js/foto.js",
  "js/icones.js",
  "js/janela.js",
  "js/notificacoes.js",
  "js/pwa.js",
  "js/supabase.js",
  "js/ui.js",
  "js/telas/cadastros.js",
  "js/telas/esqueci-senha.js",
  "js/telas/ficha.js",
  "js/telas/inicio.js",
  "js/telas/login.js",
  "js/telas/logins.js",
  "js/telas/minha-familia.js",
  "js/telas/nao-encontrada.js",
  "js/telas/notificacoes.js",
  "js/telas/pendencias.js",
  "js/telas/perfil.js",
  "js/telas/primeiro-acesso.js",
  "js/telas/trocar-senha.js",
  "js/telas/vitrine.js",
];

const BASE = self.registration.scope; // ex.: https://…/fonte-kids-app/app/
const endereco = (p) => new URL(p, BASE).href;

// Instalação: baixa todos os arquivos da versão, sem usar o cache do navegador
// (cache: "reload"), para não guardar arquivo de versão antiga.
self.addEventListener("install", (evento) => {
  evento.waitUntil(
    caches.open(CACHE).then((c) =>
      c.addAll(ARQUIVOS.map((p) => new Request(endereco(p), { cache: "reload" })))));
  // Sem skipWaiting aqui: a versão nova espera a pessoa tocar em "Atualizar".
});

// Ativação: apaga os caches das versões anteriores do app.
self.addEventListener("activate", (evento) => {
  evento.waitUntil((async () => {
    const nomes = await caches.keys();
    await Promise.all(nomes.filter((n) => n.startsWith(PREFIXO) && n !== CACHE).map((n) => caches.delete(n)));
    await self.clients.claim();
  })());
});

// O app pede a troca de versão (botão "Atualizar").
self.addEventListener("message", (evento) => {
  if (evento.data && evento.data.tipo === "atualizar") self.skipWaiting();
});

self.addEventListener("fetch", (evento) => {
  const pedido = evento.request;
  if (pedido.method !== "GET") return;
  const url = new URL(pedido.url);
  // Só arquivos do próprio app. Supabase, Cloudinary, captcha e qualquer
  // outro endereço seguem direto para a internet, sem passar pelo cache.
  if (url.origin !== self.location.origin || !pedido.url.startsWith(BASE)) return;

  evento.respondWith((async () => {
    const cache = await caches.open(CACHE);
    // Abrir o app (qualquer endereço #/…): sempre a página da versão atual.
    if (pedido.mode === "navigate") {
      const pagina = await cache.match(endereco("./"));
      if (pagina) return pagina;
      return fetch(pedido);
    }
    const guardado = await cache.match(url.origin + url.pathname);
    if (guardado) return guardado;
    return fetch(pedido); // arquivo fora da lista: vai à internet e não é guardado
  })());
});
