#!/usr/bin/env python3
"""
Fonte Kids – Fase 2: limpeza e mapeamento planilha -> Supabase.

Lê as abas exportadas (JSON, uma lista de linhas por aba, 1ª linha = cabeçalho)
de uma pasta PRIVADA e gera:
  - limpo.json       (dados limpos, prontos para importação; NUNCA versionar)
  - relatorio.json   (só contagens; pode ser compartilhado)

Uso: python3 fase2_limpeza.py <pasta_raw> <pasta_saida> [--hoje AAAA-MM-DD]
Este arquivo não contém nenhum dado pessoal.
"""
import json, re, sys, unicodedata, collections, datetime as dt

RAW, OUT = sys.argv[1], sys.argv[2]
HOJE = dt.date.fromisoformat(sys.argv[sys.argv.index("--hoje") + 1]) if "--hoje" in sys.argv else dt.date.today()

def aba(nome):
    linhas = json.load(open(f"{RAW}/{nome}.json"))
    cab = [c.strip() for c in linhas[0]]
    return [dict(zip(cab, (l + [""] * len(cab))[:len(cab)])) for l in linhas[1:] if any(x.strip() for x in l)]

R = collections.defaultdict(collections.Counter)   # relatório: R[seção][problema] += 1

# ---------------------------------------------------------------- utilitários
DDDS = {11,12,13,14,15,16,17,18,19,21,22,24,27,28,31,32,33,34,35,37,38,41,42,43,44,45,46,47,48,49,51,53,54,55,
        61,62,63,64,65,66,67,68,69,71,73,74,75,77,79,81,82,83,84,85,86,87,88,89,91,92,93,94,95,96,97,98,99}

def telefone(s, sec):
    """Retorna '55DDDNNNNNNNNN' ou None. Conta o tipo de correção."""
    s = (s or "").strip()
    if not s:
        return None
    d = re.sub(r"\D", "", s).lstrip("0")
    if len(d) in (12, 13) and d.startswith("55") and int(d[2:4]) in DDDS and not (len(d) == 12 and d[4] in "6789"):
        d = d[2:]
    if len(d) == 10 and int(d[:2]) in DDDS and d[2] in "6789":
        R[sec]["telefone celular sem o 9º dígito (9 acrescentado)"] += 1
        d = d[:2] + "9" + d[2:]
    if len(d) == 11 and int(d[:2]) in DDDS and d[2] == "9":
        R[sec]["telefones convertidos para 55+DDD"] += 1
        return "55" + d
    if len(d) == 10 and int(d[:2]) in DDDS and d[2] in "2345":
        R[sec]["telefones fixos convertidos para 55+DDD"] += 1
        return "55" + d
    R[sec]["telefone inválido (descartado, revisar)"] += 1
    return None

def data(s, sec, campo):
    s = (s or "").strip().split(" ")[0]
    if not s:
        return None
    m = re.fullmatch(r"(\d{1,2})/(\d{1,2})/(\d{4})", s)
    try:
        d = dt.date(int(m[3]), int(m[2]), int(m[1]))
        if not re.fullmatch(r"\d{2}/\d{2}/\d{4}", s):
            R[sec][f"{campo}: data em formato irregular (corrigida)"] += 1
        return d
    except Exception:
        R[sec][f"{campo}: data inválida (descartada, revisar)"] += 1
        return None

def datahora(s):
    s = (s or "").strip()
    m = re.fullmatch(r"(\d{1,2})/(\d{1,2})/(\d{4})(?: (\d{1,2}):(\d{2})(?::(\d{2}))?)?", s)
    if not m:
        return None
    return dt.datetime(int(m[3]), int(m[2]), int(m[1]), int(m[4] or 0), int(m[5] or 0), int(m[6] or 0))

def norm(s):
    s = unicodedata.normalize("NFKD", (s or "")).encode("ascii", "ignore").decode().lower()
    s = re.sub(r"\(.*?\)", " ", s)
    return re.sub(r"\s+", " ", re.sub(r"[^a-z ]", " ", s)).strip()

