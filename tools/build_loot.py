"""Собирает Shekel/Data/Loot.lua — что падает с мобов и узлов сбора, из базы vmangos.

Запуск: python -I tools/build_loot.py data_src/vmangos/sqlite-dump/mangos.sqlite Shekel/Data/Loot.lua

Мобы: только обычные (rank 0), которые есть в мире. Для каждого:
  уровень, средние монеты, стоимость серого хлама у торговца (шанс x кол-во x цена продажи),
  предметы, которые можно продать на аукционе (шанс от 0.5%), и отдельно добыча со шкур.
Узлы: трава и руда (сундуки-объекты, в добыче которых есть трава или руда/камень).
Шанс в группах лута с нулевым шансом делится поровну между записями группы.
"""
import sqlite3
import sys
from collections import defaultdict

MIN_CHANCE = 0.5
db = sqlite3.connect(sys.argv[1])


def latest(table, key="entry", col="patch"):
    return f"select * from {table} t where {col} = (select max({col}) from {table} x where x.{key} = t.{key})"


def rows_as_dicts(sql):
    cur = db.execute(sql)
    cols = [d[0] for d in cur.description]
    for r in cur:
        yield dict(zip(cols, r))


items = {r["entry"]: r for r in rows_as_dicts(latest("item_template"))}


def tradable(i):
    it = items.get(i)
    return bool(it) and it["bonding"] not in (1, 4) and it["class"] != 12 and it["quality"] >= 1


def loot(table):
    """entry -> [(item, шанс %, среднее кол-во)] с раскрытием групп. Ссылки на общий лут пропускаем."""
    by_entry = defaultdict(list)
    for entry, item, chance, group, mincount, maxcount in db.execute(
        f"select entry, item, max(ChanceOrQuestChance), groupid, mincountOrRef, maxcount from {table} "
        "group by entry, item, groupid"
    ):
        if mincount < 0 or chance < 0:  # ссылка на другой лут или квестовый предмет
            continue
        by_entry[entry].append([item, chance, group, (mincount + maxcount) / 2])
    out = {}
    for entry, lst in by_entry.items():
        groups = defaultdict(list)
        for row in lst:
            if row[2]:
                groups[row[2]].append(row)
        for g in groups.values():
            explicit = sum(r[1] for r in g if r[1] > 0)
            zero = [r for r in g if r[1] == 0]
            for r in zero:
                r[1] = max(0.0, 100 - explicit) / len(zero)
        out[entry] = [(r[0], r[1], r[3]) for r in lst]
    return out


creature_loot = loot("creature_loot_template")
skin_loot = loot("skinning_loot_template")
go_loot = loot("gameobject_loot_template")

spawn_count = defaultdict(int)  # сколько точек появления у моба в мире
for (cid,) in db.execute("select id from creature"):
    spawn_count[cid] += 1
spawned = set(spawn_count)
ru_names = {e: n for e, n in db.execute("select entry, name_loc8 from locales_creature") if n}

mobs = []
sell = {}
for c in rows_as_dicts(latest("creature_template")):
    cid = c["entry"]
    if cid not in spawned or c["rank"] != 0 or c["level_max"] < 2:
        continue
    gold = (c["gold_min"] + c["gold_max"]) / 2
    trash = 0.0
    drops = []
    for item, chance, cnt in creature_loot.get(c["loot_id"], []) if c["loot_id"] else []:
        it = items.get(item)
        if not it:
            continue
        if tradable(item) and chance >= MIN_CHANCE:
            drops.append((item, round(chance, 2), cnt))
            sell[item] = it["sell_price"]
        elif it["quality"] == 0:
            trash += chance / 100 * cnt * it["sell_price"]
    skins = []
    for item, chance, cnt in skin_loot.get(c["skinning_loot_id"], []) if c["skinning_loot_id"] else []:
        if tradable(item) and chance >= MIN_CHANCE:
            skins.append((item, round(chance, 2), cnt))
            sell[item] = items[item]["sell_price"]
    if not drops and not skins and gold < 1:
        continue
    mobs.append((cid, c["level_min"], c["level_max"], round(gold), round(trash), drops, skins,
                 ru_names.get(cid) or c["name"], spawn_count[cid]))

