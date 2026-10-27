# Fonte Kids – app novo (Fase 10)

SPA estática (HTML + CSS + JavaScript puro, sem etapa de compilação) que conversa com o Supabase `fonte-itaparica-app`.
O app atual (`index.html` na raiz + Apps Script) continua intocado.

## Estrutura
```
app/
  index.html          página única; regras de segurança (CSP) no <head>
  config.js           endereço + chave PÚBLICA do Supabase; chave pública do captcha
  css/tema.css        cores da logo, fontes, espaçamentos
  css/componentes.css botões, campos, cartões, avisos, listas
  js/app.js           início e navegação (#/endereco)
  js/supabase.js      conexão com o Supabase
  js/casca.js         barra do topo: sino + menu por papel (ITENS_MENU)
  js/notificacoes.js  contagem de não lidas + tempo real (Realtime)
  js/ui.js            utilidades (criar elementos com segurança, avisos, telefone)
  js/telas/*.js       uma tela por arquivo (layout, titulo, render)
  manifest.webmanifest  app instalável (nome, cores, ícones)
  sw.js               service worker: guarda SÓ os arquivos do app (VERSAO + ARQUIVOS)
  js/pwa.js           registro do sw, aviso de versão nova, sem conexão, convite de instalação
  img/logo.png        logo com fundo transparente
  img/icones/         ícones do app (192, 512, maskable, iPhone 180, favicon)
  fonts/              Baloo 2 e Nunito servidas pelo próprio app (sem Google Fonts)
  vendor/             supabase-js 2.118.0 (versão fixa)
```

## Regras
- **A cada entrega:** subir `versao` em `config.js` **e** `VERSAO` em `sw.js` (mesmo número); arquivo novo em `app/` entra em `ARQUIVOS` do `sw.js`. Conferir com `node ferramentas/conferir-pwa.mjs`.
- Nenhuma chave secreta, senha ou dado pessoal no código. Exemplos só com dados fictícios.
- Textos na tela sempre por `textContent` (nunca `innerHTML` com dados).
- Para trocar a versão do supabase-js: baixar o novo `dist/umd/supabase.js`, salvar em `vendor/` e mudar o nome no `index.html`.

## Telas
| Endereço | Tela | Etapa |
|---|---|---|
| `#/entrar` | Entrar (telefone + senha) | 1 (visual) · 2 (funcional) |
| `#/vitrine` | Vitrine de componentes e teste de conexão | 1 |
| `#/esqueci-senha` | Pedido de nova senha | 2 |
| `#/primeiro-acesso` | 1º acesso (senha, termo, relações) | 3 |
| `#/inicio` | Início por papel | 4 |
| `#/notificacoes` | Notificações (sino) | 4 |
| `#/perfil` | Meu perfil (só leitura) | 4 |
| `#/trocar-senha` | Trocar senha (senha atual + captcha) | 4 |

## Teste
GitHub Pages servindo o branch `supabase-migracao` (pasta raiz):
`https://rebecaroncete.github.io/fonte-kids-app/app/`

## Etapa 2 – login (27/10/2026)
- `js/supabase.js`: login (telefone → e-mail técnico), "Manter conectado" (marcado = sessão no aparelho; desmarcado = só nesta aba), sair, pedido de nova senha. Erros sempre genéricos.
- `js/captcha.js`: Cloudflare Turnstile (só a chave pública, em `config.js`).
- Telas: `entrar` (login real), `esqueci-senha`, `inicio` (provisória, mostra a etapa do 1º acesso). Rotas privadas exigem login.

## Etapa 4 – casca por papel (27/10/2026)
- Barra do topo com sino (contagem de não lidas, atualiza em tempo real) e menu. O menu só mostra telas que existem; itens por papel ficam em `ITENS_MENU` (`js/casca.js`).
- Início por papel, Meu perfil (só leitura), Trocar senha (confere a senha atual com captcha e desconecta os outros aparelhos), Notificações (marcar como lida, uma ou todas; links só para telas internas existentes).
- Nenhuma mudança no banco (o RLS de `notificacoes` já permite ler e marcar as próprias como lidas).