def normd(s):
    """como norm, mas mantém dígitos (para textos de culto: 'Domingo às 10h')"""
    s = unicodedata.normalize("NFKD", (s or "")).encode("ascii", "ignore").decode().lower()
    return re.sub(r"\s+", " ", re.sub(r"[^a-z0-9 ]", " ", s)).strip()

def nome_limpo(s):
    s = re.sub(r"\s+", " ", (s or "").strip())
    return s

def idade(nasc, ref=HOJE):
    return ref.year - nasc.year - ((ref.month, ref.day) < (nasc.month, nasc.day))

SALAS = ["0 a 2 anos", "3 a 6 anos", "7 a 9 anos", "10 a 12 anos"]
def sala_por_idade(a):
    return None if a is None or a < 0 else ("0 a 2 anos" if a <= 2 else "3 a 6 anos" if a <= 6 else
                                            "7 a 9 anos" if a <= 9 else "10 a 12 anos" if a <= 12 else None)
def sala_planilha(s):
    s = (s or "").strip().lower()
    for x in SALAS:
        if s == x:
            return x
    return None

SEM_ALERGIA = {"", "nao", "n", "nenhuma", "nenhum", "nem uma", "nao tem", "nada", "nenhuma alergia",
               "sem alergia", "nao possui", "nao ha"}
def alergia(s, sec):
    t = (s or "").strip()
    if norm(t) in SEM_ALERGIA:
        if t:
            R[sec]["alergias: 'não/nenhuma' convertido em vazio"] += 1
        return None
    return t

CULTO_TXT = {"domingo as 10h": ("dom10", 0, "10:00"), "domingo as 19h": ("dom19", 0, "19:00"),
             "terca as 20h": ("ter20", 2, "20:00")}
HORA_TXT = {"10h": "10:00", "19h": "19:00", "20h": "20:00"}

class UF:
    def __init__(s): s.p = {}
    def f(s, x):
        s.p.setdefault(x, x)
        while s.p[x] != x:
            s.p[x] = s.p[s.p[x]]; x = s.p[x]
        return x
    def u(s, a, b): s.p[s.f(a)] = s.f(b)

# ================================================================= FAMÍLIAS
fam_raw = aba("Cadastro_Familias")
cri_raw = aba("Cadastro_Criancas")
R["Cadastro_Familias"]["linhas na planilha"] = len(fam_raw)
R["Cadastro_Criancas"]["linhas na planilha"] = len(cri_raw)

TESTE = lambda n: norm(n) in {"teste", "test"}
fams = {}
for f in fam_raw:
    fid = f["ID_Familia"].strip()
    if TESTE(f["Nome_Responsavel_Principal"]):
        R["Cadastro_Familias"]["cadastro de teste (não importado)"] += 1
        continue
    if fid in fams:
        R["Cadastro_Familias"]["ID_Familia repetido"] += 1
    p_nome = nome_limpo(f["Nome_Responsavel_Principal"])
    p_tel = telefone(f["Telefone_Principal"], "Cadastro_Familias")
    s_nome = nome_limpo(f["Nome_Segundo_Responsavel"])
    s_tel = telefone(f["Telefone_Segundo_Responsavel"], "Cadastro_Familias")
    if s_nome and not norm(s_nome):
        R["Cadastro_Familias"]["2º responsável: número digitado no lugar do nome"] += 1
        s_nome = ""
    if s_nome and (norm(s_nome) == norm(p_nome)):
        R["Cadastro_Familias"]["2º responsável igual ao 1º (descartado)"] += 1
        s_nome, s_tel = "", None
    if not s_nome and s_tel and s_tel != p_tel:
        R["Cadastro_Familias"]["2º telefone sem nome (mantido como 'Responsável 2')"] += 1
        s_nome = "Responsável 2"
    elif not s_nome and s_tel:
        s_tel = None
    if s_nome and not s_tel:
        R["Cadastro_Familias"]["2º responsável sem telefone"] += 1
    if s_nome and s_tel and s_tel == p_tel:
        R["Cadastro_Familias"]["mesmo telefone para os 2 responsáveis"] += 1
    if not p_tel:
        R["Cadastro_Familias"]["responsável principal sem telefone válido"] += 1
    if f["Termo_LGPD_Aceito"].strip().lower() != "sim":
        R["Cadastro_Familias"]["termo LGPD não aceito"] += 1
    fams[fid] = dict(id=fid, resp=[r for r in [(p_nome, p_tel, True), (s_nome, s_tel, False)] if r[0]],
                     cadastro=datahora(f["Data_Cadastro"]))