# Узлы сбора. В этой базе у травы и руды одинаковый класс предмета, поэтому:
# руда — объект с "Vein"/"Deposit" в названии, трава — объект, из которого падает ванильная трава.
HERBS = {765, 785, 2447, 2449, 2450, 2452, 2453, 3355, 3356, 3357, 3358, 3369, 3818, 3819, 3820, 3821,
         4625, 8831, 8836, 8838, 8839, 8845, 8846, 13463, 13464, 13465, 13466, 13467, 13468}
# Нужный навык сбора по главному предмету узла (ванильные значения).
NODE_SKILL = {
    2770: 1, 2771: 65, 3340: 65, 2775: 75, 4278: 75, 2772: 125, 5833: 150, 2776: 155, 3858: 175,
    7911: 230, 11370: 230, 10620: 245,
    2447: 1, 765: 1, 2449: 15, 785: 50, 2450: 70, 3820: 85, 2453: 100, 3355: 115, 3369: 120,
    3356: 125, 3357: 150, 3818: 160, 3821: 170, 3358: 185, 3819: 195, 4625: 205, 8831: 210,
    8836: 220, 8838: 230, 8839: 235, 8845: 245, 8846: 250, 13464: 260, 13463: 270, 13465: 280,
    13466: 285, 13467: 290, 13468: 300,
}
go_names = {e: n for e, n in db.execute("select entry, name_loc8 from locales_gameobject") if n}
go_spawned = {r[0] for r in db.execute("select distinct id from gameobject")}
nodes = []
for g in rows_as_dicts(latest("gameobject_template")):
    if g["type"] != 3 or not g["data1"] or g["entry"] not in go_spawned:
        continue
    contents = go_loot.get(g["data1"], [])
    kind = None
    if "Vein" in g["name"] or "Deposit" in g["name"]:
        kind = "M"
    elif any(i in HERBS and ch >= 50 for i, ch, _ in contents):  # у сундуков трава случайная и редкая
        kind = "H"
    if not kind:
        continue
    drops = [(i, round(ch, 2), cnt) for i, ch, cnt in contents if tradable(i) and ch >= MIN_CHANCE]
    for i, _, _ in drops:
        sell[i] = items[i]["sell_price"]
    if drops:
        main = max(contents, key=lambda r: r[1])[0]
        skill = NODE_SKILL.get(main, 0)
        if main == 10620 and "Rich" in g["name"]:
            skill = 275
        nodes.append((g["entry"], kind, drops, go_names.get(g["entry"]) or g["name"], skill))


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def lua_drops(drops):
    flat = []
    for item, chance, cnt in drops:
        flat += [str(item), f"{chance:g}", f"{cnt:g}"]
    return "{" + ",".join(flat) + "}"


with open(sys.argv[2], "w", encoding="utf-8", newline="\n") as f:
    f.write("-- Создано tools/build_loot.py из базы vmangos. Не править вручную.\n")
    f.write("-- MOBS[id] = { ур. мин, ур. макс, монеты (медь), серый хлам (медь), {предмет, шанс %, кол-во, ...}, {шкуры ...}, имя, сколько в мире }\n")
    f.write("-- NODES[id] = { \"H\" трава / \"M\" руда, {предмет, шанс %, кол-во, ...}, имя, нужный навык }\n")
    f.write("local _, ns = ...\n\nns.MOBS = {\n")
    for cid, lmin, lmax, gold, trash, drops, skins, name, spawns in mobs:
        f.write(f"\t[{cid}]={{{lmin},{lmax},{gold},{trash},{lua_drops(drops)},{lua_drops(skins)},{lua_str(name)},{spawns}}},\n")
    f.write("}\n\nns.NODES = {\n")
    for gid, kind, drops, name, skill in nodes:
        f.write(f'\t[{gid}]={{"{kind}",{lua_drops(drops)},{lua_str(name)},{skill}}},\n')
    f.write("}\n\n-- [предмет] = цена продажи торговцу, медь\nns.SELL = {\n")
    for i in sorted(sell):
        f.write(f"\t[{i}]={sell[i]},\n")
    f.write("}\n")
    # Класс и качество: белое/серое оружие и броню не считаем по цене аукциона (их никто не покупает).
    f.write("\n-- [предмет] = { класс (2 оружие, 4 броня, 7 материалы, 0 расходники...), качество (0 серое, 1 белое, 2 зелёное...) }\nns.IQ = {\n")
    for i in sorted(sell):
        f.write(f"\t[{i}]={{{items[i]['class']},{items[i]['quality']}}},\n")
    f.write("}\n")

print("mobs", len(mobs), "nodes", len(nodes), "items", len(sell))
