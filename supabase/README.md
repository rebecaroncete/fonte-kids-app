# Banco de dados – Supabase (branch `supabase-migracao`)

Projeto Supabase: **fonte-itaparica-app** · região **sa-east-1 (São Paulo)**.
O branch `main` continua com o app atual (Apps Script + planilha) funcionando normalmente.

## O que tem aqui

| Pasta | Conteúdo |
|---|---|
| `migrations/` | Criação do banco, em ordem. Já aplicadas no projeto em 26/10/2026. Os nomes batem com o histórico do Supabase. |
| `tests/teste_seguranca_rls.sql` | Teste das regras de acesso com dados **fictícios**, num departamento fictício próprio (funciona com o banco já preenchido). Tudo é desfeito ao final; o resultado aparece como mensagem "RESULTADO DOS TESTES" (151 verificações: regras de acesso, fotos, cadastro único de pessoas, logins e 1º acesso do responsável). |
| `migracao/` | Fase 2: scripts de limpeza e importação da planilha (sem dados). |
| `functions/foto-assinada/` | Fase 3: Edge Function que devolve links **temporários** (5 min) das fotos privadas no Cloudinary, só para quem tem permissão. |
| `functions/gerenciar-login/` | Fase 4 · Etapa 3: cria e redefine logins (telefone → e-mail técnico), sem senha no código nem na resposta. |

## Quem vê o quê

| Papel | Pode |
|---|---|
| **admin** | tudo + log de erros + gestão técnica |
| **pastor** | tudo, todos os departamentos, auditoria |
| **lider** (por departamento) | tudo do departamento; aprova voluntárias; promove voluntária ↔ líder |
| **recepcao** (por departamento) | cadastro de famílias/crianças e check-in/out do departamento |
| **voluntaria** | a própria ficha; crianças e check-ins das salas em que foi escalada; contato dos pais **só no dia e só da sala dela**; escala publicada; lista da equipe com dados mínimos |
| **responsavel** (pai/mãe) | só a própria família, **depois de aceitar o termo LGPD vigente** no próprio login |
| sem login | nada (só registrar erro técnico) |

Proteções extras: voluntária não se auto-aprova; ninguém altera o código de segurança do check-in; quem faz a saída fica registrado; auditoria guarda **quem alterou quais campos e quando**, sem copiar dados pessoais.

## Como rodar o teste de novo
1. Supabase → SQL Editor → cole o conteúdo de `tests/teste_seguranca_rls.sql` → Run.
2. A "mensagem de erro" é o relatório. Deve terminar com `falhas: 0`.

## Fotos (Fase 3)

- As fotos ficam no **Cloudinary da igreja**, em modo **privado** (`authenticated`), com no máximo 400 px.
- Identificador = id interno do registro, nunca o nome: `pessoas/criancas/<uuid>` e `pessoas/voluntarias/<uuid>` (pasta da igreja, sem departamento, para outros departamentos poderem usar a mesma foto).
- O banco guarda só esse identificador em `foto_public_id`. O app **não** monta o link: chama a Edge Function `foto-assinada`.

**Quem recebe a foto**

| Foto de | Quem pode ver |
|---|---|
| criança | as mesmas pessoas que já veem a criança (família, recepção/líder do departamento, voluntária escalada na sala, pastor/admin) |
| voluntária maior de idade | ela mesma, liderança e a equipe do departamento |
| voluntária **menor** de idade | só ela mesma e a liderança (líder, pastor, admin) |

**Como o app pede as fotos** (usuário logado):

```js
const { data } = await supabase.functions.invoke('foto-assinada', {
  body: { tipo: 'crianca', ids: [idDaCrianca1, idDaCrianca2] }   // ou tipo: 'voluntaria'; até 100 ids
});
// data.fotos = { "<id>": "<link que vale 5 minutos>" }; ids sem permissão não aparecem
```