# crianças (antes da mescla)
cris, ids_vistos = [], collections.Counter()
for c in cri_raw:
    cid, fid = c["ID_Crianca"].strip(), c["ID_Familia"].strip()
    ids_vistos[cid] += 1
    if TESTE(c["Nome_Crianca"]):
        R["Cadastro_Criancas"]["cadastro de teste (não importado)"] += 1
        continue
    if fid not in fams:
        R["Cadastro_Criancas"]["vínculo órfão (família inexistente)"] += 1
        continue
    nasc = data(c["Data_Nascimento"], "Cadastro_Criancas", "nascimento")
    a = idade(nasc) if nasc else None
    sp, si = sala_planilha(c["Faixa_Etaria"]), sala_por_idade(a)
    if not sp:
        R["Cadastro_Criancas"]["faixa etária fora das 4 salas"] += 1
    if a is not None and a > 12:
        R["Cadastro_Criancas"]["idade acima de 12 anos (revisar)"] += 1
    elif sp and si and sp != si:
        R["Cadastro_Criancas"]["faixa da planilha diferente da idade atual"] += 1
    perfil = "visitante" if c["Perfil"].strip().lower().startswith("visit") else "membro"
    cris.append(dict(codigo=cid if ids_vistos[cid] == 1 else f"{cid}-{ids_vistos[cid]}", fam=fid,
                     nome=nome_limpo(c["Nome_Crianca"]), nasc=nasc, alergia=alergia(c["Alergias_Observacoes"], "Cadastro_Criancas"),
                     foto=c["Foto_URL"].strip() or None, perfil=perfil, sala_planilha=sp))
R["Cadastro_Criancas"]["ID_Crianca repetido (2ª ocorrência recebeu sufixo)"] = sum(v - 1 for v in ids_vistos.values() if v > 1)

# --- mescla de famílias: mesmo telefone em qualquer cadastro
uf = UF()
tel_dono = {}
for f in fams.values():
    uf.f(f["id"])
    for _, t, _ in f["resp"]:
        if t:
            if t in tel_dono:
                uf.u(f["id"], tel_dono[t])
            tel_dono[t] = f["id"]

def primeiro_nome_compat(a, b):
    ta, tb = norm(a).split(), norm(b).split()
    if not ta or not tb or ta[0] != tb[0]:
        return False
    return ta[:len(tb)] == tb or tb[:len(ta)] == ta

# mesma criança (nome + nascimento) em famílias com telefones diferentes
por_crianca = collections.defaultdict(set)
for c in cris:
    if c["nasc"]:
        por_crianca[(norm(c["nome"]), c["nasc"])].add(uf.f(c["fam"]))
entre_familias = [k for k, v in por_crianca.items() if len(v) > 1]
R["Duplicidades"]["mesma criança em cadastros com telefones diferentes (famílias unidas)"] = len(entre_familias)
for k in entre_familias:
    fs = list(por_crianca[k])
    for x in fs[1:]:
        uf.u(x, fs[0])

grupos = collections.defaultdict(list)
for fid in fams:
    grupos[uf.f(fid)].append(fid)
R["Duplicidades"]["cadastros de família repetidos (mesclados)"] = sum(len(g) - 1 for g in grupos.values())

familias = []
for g in grupos.values():
    g.sort(key=lambda x: fams[x]["cadastro"] or dt.datetime.max)
    resp = {}
    contagem_principal = collections.Counter()
    for fid in g:
        for nome, tel, princ in fams[fid]["resp"]:
            chave = tel or norm(nome)
            if princ and tel:
                contagem_principal[chave] += 1
            atual = resp.get(chave)
            if not atual or (len(nome) > len(atual["nome"]) and nome != "Responsável 2"):
                resp[chave] = dict(nome=nome, telefone=tel)
    # remove "sem telefone" que é a mesma pessoa de outro com telefone
    com_tel = {norm(r["nome"]) for r in resp.values() if r["telefone"]}
    resp = {k: r for k, r in resp.items() if r["telefone"] or norm(r["nome"]) not in com_tel}
    principal = contagem_principal.most_common(1)[0][0] if contagem_principal else next(iter(resp))
    lista = [dict(r, principal=(k == principal)) for k, r in resp.items()]
    familias.append(dict(codigo_legado=g[0], mesclados=g[1:], criado_em=fams[g[0]]["cadastro"], responsaveis=lista))
