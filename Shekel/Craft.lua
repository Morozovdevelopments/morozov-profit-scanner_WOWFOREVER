-- Прибыль крафта: купить реагенты (у торговца или на аукционе), скрафтить, продать на аукционе.
-- Прибыль = цена продажи x выход x (1 - комиссия 5%) - стоимость реагентов.
--
-- Рецепты берутся из трёх мест, следующее важнее предыдущего:
--   1) ns.BASE_RECIPES — все рецепты из базы vmangos (Data/Recipes.lua);
--   2) ShekelDB.seen — увиденные в окне профессии в игре (в т. ч. новые рецепты Forever);
--   3) ShekelCharDB.recipes — выученные этим персонажем ("мои").

local _, ns = ...

-- Короткие названия профессий для столбца таблицы.
local SHORT = {
	["Кузнечное дело"] = "Кузнечное", ["Портняжное дело"] = "Портняжное", ["Инженерное дело"] = "Инженерное",
	["Наложение чар"] = "Чары", ["Первая помощь"] = "Первая помощь", ["Горное дело"] = "Горное",
}
function ns.ShortProf(name) return SHORT[name] or name end

local function FromBase(id, b)
	local r = {}
	for i = 1, #b[6], 2 do r[#r + 1] = { b[6][i], b[6][i + 1] } end
	return {
		prof = ns.SKILL_NAMES[b[1]] or "?", skill = b[2], out = b[3],
		qty = (b[4] + b[5]) / 2, r = r, source = b[7],
	}
end

-- Все известные рецепты: [recipeID] = { prof, out, qty, r, skill?, source?, name?, mine? }
function ns.AllRecipes()
	local all = {}
	for id, b in pairs(ns.BASE_RECIPES or {}) do all[id] = FromBase(id, b) end
	for id, rc in pairs(ns.db.seen) do
		local base = all[id]
		all[id] = {
			prof = rc.prof, out = rc.out, qty = rc.qty, r = rc.r, name = rc.name,
			skill = base and base.skill, source = base and base.source, isNew = not base,
		}
	end
	for id, rc in pairs(ns.char.recipes) do
		local cur = all[id] or {}
		all[id] = {
			prof = rc.prof, out = rc.out, qty = rc.qty, r = rc.r, name = rc.name,
			skill = cur.skill, source = cur.source, isNew = cur.isNew, mine = true,
		}
	end
	return all
end

