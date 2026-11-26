-- Рецепты: читаются из окна профессии, когда игрок его открывает.
-- Свои выученные рецепты идут в ShekelCharDB.recipes ("мои").
-- Все рецепты из окна — свои невыученные и чужие (по ссылке из чата) — идут в общую
-- копилку ShekelDB.seen: так в базу попадают и новые рецепты Forever, которых нет в vmangos.

local _, ns = ...

local function ProfessionName()
	if C_TradeSkillUI.GetBaseProfessionInfo then
		local info = C_TradeSkillUI.GetBaseProfessionInfo()
		if info and info.professionName and info.professionName ~= "" then return info.professionName end
	end
	if C_TradeSkillUI.GetTradeSkillLine then
		local _, name = C_TradeSkillUI.GetTradeSkillLine()
		if name and name ~= "" then return name end
	end
end

function ns.CurrentProfession()
	local ok, name = pcall(ProfessionName)
	return ok and name or nil
end

local function IsForeign()
	local T = C_TradeSkillUI
	return (T.IsTradeSkillLinked and T.IsTradeSkillLinked())
		or (T.IsTradeSkillGuild and T.IsTradeSkillGuild())
		or (T.IsNPCCrafting and T.IsNPCCrafting())
end

local BASIC = Enum.CraftingReagentType and Enum.CraftingReagentType.Basic

local function ReadRecipe(id)
	local info = C_TradeSkillUI.GetRecipeInfo(id)
	if not info then return end
	local s = C_TradeSkillUI.GetRecipeSchematic(id, false)
	if not (s and s.outputItemID) then return end -- чары и прочее без предмета на выходе
	local qmin = s.quantityMin or 1
	local qmax = s.quantityMax or qmin
	local reagents = {}
	for _, slot in ipairs(s.reagentSlotSchematics or {}) do
		local basic
		if BASIC then basic = slot.reagentType == BASIC else basic = slot.required end
		local first = slot.reagents and slot.reagents[1]
		if basic and first and first.itemID then
			reagents[#reagents + 1] = { first.itemID, slot.quantityRequired or 1 }
		end
	end
	if #reagents == 0 then return end
	return { name = info.name, out = s.outputItemID, qty = (qmin + qmax) / 2, r = reagents }, info.learned
end

local lastCount = {}

local function ReadProfession()
	local foreign = IsForeign()
	local prof = ProfessionName()
	local ids = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs()
	if not (prof and ids and #ids > 0) then return end

	local found, seenNew = {}, 0
	for _, id in ipairs(ids) do
		local ok, rc, learned = pcall(ReadRecipe, id)
		if ok and rc then
			rc.prof = prof
			if not ns.db.seen[id] and not (ns.BASE_RECIPES and ns.BASE_RECIPES[id]) then seenNew = seenNew + 1 end
			ns.db.seen[id] = rc
			if learned and not foreign then found[id] = rc end
		end
	end
	if seenNew > 0 then
		ns.Print(("новых рецептов, которых не было в базе: %d (%s)."):format(seenNew, prof))
	end
	if foreign then
		if ns.Refresh then ns.Refresh() end
		return
	end
	-- Заменяем рецепты этой профессии целиком: так уходят и разученные.
	local recipes = ns.char.recipes
	for id, rc in pairs(recipes) do
		if rc.prof == prof then recipes[id] = nil end
	end
	local n = 0
	for id, rc in pairs(found) do
		recipes[id] = rc
		n = n + 1
	end
	if lastCount[prof] ~= n then
		lastCount[prof] = n
		ns.Print(("запомнил рецептов: %d (%s)."):format(n, prof))
	end
	if ns.Refresh then ns.Refresh() end
end

local pending = false
local function Schedule()
	if pending then return end
	pending = true
	C_Timer.After(0.5, function()
		pending = false
		local ok, err = pcall(ReadProfession)
		if not ok then ns.Print("|cffff4040не смог прочитать профессию:|r " .. tostring(err)) end
	end)
end

ns.On("TRADE_SKILL_SHOW", Schedule)
ns.On("TRADE_SKILL_LIST_UPDATE", Schedule)