fam_de = {fid: f["codigo_legado"] for f in familias for fid in [f["codigo_legado"]] + f["mesclados"]}

# --- crianças repetidas dentro da família mesclada
por_fam = collections.defaultdict(list)
for c in cris:
    c["fam"] = fam_de[c["fam"]]
    por_fam[c["fam"]].append(c)
criancas, removidas, divergentes = [], 0, 0
for fam, lst in por_fam.items():
    lst.sort(key=lambda c: c["codigo"])
    usados = []
    for c in lst:
        alvo = next((u for u in usados if u["nasc"] == c["nasc"] and c["nasc"] and primeiro_nome_compat(u["nome"], c["nome"])), None)
        if not alvo:
            c["codigos_mesclados"] = []
            usados.append(c)
            continue
        removidas += 1
        if (alvo["alergia"] or "") != (c["alergia"] or "") or alvo["perfil"] != c["perfil"]:
            divergentes += 1
        if len(c["nome"]) > len(alvo["nome"]):
            alvo["nome"] = c["nome"]
        if c["alergia"] and c["alergia"] != alvo["alergia"]:
            alvo["alergia"] = c["alergia"] if not alvo["alergia"] or norm(alvo["alergia"]) in norm(c["alergia"]) else f'{alvo["alergia"]} / {c["alergia"]}'
        if c["perfil"] == "membro":
            alvo["perfil"] = "membro"
        alvo["foto"] = c["foto"] or alvo["foto"]          # foto do cadastro mais recente
        alvo["codigos_mesclados"].append(c["codigo"])
    criancas += usados
R["Duplicidades"]["crianças repetidas (mescladas)"] = removidas
revisar = []
por_nasc = collections.defaultdict(list)
for c in criancas:
    if c["nasc"]:
        por_nasc[c["nasc"]].append(c)
for lst in por_nasc.values():
    for i, a in enumerate(lst):
        for b in lst[i + 1:]:
            if a["fam"] != b["fam"] and primeiro_nome_compat(a["nome"], b["nome"]):
                revisar.append((a["codigo"], a["fam"], b["codigo"], b["fam"]))
R["Duplicidades"]["possível mesma criança em famílias diferentes (NÃO mesclada – revisar)"] = len(revisar)
tam = collections.Counter(len(g) for g in grupos.values())
for n in sorted(tam):
    if n > 1:
        R["Duplicidades"][f"famílias formadas a partir de {n} cadastros"] = tam[n]
R["Duplicidades"]["…das quais com dados diferentes entre as cópias (alergia/perfil)"] = divergentes

