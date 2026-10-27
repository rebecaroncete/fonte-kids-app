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
  js/ui.js            utilidades (criar elementos com segurança, avisos, telefone)
  js/telas/*.js       uma tela por arquivo (layout, titulo, render)
  img/logo.png        logo com fundo transparente
  fonts/              Baloo 2 e Nunito servidas pelo próprio app (sem Google Fonts)
  vendor/             supabase-js 2.118.0 (versão fixa)
```

## Regras
- Nenhuma chave secreta, senha ou dado pessoal no código. Exemplos só com dados fictícios.
- Textos na tela sempre por `textContent` (nunca `innerHTML` com dados).
- Para trocar a versão do supabase-js: baixar o novo `dist/umd/supabase.js`, salvar em `vendor/` e mudar o nome no `index.html`.

## Telas
| Endereço | Tela | Etapa |
|---|---|---|
| `#/entrar` | Entrar (telefone + senha) | 1 (visual) · 2 (funcional) |
| `#/vitrine` | Vitrine de componentes e teste de conexão | 1 |

## Teste
GitHub Pages servindo o branch `supabase-migracao` (pasta raiz):
`https://rebecaroncete.github.io/fonte-kids-app/app/`
