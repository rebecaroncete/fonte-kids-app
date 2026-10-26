# Banco de dados – Supabase (branch `supabase-migracao`)

Projeto Supabase: **fonte-itaparica-app** · região **sa-east-1 (São Paulo)**.
O branch `main` continua com o app atual (Apps Script + planilha) funcionando normalmente.

## O que tem aqui

| Pasta | Conteúdo |
|---|---|
| `migrations/` | Criação do banco, em ordem. Já aplicadas no projeto em 26/10/2026. Os nomes batem com o histórico do Supabase. |
| `tests/teste_seguranca_rls.sql` | Teste das regras de acesso com dados **fictícios**, num departamento fictício próprio (funciona com o banco já preenchido). Tudo é desfeito ao final; o resultado aparece como mensagem "RESULTADO DOS TESTES" (62 verificações, incluindo fotos). |
| `migracao/` | Fase 2: scripts de limpeza e importação da planilha (sem dados). |
| `functions/foto-assinada/` | Fase 3: Edge Function que devolve links **temporários** (5 min) das fotos privadas no Cloudinary, só para quem tem permissão. |

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

**Segredos** (Supabase → Edge Functions → Secrets): `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`. Opcionais: `CLOUDINARY_CLOUD_NAME`, `FOTO_LINK_SEGUNDOS` (padrão 300). Nunca colocar esses valores no código.
