-- Перепродажа торговцу: лоты на аукционе, которые стоят дешевле, чем за них платит торговец.
-- Купил лот — сразу продал торговцу. Комиссии при покупке нет, поэтому прибыль = торговец − цена.
-- Цена с аукциона — самый дешёвый лот; сколько штук продаётся по этой цене, скан не говорит,
-- поэтому по клику на строку открывается поиск — там видны все лоты.

local _, ns = ...

function ns.FlipRows()
	local rows = {}
	local h = ns.House()
	local minProfit = ns.db.settings.flipMinProfit or 0
	for id, r in pairs(h.items) do
		local fresh = not h.lastScan or (r.t and r.t >= h.lastScan)
		if fresh and r.qty and r.qty > 0 then
			local sell = ns.GameSell(id)
			if sell and sell > 0 and r.mkt and r.mkt < sell then
				-- Проверено поиском после последнего скана: знаем точно, сколько дешёвых штук осталось.
				local fc = r.fc
				local checked = fc and fc.t >= (h.lastScan or 0)
				local row
				if checked then
					if fc.qty > 0 then
						row = {
							id = id, buy = fc.cost / fc.qty, qty = fc.qty, lot = fc.profit, checked = true,
						}
					end
				else
					-- До проверки знаем только самый дешёвый лот: гарантирована прибыль хотя бы с одной штуки.
					-- Сколько дешёвых штук на самом деле — покажет поиск (у «товаров» их бывает много).
					row = { id = id, buy = r.mkt, qty = r.qty, lot = sell - r.mkt }
				end
				if row and row.lot >= minProfit then
					row.label, row.sell, row.age = ns.db.names[id] or "", sell, time() - r.t
					row.profit = sell - row.buy
					row.pct = row.profit / row.buy * 100
					rows[#rows + 1] = row
				end
			end
		end
	end
	return rows
end

function ns.FlipTooltip(row, tip)
	tip:AddLine(" ")
	tip:AddDoubleLine("Купить на аукционе", ns.Money(row.buy), 1, 1, 1, 1, 1, 1)
	tip:AddDoubleLine("Продать торговцу", ns.Money(row.sell), 1, 1, 1, 1, 1, 1)
	tip:AddDoubleLine("Прибыль с каждой штуки", ns.Money(row.profit), 1, 0.82, 0, 1, 1, 1)
	if row.checked then
		tip:AddDoubleLine(("Проверено: дешёвых %d шт., прибыль за всё"):format(row.qty), ns.Money(row.lot), 0.4, 1, 0.4, 1, 1, 1)
	else
		tip:AddDoubleLine("Гарантированно - с одной штуки", ns.Money(row.lot), 0.7, 0.7, 0.7, 1, 1, 1)
		tip:AddLine(("Выставлено всего %d шт., но дешёвые среди них - неизвестно. Поиск (Выкупить выбранное) "
			.. "покажет точно: у руды, ткани и еды дешёвых бывает много."):format(row.qty), 0.6, 0.6, 0.6, true)
	end
	tip:AddLine(" ")
	tip:AddLine("Цена - самый дешёвый лот на момент скана (" .. ns.Age(row.age) .. " назад). "
		.. "Его могли уже купить, а остальные лоты могут быть дороже: клик откроет поиск.", 0.6, 0.6, 0.6, true)
end
