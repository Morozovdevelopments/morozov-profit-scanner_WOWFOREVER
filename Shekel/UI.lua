-- Окно: вкладки Крафт, Фарм, Торговцу и Цены; таблица с сортировкой по клику на заголовок.
-- В строках интерфейса только символы, которые есть в шрифте игры: без «·», «−», «…», «×» и ёлочек.

local _, ns = ...

local W, H = 820, 540
local ROWS, ROW_H = 30, 22 -- строк создаём с запасом; видно столько, сколько влезает по высоте
local vis = 14
local LIST_TOP = -182
local MAXCOLS = 8
local GOLD = { 1, 0.82, 0 }

local f, rows, headers, empty, footer, hint, scanBtn, statusText, profBtn, menu, bar, resetBtn, flipBuyBtn
local tabButtons, modeButtons, farmButtons, controls, boxes = {}, {}, {}, {}, {}
local tab = "home"
local offset = 0
local data = {}
local search = ""
local sortState = {
	craft = { key = "profit", desc = true },
	farm = { key = "value", desc = true },
	farmNodes = { key = "value", desc = true },
	farmItems = { key = "per100", desc = true },
	farmZones = { key = "value", desc = true },
	home = { key = "gain", desc = true }, -- «Главное» не сортируется, но столбцам нужна запись
	flip = { key = "lot", desc = true },
	prices = { key = "mkt", desc = true },
}

local COLS = {
	craft = {
		{ title = "Что крафтить", key = "label", w = 200, left = true },
		{ title = "Профессия", key = "profKey", w = 110, left = true, kind = "prof" },
		{ title = "Реагенты", key = "cost", w = 80, kind = "money" },
		{ title = "Продажа", key = "sell", w = 80, kind = "money", conf = true },
		{ title = "Прибыль", key = "profit", w = 80, kind = "money" },
		{ title = "Маржа", key = "margin", w = 50, kind = "pct" },
		{ title = "На АУК", key = "onAH", w = 50, kind = "num" },
		{ title = "В день", key = "perDay", w = 50, kind = "money",
			tip = "Сколько реально заработать в день: прибыль x сколько крафтов позволяют спрос и перезарядка" },
	},
	farm = {
		{ title = "Моб", key = "label", w = 165, left = true },
		{ title = "Уровень", key = "lvl", w = 55, kind = "lvl" },
		{ title = "Зона", key = "zone", w = 120, left = true, kind = "text" },
		{ title = "В мире", key = "spawns", w = 50, kind = "num", tip = "Сколько таких мобов в мире (по базе классики)" },
		{ title = "За убийство", key = "value", w = 95, kind = "money",
			tip = "Средний доход с одного убийства: шанс x цена всей добычи + монеты" },
		{ title = "Главная добыча", key = "bestName", w = 165, left = true, kind = "best" },
		{ title = "Цена шт.", key = "bestPrice", w = 85, kind = "money",
			tip = "Цена одной штуки главной добычи: на аукционе, а если там нет - у торговца" },
	},
	farmItems = {
		{ title = "Что добывать", key = "label", w = 170, left = true },
		{ title = "Цена шт.", key = "price", w = 80, kind = "money", conf = true, tip = "Сколько стоит одна штука на аукционе" },
		{ title = "В день", key = "demand", w = 50, kind = "qty", tip = "Сколько штук в день уходит с аукциона (по сканам)" },
		{ title = "Где лучше всего", key = "whereText", w = 200, left = true, kind = "text" },
		{ title = "Уровень", key = "lvl", w = 60, kind = "lvl" },
		{ title = "Шанс", key = "chance", w = 50, kind = "chance" },
		{ title = "За 100", key = "per100", w = 90, kind = "money",
			tip = "Сколько принесут 100 убийств (или 100 узлов) в лучшем месте - по цене аукциона за вычетом 5%" },
	},
	home = {
		{ title = "Что сделать", key = "label", w = 290, left = true },
		{ title = "Подробности", key = "detail", w = 340, left = true, kind = "text" },
		{ title = "Выгода", key = "gain", w = 120, kind = "money",
			tip = "Крафт - прибыль в день (или за крафт), торговцу - прибыль за лот, фарм - за 100 убийств" },
	},
	farmZones = {
		{ title = "Зона", key = "label", w = 170, left = true },
		{ title = "Уровни", key = "lvl", w = 60, kind = "lvl" },
		{ title = "Лучшие мобы", key = "names", w = 270, left = true, kind = "text" },
		{ title = "Мобов", key = "spawns", w = 55, kind = "num", tip = "Сколько этих мобов в зоне (по базе классики)" },
		{ title = "За убийство", key = "value", w = 95, kind = "money", tip = "Средний доход с убийства у 3 лучших мобов зоны" },
		{ title = "Твоё в час", key = "perHour", w = 85, kind = "money", tip = "Сколько ты сам заработал здесь в час (после 10+ минут фарма)" },
	},
	farmNodes = {
		{ title = "Узел", key = "label", w = 190, left = true },
		{ title = "Навык", key = "lvl", w = 75, kind = "lvl" },
		{ title = "Профессия", key = "zone", w = 120, left = true, kind = "text" },
		{ title = "Доход за узел", key = "value", w = 110, kind = "money" },
		{ title = "Главная добыча", key = "bestName", w = 165, left = true, kind = "best" },
		{ title = "Цена шт.", key = "bestPrice", w = 85, kind = "money",
			tip = "Цена одной штуки главной добычи: на аукционе, а если там нет - у торговца" },
	},
	flip = {
		{ title = "Предмет", key = "label", w = 240, left = true },
		{ title = "Купить за", key = "buy", w = 95, kind = "money", conf = true },
		{ title = "Торговец даст", key = "sell", w = 95, kind = "money" },
		{ title = "За шт.", key = "profit", w = 80, kind = "money" },
		{ title = "За лот", key = "lot", w = 115, kind = "lot",
			tip = "Прибыль со всех дешёвых штук. Зелёное - проверено поиском, точно. Серое \"от\" - ещё не проверено: гарантированно с одной штуки, может оказаться больше." },
		{ title = "%", key = "pct", w = 50, kind = "pct" },
		{ title = "Штук", key = "qty", w = 55, kind = "num" },
	},
	prices = {
		{ title = "Предмет", key = "label", w = 300, left = true },
		{ title = "Цена за штуку", key = "mkt", w = 110, kind = "money", conf = true },
		{ title = "Штук", key = "qty", w = 70, kind = "num" },
		{ title = "В день", key = "demand", w = 80, kind = "qty", tip = "Сколько штук в день уходит с аукциона (по сканам)" },
		{ title = "За 7 дней", key = "chg", w = 80, kind = "pct" },
		{ title = "Обновлено", key = "age", w = 80, kind = "age" },
	},
}

