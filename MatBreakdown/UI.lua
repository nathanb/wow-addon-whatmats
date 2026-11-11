local ADDON, ns = ...

local ROW_HEIGHT = 20
local current -- { hit = ..., count = n }

local window = CreateFrame("Frame", "MatBreakdownFrame", UIParent, "BasicFrameTemplateWithInset")
window:SetSize(360, 440)
window:SetPoint("CENTER")
window:SetMovable(true)
window:SetClampedToScreen(true)
window:EnableMouse(true)
window:RegisterForDrag("LeftButton")
window:SetScript("OnDragStart", window.StartMoving)
window:SetScript("OnDragStop", window.StopMovingOrSizing)
window:Hide()
window.TitleText:SetText(ADDON)
tinsert(UISpecialFrames, window:GetName())

local icon = window:CreateTexture(nil, "ARTWORK")
icon:SetSize(36, 36)
icon:SetPoint("TOPLEFT", 14, -32)

local title = window:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
title:SetPoint("RIGHT", window, "RIGHT", -14, 0)
title:SetJustifyH("LEFT")
title:SetWordWrap(false)

local subtitle = window:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

local qtyBox = CreateFrame("EditBox", nil, window, "InputBoxTemplate")
qtyBox:SetSize(40, 20)
qtyBox:SetPoint("TOPRIGHT", window, "TOPRIGHT", -16, -52)
qtyBox:SetAutoFocus(false)
qtyBox:SetNumeric(true)
qtyBox:SetMaxLetters(4)
qtyBox:SetText("1")

local qtyLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
qtyLabel:SetPoint("RIGHT", qtyBox, "LEFT", -8, 0)
qtyLabel:SetText("Qty")

local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
hint:SetPoint("CENTER", window, "CENTER", 0, 0)
hint:SetWidth(300)
hint:SetText("Shift-click an item in your bags or a recipe in your profession window to load it.")

local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -80)
scroll:SetPoint("BOTTOMRIGHT", -32, 10)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(310, 1)
scroll:SetScrollChild(content)

local rows = {}

local function GetRow(i)
  local row = rows[i]
  if row then return row end

  row = CreateFrame("Frame", nil, content)
  row:SetSize(310, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  row:EnableMouse(true)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", 4, 0)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row, "RIGHT", -70, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.count:SetPoint("RIGHT", -4, 0)
  row.count:SetJustifyH("RIGHT")

  row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.header:SetPoint("LEFT", 2, 0)

  row:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)

  rows[i] = row
  return row
end

local function SetHeader(i, text)
  local row = GetRow(i)
  row.itemID = nil
  row.icon:Hide()
  row.name:SetText("")
  row.count:SetText("")
  row.header:SetText(text)
  row:Show()
end

local function SetItem(i, itemID, need)
  local row = GetRow(i)
  row.itemID = itemID
  row.header:SetText("")
  row.icon:SetTexture(C_Item.GetItemIconByID(itemID))
  row.icon:Show()
  row.name:SetText(ns.ItemText(itemID))
  local have = C_Item.GetItemCount(itemID)
  local color = have >= need and GREEN_FONT_COLOR or RED_FONT_COLOR
  row.count:SetText(color:WrapTextInColorCode(have .. " / " .. need))
  row:Show()
end

local function Render()
  for _, row in ipairs(rows) do row:Hide() end
  if not current then
    icon:Hide()
    title:SetText("")
    subtitle:SetText("")
    hint:Show()
    return
  end

  hint:Hide()
  local recipe = current.hit.recipe
  icon:SetTexture(C_Item.GetItemIconByID(recipe.outputItemID))
  icon:Show()
  title:SetText(recipe.name)
  local yields = current.count * recipe.made
  subtitle:SetText(current.hit.profName .. (recipe.made > 1 and (" - makes " .. yields) or ""))

  local result = ns.Compute(current.hit, current.count)
  local i = 0
  if #result.crafted > 0 then
    i = i + 1; SetHeader(i, "Craft first")
    for _, l in ipairs(result.crafted) do
      i = i + 1; SetItem(i, l.itemID, l.n)
    end
    i = i + 1; SetHeader(i, " ")
  end
  i = i + 1; SetHeader(i, "Raw materials")
  for _, l in ipairs(result.raw) do
    i = i + 1; SetItem(i, l.itemID, l.n)
  end
  content:SetHeight(i * ROW_HEIGHT)
end

qtyBox:SetScript("OnTextChanged", function(self, userInput)
  if not userInput or not current then return end
  current.count = math.max(tonumber(self:GetText()) or 1, 1)
  Render()
end)
qtyBox:SetScript("OnEnterPressed", qtyBox.ClearFocus)
qtyBox:SetScript("OnEscapePressed", qtyBox.ClearFocus)

local function Load(link)
  local matches = ns.FindRecipes(link)
  if #matches == 0 then
    ns.Print("No known recipe makes " .. link .. ". Open its profession window once so it can be scanned.")
    return
  end
  current = { hit = matches[1], count = math.max(tonumber(qtyBox:GetText()) or 1, 1) }
  Render()
end

function ns.ToggleWindow()
  window:SetShown(not window:IsShown())
end

window:SetScript("OnShow", Render)

hooksecurefunc("HandleModifiedItemClick", function(link)
  if link and window:IsShown() and IsModifiedClick("CHATLINK") then
    Load(link)
  end
end)

window:RegisterEvent("BAG_UPDATE_DELAYED")
window:RegisterEvent("GET_ITEM_INFO_RECEIVED")
window:SetScript("OnEvent", function()
  if window:IsShown() and current then Render() end
end)
