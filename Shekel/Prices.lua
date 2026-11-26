-- Цены: снимки аукциона, история по дням, честная цена, спрос, цены торговцев.
--
-- Запись предмета: h.items[itemID] = {
--   min/mkt = минимальная цена за штуку, qty = штук на аукционе, t = когда видели,
--   h = { [номер дня] = цена } — история за 30 дней,
--   s = { {время, штук}, ... } — количество на каждом полном скане (для спроса), до 40 точек
-- }

local _, ns = ...

local SNAPSHOTS = 40

function ns.House()
	if not ns.houseKey then ns.houseKey = ns.HouseKey() end
	local h = ns.db.houses[ns.houseKey]
	if not h then
		h = { items = {} }
		ns.db.houses[ns.houseKey] = h
	end
	return h
end

function ns.Record(id)
	return ns.db and ns.House().items[id]
end

local function Snapshot(r, now, qty)
	r.s = r.s or {}
	local last = r.s[#r.s]
	if last and last[1] == now then
		last[2] = qty
	else
		r.s[#r.s + 1] = { now, qty }
	end
	while #r.s > SNAPSHOTS do table.remove(r.s, 1) end
end

-- Принимает результат поиска по аукциону: acc[itemID] = { мин. цена за штуку, штук }.
-- full = true — это полный скан: он задаёт момент, с которым сравнивается свежесть цен,
-- и пишет точку количества для оценки спроса (у пропавших предметов — 0 штук).
function ns.StoreBrowse(acc, now, full)
	local h = ns.House()
	local today = math.floor(now / ns.DAY)
	local items = 0
	for id, a in pairs(acc) do
		local r = h.items[id]
		if not r then
			r = { h = {} }
			h.items[id] = r
		end
		r.min, r.mkt, r.qty, r.t = a[1], a[1], a[2], now
		r.h[today] = math.min(r.h[today] or a[1], a[1])
		for day in pairs(r.h) do
			if day < today - ns.HISTORY_DAYS then r.h[day] = nil end
		end
		if full then Snapshot(r, now, a[2]) end
		items = items + 1
	end
	if full then
		for id, r in pairs(h.items) do
			if not acc[id] and r.s and #r.s > 0 then Snapshot(r, now, 0) end
		end
		h.lastScan = now
		h.lastCount = items
	end
	return items
end

local function AuctionatorPrice(id)
	if not (ns.db.settings.useAuctionator and Auctionator and Auctionator.API and Auctionator.API.v1) then return end
	local ok, price = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "Shekel", id)
	if not ok or not price then return end
	local okAge, days = pcall(Auctionator.API.v1.GetAuctionAgeByItemID, "Shekel", id)
	return price, (okAge and days) and days * ns.DAY or nil
end

-- Текущая цена на аукционе (самый дешёвый лот).
-- Возвращает: цена за штуку, штук на аукционе (nil — неизвестно), возраст в секундах, источник.
function ns.Price(id)
	local h = ns.House()
	local r = h.items[id]
	if r and (not h.lastScan or r.t >= h.lastScan) then return r.mkt, r.qty, time() - r.t, "скан" end
	if r then return r.mkt, 0, time() - r.t, "нет на аукционе" end
	local p, age = AuctionatorPrice(id)
	if p then return p, nil, age, "Auctionator" end
end

-- Обычная цена: медиана дневных цен за 14 дней без сегодняшнего. Нужно хотя бы 3 дня истории.
function ns.Median(id)
	local r = ns.Record(id)
	if not (r and r.h) then return end
	local today = math.floor(time() / ns.DAY)
	local list = {}
	for day, p in pairs(r.h) do
		if day < today and day >= today - 14 then list[#list + 1] = p end
	end
	if #list < 3 then return end
	table.sort(list)
	local n = #list
	if n % 2 == 1 then return list[(n + 1) / 2] end
	return (list[n / 2] + list[n / 2 + 1]) / 2
end

-- Пометка цены: "high" — сейчас вдвое дороже обычного (похоже на лот-прикол),
-- "low" — вдвое дешевле обычного (демпинг или выгодная покупка).
function ns.PriceFlag(id)
	local cur, med = ns.Price(id), ns.Median(id)
	if not (cur and med and med > 0) then return end
	if cur > med * 2 then return "high" end
	if cur < med * 0.5 then return "low" end
end

-- Цена, по которой реально получится продать: если сейчас цена задрана — берём обычную.
function ns.SellPrice(id)
	local cur, qty, age, src = ns.Price(id)
	if not cur then return end
	local med = ns.Median(id)
	if med and cur > med * 2 then return med, qty, age, "обычная цена (сейчас задрана)" end
	return cur, qty, age, src
end

-- Сколько штук уходит с аукциона в день: сумма уменьшений количества между полными сканами.
-- Сюда попадают и снятые/истёкшие лоты, поэтому это оценка сверху. nil — мало данных.
function ns.Demand(id)
	local r = ns.Record(id)
	local s = r and r.s
	if not (s and #s >= 2) then return end
	local span = s[#s][1] - s[1][1]
	if span < 3 * 3600 then return end -- меньше трёх часов наблюдений — слишком мало
	local gone = 0
	for i = 2, #s do
		local d = s[i - 1][2] - s[i][2]
		if d > 0 then gone = gone + d end
	end
	return gone / (span / ns.DAY)
end

-- Сколько стоит достать реагент: дешевле из торговца и аукциона.
function ns.Cost(id)
	local vendor = ns.db.vendor[id] or (ns.BASE_VENDOR and ns.BASE_VENDOR[id]) -- увиденное в игре важнее базы
	local ah = ns.Price(id)
	if vendor and (not ah or vendor <= ah) then return vendor, "торговец" end
	if ah then return ah, "аукцион" end
end

-- Сколько торговец платит на Forever — только то, что сообщила сама игра (без базы классики).
-- Для перепродажи нужна именно эта цена: экономика Forever отличается от классики.
function ns.GameSell(id)
	return ns.db.sell[id]
end

-- Сколько торговец платит за предмет. Из сохранённого, из базы классики или из данных игры.
function ns.VendorSell(id)
	local v = ns.db.sell[id]
	if v then return v end
	return ns.SELL and ns.SELL[id]
end

-- Изменение цены за days дней, в процентах.
function ns.Change(id, days)
	local r = ns.Record(id)
	if not (r and r.h and r.mkt) then return end
	local today = math.floor(time() / ns.DAY)
	for d = today - days, today - days - 3, -1 do -- берём ближайший день, где был скан
		local old = r.h[d]
		if old and old > 0 then return (r.mkt - old) / old * 100 end
	end
end

-- Торговцы: запоминаем цены вещей с бесконечным запасом (нитки, флаконы и т. п.).
local GetMerchantItemInfo = GetMerchantItemInfo or function(index)
	local info = C_MerchantFrame.GetItemInfo(index)
	if info then
		return info.name, info.texture, info.price, info.stackCount, info.numAvailable,
			info.isPurchasable, info.isUsable, info.hasExtendedCost
	end
end

local function ReadMerchant()
	for i = 1, GetMerchantNumItems() do
		local id = GetMerchantItemID(i)
		if id then
			local _, _, price, stack, available, _, _, extended = GetMerchantItemInfo(i)
			if price and price > 0 and not extended and available == -1 then
				ns.db.vendor[id] = price / math.max(stack or 1, 1)
			end
		end
	end
end

ns.On("MERCHANT_SHOW", function() C_Timer.After(0.3, ReadMerchant) end)
ns.On("MERCHANT_UPDATE", ReadMerchant)
