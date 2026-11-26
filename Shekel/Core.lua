-- Шекель для WoW: Forever (интерфейс 16001).
-- Ядро: сохранённые данные, события, деньги и названия предметов.
-- Аукцион в этом клиенте современный (C_AuctionHouse), общий для набора правил и фракции.

local ADDON, ns = ...

ns.BUILD = 26-- растёт с каждой правкой; по нему видно, какая версия загружена в игре
ns.AH_CUT = 0.05 -- комиссия аукциона с продажи
ns.SCAN_COOLDOWN = 15 * 60 -- полный скан сервер разрешает раз в 15 минут
ns.HISTORY_DAYS = 30
ns.DAY = 86400

local DEFAULTS = {
	settings = {
		minProfit = 1000, -- медь: 10 серебра
		minMargin = 10, -- %
		showLoss = false, -- показывать рецепты ниже порогов прибыли и маржи, в т. ч. убыточные
		showNoPrice = false, -- показывать рецепты, где не хватает цены продажи или реагента
		craftMode = "all", -- "all" — все профессии, "mine" — только мои рецепты
		craftProf = nil, -- фильтр по профессии (nil — все)
		farmMode = "items", -- "items" — ресурсы, "mobs" — мобы, "nodes" — трава и руда
		farmMySkill = true, -- узлы только по моему навыку сбора
		-- farmMin / farmMax: уровни мобов; nil — от уровня персонажа (−10 … +2)
		useAuctionator = true, -- брать цену из базы Auctionator, если своей нет
		autoOpen = true, -- открывать окно вместе с аукционом
		autoScan = true, -- сканировать сам при открытии аукциона, если скан старше autoScanMinutes
		autoScanMinutes = 60,
		tooltip = true, -- строки "Шекеля" в подсказках предметов
		flipMinProfit = 20, -- медь: перепродажа — прибыль за лот от
		dockProfession = true, -- вставать справа от окна аукциона или профессии
		openWithProfession = false, -- открываться самому вместе с окном профессии
		alerts = true, -- оповещать о дешёвых лотах из избранного
		height = 540, -- высота окна (меняется уголком справа внизу)
	},
	houses = {}, -- [ключ аукциона] = { lastScan = время, items = { [itemID] = запись } }
	vendor = {}, -- [itemID] = цена за штуку у торговца с бесконечным запасом
	seen = {}, -- [recipeID] = рецепт, увиденный в окне профессии (своей или чужой)
	names = {}, -- [itemID] = название предмета; игра знает только недавно виденные, поэтому храним сами
	quality = {}, -- [itemID] = качество (цвет названия)
	sell = {}, -- [itemID] = сколько платит торговец, медь (0 — не покупает)
	learn = { mobs = {}, nodes = {}, zones = {} }, -- что реально выпало игроку и заработок по зонам (см. Learn.lua)
	watch = {}, -- [itemID] = true — избранное: оповещать, когда дешевле обычного (см. Watch.lua)
	flipBought = {}, -- [itemID] = штук, выкупленных для перепродажи торговцу (см. Buyer.lua)
	flipLog = {}, -- журнал покупок и продаж для перепродажи (см. Buyer.lua)
}

