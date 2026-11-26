-- Список покупок для рецепта: сколько крафтов -> что купить, сколько, за сколько.
-- Учитывает то, что уже лежит в сумках и банке. Реагенты у торговца покупаются у торговца.
-- Если стоит Auctionator, список можно сразу искать в нём или сохранить как его список покупок.

local _, ns = ...

local W, LINE_H, MAX_LINES = 470, 20, 8
local frame, lines, countBox, totalText, profitText, warnText, searchBtn, saveBtn
local current, crafts = nil, 5

local function HasAuctionator()
	return Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.CreateShoppingList
end

local function ItemCount(id)
	if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, true) or 0 end
	return GetItemCount and GetItemCount(id, true) or 0
end

-- Что купить: { id, need, have, buy, unit, from, onAH }
local function Plan()
	local list = {}
	for _, p in ipairs(current.parts) do
		local need = p.n * crafts
		local have = ItemCount(p.id)
		local buy = math.max(0, need - have)
		local _, onAH = ns.Price(p.id)
		list[#list + 1] = { id = p.id, need = need, have = have, buy = buy, unit = p.unit, from = p.from, onAH = onAH }
	end
	return list
end

local function Render()
	if not current then return end
	frame.title:SetText(ns.ColoredName(current.id) .. "  |cff808080" .. (current.prof or "") .. "|r")
	local plan = Plan()
	local total, warn = 0, nil
	for i = 1, MAX_LINES do
		local l, p = lines[i], plan[i]
		l.data = p
		if p then
			l.name:SetText(ns.ColoredName(p.id))
			l.need:SetText(tostring(p.need))
			l.have:SetText(p.have > 0 and tostring(p.have) or "|cff808080-|r")
			l.buy:SetText(p.buy > 0 and ("|cffffffff" .. p.buy .. "|r") or "|cff40ff40хватает|r")
			local cost = p.unit and p.unit * p.buy
			if p.buy == 0 then
				l.cost:SetText("")
			elseif cost then
				l.cost:SetText(ns.Money(cost) .. " |cff808080" .. (p.from or "") .. "|r")
				total = total + cost
			else
				l.cost:SetText("|cffff4040нет цены|r")
			end
			if p.from == "аукцион" and p.onAH and p.buy > p.onAH then
				warn = ("%s: нужно %d, а на аукционе всего %d."):format(ns.ItemName(p.id), p.buy, p.onAH)
			end
			l:Show()
		else
			l:Hide()
		end
	end
	totalText:SetText("Купить реагентов на: " .. ns.Money(total))
	if current.sellUnit then
		local income = current.sellUnit * current.qty * crafts * (1 - ns.AH_CUT)
		profitText:SetText(("Продажа %d шт. - 5%%: %s     Прибыль: %s"):format(
			math.floor(current.qty * crafts + 0.5), ns.Money(income), ns.Money(income - total)))
	else
		profitText:SetText("|cff808080Цены продажи нет: прибыль не посчитать.|r")
	end
	warnText:SetText(warn and ("|cffff8040" .. warn .. " Остальное будет дороже.|r") or "")
	searchBtn:SetShown(HasAuctionator() and true or false)
	saveBtn:SetShown(HasAuctionator() and true or false)
end

-- Термины поиска Auctionator: только то, что покупается на аукционе.
local function Terms()
	local terms = {}
	for _, p in ipairs(Plan()) do
		local name = ns.KnownName(p.id)
		if name and p.buy > 0 and p.from ~= "торговец" then
			terms[#terms + 1] = { searchString = name, isExact = true, quantity = p.buy }
		end
	end
	return terms
end

local function Build()
	frame = CreateFrame("Frame", "ShekelShopFrame", UIParent)
	frame:SetSize(W, 120 + MAX_LINES * LINE_H)
	frame:SetPoint("CENTER", 0, 80)
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetClampedToScreen(true)
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	tinsert(UISpecialFrames, "ShekelShopFrame")
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
	head:SetText("Список покупок")
	frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	frame.title:SetPoint("TOPLEFT", 12, -28)

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("TOPRIGHT", -90, -14)
	label:SetText("Сколько крафтов:")
	countBox = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
	countBox:SetSize(44, 20)
	countBox:SetPoint("TOPRIGHT", -36, -10)
	countBox:SetAutoFocus(false)
	countBox:SetNumeric(true)
	countBox:SetJustifyH("CENTER")
	local function commit(self)
		crafts = math.max(1, tonumber(self:GetText()) or 1)
		self:SetText(tostring(crafts))
		self:ClearFocus()
		Render()
	end
	countBox:SetScript("OnEnterPressed", commit)
	countBox:SetScript("OnEditFocusLost", commit)

	local cols = { { "Реагент", 12, "LEFT" }, { "Нужно", 210, "RIGHT" }, { "Есть", 255, "RIGHT" }, { "Купить", 310, "RIGHT" }, { "Стоимость", 330, "LEFT" } }
	for _, c in ipairs(cols) do
		local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("TOPLEFT", c[2] - (c[3] == "RIGHT" and 40 or 0), -54)
		fs:SetWidth(c[3] == "RIGHT" and 40 or 130)
		fs:SetJustifyH(c[3])
		fs:SetText(c[1])
	end

	lines = {}
	for i = 1, MAX_LINES do
		local l = CreateFrame("Button", nil, frame)
		l:SetSize(W - 24, LINE_H)
		l:SetPoint("TOPLEFT", 12, -70 - (i - 1) * LINE_H)
		l:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		local function fs(x, w, justify)
			local t = l:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			t:SetPoint("LEFT", x, 0)
			t:SetWidth(w)
			t:SetJustifyH(justify)
			t:SetWordWrap(false)
			return t
		end
		l.name = fs(0, 160, "LEFT")
		l.need = fs(158, 40, "RIGHT")
		l.have = fs(203, 40, "RIGHT")
		l.buy = fs(250, 48, "RIGHT")
		l.cost = fs(318, 140, "LEFT")
		l:SetScript("OnClick", function(self)
			if self.data and ns.SearchAH then ns.SearchAH(self.data.id) end
		end)
		l:SetScript("OnEnter", function(self)
			if not self.data then return end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			ns.ownTooltip = true
			GameTooltip:SetItemByID(self.data.id)
			ns.ownTooltip = false
			GameTooltip:AddLine("Клик - найти на аукционе", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		l:SetScript("OnLeave", function() GameTooltip:Hide() end)
		lines[i] = l
	end

	local y = -76 - MAX_LINES * LINE_H
	totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	totalText:SetPoint("TOPLEFT", 12, y)
	profitText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	profitText:SetPoint("TOPLEFT", 12, y - 18)
	warnText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	warnText:SetPoint("TOPLEFT", 12, y - 34)
	warnText:SetWidth(W - 24)
	warnText:SetJustifyH("LEFT")

	searchBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	searchBtn:SetSize(170, 22)
	searchBtn:SetPoint("BOTTOMLEFT", 12, 10)
	searchBtn:SetText("Искать в Auctionator")
	searchBtn:SetScript("OnClick", function()
		local terms = Terms()
		if #terms == 0 then
			ns.Print("на аукционе покупать нечего.")
			return
		end
		pcall(Auctionator.API.v1.MultiSearchAdvanced, "Shekel", terms)
	end)
	saveBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
	saveBtn:SetSize(200, 22)
	saveBtn:SetPoint("LEFT", searchBtn, "RIGHT", 8, 0)
	saveBtn:SetText("Сохранить список в Auctionator")
	saveBtn:SetScript("OnClick", function()
		local strings = {}
		for _, t in ipairs(Terms()) do
			local ok, s = pcall(Auctionator.API.v1.ConvertToSearchString, "Shekel", t)
			if ok and s then strings[#strings + 1] = s end
		end
		if #strings == 0 then
			ns.Print("на аукционе покупать нечего.")
			return
		end
		local name = "Шекель: " .. (ns.KnownName(current.id) or "рецепт")
		local ok = pcall(Auctionator.API.v1.CreateShoppingList, "Shekel", name, strings)
		ns.Print(ok and ("список покупок \"" .. name .. "\" сохранён в Auctionator.") or "не получилось сохранить список.")
	end)

	frame:RegisterEvent("BAG_UPDATE_DELAYED")
	frame:SetScript("OnEvent", function() if frame:IsShown() then Render() end end)
end

function ns.OpenShopping(row)
	if not (row and row.parts) then return end
	if not frame then Build() end
	current = row
	crafts = math.max(1, crafts)
	countBox:SetText(tostring(crafts))
	frame:Show()
	Render()
end
