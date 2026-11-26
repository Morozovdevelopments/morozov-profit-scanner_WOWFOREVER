"""Оценка: сколько полезных для аддона записей о дропе в базе vmangos.

Запуск: python -I tools/survey_vmangos.py data_src/vmangos/sqlite-dump/mangos.sqlite
"""
import sqlite3
import sys
from collections import Counter

MIN_CHANCE = 1.0  # %, ниже этого фармить предмет бессмысленно

db = sqlite3.connect(sys.argv[1])

# Берём последнюю версию (патч) каждого предмета и моба.
items = {}
for entry, name, cls, quality, sell, bonding, stack in db.execute(
    """select entry, name, class, quality, sell_price, bonding, stackable
       from item_template t
       where patch = (select max(patch) from item_template x where x.entry = t.entry)"""
):
    items[entry] = dict(name=name, cls=cls, q=quality, sell=sell, bond=bonding, stack=stack)

# Продаётся на аукционе: не персональный при поднятии (bonding 1) и не квестовый (4), не класс «квест» (12).
def tradable(i):
    it = items.get(i)
    return it and it["bond"] not in (1, 4) and it["cls"] != 12

creatures = {}
for entry, name, lmin, lmax, loot, skin, rank in db.execute(
    """select entry, name, level_min, level_max, loot_id, skinning_loot_id, rank
       from creature_template t
       where patch = (select max(patch) from creature_template x where x.entry = t.entry)"""
):
    creatures[entry] = dict(name=name, lmin=lmin, lmax=lmax, loot=loot, skin=skin, rank=rank)

spawned = {r[0] for r in db.execute("select distinct id from creature")}

def loot_rows(table, entry):
    return db.execute(
        f"""select item, max(ChanceOrQuestChance), mincountOrRef, maxcount
            from {table} where entry = ? group by item, mincountOrRef""",
        (entry,),
    ).fetchall()

pairs = Counter()
item_sources = {}
for cid, c in creatures.items():
    if cid not in spawned or c["rank"] != 0:  # только обычные мобы открытого мира
        continue
    for table, lid in (("creature_loot_template", c["loot"]), ("skinning_loot_template", c["skin"])):
        if not lid:
            continue
        for item, chance, mc, maxc in loot_rows(table, lid):
            if mc < 0 or chance < MIN_CHANCE or not tradable(item):
                continue
            pairs[table] += 1
            item_sources.setdefault(item, []).append((chance, cid))

go_pairs = 0
for (item, chance) in db.execute(
    "select item, max(ChanceOrQuestChance) from gameobject_loot_template where mincountOrRef > 0 group by entry, item"
):
    if chance >= MIN_CHANCE and tradable(item):
        go_pairs += 1

print("моб -> предмет (дроп, шанс >= 1%):", pairs["creature_loot_template"])
print("моб -> предмет (снятие шкур):", pairs["skinning_loot_template"])
print("объекты (руда, трава, сундуки) -> предмет:", go_pairs)
print("разных продаваемых предметов с мобов:", len(item_sources))

# Самые «стабильные» источники: предмет падает с шансом >= 10% хотя бы с одного моба.
good = {i: s for i, s in item_sources.items() if max(s)[0] >= 10}
print("предметов с источником >= 10%:", len(good))
est = sum(len(s) for s in item_sources.values()) * 14  # ~14 байт на запись в Lua
print(f"примерный вес таблицы для аддона: {est / 1024:.0f} КБ")