local function Merge(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			if type(v) == "table" then
				dst[k] = {}
				Merge(dst[k], v)
			else
				dst[k] = v
			end
		elseif type(v) == "table" and type(dst[k]) == "table" then
			Merge(dst[k], v)
		end
	end
end

-- События: несколько обработчиков на одно событие.
local events = CreateFrame("Frame")
local handlers = {}
function ns.On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		events:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end
events:SetScript("OnEvent", function(_, event, ...)
	for _, fn in ipairs(handlers[event]) do
		local ok, err = pcall(fn, ...)
		if not ok then ns.Print("|cffff4040ошибка|r " .. event .. ": " .. tostring(err)) end
	end
end)

function ns.Print(msg)
	print("|cffffd200Шекель:|r " .. msg)
end

ns.On("ADDON_LOADED", function(name)
	if name ~= ADDON then return end
	ShekelDB = ShekelDB or {}
	Merge(ShekelDB, DEFAULTS)
	ShekelCharDB = ShekelCharDB or {}
	Merge(ShekelCharDB, { recipes = {} })
	ns.db = ShekelDB
	ns.char = ShekelCharDB
end)

-- Ключ аукциона: в Forever аукцион один на набор правил и фракцию в регионе.
local function Ruleset()
	if not (C_GameRules and C_GameRules.IsGameRuleActive and Enum.GameRule) then return nil end
	local function on(rule) return rule and C_GameRules.IsGameRuleActive(rule) end
	local R = Enum.GameRule
	local pvp, rp = on(R.PvPRuleset), on(R.RPRuleset)
	if pvp and rp then return "RPPvP" end
	if pvp then return "PvP" end
	if rp then return "RP" end
	if on(R.HardcoreRuleset) then return "HC" end
	return "PvE"
end

function ns.HouseKey()
	local base
	if RegionalUniqueNamesEnabled and RegionalUniqueNamesEnabled() then
		local ok, rs = pcall(Ruleset)
		base = ok and rs or nil
	end
	base = base or GetNormalizedRealmName() or GetRealmName() or "?"
	return base .. " " .. (UnitFactionGroup("player") or "?")
end

-- Деньги: от золота и выше медь не показываем, чтобы столбцы были короче.
local CoinString = GetCoinTextureString or (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString)
function ns.Money(c)
	if c == nil then return "|cff808080—|r" end
	local neg = c < 0
	c = math.floor(math.abs(c) + 0.5)
	if c >= 10000 then c = c - c % 100 end
	local s = c == 0 and "0" or CoinString(c)
	return neg and ("|cffff4040-|r" .. s) or s
end

-- Предметы.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

-- Запомнить всё, что игра знает о предмете: название, качество, цену у торговца.
local function Learn(id)
	local db = ns.db
	if not db then return end
	local name, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(id)
	if name and name ~= "" then
		db.names[id] = name
		if quality then db.quality[id] = quality end
		if sellPrice then db.sell[id] = sellPrice end
		return name
	end
	name = C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
	if name and name ~= "" then
		db.names[id] = name
		local q = C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id)
		if q then db.quality[id] = q end
	end
	return name
end

-- Всё ли нужное о предмете уже сохранено.
local function Complete(id)
	return ns.db.names[id] and ns.db.sell[id] ~= nil
end

-- Название из своей базы или из кэша игры. Сервер ни о чём не спрашивает — для этого RequestName.
function ns.KnownName(id)
	local names = ns.db and ns.db.names
	local n = names and names[id]
	if n then return n end
	return Learn(id)
end

-- Попросить сервер прислать данные предмета (придёт событием GET_ITEM_INFO_RECEIVED).
local requested = {}
function ns.RequestName(id)
	if requested[id] or not C_Item.RequestLoadItemDataByID then return end
	requested[id] = true
	C_Item.RequestLoadItemDataByID(id)
end

function ns.ItemName(id)
	return ns.KnownName(id) or "|cff808080загрузка...|r"
end

function ns.ItemIcon(id)
	return (C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)) or 134400
end

function ns.ColoredName(id)
	local n = ns.KnownName(id)
	if not n then return "|cff808080загрузка...|r" end
	local q = ns.db.quality[id] or (C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(id))
	local c = q and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	return (c and c.hex or "|cffffffff") .. n .. "|r"
end

-- Пришли данные предмета: запоминаем название навсегда.
-- На RequestLoadItemDataByID игра отвечает событием ITEM_DATA_LOAD_RESULT,
-- а GET_ITEM_INFO_RECEIVED приходит, когда предмет подгрузился по другой причине. Слушаем оба.
local function OnItemData(id, ok)
	if id and ok ~= false then
		requested[id] = nil
		Learn(id)
	end