- A coluna temporária `foto_legado_url` (links do Drive) foi apagada depois de conferir as 259 fotos.
- A chave de API do Cloudinary usada pela função precisa ter permissão de **download** (papel Master Admin); sem isso o Cloudinary responde 403.

**Segredos** (Supabase → Edge Functions → Secrets): `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`. Opcionais: `CLOUDINARY_CLOUD_NAME`, `FOTO_LINK_SEGUNDOS` (padrão 300). Nunca colocar esses valores no código.

## Logins (Fase 4 · Etapa 3)

- **Login = telefone** (55 + DDD + número). O app converte para um e-mail técnico `<telefone>@login.fonteitaparica.invalid` (domínio reservado, nunca recebe e-mail). Sem SMS.
- **Senha inicial** (decisão de 26/10/2026): voluntária = data de nascimento (DDMMAAAA); demais = o telefone de login. **Troca obrigatória no 1º acesso.**
- Enquanto não troca a senha, o usuário **não vê dado nenhum** (só o próprio perfil). Usuário **sem papel** também não vê nada.
- `concluir_troca_senha()` só funciona se a senha realmente mudou (o banco guarda só um carimbo do hash, nunca a senha).
- Uma pessoa = um login (as que são voluntária e responsável recebem os dois papéis).
- Telefone usado por mais de uma pessoa: o login fica com a voluntária; entre responsáveis, com o principal. Os demais ficam sem login até informar um número próprio.
- Os logins são criados **só pelo servidor**: a Edge Function `gerenciar-login` usa a chave de serviço que o próprio Supabase fornece nas variáveis de ambiente. Nenhuma senha ou chave fica no código, nas respostas ou nos logs (a resposta diz só qual regra de senha foi usada).

**Ações da função** (painel: Edge Functions → gerenciar-login → Test, papel *service role*; ou usuário logado com permissão):

| Ação | O que faz | Quem |
|---|---|---|
| `autoteste` | cria e apaga um login fictício para conferir o domínio técnico | admin / painel |
| `criar` | cria o login de uma pessoa (`pessoa_id`, `telefone_login` opcional, papéis extras); voluntária/responsável entram sozinhos | quem pode dar todos os papéis |
| `redefinir` | volta para a senha inicial e exige nova troca | quem pode gerir todos os papéis da pessoa |
| `trocar_telefone` | troca o telefone de contato (`pessoa_id`, `telefone`) e, se houver login, o telefone de login e o e-mail técnico juntos; a senha não muda | quem pode redefinir a senha do login (sem login: quem gere as voluntárias do departamento) |
| `lote` | sem `confirmar` só mostra contagens; com `confirmar: true` cria até `limite` por chamada | admin / painel |

**Configuração no painel** (Authentication): desligar o cadastro público (*Allow new users to sign up*), senha mínima de 8 caracteres e sem exigência de letras/símbolos (as senhas iniciais são só números).

## 1º acesso do responsável (Fase 4 · Etapa 4)

Ordem: **trocar a senha → aceitar o termo LGPD → informar a relação com cada criança**. O app pergunta em que passo a pessoa está com `estado_primeiro_acesso()` (devolve `etapa`: `trocar_senha`, `aceitar_termo`, `informar_relacoes` ou `pronto`, os ids das crianças sem relação e o número de pendências abertas; nenhum dado pessoal).

