-- Фарм. Три режима:
--   «Ресурсы» (главный) — что выгодно добывать: предмет, цена, спрос, лучшее место добычи, «за 100 убийств»;
--   «Мобы» — сколько в среднем приносит одно убийство;
--   «Трава и руда» — сколько приносит один узел.
-- Цена добычи честная: аукцион за вычетом 5% или торговец — что выгоднее, но белое и серое оружие
-- и броня — только по цене торговца: такие вещи на аукционе висят, но их не покупают.
-- Шансы — из базы классики (Data/Loot.lua), постепенно уточняются по реальной добыче игрока (Learn.lua).
-- Зону моба берём из QuestieDB (там данные Forever), если он установлен.

local _, ns = ...

local SKILL_HERB, SKILL_MINE, SKILL_SKIN = 182, 186, 393
local LEARN_WEIGHT = 15 -- после 15 убийств свои данные весят столько же, сколько база

-- Навыки сбора персонажа: [skillLine] = уровень.
function ns.GatherSkills()
	local skills = {}
	if not GetProfessions then return skills end
	local ok, p1, p2 = pcall(GetProfessions)
	if not ok then return skills end
	for _, idx in ipairs({ p1, p2 }) do
		if idx then
			local ok2, _, _, level, _, _, _, line = pcall(GetProfessionInfo, idx)
			if ok2 and line then skills[line] = level end
		end
	end
	return skills
end

-- Белое или серое оружие/броня: на аукционе их не покупают, честная цена — у торговца.
function ns.IsJunkGear(id)
	local iq = ns.IQ and ns.IQ[id]
	local class, quality
	if iq then
		class, quality = iq[1], iq[2]
	else
		if C_Item and C_Item.GetItemInfoInstant then class = select(6, C_Item.GetItemInfoInstant(id)) end
		quality = ns.db.quality[id]
	end
	return (class == 2 or class == 4) and quality ~= nil and quality <= 1
end

-- Цена одной штуки добычи и откуда она.
function ns.UnitValue(id)
	local sell = ns.VendorSell(id)
	if ns.IsJunkGear(id) then return sell or 0, sell and "торговец" or nil end
	local p = ns.SellPrice(id)
	local ah = p and p * (1 - ns.AH_CUT)
	if ah and (not sell or ah >= sell) then return ah, "аукцион" end
	if sell and sell > 0 then return sell, "торговец" end
	return 0, nil
end
local UnitValue = ns.UnitValue

local zoneCache = {}
function ns.MobZone(id)
	local z = zoneCache[id]
	if z ~= nil then return z or nil end
	z = false
	if NpcDB and NpcDB.zoneID then
		local ok, area = pcall(NpcDB.zoneID, id)
		if ok and area and C_Map and C_Map.GetAreaInfo then
			local name = C_Map.GetAreaInfo(area)
			if name and name ~= "" then z = name end
		end
	end
	zoneCache[id] = z
	return z or nil
end
local MobZone = ns.MobZone

function ns.FarmLevelRange()
	local s = ns.db.settings
	local lvl = UnitLevel and UnitLevel("player") or 60
	return s.farmMin or math.max(1, lvl - 10), s.farmMax or (lvl + 2)
end

local function LevelText(lmin, lmax)
	return (lmin == lmax) and tostring(lmin) or (lmin .. "-" .. lmax)
end

-- Сколько штук предмета в среднем за убийство: база классики, уточнённая своей добычей.
local function PerKill(mobID, itemID, baseChance, baseCnt)
	local base = (baseChance or 0) / 100 * (baseCnt or 1)
	local L = ns.db.learn.mobs[mobID]
	if L and L.k >= 3 then
		local obs = (L.d[itemID] or 0) / L.k
		local w = L.k / (L.k + LEARN_WEIGHT)
		return w * obs + (1 - w) * base
	end
	return base
end

