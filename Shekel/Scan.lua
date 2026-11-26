-- Скан аукциона обычным поиском: пустой запрос и подгрузка страниц, пока сервер не отдаст всё.
-- Полный снимок (C_AuctionHouse.ReplicateItems) в Forever сервер не присылает, поэтому его не используем.
-- Каждая строка результата — предмет с минимальной ценой за штуку и общим количеством.
-- Результаты чужих поисков (свои клики по аукциону, Auctionator) тоже запоминаем.

local _, ns = ...

local scan = { state = "idle", token = 0, items = 0 } -- idle / scanning
ns.scan = scan
local TIMEOUT = 30 -- секунд без ответа сервера — считаем скан прерванным

function ns.SetStatus(text)
	scan.status = text
	if ns.UpdateStatus then ns.UpdateStatus() end
end

function ns.ScanCooldownLeft() return 0 end

local function Ready()
	return not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
end

-- Сервер ограничивает частоту запросов: ждём, пока он снова готов.
local function WhenReady(token, fn)
	if scan.token ~= token then return end
	if Ready() then
		fn()
	else
		C_Timer.After(0.2, function() WhenReady(token, fn) end)
	end
end

-- Свести строки результата в { [itemID] = { мин. цена, штук } }.
local function Collect(results, into)
	local added = 0
	for _, r in ipairs(results or {}) do
		local id = r.itemKey and r.itemKey.itemID
		local qty, price = r.totalQuantity, r.minPrice
		if id and qty and qty > 0 and price and price > 0 then
			local a = into[id]
			if not a then
				a = { price, 0 }
				into[id] = a
				added = added + 1
			end
			if price < a[1] then a[1] = price end
			a[2] = a[2] + qty
		end
	end
	return added
end

local function Fail(reason)
	scan.token = scan.token + 1
	scan.state = "idle"
	ns.SetStatus("|cffff4040Скан прерван:|r " .. reason)
	if ns.Refresh then ns.Refresh() end
end

local function Finish()
	local count, units = 0, 0
	for _, a in pairs(scan.acc) do
		count = count + 1
		units = units + a[2]
	end
	ns.StoreBrowse(scan.acc, time(), true)
	local ids = {}
	for id in pairs(scan.acc) do ids[#ids + 1] = id end
	ns.WarmNames(ids) -- названия новых предметов подтянутся в фоне
	scan.state = "idle"
	scan.token = scan.token + 1
	scan.acc = nil
	ns.SetStatus(("|cff40ff40Готово:|r отсканировано %d предметов (%d шт. на аукционе)."):format(count, units))
	ns.Print(("скан готов: %d предметов, %d шт."):format(count, units))
	if ns.Refresh then ns.Refresh() end
end

local function Next()
	local token = scan.token
	scan.lastEvent = GetTime()
	ns.SetStatus(("Сканирую аукцион: получено %d предметов..."):format(scan.items))
	if C_AuctionHouse.HasFullBrowseResults() then
		Finish()
	else
		WhenReady(token, function() C_AuctionHouse.RequestMoreBrowseResults() end)
	end
end

function ns.StartScan()
	if not ns.ahOpen then
		ns.Print("сначала открой аукцион.")
		return
	end
	if scan.state ~= "idle" then return end
	scan.token = scan.token + 1
	local token = scan.token
	scan.state = "scanning"
	scan.acc = {}
	scan.items = 0
	scan.started = time()
	scan.lastEvent = GetTime()
	scan.expected = ns.House().lastCount -- сколько предметов было в прошлый раз, для полосы загрузки
	ns.SetStatus("Сканирую аукцион: отправляю запрос...")
	WhenReady(token, function()
		C_AuctionHouse.SendBrowseQuery({ searchString = "", sorts = {}, filters = {}, itemClassFilters = {} })
	end)
	-- Сторож: если сервер замолчал, не висим вечно.
	local function Watch()
		if scan.token ~= token or scan.state ~= "scanning" then return end
		if GetTime() - scan.lastEvent > TIMEOUT then
			Fail("сервер не отвечает " .. TIMEOUT .. " секунд. Попробуй ещё раз.")
		else
			C_Timer.After(1, Watch)
		end
	end
	C_Timer.After(1, Watch)
	if ns.Refresh then ns.Refresh() end
end

-- Доля готовности для полосы загрузки (0..1) или nil, если скан не идёт.
function ns.ScanProgress()
	if scan.state ~= "scanning" then return nil end
	if scan.expected and scan.expected > 0 then return math.min(0.97, scan.items / scan.expected) end
	return nil -- первый скан: сколько всего — неизвестно
end

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED", function()
	local results = C_AuctionHouse.GetBrowseResults()
	if scan.state == "scanning" then
		-- В событии "обновлено" лежит весь список, полученный на этот момент.
		scan.acc = {}
		scan.items = Collect(results, scan.acc)
		Next()
	else
		local acc = {}
		if Collect(results, acc) > 0 then ns.StoreBrowse(acc, time(), false) end
	end
end)

ns.On("AUCTION_HOUSE_BROWSE_RESULTS_ADDED", function(added)
	if scan.state == "scanning" then
		scan.items = scan.items + Collect(added, scan.acc)
		Next()
	else
		local acc = {}
		if Collect(added, acc) > 0 then ns.StoreBrowse(acc, time(), false) end
	end
end)

ns.On("AUCTION_HOUSE_SHOW", function()
	ns.ahOpen = true
	if ns.OnAuctionHouse then ns.OnAuctionHouse(true) end
	-- Автоскан: если последнему скану больше часа (настраивается), сканируем сами.
	local s = ns.db.settings
	local last = ns.House().lastScan
	if s.autoScan and (not last or time() - last > (s.autoScanMinutes or 60) * 60) then
		C_Timer.After(1.5, function()
			if ns.ahOpen and scan.state == "idle" then
				ns.Print("последний скан устарел - сканирую сам. Выключить: /shekel autoscan")
				ns.StartScan()
			end
		end)
	end
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
	ns.ahOpen = false
	if scan.state ~= "idle" then Fail("аукцион закрыли во время скана.") end
	if ns.OnAuctionHouse then ns.OnAuctionHouse(false) end
end)
