"""Собирает Shekel/Data/Recipes.lua — все рецепты профессий из базы vmangos.

Запуск: python -I tools/build_recipes.py data_src/vmangos/sqlite-dump/mangos.sqlite Shekel/Data/Recipes.lua

В таблицу попадают рецепты, которые создают предмет (эффект 24). Ключ — id заклинания рецепта,
он совпадает с recipeID в C_TradeSkillUI, поэтому рецепты, прочитанные в игре, заменяют базовые.
"""
import sqlite3
import sys

SKILLS = {  # id навыка -> название профессии в русском клиенте
    164: "Кузнечное дело",
    165: "Кожевничество",
    171: "Алхимия",
    197: "Портняжное дело",
    202: "Инженерное дело",
    333: "Наложение чар",
    185: "Кулинария",
    129: "Первая помощь",
    186: "Горное дело",
}
MAX_BUILD = 5875  # 1.12.1

db = sqlite3.connect(sys.argv[1])


def latest(table, key="entry"):
    """Последняя версия строки (по столбцу build) для каждой записи."""
    return f"""select * from {table} t where build = (
        select max(build) from {table} x where x.{key} = t.{key} and x.build <= {MAX_BUILD})"""


spell_cols = [r[1] for r in db.execute("pragma table_info(spell_template)")]
spells = {}
for row in db.execute(latest("spell_template")):
    s = dict(zip(spell_cols, row))
    spells[s["entry"]] = s

# Обучающее заклинание -> рецепт (эффект 36 «выучить заклинание»).
teaches = {}
for sid, s in spells.items():
    for i in (1, 2, 3):
        if s[f"effect{i}"] == 36 and s[f"effectTriggerSpell{i}"]:
            teaches[sid] = s[f"effectTriggerSpell{i}"]

# Учителя.
by_trainer = set()
for (spell,) in db.execute(f"select distinct spell from npc_trainer where build_min <= {MAX_BUILD}"):
    by_trainer.add(teaches.get(spell, spell))

# Чертежи и выкройки: предмет, который учит рецепт.
by_item = {}
for entry, s1, s2 in db.execute(
    """select entry, spellid_1, spellid_2 from item_template t
       where patch = (select max(patch) from item_template x where x.entry = t.entry)"""
):
    for s in (s1, s2):
        if s and s != 483:
            recipe = teaches.get(s, s)
            by_item.setdefault(recipe, entry)

rows = []
seen = set()
for spell_id, skill_id, req, auto in db.execute(
    f"""select spell_id, skill_id, req_skill_value, learn_on_get_skill from skill_line_ability
        where build <= {MAX_BUILD} order by build desc"""
):
    if skill_id not in SKILLS or spell_id in seen:
        continue
    s = spells.get(spell_id)
    if not s:
        continue
    out = None
    for i in (1, 2, 3):
        if s[f"effect{i}"] == 24 and s[f"effectItemType{i}"]:
            out, i_out = s[f"effectItemType{i}"], i
            break
    if not out:
        continue
    reagents = []
    for i in range(1, 9):
        if s[f"reagent{i}"] and s[f"reagentCount{i}"]:
            reagents += [s[f"reagent{i}"], s[f"reagentCount{i}"]]
    if not reagents:
        continue
    bp, dice = s[f"effectBasePoints{i_out}"], s[f"effectDieSides{i_out}"]
    qmin, qmax = bp + 1, bp + max(dice, 1)
    if auto == 1 or spell_id in by_trainer:
        src = '"T"'  # учитель или выдаётся сам
    elif spell_id in by_item:
        src = str(by_item[spell_id])  # id предмета-рецепта
    else:
        src = "nil"
    seen.add(spell_id)
    rows.append((skill_id, req or 1, spell_id, out, qmin, qmax, reagents, src))

rows.sort()

# Цены торговцев: всё, что продаётся у NPC с бесконечным запасом (maxcount = 0).
vendor_items = set()
for table in ("npc_vendor", "npc_vendor_template"):
    for (item,) in db.execute(f"select distinct item from {table} where maxcount = 0"):
        vendor_items.add(item)
vendor = {}
for entry, price, count in db.execute(
    """select entry, buy_price, buy_count from item_template t
       where patch = (select max(patch) from item_template x where x.entry = t.entry)"""
):
    if entry in vendor_items and price and price > 0:
        vendor[entry] = round(price / max(count or 1, 1), 2)
# В файл берём только то, что встречается как реагент.
reagent_ids = {r for row in rows for r in row[6][0::2]}
vendor = {k: v for k, v in vendor.items() if k in reagent_ids}

with open(sys.argv[2], "w", encoding="utf-8", newline="\n") as f:
    f.write("-- Создано tools/build_recipes.py из базы vmangos. Не править вручную.\n")
    f.write("-- [рецепт] = { навык, нужный уровень, предмет, выход мин, выход макс, {реагент, кол-во, ...}, источник }\n")
    f.write("-- источник: \"T\" — учитель, число — предмет-рецепт, nil — неизвестно.\n")
    f.write("local _, ns = ...\n\n")
    f.write("ns.SKILL_NAMES = {\n")
    for k, v in SKILLS.items():
        f.write(f'\t[{k}] = "{v}",\n')
    f.write("}\n\nns.BASE_RECIPES = {\n")
    for skill, req, sid, out, qmin, qmax, reagents, src in rows:
        f.write(f"\t[{sid}]={{{skill},{req},{out},{qmin},{qmax},{{{','.join(map(str, reagents))}}},{src}}},\n")
    f.write("}\n\n-- [предмет] = цена за штуку у торговца, медь\nns.BASE_VENDOR = {\n")
    for k in sorted(vendor):
        v = vendor[k]
        f.write(f"\t[{k}]={int(v) if v == int(v) else v},\n")
    f.write("}\n")
print("реагентов у торговцев:", len(vendor))

from collections import Counter
cnt = Counter(r[0] for r in rows)
print("рецептов:", len(rows))
for k, v in sorted(cnt.items()):
    print(" ", SKILLS[k], v)
print("с источником-учителем:", sum(1 for r in rows if r[7] == '"T"'),
      "с предметом-рецептом:", sum(1 for r in rows if r[7] not in ('"T"', "nil")),
      "без источника:", sum(1 for r in rows if r[7] == "nil"))