# ================================================================= VOLUNTÁRIAS
vol_raw = aba("Cadastro_Professoras")
R["Cadastro_Professoras"]["linhas na planilha"] = len(vol_raw)
NENHUMA = lambda s: not s.strip() or norm(s).startswith("nenhuma")
voluntarias, por_nome_vol = [], {}
emails = collections.Counter(v["Email"].strip().lower() for v in vol_raw if v["Email"].strip())
R["Cadastro_Professoras"]["e-mail compartilhado por mais de 1 voluntária"] = sum(n for n in emails.values() if n > 1)
tels = collections.Counter()
for v in vol_raw:
    nasc = data(v["Data de Nascimento"], "Cadastro_Professoras", "nascimento")
    a = idade(nasc) if nasc else None
    tel = telefone(v["Telefone_WhatsApp"], "Cadastro_Professoras")
    tels[tel] += 1
    salas, rep = [], False
    for col in ["Faixa_Etaria_Atuacao", "Faixa_Etaria_Atuacao_SegundaOpcao", "Faixa_Etaria_Atuacao_TerceiraOpcao", "Faixa_Etaria_Atuacao_QuartaOpcao"]:
        s = sala_planilha(v.get(col, ""))
        if s and s in salas:
            rep = True
        elif s:
            salas.append(s)
        elif not NENHUMA(v.get(col, "")):
            R["Cadastro_Professoras"]["preferência de sala não reconhecida"] += 1
    cultos = []
    for col in ["Culto_Preferido", "Culto_Preferido_SegundaOpcao", "Culto_Preferido_TerceiraOpcao"]:
        k = CULTO_TXT.get(normd(v.get(col, "")))
        if k and k[0] in cultos:
            rep = True
        elif k:
            cultos.append(k[0])
        elif not NENHUMA(v.get(col, "")):
            R["Cadastro_Professoras"]["preferência de culto não reconhecida"] += 1
    if rep:
        R["Cadastro_Professoras"]["preferências repetidas (removida a repetição, ordem mantida)"] += 1
    funcao = "professora" if norm(v["Perfil_Atuacao"]).startswith("prof") else "auxiliar"
    if a is not None and a < 18:
        R["Menores de idade"]["voluntárias menores de 18 anos (sinalizadas)"] += 1
        if a < 16:
            R["Menores de idade"]["…com menos de 16 anos"] += 1
        if funcao == "professora" and a < 16:
            R["Menores de idade"]["…professora com menos de 16 (regra mínima = 16)"] += 1
    prof = v["Profissao"].strip()
    teto = v.get("Teto_Mensal", "").strip()
    reg = dict(codigo_legado=v["ID_Professora"].strip(), nome=nome_limpo(v["Nome_Professora"]), telefone=tel,
               email=v["Email"].strip().lower() or None, nasc=nasc, menor=(a is not None and a < 18),
               sexo={"f": "F", "m": "M"}.get(norm(v["Sexo"])[:1]), profissao=None if norm(prof) in ("", "nenhuma") else prof,
               funcao=funcao, salas=salas, cultos=cultos,
               status="ativa" if norm(v["Status"]).startswith("ativ") else "inativa",
               foto=v["Foto_URL"].strip() or None, teto=int(teto) if teto.isdigit() else None,
               criado_em=datahora(v["Data_Cadastro"]))
    if norm(reg["nome"]) in por_nome_vol:
        R["Cadastro_Professoras"]["voluntária repetida (mesmo nome)"] += 1
        continue
    por_nome_vol[norm(reg["nome"])] = reg
    voluntarias.append(reg)
R["Cadastro_Professoras"]["voluntária repetida (mesmo telefone)"] = sum(n - 1 for t, n in tels.items() if t and n > 1)
R["Cadastro_Professoras"]["com teto mensal próprio"] = sum(1 for v in voluntarias if v["teto"] is not None)

def acha_vol(nome):
    n = norm(nome)
    if n in por_nome_vol:
        return por_nome_vol[n]
    cands = [v for k, v in por_nome_vol.items() if k.startswith(n + " ") or n.startswith(k + " ")]
    return cands[0] if len(cands) == 1 else None

# ================================================================= CULTOS
cultos = {}
def culto(d, hhmm, sec):
    if d is None or not hhmm:
        R[sec]["culto sem data/horário válido"] += 1
        return None
    k = (d.isoformat(), hhmm)
    if k not in cultos:
        rec = {(0, "10:00"): "dom10", (0, "19:00"): "dom19", (2, "20:00"): "ter20"}.get(((d.weekday() + 1) % 7, hhmm))
        if not rec:
            R["Cultos"]["culto fora dos dias/horários fixos"] += 1
        cultos[k] = dict(data=k[0], horario=hhmm, recorrente=rec)
    return k

