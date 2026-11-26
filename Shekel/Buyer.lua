-- Выкуп для перепродажи торговцу.
--
-- 1. Поиск: по каждому выбранному предмету — все лоты дешевле цены торговца (свои лоты пропускаем).
-- 2. Окно расчёта: сколько лотов, сколько потратишь, сколько даст торговец, прибыль; можно задать предел трат.
-- 3. Покупка: игра разрешает покупку только по клику игрока, поэтому одна кнопка «Купить следующий»:
--    один клик — один лот. «Товары» (руда, ткань — общий стакан) покупаются в два клика:
--    первый спрашивает у сервера точную цену, второй подтверждает. Если цена выросла выше торговой — отменяем.
-- 4. Продажа: у торговца кнопка «Продать купленное» продаёт только то, что куплено здесь
--    (ShekelDB.flipBought[itemID] = штук), и только целые стопки, чтобы не задеть свои вещи.
-- Купленное на аукционе приходит на почту: перед торговцем нужно забрать почту.

local _, ns = ...

ns.flipSel = {} -- [itemID] = true — отмечено во вкладке «Торговцу»

-- Журнал сделок: ShekelDB.flipLog = { {время, "buy"/"sell", itemID, штук, деньги, ожидалось}, ... }, до 300 записей.
-- buy: деньги = сколько заплатил, ожидалось = сколько должен дать торговец;
-- sell: деньги = сколько реально пришло (по кошельку), ожидалось = по цене торговца.
function ns.FlipLog(kind, id, qty, money, expected)
	local log = ns.db.flipLog
	log[#log + 1] = { time(), kind, id, qty, money, expected }
	while #log > 300 do table.remove(log, 1) end
end

function ns.FlipReport()
	local spent, expected, got, buys, sells = 0, 0, 0, 0, 0
	for _, e in ipairs(ns.db.flipLog) do
		if e[2] == "buy" then
			spent, expected, buys = spent + e[5], expected + (e[6] or 0), buys + 1
		else
			got, sells = got + e[5], sells + 1
		end
	end
	ns.Print(("сделок: куплено лотов %d на %s (торговец должен дать %s), продаж %d - пришло %s. Итог: %s")
		:format(buys, ns.Money(spent), ns.Money(expected), sells, ns.Money(got), ns.Money(got - spent)))
	local pending = 0
	for _, n in pairs(ns.db.flipBought) do pending = pending + n end
	if pending > 0 then ns.Print(("ещё не продано: %d шт. (может, лежит на почте)"):format(pending)) end
end

local B = { state = "idle", token = 0, queue = {}, lots = {}, idx = 1, spent = 0, profit = 0, bought = 0, budget = 0 }
local frame, statusText, sumText, buyBtn, skipBtn, budgetBox, lines
local SORTS = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
local MAX_LINES = 8

function ns.FlipSelectedCount()
	local n = 0
	for _ in pairs(ns.flipSel) do n = n + 1 end
	return n
end

local function Ready()
	return not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady()
end

local Render -- объявлена ниже

---------------------------------------------------------------------------
-- Поиск лотов
---------------------------------------------------------------------------

-- Запомнить на записи предмета, что реально нашлось: r.fc = { t, qty, cost, profit }.
-- По этим данным вкладка «Торговцу» убирает пустые строки и показывает точную прибыль без нового скана.
local function SaveChecked()
	local now, agg = time(), {}
	for _, lot in ipairs(B.lots) do
		local a = agg[lot.id] or { qty = 0, cost = 0, profit = 0 }
		agg[lot.id] = a
		a.qty, a.cost, a.profit = a.qty + lot.qty, a.cost + lot.total, a.profit + lot.sell * lot.qty - lot.total
	end
	for _, id in ipairs(B.ids or {}) do
		local r = ns.Record(id)
		if r then
			local a = agg[id] or { qty = 0, cost = 0, profit = 0 }
			r.fc = { t = now, qty = a.qty, cost = a.cost, profit = a.profit }
		end
	end
end

local function FinishSearch()
	SaveChecked()
	if ns.Refresh then ns.Refresh() end
	B.state = "ready"
	-- Сначала самые выгодные лоты.
	table.sort(B.lots, function(a, b) return (a.sell * a.qty - a.total) > (b.sell * b.qty - b.total) end)
	B.idx = 1
	Render()
end

local NextSearch

local function AddLot(lot)
	lot.profit = lot.sell * lot.qty - lot.total
	B.lots[#B.lots + 1] = lot
end

local function ReadCommodity(id, sell)
	local qty, total = 0, 0
	for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(id) do
		local r = C_AuctionHouse.GetCommoditySearchResultInfo(id, i)
		if r and r.unitPrice and r.quantity and r.unitPrice < sell and not r.containsOwnerItem then
			qty = qty + r.quantity
			total = total + r.unitPrice * r.quantity
		end
	end
	if qty > 0 then AddLot({ kind = "commodity", id = id, qty = qty, total = total, sell = sell }) end
end

local function ReadItems(key, sell)
	for i = 1, C_AuctionHouse.GetNumItemSearchResults(key) do
		local r = C_AuctionHouse.GetItemSearchResultInfo(key, i)
		local price, qty = r and r.buyoutAmount, r and r.quantity
		if price and qty and qty > 0 and not r.containsOwnerItem and price / qty < sell then
			AddLot({ kind = "item", id = key.itemID, auctionID = r.auctionID, qty = qty, total = price, sell = sell })
		end
	end
end

local function Attempt(token)
	if B.token ~= token or B.state ~= "search" then return end
	local id = B.cur
	local key = C_AuctionHouse.MakeItemKey(id)
	local info = C_AuctionHouse.GetItemKeyInfo(key)
	if not info then -- данные предмета ещё не в кэше: без них сервер игнорирует поиск
		B.tries = B.tries + 1
		if B.tries > 15 then
			NextSearch()
		else
			C_Timer.After(0.3, function() Attempt(token) end)
		end
		return
	end
	if not Ready() then
		C_Timer.After(0.2, function() Attempt(token) end)
		return
	end
	B.sent = GetTime()
	C_AuctionHouse.SendSearchQuery(key, SORTS, true)
	-- Сторож: нет ответа 6 секунд — пробуем ещё раз, потом пропускаем предмет.
	local sentAt = B.sent
	C_Timer.After(6, function()
		if B.token == token and B.state == "search" and B.cur == id and B.sent == sentAt then
			B.retries = B.retries + 1
			if B.retries > 1 then NextSearch() else Attempt(token) end
		end
	end)
end

function NextSearch()
	if B.state ~= "search" then return end
	local id = table.remove(B.queue, 1)
	if not id then
		FinishSearch()
		return
	end
	B.cur, B.tries, B.retries = id, 0, 0
	B.done = B.done + 1
	Render()
	local token = B.token
	C_Timer.After(0.1, function() Attempt(token) end)
end

ns.On("COMMODITY_SEARCH_RESULTS_UPDATED", function(itemID)
	if B.state ~= "search" or itemID ~= B.cur then return end
	local sell = ns.GameSell(itemID)
	if sell then ReadCommodity(itemID, sell) end
	B.cur = nil
	NextSearch()
end)

ns.On("ITEM_SEARCH_RESULTS_UPDATED", function(key)
	if B.state ~= "search" or not key or key.itemID ~= B.cur then return end
	local sell = ns.GameSell(key.itemID)
	if sell then ReadItems(key, sell) end
	B.cur = nil
	NextSearch()
end)

function ns.FlipFind(ids)
	if not ns.ahOpen then
		ns.Print("сначала открой аукцион.")
		return
	end
	if #ids == 0 then
		ns.Print("отметь галочками предметы во вкладке Торговцу.")
		return
	end
	B.token = B.token + 1
	B.state = "search"
	B.ids = {}
	for i, id in ipairs(ids) do B.ids[i] = id end
	B.queue, B.lots, B.idx = ids, {}, 1
	B.total, B.done = #ids, 0
	B.spent, B.profit, B.bought = 0, 0, 0
	B.stage, B.pending = nil, nil
	ns.ShowBuyer()
	NextSearch()
end

---------------------------------------------------------------------------
-- Покупка
---------------------------------------------------------------------------

local function Current()
	return B.lots[B.idx]
end

local function Advance()
	B.idx = B.idx + 1
	B.stage, B.pending = nil, nil
	Render()
end

local function Success(lot)
	lot.done = true
	B.spent = B.spent + lot.total
	B.profit = B.profit + lot.sell * lot.qty - lot.total
	B.bought = B.bought + 1
	ns.db.flipBought[lot.id] = (ns.db.flipBought[lot.id] or 0) + lot.qty
	ns.FlipLog("buy", lot.id, lot.qty, lot.total, lot.sell * lot.qty)
	-- Купленное больше не висит в списке «Торговцу».
	local r = ns.Record(lot.id)
	if r and r.fc then
		r.fc.qty = math.max(0, r.fc.qty - lot.qty)
		r.fc.cost = math.max(0, r.fc.cost - lot.total)
		r.fc.profit = r.fc.profit - (lot.sell * lot.qty - lot.total)
	end
	if ns.Refresh then ns.Refresh() end
	Advance()
end

local function Fail(lot, why)
	lot.failed = why
	ns.Print(("не купил %s: %s"):format(ns.ItemName(lot.id), why))
	Advance()
end

-- Вызывается только из клика по кнопке: игра разрешает покупку лишь по действию игрока.
local function BuyClick()
	local lot = Current()
	if not lot or B.state ~= "ready" or B.pending then return end
	if not ns.ahOpen then
		ns.Print("аукцион закрыт.")
		return
	end
	if B.budget > 0 and B.spent + lot.total > B.budget then
		ns.Print("дальше выходит за предел трат. Увеличь предел или пропусти лот.")
		return
	end
	if GetMoney() < lot.total then
		ns.Print("не хватает денег на этот лот.")
		return
	end
	if lot.kind == "item" then
		B.pending = { lot = lot, money = GetMoney() }
		C_AuctionHouse.PlaceBid(lot.auctionID, lot.total)
		local pending = B.pending
		C_Timer.After(4, function()
			if B.pending == pending then
				B.pending = nil
				Fail(lot, "лот уже купили или сервер отказал")
			end
		end)
	elseif B.stage ~= "confirm" then
		B.stage = "price"
		C_AuctionHouse.StartCommoditiesPurchase(lot.id, lot.qty)
	else
		B.stage = "buying"
		B.pending = { lot = lot }
		C_AuctionHouse.ConfirmCommoditiesPurchase(lot.id, lot.qty)
	end
	Render()
end

local function SkipClick()
	local lot = Current()
	if not lot then return end
	if lot.kind == "commodity" and B.stage then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
	lot.skipped = true
	Advance()
end

-- Штучный лот: покупку видно по списанию денег.
ns.On("PLAYER_MONEY", function()
	local p = B.pending
	if p and p.money and GetMoney() <= p.money - p.lot.total * 0.99 then
		B.pending = nil
		Success(p.lot)
	end
end)

-- «Товар»: сервер назвал точную цену — проверяем, что всё ещё дешевле торговца.
ns.On("COMMODITY_PRICE_UPDATED", function(unitPrice, totalPrice)
	local lot = Current()
	if B.stage ~= "price" or not lot then return end
	if not unitPrice or unitPrice >= lot.sell then
		pcall(C_AuctionHouse.CancelCommoditiesPurchase)
		Fail(lot, "цена выросла выше торговой")
		return
	end
	lot.total = totalPrice or lot.total
	B.stage = "confirm"
	Render()
end)

ns.On("COMMODITY_PRICE_UNAVAILABLE", function()
	local lot = Current()
	if B.stage == "price" and lot then Fail(lot, "сервер не назвал цену") end
end)

ns.On("COMMODITY_PURCHASE_SUCCEEDED", function()
	local p = B.pending
	if p and B.stage == "buying" then
		B.pending = nil
		Success(p.lot)
	end
end)

ns.On("COMMODITY_PURCHASE_FAILED", function()
	local p = B.pending
	if p and B.stage == "buying" then
		B.pending = nil
		Fail(p.lot, "покупка не прошла")
	end
end)

ns.On("AUCTION_HOUSE_CLOSED", function()
	if B.state == "search" then
		B.state = "ready"
		B.queue = {}
	end
	if B.stage == "price" or B.stage == "confirm" then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
	B.stage, B.pending = nil, nil
	if frame and frame:IsShown() then Render() end
end)

---------------------------------------------------------------------------
-- Окно
---------------------------------------------------------------------------

function Render()
	if not (frame and frame:IsShown()) then return end
	-- Итоги по оставшимся лотам.
	local left, cost, income = 0, 0, 0
	for i = B.idx, #B.lots do
		local l = B.lots[i]
		left = left + 1
		cost = cost + l.total
		income = income + l.sell * l.qty
	end
	if B.state == "search" then
		statusText:SetText(("Ищу лоты: %d из %d - %s"):format(B.done, B.total, B.cur and ns.ItemName(B.cur) or ""))
	elseif #B.lots == 0 then
		statusText:SetText("Лотов дешевле торговца не нашлось: их уже выкупили или цены выросли.")
	else
		statusText:SetText(("Куплено лотов: %d, потрачено %s, прибыль у торговца ~%s"):format(
			B.bought, ns.Money(B.spent), ns.Money(B.profit)))
	end
	sumText:SetText(("Осталось лотов: %d.  Потратишь %s, торговец даст %s.  |cffffd200Прибыль %s|r"):format(
		left, ns.Money(cost), ns.Money(income), ns.Money(income - cost)))

	for i = 1, MAX_LINES do
		local l, lot = lines[i], B.lots[B.idx + i - 1]
		if lot then
			l.name:SetText(ns.ColoredName(lot.id) .. (lot.qty > 1 and ("  |cff808080x" .. lot.qty .. "|r") or ""))
			l.cost:SetText(ns.Money(lot.total))
			l.profit:SetText("|cff40ff40+" .. ns.Money(lot.sell * lot.qty - lot.total) .. "|r")
			l:Show()
		else
			l:Hide()
		end
	end

	local lot = Current()
	if B.state == "search" then
		buyBtn:SetText("Идёт поиск...")
		buyBtn:Disable()
	elseif not lot then
		buyBtn:SetText(#B.lots > 0 and "Всё куплено - иди к торговцу" or "Нечего покупать")
		buyBtn:Disable()
	elseif B.pending then
		buyBtn:SetText("Покупаю...")
		buyBtn:Disable()
	elseif B.stage == "price" then
		buyBtn:SetText("Узнаю цену у сервера...")
		buyBtn:Disable()
	elseif B.stage == "confirm" then
		buyBtn:SetText(("Подтвердить: %s x%d за %s"):format(ns.ItemName(lot.id), lot.qty, ns.Money(lot.total)))
		buyBtn:Enable()
	else
		buyBtn:SetText(("Купить: %s x%d за %s"):format(ns.ItemName(lot.id), lot.qty, ns.Money(lot.total)))
		buyBtn:Enable()
	end
	skipBtn:SetEnabled(lot ~= nil and B.state == "ready" and not B.pending)
end

local function Build()
	frame = CreateFrame("Frame", "ShekelBuyerFrame", UIParent)
	frame:SetSize(520, 120 + MAX_LINES * 20 + 70)
	frame:SetPoint("CENTER", 0, 60)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "ShekelBuyerFrame")
	local bg = frame:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.06, 0.06, 0.09, 0.97)
	local edge = frame:CreateTexture(nil, "BORDER")
	edge:SetPoint("TOPLEFT")
	edge:SetPoint("TOPRIGHT")
	edge:SetHeight(2)
	edge:SetColorTexture(1, 0.82, 0, 0.6)

	local head = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	head:SetPoint("TOPLEFT", 12, -10)
	head:SetText("Выкуп для перепродажи торговцу")
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	statusText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	statusText:SetPoint("TOPLEFT", 12, -32)
	statusText:SetWidth(496)
	statusText:SetJustifyH("LEFT")
	sumText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	sumText:SetPoint("TOPLEFT", 12, -50)
	sumText:SetWidth(496)
	sumText:SetJustifyH("LEFT")

	local budgetLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	budgetLabel:SetPoint("TOPLEFT", 12, -74)
	budgetLabel:SetText("Не тратить больше, золота (0 - без предела):")
	budgetBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	budgetBox:SetSize(60, 20)
	budgetBox:SetPoint("LEFT", budgetLabel, "RIGHT", 10, 0)
	budgetBox:SetAutoFocus(false)
	budgetBox:SetNumeric(true)
	budgetBox:SetJustifyH("CENTER")
	budgetBox:SetText("0")
	local function commit(self)
		B.budget = (tonumber(self:GetText()) or 0) * 10000
		self:ClearFocus()
		Render()
	end
	budgetBox:SetScript("OnEnterPressed", commit)
	budgetBox:SetScript("OnEditFocusLost", commit)

	lines = {}
	for i = 1, MAX_LINES do
		local l = CreateFrame("Frame", nil, frame)
		l:SetSize(496, 20)
		l:SetPoint("TOPLEFT", 12, -100 - (i - 1) * 20)
		l.name = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.name:SetPoint("LEFT", 0, 0)
		l.name:SetWidth(280)
		l.name:SetJustifyH("LEFT")
		l.name:SetWordWrap(false)
		l.cost = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.cost:SetPoint("LEFT", 290, 0)
		l.cost:SetWidth(100)
		l.cost:SetJustifyH("RIGHT")
		l.profit = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		l.profit:SetPoint("LEFT", 396, 0)
		l.profit:SetWidth(100)
		l.profit:SetJustifyH("RIGHT")
		if i == 1 then -- следующий лот — выделен
			local hl = l:CreateTexture(nil, "BACKGROUND")
			hl:SetAllPoints()
			hl:SetColorTexture(1, 0.82, 0, 0.12)
		end
		lines[i] = l
	end

	buyBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	buyBtn:SetSize(380, 30)
	buyBtn:SetPoint("BOTTOMLEFT", 12, 32)
	buyBtn:SetScript("OnClick", BuyClick)
	skipBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	skipBtn:SetSize(110, 30)
	skipBtn:SetPoint("LEFT", buyBtn, "RIGHT", 6, 0)
	skipBtn:SetText("Пропустить")
	skipBtn:SetScript("OnClick", SkipClick)

	local note = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	note:SetPoint("BOTTOMLEFT", 12, 10)
	note:SetWidth(496)
	note:SetJustifyH("LEFT")
	note:SetTextColor(0.6, 0.6, 0.6)
	note:SetText("Один клик - одна покупка: так требует игра. Купленное приходит на почту - забери и продай у торговца.")

	frame:SetScript("OnHide", function()
		if B.stage == "price" or B.stage == "confirm" then pcall(C_AuctionHouse.CancelCommoditiesPurchase) end
		B.stage, B.pending = nil, nil
	end)
end

function ns.ShowBuyer()
	if not frame then Build() end
	frame:Show()
	Render()
end

---------------------------------------------------------------------------
-- Продажа купленного у торговца
---------------------------------------------------------------------------

local sellBtn

local function BoughtInBags()
	local want = {}
	for id, n in pairs(ns.db.flipBought) do
		if n > 0 then want[id] = n end
	end
	local list = {}
	local lastBag = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
	for bag = 0, lastBag do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			local id = info and info.itemID
			if id and want[id] and not info.isLocked and info.stackCount <= want[id] then
				want[id] = want[id] - info.stackCount
				list[#list + 1] = { bag = bag, slot = slot, id = id, count = info.stackCount }
			end
		end
	end
	return list
end

local function UpdateSellButton()
	if not sellBtn then return end
	local list = BoughtInBags()
	local units = 0
	for _, it in ipairs(list) do units = units + it.count end
	sellBtn:SetText(("Шекель: продать купленное (%d шт.)"):format(units))
	sellBtn:SetShown(#list > 0)
end

-- Кнопка продаёт по одной стопке каждые 0,15 с. Учёт продаж — отдельно, ниже: он ловит любую продажу.
local function SellAll()
	local list = BoughtInBags()
	local i = 0
	local function step()
		i = i + 1
		local it = list[i]
		if not it or not (MerchantFrame and MerchantFrame:IsShown()) then return end
		C_Container.UseContainerItem(it.bag, it.slot)
		C_Timer.After(0.15, step)
	end
	step()
end

-- Учёт продаж торговцу любым способом (кнопкой или правым кликом): пока открыто окно торговца,
-- следим, на сколько уменьшилось в сумках предметов, купленных для перепродажи.
-- Торговец платит ровно цену продажи предмета из данных игры, поэтому выручка = штук x эта цена.
local track
local function BagCount(id)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, false) or 0 end
	return GetItemCount and GetItemCount(id) or 0
end

local function CheckSales()
	if not track then return end
	for id, before in pairs(track.counts) do
		local now = BagCount(id)
		if now < before then
			local sold = math.min(before - now, ns.db.flipBought[id] or 0)
			if sold > 0 then
				ns.db.flipBought[id] = ns.db.flipBought[id] - sold
				local got = sold * (ns.GameSell(id) or ns.VendorSell(id) or 0)
				ns.FlipLog("sell", id, sold, got, got)
				track.got, track.units = track.got + got, track.units + sold
			end
		end
		track.counts[id] = now
	end
end

local function UpdateSellButton()
	if not sellBtn then return end
	local list = BoughtInBags()
	local units = 0
	for _, it in ipairs(list) do units = units + it.count end
	sellBtn:SetText(("Шекель: продать купленное (%d шт.)"):format(units))
	sellBtn:SetShown(#list > 0)
	return units
end

ns.On("MERCHANT_SHOW", function()
	if not sellBtn and MerchantFrame then
		sellBtn = CreateFrame("Button", "ShekelSellButton", MerchantFrame, "UIPanelButtonTemplate")
		sellBtn:SetSize(250, 26)
		sellBtn:SetPoint("TOPLEFT", MerchantFrame, "TOPRIGHT", 6, -40) -- справа от окна торговца, на виду
		sellBtn:SetScript("OnClick", SellAll)
	end
	track = { counts = {}, got = 0, units = 0 }
	for id, n in pairs(ns.db.flipBought) do
		if n > 0 then track.counts[id] = BagCount(id) end
	end
	C_Timer.After(0.2, function()
		local units = UpdateSellButton()
		if units and units > 0 then
			ns.Print(("в сумках %d шт. для перепродажи - кнопка справа от окна торговца."):format(units))
		end
	end)
end)

ns.On("BAG_UPDATE_DELAYED", function()
	if MerchantFrame and MerchantFrame:IsShown() then
		CheckSales()
		UpdateSellButton()
	end
end)

ns.On("MERCHANT_CLOSED", function()
	CheckSales()
	if track and track.units > 0 then
		ns.Print(("продано для перепродажи: %d шт. на %s. Итог по сделкам: /shekel flips"):format(track.units, ns.Money(track.got)))
	end
	track = nil
end)

-- Начать учёт перепродажи с нуля.
function ns.FlipReset()
	wipe(ns.db.flipLog)
	wipe(ns.db.flipBought)
	ns.Print("журнал перепродажи очищен.")
end

-- Для тестов вне игры: состояние и обработчики кнопок.
ns.BuyerDebug = { B = B, Buy = BuyClick, Skip = SkipClick, Bought = BoughtInBags, Sell = SellAll, Check = CheckSales }