local HINTS = {
	home = "Лучшее, что можно сделать прямо сейчас - из твоих рецептов, на твоём уровне. Клик по строке - сделать.",
	farmZones = "Где фармить целой зоной: 3 самых доходных моба твоих уровней. Правый клик - лучший моб на карте.",
	craft = "Наведи мышь на строку - расчёт и где взять рецепт. Правый клик - список покупок. "
		.. "|cff40ff40Зелёным|r - рецепты, которые ты знаешь.",
	farmItems = "Что выгодно добывать на твоём уровне: цена, сколько покупают в день и лучшее место. "
		.. "Наведи на строку - все места добычи. Только то, что реально продаётся.",
	farmNodes = "Доход - в среднем за один узел по цене аукциона. Наведи мышь - увидишь, что из него падает.",
	flip = "Лоты дешевле, чем платит торговец. Отметь галочками и нажми Выкупить выбранное: аддон найдёт "
		.. "все такие лоты, |cff40ff40зелёным|r покажет точную прибыль, а пустые строки уберёт.",
	prices = "Цена - самый дешёвый лот за штуку. Оранжевым - цена вдвое выше или ниже обычной.",
}

-- Ключ текущей таблицы: у вкладки Фарм два вида.
local function View()
	if tab == "farm" and ns.db.settings.farmMode == "nodes" then return "farmNodes" end
	if tab == "farm" and ns.db.settings.farmMode == "items" then return "farmItems" end
	if tab == "farm" and ns.db.settings.farmMode == "zones" then return "farmZones" end
	return tab
end

-- Нижний регистр для UTF-8. string.lower зависит от локали и может испортить
-- байты кириллицы, поэтому латиницу переводим вручную, а кириллицу — по таблице байтов.
local function ulower(s)
	s = s:gsub("[A-Z]", function(c) return string.char(c:byte() + 32) end)
	s = s:gsub("\208([\144-\159])", function(c) return "\208" .. string.char(c:byte() + 32) end)
	s = s:gsub("\208([\160-\175])", function(c) return "\209" .. string.char(c:byte() - 32) end)
	s = s:gsub("\208\129", "\209\145")
	return s
end

local DASH = "|cff808080—|r"

local function Cell(col, d)
	local v = d[col.key]
	if col.kind == "prof" then return ns.ProfCell(d) end
	if col.kind == "money" then
		if d.header or (v == nil and col.key == "gain") then return "" end
		-- Цветная отметка: можно ли верить этой цене (подробности — в подсказке предмета).
		local icon = (col.conf and d.id and v) and (ns.ConfIcon(d.id) .. " ") or ""
		return icon .. ns.Money(v)
	end
	if col.kind == "age" then return ns.Age(v) end
	if col.kind == "chance" then return v and (ns.FormatQty(v) .. "%") or DASH end
	if col.kind == "lot" then
		if d.checked then return "|cff40ff40" .. ns.Money(v) .. "|r" end
		return "|cff808080от|r " .. ns.Money(v)
	end
	if col.kind == "lvl" then return d.lvlText or DASH end
	if col.kind == "best" then
		if not d.best then return DASH end
		return ns.ColoredName(d.best) .. (" |cff808080%s%%|r"):format(ns.FormatQty(d.bestChance or 0))
	end
	if v == nil then return DASH end
	if col.kind == "pct" then
		local color = v >= 0 and "|cff40ff40" or "|cffff4040"
		return color .. ("%+d%%"):format(math.floor(v + 0.5)) .. "|r"
	end
	if col.kind == "num" then return tostring(math.floor(v + 0.5)) end
	if col.kind == "qty" then return ns.FormatQty(v) end
	return tostring(v)
end