# ================================================================= INDISPONIBILIDADE
ind_raw = aba("Indisponibilidade")
R["Indisponibilidade"]["linhas (envios) na planilha"] = len(ind_raw)
indisp = set()
for r in ind_raw:
    v = acha_vol(r["Nome_Voluntaria"])
    if not v:
        R["Indisponibilidade"]["envio de voluntária não encontrada (órfão)"] += 1
        continue
    itens = [x.strip() for x in r["Cultos_Indisponiveis"].split(",") if x.strip()]
    if not itens:
        R["Indisponibilidade"]["envio sem nenhuma data (nada a importar)"] += 1
    for x in itens:
        m = re.fullmatch(r"(\d{1,2}/\d{1,2}/\d{4})\s*-\s*(\d{1,2}h)", x)
        d = data(m[1], "Indisponibilidade", "data") if m else None
        if not d:
            R["Indisponibilidade"]["item ilegível"] += 1
            continue
        chave = (v["codigo_legado"], d.isoformat(), HORA_TXT.get(m[2]))
        if chave in indisp:
            R["Indisponibilidade"]["data repetida (enviada mais de uma vez)"] += 1
        indisp.add(chave)
R["Indisponibilidade"]["datas indisponíveis a importar"] = len(indisp)

# ================================================================= ESCALAS
esc_raw = aba("Escala_Mensal")
R["Escala_Mensal"]["linhas na planilha"] = len(esc_raw)
cfg = aba("Config_Escala")
exc = aba("Excecoes_Cultos")
PAPEL = {"lider": "professora", "professora": "professora", "auxiliar": "auxiliar", "reserva": "reserva",
         "lider do culto": "lider_culto"}
escalas, itens = {}, []
for r in esc_raw:
    mm = re.fullmatch(r"(\d{1,2})/(\d{4})", r["Mes_Ano"].strip())
    mes = dt.date(int(mm[2]), int(mm[1]), 1).isoformat()
    escalas.setdefault(mes, dict(mes=mes, status=set()))
    st = norm(r["Status"])
    escalas[mes]["status"].add(st)
    d = data(r["Data_Culto"], "Escala_Mensal", "data do culto")
    k = culto(d, HORA_TXT.get(r["Horario_Culto"].strip()), "Escala_Mensal")
    sala_txt = r["Sala"].strip().lower()
    sala = sala_planilha(sala_txt) or ("7 a 9 anos" if sala_txt == "7 a 12 anos" else None)
    if sala_txt == "7 a 12 anos":
        R["Escala_Mensal"]["vaga na sala combinada 7 a 12 (terça) -> sala 7 a 9 + combinação registrada"] += 1
        cultos[k]["combinada_7_12"] = True
    funcao = PAPEL.get(norm(r["Papel_Vaga"]))
    if not funcao:
        R["Escala_Mensal"]["papel não reconhecido"] += 1
        continue
    if funcao != "lider_culto" and not sala:
        R["Escala_Mensal"]["sala não reconhecida"] += 1
        continue
    nome = r["Nome_Alocado"].strip()
    v = None if norm(nome) in ("", "vazio") else acha_vol(nome)
    if norm(nome) in ("", "vazio"):
        R["Escala_Mensal"]["vaga em aberto (VAZIO)"] += 1
    elif not v:
        R["Escala_Mensal"]["nome que não é voluntária cadastrada (vai como nome livre)"] += 1
    if st == "ciente":
        R["Escala_Mensal"]["vagas com 'Ciente'"] += 1
    if r.get("ID_Calendar", "").strip():
        R["Escala_Mensal"]["vínculo com Google Agenda (descartado)"] += 1
    itens.append(dict(mes=mes, culto=k, sala=None if funcao == "lider_culto" else sala, funcao=funcao,
                      voluntaria=v["codigo_legado"] if v else None,
                      nome_livre=None if v or norm(nome) in ("", "vazio") else nome,
                      resposta="ciente" if st == "ciente" else ("recusado" if st.startswith("recus") else "pendente")))
for e in escalas.values():
    e["status"] = "publicada" if e["status"] & {"oficial", "ciente", "recusado"} else "rascunho"
    e["config_salas"] = None