- **Termo LGPD por responsável** (decisão de 27/10/2026): o texto fica em `termos_lgpd_versoes` (uma versão vigente; v1 inclui a consulta das relações familiares por líderes e pastores). Cada responsável aceita no próprio login com `aceitar_termo_lgpd('v1')`. Os aceites vindos da planilha ficam guardados como histórico (`legado-planilha`).
- **Até aceitar, não vê dado nenhum** (igual à troca de senha). Quem não aceitar fica sem acesso ao app; o check-in pela recepção continua normal. Não há "recusar": quem não concorda fala com a liderança.
- Publicar uma versão nova do termo (marcar como vigente) faz **todos os responsáveis** aceitarem de novo. Voluntárias, líderes e pastores que não são responsáveis não são afetados.
- Ninguém registra aceite em nome de outro login.
- **Relação com a criança:** `informar_relacao(crianca_id, tipo, detalhe)`. Só para criança ligada ao responsável; "cônjuge" não vale; "outro" exige descrição (ex.: madrinha). Grava em `relacoes_pessoas` com origem `responsavel`; informar de novo corrige (fica uma relação só entre os dois). O responsável não grava direto na tabela.
- **Pendências (só aviso, não bloqueiam check-in):**
  - automáticas, abrem e somem sozinhas: `relacao_nao_informada` (algum responsável da criança sem relação) e `nascimento_vazio`;
  - manuais (importação/recepção): `conferir_nascimento` some quando a data é alterada; `nome_responsavel` some quando o nome é alterado; qualquer manual pode ser fechada pela família ou recepção com `confirmar_pendencia(id)` ("está certo").
  - A família não edita a tabela de pendências direto; recepção e liderança sim.

## Pedido de nova senha (Fase 10 · Etapa 2)
- Tabela `pedidos_redefinicao_senha` (migração `20261027160000_fase10_pedidos_redefinicao_senha.sql`): perfil, pessoa, data, status `pendente`/`atendido`, quem atendeu. Não guarda telefone digitado nem IP. Leitura só para pastores/admin e líderes do Fonte Kids; ninguém grava pelo app.
- `registrar_pedido_redefinicao(perfil)`: só o servidor (service_role) chama. Limite de 1 pedido por login a cada 24 h; avisa no sino (`notificacoes`, tipo `pedido_senha`) líderes do Fonte Kids, admin e pastores.
- Edge Function `pedir-redefinicao` (pública, `verify_jwt = false`): confere o captcha (Turnstile) no servidor e responde sempre "Pedido enviado. A liderança vai falar com você.". Nunca redefine a senha.
- Segredos no painel: `TURNSTILE_SECRET_KEY` (obrigatório); `ORIGENS_PERMITIDAS` (opcional; na virada, acrescentar o endereço do Netlify).
- Captcha também ligado no Supabase Auth (Attack Protection → Turnstile): o login exige o token.
- Marcar como atendido ao redefinir: Etapa 5 (gestão de logins).

## Comunicação e push (Fase 7)

- **Avisos da liderança:** `enviar_aviso(publico, titulo, texto)` com público `todos`, `equipe`, `lideres` ou `responsaveis`; o banco monta a lista de quem recebe (logins ativos do Fonte Kids, sem quem envia). `avisos_enviados()` mostra quantas pessoas receberam e leram. **Ninguém grava direto em `notificacoes`** (só as funções do banco).
- **Enquetes:** `criar_enquete`, `votar_enquete` (muda o voto até encerrar), `encerrar_enquete`, `apagar_enquete`, `enquetes_lista`, `enquetes_pendentes`. A liderança vê quem votou; quem vota vê só os totais depois de votar ou quando encerra.
- **Push:** o app grava o aparelho por `salvar_push` / `remover_push` (só quando a pessoa toca em "Ativar"; ao sair, desliga). Toda notificação nova de quem tem aparelho chama a Edge Function `enviar-push` pelo `pg_net` (gatilho `notificacoes_push`). A função pede ao banco o que mostrar (`push_preparar`, só chave de serviço): cada notificação vai **uma vez**, só nos primeiros 15 min; as automáticas vão **só com o título + "Abra o app para ver."** (sem nomes); avisos e enquetes vão com o texto. Aparelhos recusados (404/410) são apagados.
- `functions/enviar-push/`: Web Push sem biblioteca (Web Crypto: `aes128gcm` + VAPID). Publicar com **verify_jwt = false** (quem chama é o banco).

**Segredos** (Supabase → Edge Functions → Secrets): `VAPID_PUBLIC_KEY` (a mesma de `app/config.js`), `VAPID_PRIVATE_KEY` (**nunca** no código), `VAPID_SUBJECT` opcional.
