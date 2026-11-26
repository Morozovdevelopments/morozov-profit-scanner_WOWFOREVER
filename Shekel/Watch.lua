-- Избранное и оповещения.
-- Alt+клик по строке с предметом добавляет его в избранное (звёздочка перед названием).
-- Когда после скана или обычного поиска на аукционе предмет из избранного стоит заметно
-- дешевле обычного (меньше 75% обычной цены), аддон пишет в чат и подаёт звук. Не чаще раза в 30 минут на предмет.

local _, ns = ...

local STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:12:12|t"
local CHEAP = 0.75
local alerted = {} -- [itemID] = время последнего оповещения

function ns.IsWatched(id)
	return id and ns.db.watch[id] and true or false
end

function ns.WatchStar(id)
	return ns.IsWatched(id) and (STAR .. " ") or ""
end

function ns.ToggleWatch(id)
	if not id then return end
	if ns.db.watch[id] then
		ns.db.watch[id] = nil
		ns.Print(ns.ColoredName(id) .. " убран из избранного.")
	else
		ns.db.watch[id] = true
		ns.Print(ns.ColoredName(id) .. " в избранном: сообщу, когда будет дешевле обычного.")
	end
	if ns.Refresh then ns.Refresh() end
end

-- Избранное, которое сейчас дешевле обычного: { {id, price, median, qty}, ... }
function ns.WatchDeals()
	local list = {}
	for id in pairs(ns.db.watch) do
		local price, qty, _, src = ns.Price(id)
		local med = ns.Median(id)
		if price and med and src == "скан" and price < med * CHEAP then
			list[#list + 1] = { id = id, price = price, median = med, qty = qty, save = med - price }
		end
	end
	table.sort(list, function(a, b) return a.save > b.save end)
	return list
end

local function Check(acc)
	if not (ns.db.settings.alerts and next(ns.db.watch)) then return end
	local now = time()
	for id, a in pairs(acc) do
		if ns.db.watch[id] and (not alerted[id] or now - alerted[id] > 1800) then
			local med = ns.Median(id)
			if med and a[1] < med * CHEAP then
				alerted[id] = now
				ns.Print(("%s|cff40ff40дёшево:|r %s по %s (обычно %s), %d шт."):format(
					STAR .. " ", ns.ColoredName(id), ns.Money(a[1]), ns.Money(med), a[2]))
				if PlaySound and SOUNDKIT and SOUNDKIT.AUCTION_WINDOW_OPEN then
					pcall(PlaySound, SOUNDKIT.AUCTION_WINDOW_OPEN)
				end
			end
		end
	end
end

-- Проверяем всё, что приходит с аукциона: и полный скан, и обычные поиски.
local store = ns.StoreBrowse
function ns.StoreBrowse(acc, now, full)
	local n = store(acc, now, full)
	local ok, err = pcall(Check, acc)
	if not ok then ns.Print("|cffff4040ошибка оповещения:|r " .. tostring(err)) end
	return n
end