for c in cfg:
    mm = re.fullmatch(r"(\d{1,2})/(\d{4})", c["Mes_Ano_Alvo"].strip())
    mes = dt.date(int(mm[2]), int(mm[1]), 1).isoformat()
    e = escalas.setdefault(mes, dict(mes=mes, status="rascunho", config_salas=None))
    n = lambda k: int(c.get(k, "0").strip() or 0)
    e["teto"] = n("Teto_Maximo_Cultos") or None
    e["config_salas"] = {
        "0 a 2 anos": (n("Lideres_0_a_2"), n("Aux_0_a_2"), n("Res_0_a_2")),
        "3 a 6 anos": (n("Lideres_3_a_6"), n("Aux_3_a_6"), n("Res_3_a_6")),
        "7 a 9 anos": (n("Lideres_7_a_9"), n("Aux_7_a_9"), n("Res_7_a_9")),
        "10 a 12 anos": (n("Lideres_10_a_12"), n("Aux_10_a_12"), n("Res_10_a_12")),
    }
    e["terca_7_12"] = (n("Terca_7_12_Professora"), n("Terca_7_12_Auxiliar"), n("Terca_7_12_Reserva"))
    if c.get("Cultos_Cancelados_Geral", "").strip():
        R["Config_Escala"]["cultos cancelados no mês (a registrar)"] += 1
R["Config_Escala"]["meses configurados"] = len(cfg)

culto_salas = []
for r in exc:
    d = data(r["Data_Culto"], "Excecoes_Cultos", "data")
    k = culto(d, HORA_TXT.get(r["Horario"].strip()), "Excecoes_Cultos")
    s = sala_planilha(r["Sala_Cancelada"])
    if k and s:
        culto_salas.append(dict(culto=k, sala=s, cancelada=True, combinada=None))
        R["Excecoes_Cultos"]["sala cancelada em culto específico"] += 1
for k, c in cultos.items():
    if c.get("combinada_7_12"):
        culto_salas.append(dict(culto=k, sala="10 a 12 anos", cancelada=False, combinada="7 a 9 anos"))

# ================================================================= HISTÓRICO DE CHECK-IN
hist_raw = aba("Historico_Frequencia")
R["Historico_Frequencia"]["linhas na planilha"] = len(hist_raw)
idx_nome = collections.defaultdict(list)
for c in criancas:
    idx_nome[norm(c["nome"])].append(c)
    for _ in c["codigos_mesclados"]:
        pass
tel_fam = {r["telefone"]: f["codigo_legado"] for f in familias for r in f["responsaveis"] if r["telefone"]}
checkins, vistos, por_mes = [], set(), collections.Counter()
for h in hist_raw:
    ctxt = CULTO_TXT.get(normd(h["Culto_Atual"]))
    dh = datahora(h["Data_Hora_Entrada"])
    if not ctxt or not dh:
        R["Historico_Frequencia"]["sem data ou culto reconhecível"] += 1
        continue
    k = culto(dh.date(), ctxt[2], "Historico_Frequencia")
    por_mes[dh.strftime("%Y-%m")] += 1
    tel = telefone(h["Telefone_WhatsApp"], "_hist_tel")
    fam = tel_fam.get(tel)
    n = norm(h["Nome_Crianca"])
    cands = [c for c in criancas if c["fam"] == fam and (norm(c["nome"]) == n or primeiro_nome_compat(c["nome"], h["Nome_Crianca"]))] if fam else []
    if len(cands) != 1:
        cands = idx_nome.get(n, [])
    if len(cands) != 1:
        R["Historico_Frequencia"]["não foi possível ligar a uma criança cadastrada"] += 1
        continue
    c = cands[0]
    if (k, c["codigo"]) in vistos:
        R["Historico_Frequencia"]["check-in repetido da mesma criança no mesmo culto"] += 1
        continue
    vistos.add((k, c["codigo"]))
    sp = sala_planilha(h["Faixa_Etaria_Sala"])
    if h["Faixa_Etaria_Sala"].strip().lower() == "7 a 12 anos":
        sp = "7 a 9 anos"
    if not sp:
        R["Historico_Frequencia"]["sala ilegível/fora das 4 salas (usada a sala pela idade)"] += 1
        sp = sala_por_idade(idade(c["nasc"], dh.date())) if c["nasc"] else None
    if not sp:
        R["Historico_Frequencia"]["sem sala possível (não importado)"] += 1
        continue
    if dh.hour == 0 and dh.minute == 0:
        R["Historico_Frequencia"]["só data, sem hora (usado o horário do culto)"] += 1
        dh = dt.datetime.combine(dh.date(), dt.time.fromisoformat(ctxt[2]))
    checkins.append(dict(culto=k, crianca=c["codigo"], sala=sp, codigo=h["Codigo_Seguranca"].strip().upper(),
                         entrada=dh.isoformat()))
