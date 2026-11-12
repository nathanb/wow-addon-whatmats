local ADDON, ns = ...

local DEFAULT_ANGLE = 200
local EDGE_OFFSET = 5

local button = CreateFrame("Button", "WhatMatsMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("AnyUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local background = button:CreateTexture(nil, "BACKGROUND")
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetSize(20, 20)
background:SetPoint("TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetTexture("Interface\\Icons\\inv_gizmo_03")
icon:SetSize(17, 17)
icon:SetPoint("TOPLEFT", 7, -6)
icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

local border = button:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(53, 53)
border:SetPoint("TOPLEFT")

local function SetAngle(angle)
  local radius = Minimap:GetWidth() / 2 + EDGE_OFFSET
  local rad = math.rad(angle)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function FollowCursor()
  local mx, my = Minimap:GetCenter()
  local cx, cy = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
  WhatMatsDB.minimapAngle = angle
  SetAngle(angle)
end

button:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", FollowCursor)
end)
button:SetScript("OnDragStop", function(self)
  self:SetScript("OnUpdate", nil)
end)
button:SetScript("OnClick", function()
  ns.ToggleWindow()
end)
button:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT")
  GameTooltip:SetText(ADDON)
  GameTooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
  GameTooltip:Show()
end)
button:SetScript("OnLeave", GameTooltip_Hide)

function ns.InitMinimapButton()
  SetAngle(WhatMatsDB.minimapAngle or DEFAULT_ANGLE)
end
