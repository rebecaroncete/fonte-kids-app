# Fase 2 – Migração dos dados (planilha → Supabase)

> **Nenhum dado pessoal fica neste repositório.** Os dados exportados e os arquivos limpos
> ficam só numa pasta privada fora do Git (`supabase/migracao/dados/` está no `.gitignore`).
> O relatório de conferência tem **apenas contagens**.

## Arquivos
| Arquivo | O que faz |
|---|---|
| `fase2_limpeza.py` | Lê as abas exportadas, limpa, deduplica e gera `limpo.json` (privado) + `relatorio.json` (só contagens). |
| `../migrations/20261026180000_fase2_campos_migracao.sql` | Acrescenta `foto_legado_url` (temporário) e `teto_mensal` da voluntária. |

## Mapeamento aba → tabela

| Aba da planilha | Tabela(s) no Supabase | Regras |
|---|---|---|
| Cadastro_Familias | `familias`, `responsaveis`, `termos_lgpd` | `ID_Familia` → `codigo_legado` (cadastros mesclados ficam anotados em `observacoes`). Cada família vira 1–4 responsáveis; o principal é o telefone mais usado como "principal". Aceite LGPD da planilha → `termos_lgpd` versão `legado-planilha` (o termo v1 será pedido no 1º login, Fase 4). |
| Cadastro_Criancas | `criancas` | `ID_Crianca` → `codigo_legado`. Faixa etária → sala (o app calcula a sala pela idade; `sala_fixa_id` só se a líder fixar manualmente). Perfil → `membro`/`visitante`. `Foto_URL` → `foto_legado_url`. |
| Cadastro_Professoras | `voluntarias` | `ID_Professora` → `codigo_legado`. `Perfil_Atuacao` → `funcao` (professora/auxiliar). Faixas 1–4 → `salas_preferidas` (em ordem, sem repetição). Cultos 1–3 → `cultos_preferidos` (em ordem). Status Ativo → `ativa`. `Teto_Mensal` → `teto_mensal`. Sem login (Fase 4). |
| Indisponibilidade | `indisponibilidades` | 1 linha por data/horário; envios repetidos somados. |
| Escala_Mensal + Config_Escala | `escalas`, `escala_config_salas`, `escala_itens`, `cultos` | Líder → `professora`; Auxiliar → `auxiliar`; Reserva → `reserva`; Líder do Culto → `lider_culto` (sem sala). Oficial → resposta `pendente`; Ciente → `ciente`. VAZIO → vaga aberta. Vínculo com Google Agenda descartado. |
| Excecoes_Cultos | `culto_salas` (`cancelada = true`) | — |
| Sala "7 a 12 anos" (terça) | `culto_salas` (10 a 12 **combinada com** 7 a 9) | as vagas vão para a sala 7 a 9. |
| Historico_Frequencia | `checkins` (com `saida_em` preenchida) | ligado à criança por telefone do responsável + nome. Só data → horário do culto. |
| Configuracoes | `configuracoes`, `mensagens_whatsapp_modelos` | Mensagem_Choro/Telao/Lembrete_Escala → modelos. Telefone_Midia e lotação da terça → configurações. Limites de sala, cultos e dia limite já existem no banco. **PINs não são migrados.** |
| Checkin_Ativo, Licoes | — | vazias no momento da exportação. |
| Log_Erros | — | não migrado (log técnico antigo). |

## Limpeza aplicada
- Telefones → `55` + DDD + número; celular sem o 9º dígito recebe o 9; inválidos ficam vazios e entram no relatório.
- Datas → ISO (`AAAA-MM-DD`).
- Famílias com o mesmo telefone (ou com a mesma criança, mesmo nome + nascimento) são mescladas.
- Crianças repetidas na mesma família (mesmo nascimento e mesmo nome/prefixo) são mescladas: fica o nome mais completo, as alergias somadas, "membro" se alguma cópia for membro, a foto mais recente.
- "Não", "Nenhuma" etc. no campo de alergias → vazio.
- Cadastros "Teste" não são importados.
- Voluntárias menores de 18 anos são contadas e identificadas pela data de nascimento (sem campo extra).

## Como rodar
```bash
python3 fase2_limpeza.py <pasta_com_abas_json> <pasta_saida_privada> --hoje 2026-10-26
```
