#!/usr/bin/env python3
"""
Gera os blocos SQL de carga (staging) a partir do limpo.json (privado).
Saída: <pasta>/carga_NN.sql — contêm dados pessoais: NUNCA versionar.
Uso: python3 fase2_gerar_carga.py <limpo.json> <pasta_saida>
"""
import json, sys
L = json.load(open(sys.argv[1])); OUT = sys.argv[2]
cult_ok = {(c["data"], c["horario"]) for c in L["cultos"] if c["recorrente"]}
pacotes = {
 "familias": [[f["codigo_legado"], f["mesclados"], f["criado_em"],
               [[r["nome"], r["telefone"], r["principal"]] for r in f["responsaveis"]]] for f in L["familias"]],
 "criancas": [[c["codigo"], c["fam"], c["nome"], c["nasc"], c["alergia"], c["foto"], c["perfil"]] for c in L["criancas"]],
 "voluntarias": [[v["codigo_legado"], v["nome"], v["telefone"], v["email"], v["nasc"], v["sexo"], v["profissao"],
                  v["funcao"], v["salas"], v["cultos"], v["status"], v["foto"], v["teto"], v["criado_em"]] for v in L["voluntarias"]],
 "indisponibilidades": L["indisponibilidades"],
 "cultos": [[c["data"], c["horario"], c["recorrente"]] for c in L["cultos"] if c["recorrente"]],
 "culto_salas": [[x["culto"][0], x["culto"][1], x["sala"], x["cancelada"], x["combinada"]] for x in L["culto_salas"]],
 "escalas": [[e["mes"], e["status"], e.get("teto"), e.get("config_salas"), e.get("terca_7_12")] for e in L["escalas"]],
 "escala_itens": [[i["mes"], i["culto"][0], i["culto"][1], i["sala"], i["funcao"], i["voluntaria"], i["nome_livre"], i["resposta"]] for i in L["escala_itens"]],
 "checkins": [[k["culto"][0], k["culto"][1], k["crianca"], k["sala"], k["codigo"], k["entrada"]] for k in L["checkins"] if tuple(k["culto"]) in cult_ok],
 "mensagens": [[k, t, x] for k, (t, x) in L["mensagens"].items() if x],
 "configuracoes": [[k, v, d] for k, (v, d) in L["configuracoes"].items() if v],
 "pendencias": [[p["fam"], p["crianca"], p["tipo"], p["mensagem"]] for p in L["pendencias"]],
}
blocos, atual = [], []
for tab, linhas in pacotes.items():
    for i in range(0, max(len(linhas), 1), 120):
        j = json.dumps(linhas[i:i + 120], ensure_ascii=False, separators=(",", ":"))
        assert "$j$" not in j
        atual.append(f"insert into migracao_fase2.carga(tabela, dados) values ('{tab}', $j${j}$j$::jsonb);")
        if sum(map(len, atual)) > 30000:
            blocos.append(atual); atual = []
if atual: blocos.append(atual)
for n, b in enumerate(blocos, 1):
    open(f"{OUT}/carga_{n:02d}.sql", "w").write("\n".join(b) + "\n")
print({k: len(v) for k, v in pacotes.items()}, "blocos:", len(blocos), [sum(map(len, b)) for b in blocos])
