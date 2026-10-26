# Fase 2 – Migração dos dados (planilha → Supabase)

> **Nenhum dado pessoal fica neste repositório.** Os dados exportados, o arquivo limpo e os blocos
> de carga ficaram só numa pasta privada e temporária, apagada ao final. A área de carga no banco
> (`migracao_fase2`) também foi apagada. Relatórios têm **apenas contagens**.

**Status:** concluída em 26/10/2026 (teste com tudo desfeito → importação definitiva → teste de segurança 48/48).

## Arquivos
| Arquivo | O que faz |
|---|---|
| `fase2_limpeza.py` | Lê as abas exportadas, limpa, deduplica e gera `limpo.json` (privado) + `relatorio.json` (só contagens). Aceita `--unir-criancas CRI-a:CRI-b,...` para uniões confirmadas manualmente. |
| `fase2_gerar_carga.py` | Gera os blocos `insert` da área de carga a partir do `limpo.json` (os blocos contêm dados: nunca versionar). |
| `fase2_importar.sql` | Cria a área de carga e a função `migracao_fase2.importar(teste)`. `true` = faz tudo e desfaz; `false` = importa. |
| `../migrations/20261026180000_fase2_campos_migracao.sql` | `foto_legado_url` (temporário), `teto_mensal`, tabela `responsaveis_criancas` (parentesco) e `pendencias_cadastro`, com RLS e auditoria. |

## Resultado (contagens)
| Tabela | Registros |
|---|---|
| familias / termos_lgpd | 158 / 158 |
| responsaveis | 260 |
| responsaveis_criancas (parentesco **a confirmar**) | 350 |
| criancas (todas sem sala fixa; foto = link antigo) | 210 (1 mescla confirmada depois) |
| voluntarias (8 menores de 18; nenhuma com login) | 49 |
| indisponibilidades | 197 |
| cultos / culto_salas | 32 / 11 |
| escalas / escala_config_salas / escala_itens | 2 / 4 / 208 |
| checkins (histórico 20/09–25/10, todos encerrados) | 523 |
| mensagens_whatsapp_modelos / configuracoes | 3 / 4 (nenhum PIN) |
| pendencias_cadastro | 4 |

## Mapeamento aba → tabela

| Aba da planilha | Tabela(s) no Supabase | Regras |
|---|---|---|
| Cadastro_Familias | `familias`, `responsaveis`, `termos_lgpd`, `responsaveis_criancas` | `ID_Familia` → `codigo_legado` (cadastros mesclados anotados em `observacoes`). 1 responsável por pessoa; o principal é quem mais aparece como principal. Cada responsável é ligado a cada criança da família com parentesco **nulo = a confirmar** (o app pergunta no 1º login). Aceite LGPD da planilha → `termos_lgpd` versão `legado-planilha`. |
| Cadastro_Criancas | `criancas`, `pendencias_cadastro` | `ID_Crianca` → `codigo_legado`. Sala calculada pela idade (`sala_fixa_id` vazio). Perfil → `membro`/`visitante`. `Foto_URL` → `foto_legado_url`. Idade acima de 12 → pendência "conferir nascimento". |
| Cadastro_Professoras | `voluntarias` | `ID_Professora` → `codigo_legado`. `Perfil_Atuacao` → `funcao`. Faixas 1–4 → `salas_preferidas` e cultos 1–3 → `cultos_preferidos` (em ordem, sem repetição). Ativo → `ativa`. `Teto_Mensal` → `teto_mensal`. Sem login (Fase 4). |
| Indisponibilidade | `indisponibilidades` | 1 linha por data/horário; envios repetidos somados. |
| Escala_Mensal + Config_Escala | `escalas`, `escala_config_salas`, `escala_itens`, `cultos`, `configuracoes` | Líder → `professora`; Auxiliar → `auxiliar`; Líder do Culto → `lider_culto`. Oficial → `pendente`; Ciente → `ciente`. VAZIO → vaga aberta. Vagas da terça 7–12 → configuração `vagas_terca_sala_combinada_7_12`. Google Agenda descartado. |
| Excecoes_Cultos | `culto_salas` (`cancelada = true`) | — |
| Sala "7 a 12 anos" (terça) | `culto_salas` (10 a 12 **combinada com** 7 a 9) | vagas e check-ins vão para a sala 7 a 9. |
| Historico_Frequencia | `checkins` | ligado à criança por telefone + nome; só data → horário do culto; `saida_em` = entrada (o sistema antigo não registrava a saída). Check-ins em dia/horário sem culto não foram importados. |
| Configuracoes | `configuracoes`, `mensagens_whatsapp_modelos` | Mensagens de choro, telão e lembrete → modelos. Telefone da mídia e lotação da terça → configurações. **PINs não migrados.** |
| Checkin_Ativo, Licoes, Log_Erros | — | vazias / não migrado. |

## Limpeza aplicada
- Telefones → `55` + DDD + número; celular sem o 9º dígito recebe o 9; inválidos ficam vazios.
- Datas → ISO (`AAAA-MM-DD`).
- Famílias com o mesmo telefone, ou com a mesma criança (nome + nascimento), são mescladas; uniões duvidosas só com confirmação.
- Mesma pessoa repetida dentro da família (mesmo primeiro nome) vira 1 responsável.
- Crianças repetidas na mesma família (mesmo nascimento e mesmo nome/prefixo, ou mesmo primeiro e último nome) são mescladas: nome mais completo, alergias somadas, "membro" se alguma cópia for membro, foto mais recente.
- "Não", "Nenhuma" etc. em alergias → vazio. Cadastros "Teste" não importados.

## Como repetir (se um dia precisar)
1. Exportar as abas para uma pasta privada e rodar `fase2_limpeza.py` e `fase2_gerar_carga.py`.
2. No SQL Editor: rodar `fase2_importar.sql`, depois os blocos de carga, depois `select migracao_fase2.importar(true);` (teste) e `select migracao_fase2.importar(false);`.
3. **Rodar o teste e a carga em execuções separadas** (o teste desfaz tudo o que estiver na mesma execução).
4. `drop schema migracao_fase2 cascade;` e apagar a pasta privada.