-- Данные вкладок.
local function CraftData()
	local list, count = {}, {}
	for _, row in ipairs(ns.CraftRows()) do
		if ns.PassesFilter(row) then
			row.label = ns.KnownName(row.id) or ""
			list[#list + 1] = row
			count[row.id] = (count[row.id] or 0) + 1
		end
	end
	-- Один предмет из разных рецептов (например, трансмутации): подписываем главный реагент.
	for _, row in ipairs(list) do
		row.via = count[row.id] > 1 and row.parts[1] and row.parts[1].id or nil
	end
	return list
end

local function FarmData()
	local list = ns.FarmRows()
	for _, row in ipairs(list) do
		row.bestName = row.best and ns.KnownName(row.best) or nil
		row.bestPrice = row.best and (ns.SellPrice(row.best) or ns.VendorSell(row.best)) or nil
	end
	return list
end

local function PriceData()
	local list = {}
	local h = ns.House()
	local now = time()
	local needle = search ~= "" and ulower(search) or nil
	local names = ns.db.names -- только своя база: 7000 обращений к игре на каждую перерисовку тормозят
	for id, r in pairs(h.items) do
		local label = names[id] or ""
		if (not needle or ulower(label):find(needle, 1, true)) and (not ns.db.settings.pricesWatchOnly or ns.db.watch[id]) then
			local fresh = not h.lastScan or (r.t and r.t >= h.lastScan)
			list[#list + 1] = {
				id = id, label = label, mkt = r.mkt,
				qty = fresh and r.qty or 0,
				chg = ns.Change(id, 7), age = r.t and (now - r.t) or nil,
				demand = ns.Demand(id), flag = ns.PriceFlag(id),
			}
		end
	end
	return list
end

local function Sort()
	if tab == "home" then return end
	local st = sortState[View()]
	local key, desc = st.key, st.desc
	table.sort(data, function(a, b)
		local x, y = a[key], b[key]
		if x == nil and y == nil then return (a.label or "") < (b.label or "") end
		if x == nil then return false end
		if y == nil then return true end
		if x == y then return (a.label or "") < (b.label or "") end
		if desc then return x > y end
		return x < y
	end)
end

local NO_PRICES = "Цен с аукциона пока нет.\n\nОткрой аукцион и нажми кнопку Скан аукциона вверху справа."

local function EmptyText()
	local s = ns.db.settings
	if tab == "home" then return NO_PRICES end
	if tab == "farm" then
		if s.farmMode == "items" then
			if not ns.House().lastScan then return NO_PRICES end
			return "На этих уровнях ничего ценного не падает.\n\nИзмени уровни справа или нажми Мой уровень."
		end
		if s.farmMode == "nodes" then
			return "Нет узлов по твоему навыку сбора.\n\nСними галочку справа, чтобы увидеть все узлы."
		end
		return "Нет мобов в этом диапазоне уровней.\n\nИзмени уровни справа или нажми Мой уровень."
	end
	if not ns.House().lastScan then return NO_PRICES end
	if tab == "prices" then return "Ничего не найдено." end
	if tab == "flip" then
		return "Сейчас нет лотов дешевле, чем платит торговец.\n\n"
			.. "Загляни после следующего скана. Сразу после первого скана аддон ещё\nподтягивает цены торговцев - это минута-две."
	end
	if s.craftMode == "mine" and not next(ns.char.recipes) then
		return "Рецептов этого персонажа пока нет.\n\nОткрой окно своей профессии - аддон запомнит рецепты.\nИли переключись на Все рецепты."
	end
	if s.craftMode == "mine" and s.craftProf then
		local has = false
		for _, rc in pairs(ns.char.recipes) do
			if rc.prof == s.craftProf then
				has = true
				break
			end
		end
		if not has then
			return ("У этого персонажа нет рецептов: %s.\n\nВыбери другую профессию или переключись на Все рецепты."):format(s.craftProf)
		end
	end
	return "Ничего не прошло фильтр.\n\nСнизь пороги прибыли и маржи или включи галочки справа."
end

local function Render()
	local cols = COLS[View()]
	offset = math.max(0, math.min(offset, #data - vis))
	for i = 1, ROWS do
		local row = rows[i]
		local d = i <= vis and data[offset + i] or nil
		row.data = d
		if d then
			-- Название спрашиваем у сервера только для видимых строк.
			if d.id and not ns.KnownName(d.id) then ns.RequestName(d.id) end
			if d.best and d.best ~= d.id and not ns.KnownName(d.best) then ns.RequestName(d.best) end
			row.icon:SetTexture(d.id and ns.ItemIcon(d.id) or 134400)
			-- Во вкладке «Торговцу» вместо иконки — галочка выбора.
			local flip = tab == "flip"
			row.icon:SetShown(not flip)
			row.check:SetShown(flip)
			if flip then row.check:SetChecked(ns.flipSel[d.id] and true or false) end
			if d.header or d.noIcon then row.icon:Hide() end
			for c, col in ipairs(cols) do
				local text
				if c == 1 then
					text = d.labelText or (ns.WatchStar(d.id) .. ns.ColoredName(d.id))
					if tab == "craft" and d.qty and d.qty ~= 1 then text = text .. (" |cff808080x%g|r"):format(d.qty) end
					if tab == "craft" and d.via then text = text .. " |cff808080из " .. (ns.KnownName(d.via) or "...") .. "|r" end
				else
					text = Cell(col, d)
				end
				row.cells[c]:SetText(text)
			end
			row:Show()
		else
			row:Hide()
		end
	end
	empty:SetShown(#data == 0)
	if #data == 0 then empty:SetText(EmptyText()) end
	local from, to = math.min(offset + 1, #data), math.min(offset + vis, #data)
	local click = "клик - найти на аукционе"
	if tab == "home" then click = "клик - сделать"
	elseif tab == "farm" then click = "правый клик - на карте"
	elseif tab == "craft" then click = click .. "    ||    правый клик - список покупок" end
	if tab ~= "home" then click = click .. "    ||    Alt+клик - в избранное" end
	footer:SetText(("Строки %d-%d из %d    ||    колёсико - прокрутка    ||    %s    ||    Shift+клик - ссылка в чат")
		:format(from, to, #data, click))
end

local function LayoutColumns()
	local cols = COLS[View()]
	local st = sortState[View()]
	local x = 36
	for i = 1, ROWS do rows[i].bestBtn:Hide() end
	for c, col in ipairs(cols) do
		if col.kind == "best" then
			for i = 1, ROWS do
				local b = rows[i].bestBtn
				b:ClearAllPoints()
				b:SetPoint("LEFT", rows[i], "LEFT", x - 14, 0)
				b:SetSize(col.w, ROW_H)
				b:Show()
			end
		end
		local hb = headers[c]
		hb:ClearAllPoints()
		hb:SetPoint("TOPLEFT", f, "TOPLEFT", x, LIST_TOP + 22)
		hb:SetSize(col.w, 20)
		local arrow = (st.key == col.key) and (st.desc and " |cffffffffv|r" or " |cffffffff^|r") or "" -- в шрифте игры нет стрелок
		hb.text:SetText(col.title .. arrow)
		hb.text:SetJustifyH(col.left and "LEFT" or "RIGHT")
		hb:Show()
		for i = 1, ROWS do
			local fs = rows[i].cells[c]
			fs:ClearAllPoints()
			fs:SetPoint("LEFT", rows[i], "LEFT", x - 14 + (c == 1 and 22 or 0), 0)
			fs:SetWidth(col.w - (c == 1 and 22 or 0))
			fs:SetJustifyH(col.left and "LEFT" or "RIGHT")
			fs:Show()
		end
		x = x + col.w + 6
	end
	for c = #cols + 1, MAXCOLS do
		headers[c]:Hide()
		for i = 1, ROWS do rows[i].cells[c]:Hide() end
	end
end

local function UpdateControls()
	local s = ns.db.settings
	for key, b in pairs(tabButtons) do b.line:SetShown(key == tab) end
	for key, b in pairs(modeButtons) do b.line:SetShown(key == s.craftMode) end
	for key, b in pairs(farmButtons) do b.line:SetShown(key == s.farmMode) end
	profBtn:SetText("Профессия: " .. (s.craftProf and ns.ShortProf(s.craftProf) or "все"))
	local group = View()
	local farmGroup = (s.farmMode == "nodes") and "farmNodes" or "farmMobs"
	for key, list in pairs(controls) do
		local show = key == tab or (tab == "farm" and key == farmGroup)
		for _, w in ipairs(list) do w:SetShown(show) end
	end
	for _, b in ipairs(boxes) do
		if not b:HasFocus() then b:SetText(tostring(b.get())) end
	end
	-- На вкладке мобов вместо подсказки — живая сессия фарма с золотом в час.
	if group == "farm" then
		hint:SetText(ns.SessionText())
	else
		hint:SetText(HINTS[group])
	end
	resetBtn:SetShown(tab == "farm" and ns.session ~= nil)
	local n = ns.FlipSelectedCount()
	flipBuyBtn:SetText(n > 0 and ("Выкупить выбранное (" .. n .. ")") or "Выкупить выбранное")
	flipBuyBtn:SetEnabled(n > 0 and ns.ahOpen and true or false)
end

-- «Главное»: по 3 лучших действия из каждого раздела — только то, что доступно тебе.
local function HomeData()
	local list = {}
	local s = ns.db.settings
	local function header(text) list[#list + 1] = { header = true, labelText = "|cffffd200" .. text .. "|r", detail = "" } end
	local function note(text) list[#list + 1] = { noIcon = true, labelText = "|cff808080" .. text .. "|r", detail = "" } end

	header("Скрафтить и продать")
	local mode, prof = s.craftMode, s.craftProf
	s.craftMode, s.craftProf = "mine", nil
	local crafts = {}
	for _, r in ipairs(ns.CraftRows()) do
		if r.profit and r.profit >= s.minProfit and (r.margin or 0) >= s.minMargin and ns.Confidence(r.id) ~= "bad" then
			crafts[#crafts + 1] = r
		end
	end
	s.craftMode, s.craftProf = mode, prof
	table.sort(crafts, function(a, b) return (a.perDay or a.profit) > (b.perDay or b.profit) end)
	for i = 1, math.min(3, #crafts) do
		local r = crafts[i]
		list[#list + 1] = {
			id = r.id, detail = ("%s: реагенты %s, продажа %s"):format(ns.ShortProf(r.prof or ""), ns.Money(r.cost), ns.Money(r.sell)),
			gain = r.perDay or r.profit, craftRow = r, action = function() ns.OpenShopping(r) end,
		}
	end
	if #crafts == 0 then
		note(next(ns.char.recipes) and "Сейчас нет выгодного крафта по твоим рецептам." or "Открой окно своей профессии - аддон запомнит рецепты.")
	end

	header("Перепродать торговцу")
	local flips = ns.FlipRows()
	table.sort(flips, function(a, b) return a.lot > b.lot end)
	for i = 1, math.min(3, #flips) do
		local r = flips[i]
		list[#list + 1] = {
			id = r.id, detail = ("купить за %s, торговец даст %s"):format(ns.Money(r.buy), ns.Money(r.sell)),
			gain = r.lot, flipRow = r, action = function() ns.FlipFind({ r.id }) end,
		}
	end
	if #flips == 0 then note("Лотов дешевле торговца нет (или нужен свежий скан).") end

	header("Пофармить на твоём уровне")
	local farm = ns.FarmItemRows()
	table.sort(farm, function(a, b) return a.per100 > b.per100 end)
	for i = 1, math.min(3, #farm) do
		local r = farm[i]
		list[#list + 1] = {
			id = r.id, detail = r.whereText .. "  |cff808080" .. r.lvlText .. ", " .. ns.FormatQty(r.chance) .. "%|r",
			gain = r.per100, farmRow = r, action = function() ns.ShowOnMap(r.mapKind, r.mapID, r.mapName) end,
		}
	end
	if #farm == 0 then note("Нет ценной добычи на твоих уровнях (или нужен скан аукциона).") end

	local deals = ns.WatchDeals()
	header("Избранное подешевело")
	for i = 1, math.min(3, #deals) do
		local r = deals[i]
		list[#list + 1] = {
			id = r.id, detail = ("сейчас %s, обычно %s, %d шт."):format(ns.Money(r.price), ns.Money(r.median), r.qty or 0),
			gain = r.save, action = function() SearchAH(r.id) end,
		}
	end
	if #deals == 0 then
		note(next(ns.db.watch) and "Пока ничего из избранного не подешевело." or "Alt+клик по любому предмету - в избранное: сообщу, когда подешевеет.")
	end
	return list
end

local function RefreshUnsafe()
	if not (f and f:IsShown()) then return end
	if tab == "home" then
		data = HomeData()
	elseif tab == "craft" then
		data = CraftData()
	elseif tab == "farm" then
		data = FarmData()
	elseif tab == "flip" then
		data = ns.FlipRows()
		-- Строка пропала (выкупили, проверка нашла пусто, отфильтрована) — снимаем и её отметку.
		local present = {}
		for _, d in ipairs(data) do present[d.id] = true end
		for id in pairs(ns.flipSel) do
			if not present[id] then ns.flipSel[id] = nil end
		end
	else
		data = PriceData()
	end
	Sort()
	LayoutColumns()
	UpdateControls()
	Render()
	ns.UpdateStatus()
end

-- Ошибка при обновлении не должна ломать окно молча: пишем её в чат (одну и ту же — один раз).
local lastError
function ns.Refresh()
	local ok, err = pcall(RefreshUnsafe)
	if not ok and err ~= lastError then
		lastError = err
		ns.Print("|cffff4040ошибка окна:|r " .. tostring(err) .. " (сборка " .. ns.BUILD .. ")")
	end
end

function ns.UpdateStatus()
	if not f then return end
	local h = ns.House()
	local last = h.lastScan and (ns.Age(time() - h.lastScan) .. " назад") or "|cffff8040ещё не было|r"
	local line = ("Аукцион: %s    ||    последний скан: %s"):format(ns.houseKey or "?", last)
	if ns.scan.status then line = line .. "\n" .. ns.scan.status end
	statusText:SetText(line)
	local scanning = ns.scan.state ~= "idle"
	bar:SetShown(scanning)
	if scanning then
		scanBtn:SetText("Сканирую...")
		scanBtn:Disable()
	elseif not ns.ahOpen then
		scanBtn:SetText("Скан: открой аукцион")
		scanBtn:Disable()
	else
		scanBtn:SetText("Скан аукциона")
		scanBtn:Enable()
	end
end

-- Действия со строкой.
local function SearchAH(id)
	if not (ns.ahOpen and id) then return end
	local sb = AuctionHouseFrame and AuctionHouseFrame.SearchBar
	if not (sb and sb.SearchBox) then return end
	if AuctionHouseFrame.SetDisplayMode and AuctionHouseFrameDisplayMode then
		pcall(AuctionHouseFrame.SetDisplayMode, AuctionHouseFrame, AuctionHouseFrameDisplayMode.Buy)
	end
	local name = ns.KnownName(id)
	if not name then return end
	sb.SearchBox:SetText(name)
	if sb.StartSearch then pcall(sb.StartSearch, sb) end
end
ns.SearchAH = SearchAH -- нужен списку покупок

-- Подсказка справа от строки, а если окно у правого края экрана — слева.
local function TipOwner(owner)
	local right = owner:GetRight() or 0
	local screen = UIParent:GetRight() or GetScreenWidth()
	GameTooltip:SetOwner(owner, (screen - right < 380) and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
end

local function InsertLink(id)
	local link = id and ns.ItemLink(id)
	if not link then return end
	if ChatEdit_InsertLink then
		ChatEdit_InsertLink(link)
	elseif ChatFrameUtil and ChatFrameUtil.InsertLink then
		ChatFrameUtil.InsertLink(link)
	end
end

-- Элементы управления.
local function Label(parent, text, x, y, template)
	local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
	fs:SetPoint("TOPLEFT", x, y)
	fs:SetText(text)
	return fs
end

local function Button(text, w, x, y, onClick)
	local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	b:SetSize(w, 22)
	b:SetPoint("TOPLEFT", x, y)
	b:SetText(text)
	b:SetScript("OnClick", onClick)
	return b
end

-- Кнопка-переключатель: выбранная подчёркнута золотой линией.
local function Toggle(text, w, x, y, onClick)
	local b = Button(text, w, x, y, onClick)
	b.line = b:CreateTexture(nil, "OVERLAY")
	b.line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 1)
	b.line:SetPoint("TOPLEFT", b, "BOTTOMLEFT", 4, -1)
	b.line:SetPoint("TOPRIGHT", b, "BOTTOMRIGHT", -4, -1)
	b.line:SetHeight(2)
	return b
end

local function NumberBox(x, y, get, set)
	local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	eb:SetSize(44, 20)
	eb:SetPoint("TOPLEFT", x, y)
	eb:SetAutoFocus(false)
	eb:SetNumeric(true)
	eb:SetJustifyH("CENTER")
	eb.get = get
	eb:SetText(tostring(get()))
	local function commit(self)
		set(tonumber(self:GetText()) or 0)
		self:ClearFocus()
		ns.Refresh()
	end
	eb:SetScript("OnEnterPressed", commit)
	eb:SetScript("OnEditFocusLost", function(self)
		set(tonumber(self:GetText()) or 0)
		ns.Refresh()
	end)
	eb:SetScript("OnEscapePressed", function(self) self:SetText(tostring(get())) self:ClearFocus() end)
	boxes[#boxes + 1] = eb
	return eb
end

local function Check(x, y, text, get, set)
	local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
	cb:SetSize(24, 24)
	cb:SetPoint("TOPLEFT", x, y)
	cb:SetChecked(get())
	cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) ns.Refresh() end)
	return cb, Label(f, text, x + 26, y - 6)
end

local function SelectTab(name)
	tab = name
	offset = 0
	if menu then menu:Hide() end
	ns.Refresh()
end
ns.TestSelectTab = SelectTab -- для проверки вне игры

-- Выпадающий список профессий (свой: стандартные выпадающие меню в новых клиентах меняются).
local function OpenProfMenu()
	if menu:IsShown() then
		menu:Hide()
		return
	end
	local list = ns.ProfessionList()
	table.insert(list, 1, false) -- false = все профессии
	menu.buttons = menu.buttons or {}
	for i, prof in ipairs(list) do
		local b = menu.buttons[i]
		if not b then
			b = CreateFrame("Button", nil, menu)
			b:SetSize(170, 20)
			b:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 20)
			b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
			b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			b.text:SetPoint("LEFT", 6, 0)
			menu.buttons[i] = b
		end
		local selected = (prof or nil) == ns.db.settings.craftProf
		b.text:SetText((selected and "|cffffd200" or "") .. (prof or "Все профессии"))
		b:SetScript("OnClick", function()
			ns.db.settings.craftProf = prof or nil
			menu:Hide()
			offset = 0
			ns.Refresh()
		end)
		b:Show()
	end
	for i = #list + 1, #menu.buttons do menu.buttons[i]:Hide() end
	menu:SetSize(180, #list * 20 + 10)
	menu:ClearAllPoints()
	menu:SetPoint("TOPLEFT", profBtn, "BOTTOMLEFT", 0, -2)
	menu:Show()
end

local function Build()
	local s = ns.db.settings
	f = CreateFrame("Frame", "ShekelFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(W, s.height or H)
	vis = math.max(5, math.min(ROWS, math.floor(((s.height or H) + LIST_TOP - 34) / ROW_H)))
	-- Рамка в стиле окон самой игры: тёмный фон и золотой край.
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
			tile = true, tileSize = 32, edgeSize = 24,
			insets = { left = 6, right = 6, top = 6, bottom = 6 },
		})
	end
	f:SetPoint("CENTER")
	f:SetFrameStrata("HIGH")
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetClampedToScreen(true)
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		s.point = { "TOPLEFT", "BOTTOMLEFT", self:GetLeft(), self:GetTop() }
		ns.docked = false
		ns.dockManual = true -- передвинул руками — не прилипаем до следующего открытия аукциона/профессии
	end)
	tinsert(UISpecialFrames, "ShekelFrame") -- закрытие по Esc
	f:Hide()

	local bg = f:CreateTexture(nil, "BACKGROUND")
	bg:SetPoint("TOPLEFT", 6, -6)
	bg:SetPoint("BOTTOMRIGHT", -6, 6)
	bg:SetColorTexture(0.05, 0.05, 0.08, 0.85)
	local top = f:CreateTexture(nil, "BORDER")
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(58)
	top:SetColorTexture(1, 1, 1, 0.04)

	-- Портрет в золотом кольце в левом верхнем углу, заходит за край окна — как в окнах самой игры.
	local portrait = f:CreateTexture(nil, "OVERLAY", nil, 7)
	portrait:SetTexture("Interface\\AddOns\\Shekel\\Media\\portrait")
	portrait:SetSize(72, 72)
	portrait:SetPoint("TOPLEFT", -14, 14)

	Label(f, "Шекель", 66, -10, "GameFontNormalLarge")
	statusText = Label(f, "", 140, -12)
	statusText:SetJustifyH("LEFT")

	-- Полоса загрузки скана.
	bar = CreateFrame("StatusBar", nil, f)
	bar:SetPoint("TOPLEFT", 140, -44)
	bar:SetSize(440, 8)
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	bar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3])
	bar:SetMinMaxValues(0, 1)
	local barBg = bar:CreateTexture(nil, "BACKGROUND")
	barBg:SetAllPoints()
	barBg:SetColorTexture(1, 1, 1, 0.1)
	bar:Hide()
	local phase = 0
	bar:SetScript("OnUpdate", function(self, elapsed)
		local p = ns.ScanProgress()
		if p then
			self:SetValue(p)
		else -- сколько всего, неизвестно: бегущая полоса
			phase = (phase + elapsed * 0.6) % 2
			self:SetValue(phase < 1 and phase or 2 - phase)
		end
	end)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)

	scanBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	scanBtn:SetSize(180, 26)
	scanBtn:SetPoint("TOPRIGHT", -34, -14)
	scanBtn:SetScript("OnClick", function() ns.StartScan() ns.UpdateStatus() end)

	-- Вкладки.
	tabButtons.home = Toggle("Главное", 110, 14, -68, function() SelectTab("home") end)
	tabButtons.craft = Toggle("Крафт", 110, 128, -68, function() SelectTab("craft") end)
	tabButtons.farm = Toggle("Фарм", 110, 242, -68, function() SelectTab("farm") end)
	tabButtons.flip = Toggle("Торговцу", 110, 356, -68, function() SelectTab("flip") end)
	tabButtons.prices = Toggle("Цены", 110, 470, -68, function() SelectTab("prices") end)

	-- Настройки: галочки вместо команд /shekel ...
	local opts = CreateFrame("Frame", nil, f)
	opts:SetSize(360, 230)
	opts:SetPoint("TOPRIGHT", -12, -46)
	opts:SetFrameStrata("DIALOG")
	local obg = opts:CreateTexture(nil, "BACKGROUND")
	obg:SetAllPoints()
	obg:SetColorTexture(0.08, 0.08, 0.11, 0.98)
	local otitle = opts:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	otitle:SetPoint("TOPLEFT", 12, -10)
	otitle:SetText("Настройки")
	opts:Hide()
	local OPTIONS = {
		{ "Открывать вместе с аукционом", "autoOpen" },
		{ "Сканировать сам, если скан старше часа", "autoScan" },
		{ "Цены Шекеля в подсказках предметов", "tooltip" },
		{ "Вставать рядом с аукционом и профессией", "dockProfession" },
		{ "Открываться вместе с окном профессии", "openWithProfession" },
		{ "Сообщать, когда избранное подешевело", "alerts" },
		{ "Кнопка у миникарты", "minimap" },
	}
	for i, o in ipairs(OPTIONS) do
		local cb = CreateFrame("CheckButton", nil, opts, "UICheckButtonTemplate")
		cb:SetSize(24, 24)
		cb:SetPoint("TOPLEFT", 10, -28 - (i - 1) * 27)
		local label = opts:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
		label:SetText(o[1])
		cb:SetScript("OnShow", function(self)
			if o[2] == "minimap" then self:SetChecked(not s.minimapHide) else self:SetChecked(s[o[2]] and true or false) end
		end)
		cb:SetScript("OnClick", function(self)
			if o[2] == "minimap" then
				if (not s.minimapHide) ~= (self:GetChecked() and true or false) then ns.ToggleMinimapButton() end
			else
				s[o[2]] = self:GetChecked() and true or false
			end
		end)
	end
	local optBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	optBtn:SetSize(100, 26)
	optBtn:SetPoint("TOPRIGHT", -220, -14)
	optBtn:SetText("Настройки")
	optBtn:SetScript("OnClick", function() opts:SetShown(not opts:IsShown()) end)

	-- Крафт.
	local function SetMode(mode)
		s.craftMode = mode
		offset = 0
		ns.Refresh()
	end
	modeButtons.all = Toggle("Все рецепты", 120, 14, -104, function() SetMode("all") end)
	modeButtons.mine = Toggle("Мои рецепты", 120, 138, -104, function() SetMode("mine") end)
	profBtn = Button("Профессия: все", 180, 272, -104, OpenProfMenu)

	menu = CreateFrame("Frame", nil, f)
	menu:SetFrameStrata("DIALOG")
	local mbg = menu:CreateTexture(nil, "BACKGROUND")
	mbg:SetAllPoints()
	mbg:SetColorTexture(0.1, 0.1, 0.14, 0.98)
	menu:Hide()

	local showLoss, showLossLabel = Check(470, -134, "показывать убыточные",
		function() return s.showLoss end, function(v) s.showLoss = v end)
	local showNoPrice, showNoPriceLabel = Check(640, -134, "показывать без цены",
		function() return s.showNoPrice end, function(v) s.showNoPrice = v end)
	for _, w in ipairs({ showLoss }) do
		w:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText("Показывать убыточные", 1, 0.82, 0)
			GameTooltip:AddLine("Рецепты, где прибыль или маржа ниже порогов слева, в том числе в минус.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		w:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	for _, w in ipairs({ showNoPrice }) do
		w:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText("Показывать без цены", 1, 0.82, 0)
			GameTooltip:AddLine("Рецепты, где на аукционе нет готового предмета или одного из реагентов: прибыль посчитать нельзя.", 1, 1, 1, true)
			GameTooltip:Show()
		end)
		w:SetScript("OnLeave", function() GameTooltip:Hide() end)
	end
	controls.craft = {
		modeButtons.all, modeButtons.mine, profBtn,
		Label(f, "Прибыль от", 470, -110),
		NumberBox(540, -105, function() return math.floor(s.minProfit / 100) end, function(v) s.minProfit = v * 100 end),
		Label(f, "серебра,  маржа от", 590, -110),
		NumberBox(706, -105, function() return s.minMargin end, function(v) s.minMargin = v end),
		Label(f, "%", 756, -110),
		showLoss, showLossLabel, showNoPrice, showNoPriceLabel,
	}

	-- Фарм.
	local function SetFarm(mode)
		s.farmMode = mode
		offset = 0
		ns.Refresh()
	end
	if not s.farmItemsIntro then
		s.farmMode, s.farmItemsIntro = "items", true
	end
	farmButtons.items = Toggle("Ресурсы", 110, 14, -104, function() SetFarm("items") end)
	farmButtons.mobs = Toggle("Мобы", 110, 128, -104, function() SetFarm("mobs") end)
	farmButtons.nodes = Toggle("Трава и руда", 110, 242, -104, function() SetFarm("nodes") end)
	farmButtons.zones = Toggle("Зоны", 100, 356, -104, function() SetFarm("zones") end)
	controls.farm = { farmButtons.items, farmButtons.mobs, farmButtons.nodes, farmButtons.zones }
	controls.farmMobs = {
		Label(f, "Уровни от", 470, -110),
		NumberBox(530, -105, function() return (ns.FarmLevelRange()) end, function(v) s.farmMin = math.max(1, v) end),
		Label(f, "до", 580, -110),
		NumberBox(600, -105, function() return select(2, ns.FarmLevelRange()) end, function(v) s.farmMax = math.max(1, v) end),
		Button("Мой уровень", 110, 654, -104, function()
			s.farmMin, s.farmMax = nil, nil
			offset = 0
			ns.Refresh()
		end),
	}
	local mySkill, mySkillLabel = Check(470, -104, "только узлы, которые я могу собрать",
		function() return s.farmMySkill end, function(v) s.farmMySkill = v end)
	controls.farmNodes = { mySkill, mySkillLabel }
	resetBtn = Button("Сбросить сессию", 140, 666, -136, function() ns.ResetSession() end)

	-- Цены.
	local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
	box:SetSize(260, 20)
	box:SetPoint("TOPLEFT", 120, -105)
	box:SetAutoFocus(false)
	box:SetScript("OnTextChanged", function(self)
		search = self:GetText() or ""
		offset = 0
		ns.Refresh()
	end)
	box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
	local watchOnly, watchOnlyLabel = Check(400, -104, "только избранное",
		function() return s.pricesWatchOnly end, function(v) s.pricesWatchOnly = v end)
	controls.prices = { Label(f, "Найти предмет:", 18, -110), box, watchOnly, watchOnlyLabel }

	-- Торговцу: выбор и выкуп.
	local function SelectAll(on)
		if on then
			for _, d in ipairs(data) do ns.flipSel[d.id] = true end
		else
			wipe(ns.flipSel)
		end
		ns.Refresh()
	end
	flipBuyBtn = Button("Выкупить выбранное", 220, 242, -104, function()
		local ids = {}
		for _, d in ipairs(data) do
			if ns.flipSel[d.id] then ids[#ids + 1] = d.id end
		end
		ns.FlipFind(ids)
	end)
	controls.flip = {
		Button("Выбрать все", 110, 14, -104, function() SelectAll(true) end),
		Button("Снять выбор", 110, 128, -104, function() SelectAll(false) end),
		flipBuyBtn,
		Label(f, "Прибыль за лот от", 500, -110),
		NumberBox(612, -105, function() return s.flipMinProfit or 0 end, function(v) s.flipMinProfit = v end),
		Label(f, "меди", 662, -110),
	}

	hint = Label(f, "", 18, -140)
	hint:SetWidth(440)
	hint:SetJustifyH("LEFT")
	hint:SetTextColor(0.7, 0.7, 0.7)

	-- Заголовки столбцов.
	headers = {}
	for c = 1, MAXCOLS do
		local hb = CreateFrame("Button", nil, f)
		hb.text = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		hb.text:SetAllPoints()
		hb:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		hb:SetScript("OnClick", function()
			local col = COLS[View()][c]
			local st = sortState[View()]
			if st.key == col.key then st.desc = not st.desc else st.key, st.desc = col.key, not col.left end
			ns.Refresh()
		end)
		hb:SetScript("OnEnter", function(self)
			local col = COLS[View()][c]
			if not (col and col.tip) then return end
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			GameTooltip:SetText(col.tip, 1, 1, 1, 1, true)
			GameTooltip:Show()
		end)
		hb:SetScript("OnLeave", function() GameTooltip:Hide() end)
		headers[c] = hb
	end
	local line = f:CreateTexture(nil, "ARTWORK")
	line:SetColorTexture(GOLD[1], GOLD[2], GOLD[3], 0.3)
	line:SetPoint("TOPLEFT", 14, LIST_TOP)
	line:SetPoint("TOPRIGHT", -14, LIST_TOP)
	line:SetHeight(1)

	-- Строки таблицы.
	rows = {}
	for i = 1, ROWS do
		local row = CreateFrame("Button", nil, f)
		row:SetSize(W - 28, ROW_H)
		row:SetPoint("TOPLEFT", 14, LIST_TOP - 2 - (i - 1) * ROW_H)
		row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
		if i % 2 == 0 then
			local stripe = row:CreateTexture(nil, "BACKGROUND")
			stripe:SetAllPoints()
			stripe:SetColorTexture(1, 1, 1, 0.03)
		end
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("LEFT", 2, 0)
		row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
		row.check:SetSize(20, 20)
		row.check:SetPoint("LEFT", 1, 0)
		row.check:Hide()
		row.bestBtn = CreateFrame("Button", nil, row)
		row.bestBtn:Hide()
		row.bestBtn:RegisterForClicks("LeftButtonUp")
		row.bestBtn:SetScript("OnEnter", function(self)
			local d = row.data
			if not (d and d.best) then return end
			TipOwner(self)
			GameTooltip:SetItemByID(d.best) -- обычное окно предмета + строки «Шекеля» с ценой
			GameTooltip:AddLine("Клик - найти на аукционе, Shift+клик - ссылка в чат", 0.6, 0.6, 0.6)
			GameTooltip:Show()
		end)
		row.bestBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
		row.bestBtn:SetScript("OnClick", function()
			local d = row.data
			if not (d and d.best) then return end
			if IsShiftKeyDown() then InsertLink(d.best) else SearchAH(d.best) end
		end)
		row.check:SetScript("OnClick", function(self)
			local d = row.data
			if not d then return end
			ns.flipSel[d.id] = self:GetChecked() and true or nil
			UpdateControls()
		end)
		row.cells = {}
		for c = 1, MAXCOLS do
			local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
			fs:SetWordWrap(false)
			row.cells[c] = fs
		end
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, button)
			local d = self.data
			if not d then return end
			if d.header or d.noIcon then return end
			if IsAltKeyDown() then -- в избранное / из избранного
				ns.ToggleWatch(d.id or d.best)
				return
			end
			if button == "RightButton" then
				if tab == "craft" then ns.OpenShopping(d) end
				if tab == "farm" and d.mapID then ns.ShowOnMap(d.mapKind, d.mapID, d.mapName) end
				return
			end
			if tab == "home" then
				if d.action then d.action() end
				return
			end
			if IsShiftKeyDown() then InsertLink(d.id) else SearchAH(d.id) end
		end)
		row:SetScript("OnEnter", function(self)
			local d = self.data
			if not d then return end
			TipOwner(self)
			if d.header or d.noIcon then return end
			if tab == "home" then
				if d.farmRow then
					ns.FarmItemTooltip(d.farmRow, GameTooltip)
				else
					ns.ownTooltip = d.craftRow or d.flipRow
					GameTooltip:SetItemByID(d.id)
					ns.ownTooltip = false
					if d.craftRow then ns.CraftTooltip(d.craftRow, GameTooltip) end
					if d.flipRow then ns.FlipTooltip(d.flipRow, GameTooltip) end
				end
			elseif tab == "farm" then
				if d.kind == "item" then ns.FarmItemTooltip(d, GameTooltip)
				elseif d.kind == "zone" then ns.FarmZoneTooltip(d, GameTooltip)
				else ns.FarmTooltip(d, GameTooltip) end
			else
				ns.ownTooltip = true -- свои строки добавим сами, без общих строк «Шекеля»
				GameTooltip:SetItemByID(d.id)
				ns.ownTooltip = false
				if tab == "craft" then ns.CraftTooltip(d, GameTooltip) end
				if tab == "flip" then ns.FlipTooltip(d, GameTooltip) end
			end
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", function() GameTooltip:Hide() end)
		rows[i] = row
	end

	empty = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	empty:SetPoint("CENTER", 0, -60)
	empty:SetJustifyH("CENTER")

	footer = Label(f, "", 14, -(H - 20))
	footer:ClearAllPoints()
	footer:SetPoint("BOTTOMLEFT", 16, 12)
	footer:SetTextColor(0.55, 0.55, 0.55)

	-- Высоту окна можно менять уголком справа внизу: строк станет больше или меньше.
	f:SetResizable(true)
	if f.SetResizeBounds then
		f:SetResizeBounds(W, 380, W, 1200)
	elseif f.SetMinResize then
		f:SetMinResize(W, 380)
		f:SetMaxResize(W, 1200)
	end
	local grip = CreateFrame("Button", nil, f)
	grip:SetSize(16, 16)
	grip:SetPoint("BOTTOMRIGHT", -6, 6)
	grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
	grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
	grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
	grip:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
	grip:SetScript("OnMouseUp", function()
		f:StopMovingOrSizing()
		s.height = math.floor(f:GetHeight() + 0.5)
		if not ns.docked then s.point = { "TOPLEFT", "BOTTOMLEFT", f:GetLeft(), f:GetTop() } end
	end)
	f:SetScript("OnSizeChanged", function(_, _, h)
		vis = math.max(5, math.min(ROWS, math.floor((h + LIST_TOP - 34) / ROW_H)))
		if f:IsShown() then Render() end
	end)

	f:EnableMouseWheel(true)
	f:SetScript("OnMouseWheel", function(_, delta)
		offset = offset - delta * 3
		Render()
	end)

	f:SetScript("OnShow", function() ns.Refresh() end)
	f:SetScript("OnHide", function() menu:Hide() end)
end

local function Restore()
	local p = ns.db.settings.point
	f:ClearAllPoints()
	if p then
		f:SetPoint(p[1], UIParent, p[2], p[3], p[4])
	else
		f:SetPoint("CENTER")
	end
end

function ns.Toggle()
	if not f then
		Build()
		Restore()
	end
	f:SetShown(not f:IsShown())
	if f:IsShown() and ns.PlaceWindow then ns.PlaceWindow() end
end

-- Прилипание: «Шекель» встаёт справа от открытого окна игры.
-- Окно профессии важнее аукциона (если открыты оба — встаём за профессией, она сама стоит правее аукциона).
-- Передвинул окно руками — до следующего открытия аукциона или профессии оно стоит, где поставил.
local function Shown(name)
	local fr = _G[name]
	if fr and fr:IsShown() then return fr end
end

local function ProfessionFrame()
	return Shown("ProfessionsFrame") or Shown("TradeSkillFrame")
end

local function Anchor()
	local pf = ProfessionFrame()
	if pf then return pf, 52 end -- справа у окна профессии столбик закладок (~40 px): встаём за ним
	local ah = Shown("AuctionHouseFrame")
	if ah then return ah, 8 end
end

local function Place()
	local anchor, dx = Anchor()
	if anchor and ns.db.settings.dockProfession and not ns.dockManual then
		f:ClearAllPoints()
		f:SetPoint("TOPLEFT", anchor, "TOPRIGHT", dx, 0)
		ns.docked = true
	elseif ns.docked then
		ns.docked = false
		Restore()
	end
end

ns.PlaceWindow = Place

local function Ensure()
	if not f then
		Build()
		Restore()
	end
end

local autoShown, profShown = false, false -- окно открыл аддон (вместе с аукционом / профессией)

function ns.OnAuctionHouse(open)
	Ensure()
	if open then
		ns.dockManual = false
		if ns.db.settings.autoOpen and not f:IsShown() then
			tab = "home"
			f:Show()
			autoShown = true
		end
	else
		if autoShown and not ProfessionFrame() then f:Hide() end
		autoShown = false
	end
	-- Окно аукциона появляется и прячется чуть позже события: место выбираем с задержкой.
	C_Timer.After(0.05, function()
		Place()
		ns.Refresh()
		ns.UpdateStatus()
	end)
end

ns.On("TRADE_SKILL_SHOW", function()
	C_Timer.After(0.2, function()
		if not ns.db.settings.dockProfession or not ProfessionFrame() then return end
		Ensure()
		-- Само с профессией не открываемся (выключено по просьбе); если окно уже открыто — встаём рядом.
		if not f:IsShown() and not ns.db.settings.openWithProfession then return end
		ns.dockManual = false
		if not f:IsShown() then profShown = true end
		tab = "craft"
		offset = 0
		local prof = ns.CurrentProfession and ns.CurrentProfession()
		if prof then
			ns.db.settings.craftMode = "mine"
			ns.db.settings.craftProf = prof
		end
		f:Show()
		Place()
		ns.Refresh()
	end)
end)

ns.On("TRADE_SKILL_CLOSE", function()
	C_Timer.After(0.05, function()
		if not f then return end
		if profShown and not Shown("AuctionHouseFrame") then f:Hide() end
		profShown = false
		Place()
	end)
end)

-- Названия предметов приходят с сервера не сразу. Перерисовываем только видимые строки
-- (без пересчёта и сортировки всей таблицы) и не чаще трёх раз в секунду.
local redrawPending = false
local function Redraw()
	if redrawPending or not (f and f:IsShown()) then return end
	redrawPending = true
	C_Timer.After(0.3, function()
		redrawPending = false
		if f:IsShown() then Render() end
	end)
end
ns.On("ITEM_DATA_LOAD_RESULT", Redraw)
ns.On("GET_ITEM_INFO_RECEIVED", Redraw)