-- Сумма по добыче моба: стоимость, самый ценный предмет, его шанс %, список частей.
local function MobLoot(mobID, drops, wantParts)
	local total, best, bestValue, bestChance, parts = 0, nil, -1, 0, wantParts and {} or nil
	local seen = {}
	for i = 1, #drops, 3 do
		local id = drops[i]
		seen[id] = true
		local per = PerKill(mobID, id, drops[i + 1], drops[i + 2])
		local unit, from = UnitValue(id)
		local v = per * unit
		total = total + v
		if parts then parts[#parts + 1] = { id = id, per = per, unit = unit, from = from, value = v } end
		if v > bestValue then best, bestValue, bestChance = id, v, per * 100 end
	end
	-- То, что выпадало игроку, а в базе классики этого нет.
	local L = ns.db.learn.mobs[mobID]
	if L and L.k >= 3 then
		for id in pairs(L.d) do
			if not seen[id] then
				local per = PerKill(mobID, id, 0, 1)
				local unit, from = UnitValue(id)
				local v = per * unit
				total = total + v
				if parts then parts[#parts + 1] = { id = id, per = per, unit = unit, from = from, value = v } end
				if v > bestValue then best, bestValue, bestChance = id, v, per * 100 end
			end
		end
	end
	return total, best, bestChance, parts
end

---------------------------------------------------------------------------
-- Режим «Ресурсы»: строки — предметы
---------------------------------------------------------------------------

-- Где падает каждый предмет: [itemID] = { { mob = id или node = id, chance, cnt }, ... }
local sources
local function Sources()
	if sources then return sources end
	sources = {}
	local function add(id, src)
		local list = sources[id]
		if not list then
			list = {}
			sources[id] = list
		end
		list[#list + 1] = src
	end
	for mob, m in pairs(ns.MOBS or {}) do
		local drops = m[5]
		for i = 1, #drops, 3 do add(drops[i], { mob = mob, chance = drops[i + 1], cnt = drops[i + 2] }) end
	end
	for node, n in pairs(ns.NODES or {}) do
		local drops = n[2]
		for i = 1, #drops, 3 do add(drops[i], { node = node, chance = drops[i + 1], cnt = drops[i + 2] }) end
	end
	return sources
end

-- Описание источника для строк и подсказок (nil — не подходит по уровню).
local function SourceInfo(src, itemID, minL, maxL, skills)
	if src.mob then
		local m = ns.MOBS[src.mob]
		if not m or m[2] < minL or m[1] > maxL then return end
		return {
			name = m[7], where = MobZone(src.mob), lvl = m[1], lvlText = LevelText(m[1], m[2]),
			per = PerKill(src.mob, itemID, src.chance, src.cnt), kind = "mob",
		}
	end
	local n = ns.NODES[src.node]
	if not n then return end
	local isHerb = n[1] == "H"
	local have = skills[isHerb and SKILL_HERB or SKILL_MINE]
	return {
		name = n[3], where = isHerb and "Травничество" or "Горное дело", lvl = n[4], lvlText = "навык " .. n[4],
		per = src.chance / 100 * src.cnt, kind = "node", canGather = have and have >= n[4],
	}
end

function ns.FarmItemRows()
	local rows = {}
	local minL, maxL = ns.FarmLevelRange()
	local skills = ns.GatherSkills()
	for id, list in pairs(Sources()) do
		local price = not ns.IsJunkGear(id) and ns.SellPrice(id)
		if price then -- только то, что реально продаётся на аукционе
			local unit = UnitValue(id)
			local bestInfo
			for _, src in ipairs(list) do
				local info = SourceInfo(src, id, minL, maxL, skills)
				if info and (not bestInfo or info.per > bestInfo.per) then bestInfo = info end
			end
			if bestInfo and bestInfo.per > 0 then
				rows[#rows + 1] = {
					kind = "item", id = id, label = ns.db.names[id] or "",
					price = price, demand = ns.Demand(id),
					where = bestInfo.name,
					whereText = bestInfo.name .. (bestInfo.where and ("|cff808080, " .. bestInfo.where .. "|r") or ""),
					lvl = bestInfo.lvl, lvlText = bestInfo.lvlText, chance = bestInfo.per * 100,
					per100 = bestInfo.per * 100 * unit, sources = list,
				}
			end
		end
	end
	return rows
end

function ns.FarmItemTooltip(row, tip)
	tip:SetItemByID(row.id) -- обычное окно предмета + строки «Шекеля» с ценой и спросом
	local minL, maxL = ns.FarmLevelRange()
	local skills = ns.GatherSkills()
	local unit = UnitValue(row.id)
	local list = {}
	for _, src in ipairs(row.sources) do
		local info = SourceInfo(src, row.id, minL, maxL, skills)
		if info and info.per > 0 then list[#list + 1] = info end
	end
	table.sort(list, function(a, b) return a.per > b.per end)
	tip:AddLine(" ")
	tip:AddLine(("Где добыть на уровнях %d-%d:"):format(minL, maxL), 1, 0.82, 0)
	for i = 1, math.min(6, #list) do
		local s = list[i]
		local extra = (s.kind == "node" and not s.canGather) and " |cffff8040(нет навыка)|r" or ""
		tip:AddDoubleLine(("%s |cff808080%s%s|r%s"):format(s.name, s.lvlText, s.where and (", " .. s.where) or "", extra),
			ns.FormatQty(s.per * 100) .. "%", 1, 1, 1, 1, 1, 1)
	end
	if #list > 6 then tip:AddLine(("... и ещё %d мест"):format(#list - 6), 0.6, 0.6, 0.6) end
	local best = list[1]
	if best then
		local what = best.kind == "mob" and "убийств" or "узлов"
		tip:AddLine(" ")
		tip:AddLine(("За 100 %s: ~%s шт. = %s"):format(what, ns.FormatQty(best.per * 100), ns.Money(best.per * 100 * unit)), 0.4, 1, 0.4)
	end
	tip:AddLine("Клик - найти на аукционе", 0.6, 0.6, 0.6)
end

---------------------------------------------------------------------------
-- Режимы «Мобы» и «Трава и руда»
---------------------------------------------------------------------------

function ns.FarmRows()
	local s = ns.db.settings
	if s.farmMode == "items" then return ns.FarmItemRows() end
	local rows = {}
	local skills = ns.GatherSkills()
	if s.farmMode == "nodes" then
		local byName = {}
		for id, n in pairs(ns.NODES or {}) do
			local kind, drops, name, need = n[1], n[2], n[3], n[4]
			local have = skills[(kind == "H") and SKILL_HERB or SKILL_MINE]
			if not s.farmMySkill or (have and have >= need) then
				local value, bestId, bestChance = MobLoot(-id, drops)
				local cur = byName[name]
				if not cur or value > cur.value then
					byName[name] = {
						kind = "node", node = id, label = name, labelText = name,
						lvl = need, lvlText = "навык " .. need,
						zone = (kind == "H") and "Травничество" or "Горное дело",
						value = value, id = bestId, best = bestId, bestChance = bestChance,
						drops = drops, have = have, need = need,
					}
				end
			end
		end
		for _, r in pairs(byName) do rows[#rows + 1] = r end
		return rows
	end

	local minL, maxL = ns.FarmLevelRange()
	local skinning = skills[SKILL_SKIN]
	local learned = ns.db.learn.mobs
	for id, m in pairs(ns.MOBS or {}) do
		local lmin, lmax = m[1], m[2]
		if lmax >= minL and lmin <= maxL then
			local lootValue, bestId, bestChance = MobLoot(id, m[5])
			local skinValue = (#m[6] > 0) and MobLoot(-id, m[6]) or 0
			local value = m[3] + m[4] + lootValue + (skinning and skinValue or 0)
			rows[#rows + 1] = {
				kind = "mob", mob = id, label = m[7], labelText = m[7],
				lvl = lmin, lvlText = LevelText(lmin, lmax),
				zone = MobZone(id), value = value, gold = m[3], trash = m[4], spawns = m[8],
				skinValue = skinValue, skinning = skinning,
				id = bestId, best = bestId, bestChance = bestChance, drops = m[5],
				learnK = learned[id] and learned[id].k or 0, learned = learned[id],
			}
		end
	end
	-- Мобы, которых нет в базе классики (новые мобы Forever): только по своим данным.
	for id, L in pairs(learned) do
		if not (ns.MOBS and ns.MOBS[id]) and L.k >= 3 then
			local lvl = L.lvl
			if not lvl or (lvl >= minL and lvl <= maxL) then
				local value, bestId, bestChance = MobLoot(id, {})
				local name = L.name
				if not name and NpcDB and NpcDB.name then
					local ok, n = pcall(NpcDB.name, id)
					if ok then name = n end
				end
				name = name or ("Моб #" .. id)
				rows[#rows + 1] = {
					kind = "mob", mob = id, label = name, labelText = name .. " |cff40ff40(новый)|r",
					lvl = lvl or 0, lvlText = lvl and tostring(lvl) or "?",
					zone = MobZone(id) or L.zone, value = value, drops = {},
					id = bestId, best = bestId, bestChance = bestChance,
					learnK = L.k, learned = L, onlyLearned = true,
				}
			end
		end
	end
	return rows
end

-- Подсказка моба или узла: только главное.
function ns.FarmTooltip(row, tip)
	tip:SetText(row.labelText, 1, 0.82, 0)
	if row.kind == "mob" then
		local spawns = row.spawns and (", в мире " .. row.spawns) or ""
		tip:AddLine(("Уровень %s%s%s"):format(row.lvlText, row.zone and (", " .. row.zone) or "", spawns), 1, 1, 1)
	else
		local have = row.have and ("у тебя " .. row.have) or "у тебя нет этой профессии"
		tip:AddLine(("%s, нужен навык %d (%s)"):format(row.zone, row.need, have), 1, 1, 1)
	end
	local _, _, _, parts = MobLoot(row.kind == "mob" and row.mob or -row.node, row.drops, true)
	table.sort(parts, function(a, b) return a.value > b.value end)
	tip:AddLine(" ")
	tip:AddLine("Самое ценное:", 1, 0.82, 0)
	local shown = 0
	for _, p in ipairs(parts) do
		if shown >= 5 or p.value <= 0 then break end
		shown = shown + 1
		local where = p.from == "торговец" and " |cff808080торговцу|r" or ""
		tip:AddDoubleLine(("%s |cff808080%s%%|r"):format(ns.ColoredName(p.id), ns.FormatQty(p.per * 100)),
			ns.Money(p.unit) .. " за шт." .. where, 1, 1, 1, 1, 1, 1)
	end
	tip:AddLine(" ")
	local what = row.kind == "mob" and "убийство" or "узел"
	tip:AddDoubleLine("В среднем за " .. what, ns.Money(row.value), 1, 0.82, 0, 1, 1, 1)
	tip:AddLine(("За 100 %s ~%s"):format(row.kind == "mob" and "убийств" or "узлов", ns.Money(row.value * 100)), 0.4, 1, 0.4)
	if row.kind == "mob" and row.skinValue and row.skinValue > 0 and not row.skinning then
		tip:AddLine(("Со снятием шкур было бы ещё ~%s за убийство."):format(ns.Money(row.skinValue)), 0.6, 0.6, 0.6, true)
	end
	if row.onlyLearned then
		tip:AddLine(("Нового моба нет в базе классики: доход по твоим %d убийствам."):format(row.learnK), 0.6, 0.6, 0.6, true)
	elseif row.learnK and row.learnK >= 3 then
		tip:AddLine(("Уточнено по твоим %d убийствам."):format(row.learnK), 0.6, 0.6, 0.6, true)
	end
end
