-- «Показать на карте»: ставит метку игры (как при ручной отметке на карте) туда, где стоят мобы
-- или растёт трава / лежит руда. Точки появления — из QuestieDB (данные Forever),
-- перевод зоны в карту игры — модуль зон Questie. Без Questie кнопка просто сообщит, что данных нет.

local _, ns = ...

local function ZoneDB()
	if not (QuestieLoader and QuestieLoader.ImportModule) then return end
	local ok, mod = pcall(QuestieLoader.ImportModule, QuestieLoader, "ZoneDB")
	return ok and mod or nil
end

local function UiMap(areaId)
	local z = ZoneDB()
	if not z then return end
	local ok, id = pcall(z.GetUiMapIdByAreaId, z, areaId)
	return ok and id or nil
end

-- Точки появления: { [areaId] = { {x, y}, ... } }, координаты 0..100.
local function Spawns(kind, id)
	local db = (kind == "node") and ObjectDB or NpcDB
	if not (db and db.spawns) then return end
	local ok, spawns = pcall(db.spawns, id)
	return ok and spawns or nil
end

-- Из всех точек выбираем: на карте, где стоит игрок, — ближайшую к нему;
-- иначе — в зоне с наибольшим числом точек, ближайшую к их середине.
local function PickPoint(spawns)
	local playerMap = C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local px, py
	if playerMap and C_Map.GetPlayerMapPosition then
		local pos = C_Map.GetPlayerMapPosition(playerMap, "player")
		if pos then px, py = pos:GetXY() end
	end
	local bestArea, bestCount
	for area, points in pairs(spawns) do
		local map = UiMap(area)
		if map and px and map == playerMap then
			local best, bestD
			for _, p in ipairs(points) do
				local dx, dy = p[1] / 100 - px, p[2] / 100 - py
				local d = dx * dx + dy * dy
				if not bestD or d < bestD then best, bestD = p, d end
			end
			if best then return map, best[1], best[2] end
		end
		if map and (not bestCount or #points > bestCount) then bestArea, bestCount = area, #points end
	end
	if not bestArea then return end
	local points = spawns[bestArea]
	local cx, cy = 0, 0
	for _, p in ipairs(points) do cx, cy = cx + p[1], cy + p[2] end
	cx, cy = cx / #points, cy / #points
	local best, bestD
	for _, p in ipairs(points) do
		local d = (p[1] - cx) ^ 2 + (p[2] - cy) ^ 2
		if not bestD or d < bestD then best, bestD = p, d end
	end
	return UiMap(bestArea), best[1], best[2]
end

-- kind: "mob" или "node"; id: номер моба или объекта; name — для сообщения.
function ns.ShowOnMap(kind, id, name)
	local spawns = Spawns(kind, id)
	if not spawns or not next(spawns) then
		ns.Print(("нет координат для %s: нужен Questie, или этого места нет в его базе."):format(name or "этой цели"))
		return
	end
	local map, x, y = PickPoint(spawns)
	if not (map and x and C_Map.SetUserWaypoint and UiMapPoint) then
		ns.Print("не получилось поставить метку на карте.")
		return
	end
	if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(map) then
		ns.Print("на этой карте игра не разрешает ставить метку.")
		return
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x / 100, y / 100))
	if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
	local info = C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	ns.Print(("метка на карте: %s - %s, %.1f %.1f"):format(name or "", info and info.name or "", x, y))
end
