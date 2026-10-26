# Banco de dados – Supabase (branch `supabase-migracao`)

Projeto Supabase: **fonte-itaparica-app** · região **sa-east-1 (São Paulo)**.
O branch `main` continua com o app atual (Apps Script + planilha) funcionando normalmente.

## O que tem aqui

| Pasta | Conteúdo |
|---|---|
| `migrations/` | Criação do banco, em ordem. Já aplicadas no projeto em 26/10/2026. Os nomes batem com o histórico do Supabase. |
| `tests/teste_seguranca_rls.sql` | Teste das regras de acesso com dados **fictícios**. Tudo é desfeito ao final; o resultado aparece como mensagem "RESULTADO DOS TESTES". |

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
