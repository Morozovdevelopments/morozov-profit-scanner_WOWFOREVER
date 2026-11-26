-- Обучение по реальному луту: что на самом деле падает на Forever.
--
-- Журнал боя в этом клиенте аддонам закрыт, поэтому убийство считаем по добыче:
-- каждый новый труп (GUID источника добычи) — одно убийство. Если тот же труп открыли снова
-- и там другие предметы — это снятие шкур (или сбор с трупа), пишем отдельно.
-- Трупы без добычи не открываются и не считаются: шансы чуть завышены, это ок для оценки.
--
-- ShekelDB.learn.mobs[npcID]  = { k = убийств, d = {[itemID] = штук}, sk = снятий шкур, s = {[itemID] = штук},
--                                 name, lvl, zone }
-- ShekelDB.learn.nodes[objID] = { k = сборов, d = {[itemID] = штук} }
--
-- Сессия фарма (ns.session) — в памяти: время, убийства, стоимость добычи и монеты.
-- Новая сессия начинается, если 15 минут ничего не добывал.

local _, ns = ...

local issecret = issecretvalue or function() return false end
local IDLE = 15 * 60
local MONEY = Enum.LootSlotType and Enum.LootSlotType.Money or 2

local firstLoot, firstCount = {}, 0 -- [guid] = { [itemID] = true } — что было в трупе при первом открытии

local function Session(now)
	local s = ns.session
	if not s or now - s.last > IDLE then
		s = { start = now, last = now, kills = 0, nodes = 0, value = 0, money = 0, zone = GetRealZoneText and GetRealZoneText() }
		ns.session = s
	end
	s.last = now
	return s
end

function ns.ResetSession()
	ns.session = nil
	if ns.Refresh then ns.Refresh() end
end

local function Parse(guid)
	if type(guid) ~= "string" or issecret(guid) then return end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return kind, tonumber(id)
end

local function ItemID(link)
	if not link or issecret(link) then return end
	if C_Item.GetItemInfoInstant then
		local id = C_Item.GetItemInfoInstant(link)
		if id then return id end
	end
	return tonumber(link:match("item:(%d+)"))
end

-- Имя и уровень моба: если он в цели или под курсором.
local function UnitInfo(guid)
	for _, unit in ipairs({ "target", "mouseover" }) do
		local g = UnitGUID(unit)
		if g and not issecret(g) and g == guid then
			return UnitName(unit), UnitLevel(unit)
		end
	end
end

local function Value(items)
	local v = 0
	for id, q in pairs(items) do v = v + q * ns.UnitValue(id) end
	return v
end

local function Add(map, items)
	for id, q in pairs(items) do map[id] = (map[id] or 0) + q end
end

local moneyBefore

local function OnLoot()
	if not ns.db then return end
	-- Сгруппировать добычу по источникам.
	local sources = {}
	for i = 1, GetNumLootItems() do
		local isMoney = GetLootSlotType and GetLootSlotType(i) == MONEY
		local item = not isMoney and ItemID(GetLootSlotLink(i)) or nil
		local src = { GetLootSourceInfo(i) }
		for j = 1, #src, 2 do
			local guid, q = src[j], src[j + 1]
			if guid and not issecret(guid) then
				local b = sources[guid]
				if not b then
					b = { items = {} }
					sources[guid] = b
				end
				if item then
					q = (q and not issecret(q)) and q or 1
					b.items[item] = (b.items[item] or 0) + q
				end
			end
		end
	end

	local now = time()
	for guid, b in pairs(sources) do
		local kind, id = Parse(guid)
		local first = firstLoot[guid]
		if (kind == "Creature" or kind == "Vehicle") and id then
			local L = ns.db.learn.mobs
			local m = L[id]
			if not m then
				m = { k = 0, d = {}, sk = 0, s = {} }
				L[id] = m
			end
			if not first then
				local set = {}
				for item in pairs(b.items) do set[item] = true end
				firstLoot[guid], firstCount = set, firstCount + 1
				m.k = m.k + 1
				Add(m.d, b.items)
				local name, lvl = UnitInfo(guid)
				if name then m.name, m.lvl = name, lvl end
				m.zone = GetRealZoneText and GetRealZoneText() or m.zone
				local s = Session(now)
				s.kills = s.kills + 1
				s.value = s.value + Value(b.items)
			elseif next(b.items) then
				-- Тот же труп ещё раз: если предметы те же — это недобранная добыча, иначе — шкуры.
				local same = false
				for item in pairs(b.items) do
					if first[item] then same = true end
				end
				if not same then
					m.sk = m.sk + 1
					Add(m.s, b.items)
					for item in pairs(b.items) do first[item] = true end
					local s = Session(now)
					s.value = s.value + Value(b.items)
				end
			end
		elseif kind == "GameObject" and id and not first then
			firstLoot[guid], firstCount = {}, firstCount + 1
			local N = ns.db.learn.nodes
			local n = N[id]
			if not n then
				n = { k = 0, d = {} }
				N[id] = n
			end
			n.k = n.k + 1
			Add(n.d, b.items)
			local s = Session(now)
			s.nodes = s.nodes + 1
			s.value = s.value + Value(b.items)
		end
	end
	if firstCount > 3000 then firstLoot, firstCount = {}, 0 end -- не копим бесконечно
	moneyBefore = GetMoney()
end

ns.On("LOOT_READY", function()
	local ok, err = pcall(OnLoot)
	if not ok then ns.Print("|cffff4040ошибка учёта добычи:|r " .. tostring(err)) end
end)

-- Монеты: всё, что пришло, пока открыто окно добычи.
ns.On("LOOT_CLOSED", function()
	if moneyBefore and ns.session then
		local delta = GetMoney() - moneyBefore
		if delta > 0 then ns.session.money = ns.session.money + delta end
	end
	moneyBefore = nil
	if ns.Refresh then ns.Refresh() end
end)

-- Текст для вкладки «Фарм».
function ns.SessionText()
	local s = ns.session
	if not s then return "Сессия фарма начнётся с первой добычи: аддон посчитает золото в час." end
	local minutes = math.max(1, math.floor((time() - s.start) / 60))
	local total = s.value + s.money
	local perHour = total / minutes * 60
	local what = s.kills .. " убийств"
	if s.nodes > 0 then what = what .. ", " .. s.nodes .. " узлов" end
	return ("Сессия: %d мин, %s, добыто ~%s  =  |cffffd200%s в час|r"):format(minutes, what, ns.Money(total), ns.Money(perHour))
end