cods = collections.Counter((x["culto"], x["codigo"]) for x in checkins)
R["Historico_Frequencia"]["código de segurança repetido no mesmo culto"] = sum(n - 1 for n in cods.values() if n > 1)
R["Historico_Frequencia"]["check-ins aproveitáveis"] = len(checkins)
for m, n in sorted(por_mes.items()):
    R["Historico_Frequencia"][f"check-ins em {m}"] = n
R.pop("_hist_tel", None)

# ================================================================= CONFIGURAÇÕES
conf = {r["Parametro"].strip(): r["Valor"] for r in aba("Configuracoes")}
mensagens = {"choro": ("Aviso aos pais (choro)", conf.get("Mensagem_Choro")),
             "telao": ("Aviso no telão", conf.get("Mensagem_Telao")),
             "lembrete_escala": ("Lembrete de escala", conf.get("Mensagem_Lembrete_Escala"))}
configuracoes = {"telefone_midia": (telefone(conf.get("Telefone_Midia"), "Configuracoes"), "WhatsApp do operador do telão"),
                 "capacidade_sala_combinada_terca": (conf.get("Limite_7_12_Terca", "").strip() or None,
                                                     "Lotação da sala combinada 7 a 12 anos (terça)")}
R["Configuracoes"]["PINs antigos (NÃO migrados)"] = sum(1 for k in conf if k.upper().startswith("PIN"))
R["Configuracoes"]["parâmetros que já existem no banco (salas, cultos, dia limite)"] = sum(
    1 for k in conf if k.startswith("Limite_") and k != "Limite_7_12_Terca" or k in ("Cultos_Semana", "Dia_Limite_Escala"))

# ================================================================= SAÍDA
def dstr(x):
    return x.isoformat() if isinstance(x, (dt.date, dt.datetime)) else x
limpo = dict(
    familias=familias, criancas=criancas, voluntarias=voluntarias,
    indisponibilidades=sorted(indisp), cultos=list(cultos.values()),
    culto_salas=[dict(x, culto=list(x["culto"])) for x in culto_salas],
    escalas=list(escalas.values()), escala_itens=[dict(x, culto=list(x["culto"]) if x["culto"] else None) for x in itens],
    checkins=[dict(x, culto=list(x["culto"])) for x in checkins],
    mensagens=mensagens, configuracoes=configuracoes)
json.dump(limpo, open(f"{OUT}/limpo.json", "w"), ensure_ascii=False, default=dstr)
json.dump(dict(revisar_criancas=revisar,
               uniao_por_crianca=[sorted(por_crianca[k]) for k in entre_familias]),
          open(f"{OUT}/revisar_codigos.json", "w"), indent=1)

tot = R["Totais a importar"]
tot["familias"] = len(familias)
tot["responsaveis"] = sum(len(f["responsaveis"]) for f in familias)
tot["termos_lgpd (aceite da planilha)"] = len(familias)
tot["criancas"] = len(criancas)
tot["voluntarias"] = len(voluntarias)
tot["indisponibilidades"] = len(indisp)
tot["cultos"] = len(cultos)
tot["culto_salas"] = len(culto_salas)
tot["escalas (meses)"] = len(escalas)
tot["escala_config_salas"] = sum(4 for e in escalas.values() if e.get("config_salas"))
tot["escala_itens"] = len(itens)
tot["checkins (histórico)"] = len(checkins)
tot["mensagens_whatsapp_modelos"] = sum(1 for v in mensagens.values() if v[1])
tot["configuracoes (novas)"] = sum(1 for v in configuracoes.values() if v[0])
tot["crianças com foto (link antigo do Drive)"] = sum(1 for c in criancas if c["foto"])
tot["voluntárias com foto (link antigo do Drive)"] = sum(1 for v in voluntarias if v["foto"])
json.dump({k: dict(v) for k, v in R.items()}, open(f"{OUT}/relatorio.json", "w"), ensure_ascii=False, indent=1)
for sec, c in R.items():
    print(f"\n## {sec}")
    for k, v in c.items():
        print(f"  {v:>4}  {k}")
