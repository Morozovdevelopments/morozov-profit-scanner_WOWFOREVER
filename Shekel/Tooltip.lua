-- Строки «Шекеля» в подсказке любого предмета: цена на аукционе, обычная цена, спрос,
-- сколько даст торговец и откуда предмет падает. Выключается: /shekel tooltip.

local _, ns = ...

-- Лучший источник предмета в базе классики: моб с самым высоким шансом.
local bestSource
local function BestSource(id)
	if not bestSource then
		bestSource = {}
		for mob, m in pairs(ns.MOBS or {}) do
			local drops = m[5]
			for i = 1, #drops, 3 do
				local item, chance = drops[i], drops[i + 1]
				local cur = bestSource[item]
				if not cur or chance > cur[2] then bestSource[item] = { mob, chance } end
			end
		end
	end
	return bestSource[id]
end

local function AddLines(tip, id)
	local price, qty, age, src = ns.Price(id)
	local med = ns.Median(id)
	local demand = ns.Demand(id)
	local sell = ns.VendorSell(id)
	local source = BestSource(id)
	if not (price or sell or source) then return end

	tip:AddLine(" ")
	if price then
		local where = src == "скан" and (qty .. " шт., " .. ns.Age(age) .. " назад")
			or (src == "нет на аукционе" and "сейчас нет на аукционе") or src
		tip:AddDoubleLine("|cffffd200Шекель:|r аукцион", ns.Money(price) .. " |cff808080(" .. where .. ")|r", 1, 1, 1, 1, 1, 1)
		local flag = ns.PriceFlag(id)
		if med and flag then
			local text = flag == "high" and "сейчас задрана, обычно" or "сейчас дёшево, обычно"
			tip:AddDoubleLine("   " .. text, ns.Money(med), 1, 0.5, 0.25, 1, 1, 1)
		end
	end
	if demand then
		tip:AddDoubleLine("   уходит с аукциона", "~" .. ns.FormatQty(demand) .. " шт. в день", 0.7, 0.7, 0.7, 1, 1, 1)
	end
	if sell and sell > 0 then
		tip:AddDoubleLine("   торговец даст", ns.Money(sell), 0.7, 0.7, 0.7, 1, 1, 1)
	end
	if source then
		local m = ns.MOBS[source[1]]
		local lvl = (m[1] == m[2]) and tostring(m[1]) or (m[1] .. "-" .. m[2])
		tip:AddDoubleLine("   падает", ("%s (%s) %g%%"):format(m[7], lvl, source[2]), 0.7, 0.7, 0.7, 1, 1, 1)
	end
end

if TooltipDataProcessor and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tip, data)
		if tip ~= GameTooltip and tip ~= ItemRefTooltip then return end
		if ns.ownTooltip or not ns.db or not ns.db.settings.tooltip then return end
		local id = data and data.id
		if type(id) ~= "number" or (issecretvalue and issecretvalue(id)) then return end
		local ok, err = pcall(AddLines, tip, id)
		if not ok and not ns.tooltipErrorShown then
			ns.tooltipErrorShown = true
			ns.Print("|cffff4040ошибка в подсказке:|r " .. tostring(err))
		end
	end)
end

function ns.ToggleTooltip()
	local s = ns.db.settings
	s.tooltip = not s.tooltip
	ns.Print(s.tooltip and "цены в подсказках предметов включены." or "цены в подсказках предметов выключены. Вернуть: /shekel tooltip")
end
