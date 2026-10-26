# Banco de dados – Supabase (branch `supabase-migracao`)

Projeto Supabase: **fonte-itaparica-app** · região **sa-east-1 (São Paulo)**.
O branch `main` continua com o app atual (Apps Script + planilha) funcionando normalmente.

## O que tem aqui

| Pasta | Conteúdo |
|---|---|
| `migrations/` | Criação do banco, em ordem. Já aplicadas no projeto em 26/10/2026. Os nomes batem com o histórico do Supabase. |
| `tests/teste_seguranca_rls.sql` | Teste das regras de acesso com dados **fictícios**, num departamento fictício próprio (funciona com o banco já preenchido). Tudo é desfeito ao final; o resultado aparece como mensagem "RESULTADO DOS TESTES" (121 verificações: regras de acesso, fotos, cadastro único de pessoas e logins). |
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
| **responsavel** (pai/mãe) | só a própria família |
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
| `lote` | sem `confirmar` só mostra contagens; com `confirmar: true` cria até `limite` por chamada | admin / painel |

**Configuração no painel** (Authentication): desligar o cadastro público (*Allow new users to sign up*), senha mínima de 8 caracteres e sem exigência de letras/símbolos (as senhas iniciais são só números).
