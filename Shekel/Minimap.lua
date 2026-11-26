-- Кнопка у миникарты: клик открывает окно, перетаскивание двигает кнопку по краю карты.
-- Размеры и рамка — как у стандартных кнопок аддонов (та же рамка, что у соседних кнопок).

local _, ns = ...

local ICON = "Interface\\AddOns\\Shekel\\Media\\icon"
local btn

local function Place()
	local angle = math.rad(ns.db.settings.minimapAngle or 200)
	local radius = (Minimap:GetWidth() / 2) + 10
	btn:ClearAllPoints()
	btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
	local mx, my = Minimap:GetCenter()
	local scale = Minimap:GetEffectiveScale()
	local px, py = GetCursorPosition()
	px, py = px / scale, py / scale
	ns.db.settings.minimapAngle = math.deg(math.atan2(py - my, px - mx)) % 360
	Place()
end

local function Create()
	btn = CreateFrame("Button", "ShekelMinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("AnyUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = btn:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)

	local icon = btn:CreateTexture(nil, "ARTWORK")
	icon:SetSize(20, 20)
	icon:SetTexture(ICON)
	icon:SetPoint("TOPLEFT", 7, -6)
	btn.icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	btn:SetScript("OnClick", function() ns.Toggle() end)
	btn:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", OnDragUpdate)
		GameTooltip:Hide()
	end)
	btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Шекель", 1, 0.82, 0)
		GameTooltip:AddLine("Клик - открыть или закрыть окно", 1, 1, 1)
		GameTooltip:AddLine("Перетащи - передвинуть кнопку", 1, 1, 1)
		GameTooltip:AddLine("/shekel minimap - спрятать кнопку", 0.6, 0.6, 0.6)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

	Place()
	btn:SetShown(not ns.db.settings.minimapHide)
end

function ns.ToggleMinimapButton()
	local s = ns.db.settings
	s.minimapHide = not s.minimapHide
	if btn then btn:SetShown(not s.minimapHide) end
	ns.Print(s.minimapHide and "кнопка у миникарты спрятана. Вернуть: /shekel minimap"
		or "кнопка у миникарты показана.")
end

ns.On("PLAYER_LOGIN", function()
	if Minimap then Create() end
end)