end
ns.On("ITEM_DATA_LOAD_RESULT", OnItemData)
ns.On("GET_ITEM_INFO_RECEIVED", OnItemData)

-- Тихая подгрузка названий в фоне: по 20 предметов каждые 0,2 секунды.
local warmQueue, warming = {}, false
local function WarmStep()
	local n = 0
	while n < 20 and #warmQueue > 0 do
		local id = table.remove(warmQueue)
		Learn(id)
		if not Complete(id) then
			ns.RequestName(id)
			n = n + 1
		end
	end
	if #warmQueue > 0 then
		C_Timer.After(0.2, WarmStep)
	else
		warming = false
		-- Последние ответы сервера ещё в пути: пересчитываем таблицу чуть позже, один раз.
		C_Timer.After(2, function() if ns.Refresh then ns.Refresh() end end)
	end
end

-- При входе в игру подтягиваем названия того, что уже есть в базе цен.
ns.On("PLAYER_LOGIN", function()
	C_Timer.After(10, function()
		local ids = {}
		for id in pairs(ns.House().items) do ids[#ids + 1] = id end
		ns.WarmNames(ids)
	end)
end)

function ns.WarmNames(ids)
	for _, id in ipairs(ids) do
		if not Complete(id) then warmQueue[#warmQueue + 1] = id end
	end
	if not warming and #warmQueue > 0 then
		warming = true
		C_Timer.After(0.2, WarmStep)
	end
end

function ns.ItemLink(id)
	local _, link = GetItemInfo(id)
	return link
end

-- Количество для показа: 0.4 -> "0.4", 12.6 -> "13".
function ns.FormatQty(v)
	if v < 10 then return (("%.1f"):format(v):gsub("%.0$", "")) end
	return tostring(math.floor(v + 0.5))
end

function ns.Age(sec)
	if not sec then return "|cff808080—|r" end
	if sec < 3600 then return math.floor(sec / 60) .. " мин" end
	if sec < ns.DAY then return math.floor(sec / 3600) .. " ч" end
	return math.floor(sec / ns.DAY) .. " дн"
end

SLASH_SHEKEL1 = "/shekel"
SLASH_SHEKEL2 = "/shk"
SlashCmdList.SHEKEL = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if msg == "scan" or msg == "Scan" or msg == "скан" then
		ns.StartScan()
	elseif msg == "build" then
		ns.Print("сборка " .. ns.BUILD)
	elseif msg == "minimap" then
		ns.ToggleMinimapButton()
	elseif msg == "flips reset" or msg == "сделки сброс" then
		ns.FlipReset()
	elseif msg == "flips" or msg == "сделки" then
		ns.FlipReport()
	elseif msg == "prof" then
		ns.db.settings.openWithProfession = not ns.db.settings.openWithProfession
		ns.Print(ns.db.settings.openWithProfession and "окно открывается вместе с профессией." or "окно не открывается само с профессией.")
	elseif msg == "dock" then
		ns.db.settings.dockProfession = not ns.db.settings.dockProfession
		ns.Print(ns.db.settings.dockProfession and "окно встаёт рядом с окнами аукциона и профессии." or "окно больше не прилипает к аукциону и профессии.")
	elseif msg == "tooltip" then
		ns.ToggleTooltip()
	elseif msg == "autoscan" then
		ns.db.settings.autoScan = not ns.db.settings.autoScan
		ns.Print(ns.db.settings.autoScan and "автоскан при открытии аукциона включён." or "автоскан выключен.")
	elseif msg == "help" or msg == "помощь" then
		ns.Print("/shekel - окно, /shekel scan - скан, /shekel tooltip - цены в подсказках, "
			.. "/shekel autoscan - автоскан, /shekel flips - итог перепродажи (flips reset - очистить), /shekel minimap - кнопка у карты, /shekel dock - прилипание к аукциону и профессии, /shekel prof - открываться с профессией, /shekel build - версия.")
	else
		ns.Toggle()
	end
end