-- Список профессий, встречающихся в рецептах (для фильтра).
function ns.ProfessionList()
	local set, list = {}, {}
	-- В режиме "мои" — только профессии этого персонажа.
	local source = (ns.db.settings.craftMode == "mine") and ns.char.recipes or ns.AllRecipes()
	for _, rc in pairs(source) do
		if rc.prof and not set[rc.prof] then
			set[rc.prof] = true
			list[#list + 1] = rc.prof
		end
	end
	table.sort(list)
	return list
end

function ns.CraftRows()
	local s = ns.db.settings
	local rows = {}
	for recipeID, rc in pairs(ns.AllRecipes()) do
		if (s.craftMode ~= "mine" or rc.mine) and (not s.craftProf or s.craftProf == rc.prof) then
			local sellUnit, onAH, age, src = ns.SellPrice(rc.out)
			local cost, missing, parts = 0, false, {}
			for _, r in ipairs(rc.r) do
				local unit, from = ns.Cost(r[1])
				parts[#parts + 1] = { id = r[1], n = r[2], unit = unit, from = from }
				if unit then cost = cost + unit * r[2] else missing = true end
			end
			local row = {
				id = rc.out, recipe = recipeID, name = rc.name, prof = rc.prof, skill = rc.skill,
				source = rc.source, mine = rc.mine, isNew = rc.isNew, qty = rc.qty,
				parts = parts, cost = (not missing) and cost or nil, missing = missing,
				onAH = onAH, age = age, src = src, sellUnit = sellUnit,
				demand = ns.Demand(rc.out), flag = ns.PriceFlag(rc.out),
				profKey = (rc.mine and "0" or "1") .. (rc.prof or "") .. string.format("%04d", rc.skill or 0),
			}
			if sellUnit and not missing then
				row.sell = sellUnit * rc.qty * (1 - ns.AH_CUT)
				row.profit = row.sell - cost
				row.margin = cost > 0 and row.profit / cost * 100 or nil
			end
			rows[#rows + 1] = row
		end
	end
	return rows
end

function ns.PassesFilter(row)
	local s = ns.db.settings
	if not row.profit then return s.showNoPrice end -- не хватает цены продажи или реагента
	if row.profit >= s.minProfit and (row.margin or 0) >= s.minMargin then return true end
	return s.showLoss -- ниже порогов, в т. ч. в минус
end

-- Текст столбца "Профессия": зелёный — рецепт знаешь, серый — нет.
function ns.ProfCell(row)
	local text = ns.ShortProf(row.prof or "?")
	if row.skill and row.skill > 1 then text = text .. " " .. row.skill end
	return (row.mine and "|cff40ff40" or "|cffa0a0a0") .. text .. "|r"
end

local function SourceText(row)
	if row.mine then return "|cff40ff40ты знаешь этот рецепт|r" end
	if row.source == "T" then return "у учителя профессии" end
	if type(row.source) == "number" then
		local price = ns.Price(row.source)
		return ns.ColoredName(row.source) .. (price and (" — на аукционе " .. ns.Money(price)) or "")
	end
	if row.isNew then return "новый рецепт Forever (увиден в игре)" end
	return "|cff808080неизвестно|r"
end

-- Подсказка к строке крафта: из чего складывается цена.
function ns.CraftTooltip(row, tip)
	tip:AddLine(" ")
	local skill = (row.skill and row.skill > 1) and (", навык от " .. row.skill) or ""
	tip:AddLine((row.prof or "?") .. skill, 1, 0.82, 0)
	tip:AddDoubleLine("Рецепт:", SourceText(row), 0.8, 0.8, 0.8, 1, 1, 1)
	tip:AddLine(" ")
	for _, p in ipairs(row.parts) do
		local cost = p.unit and ns.Money(p.unit * p.n) or "|cffff4040нет цены|r"
		tip:AddDoubleLine(("%d x %s"):format(p.n, ns.ColoredName(p.id)),
			cost .. (p.from and (" |cff808080" .. p.from .. "|r") or ""), 1, 1, 1, 1, 1, 1)
	end
	tip:AddDoubleLine("Себестоимость", ns.Money(row.cost), 1, 1, 1, 1, 1, 1)
	local qty = row.qty ~= 1 and (" x " .. row.qty) or ""
	tip:AddDoubleLine("Продажа" .. qty .. " - 5% комиссии", ns.Money(row.sell), 1, 1, 1, 1, 1, 1)
	tip:AddDoubleLine("Прибыль", ns.Money(row.profit), 1, 0.82, 0, 1, 1, 1)
	if row.src then
		tip:AddDoubleLine("Цена продажи", row.src .. ", " .. ns.Age(row.age), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6)
	end
	if row.demand then
		tip:AddDoubleLine("Уходит с аукциона", ("~%s шт. в день"):format(ns.FormatQty(row.demand)), 0.6, 0.6, 0.6, 1, 1, 1)
	else
		tip:AddLine("Спрос пока неизвестен: нужно несколько сканов в разное время.", 0.6, 0.6, 0.6, true)
	end
	if row.flag == "low" then
		tip:AddLine("Цена продажи сейчас вдвое ниже обычной: кто-то демпингует.", 1, 0.5, 0.25, true)
	end
	-- Хватит ли реагентов на аукционе на один крафт.
	for _, p in ipairs(row.parts) do
		if p.from == "аукцион" then
			local _, have = ns.Price(p.id)
			if have and have < p.n then
				tip:AddLine(("На аукционе всего %d шт. %s - остальное дороже или нет."):format(have, ns.ItemName(p.id)), 1, 0.5, 0.25, true)
			end
		end
	end
	tip:AddLine(" ")
	tip:AddLine("Правый клик - список покупок на несколько крафтов.", 0.6, 0.6, 0.6)
end
