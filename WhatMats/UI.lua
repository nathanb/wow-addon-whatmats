local ADDON, ns = ...

local ROW_HEIGHT = 22
local current -- { hit = ..., count = n }

local window = CreateFrame("Frame", "WhatMatsFrame", UIParent, "BasicFrameTemplateWithInset")
window:SetSize(380, 440)
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

local function NumberBox(parent)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(44, 18)
  box:SetAutoFocus(false)
  box:SetNumeric(true)
  box:SetMaxLetters(5)
  box:SetJustifyH("RIGHT")
  box:SetTextInsets(0, 6, 0, 0)
  box:SetScript("OnEnterPressed", box.ClearFocus)
  box:SetScript("OnEscapePressed", box.ClearFocus)
  return box
end

local qtyBox = NumberBox(window)
qtyBox:SetPoint("TOPRIGHT", window, "TOPRIGHT", -34, -54)
qtyBox:SetText("1")

local qtyLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
qtyLabel:SetPoint("RIGHT", qtyBox, "LEFT", -8, 0)
qtyLabel:SetText("Qty")

local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
hint:SetPoint("CENTER", window, "CENTER", 0, 0)
hint:SetWidth(300)
hint:SetText("Shift-click an item in your bags or a recipe in your profession window to load it.")

local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", 12, -82)
scroll:SetPoint("BOTTOMRIGHT", -32, 10)
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(330, 1)
scroll:SetScrollChild(content)

local rows = {}
local needs = {}

local function NeedsFor(count)
  local map = {}
  if count > 0 then
    local result = ns.Compute(current.hit, count)
    for _, l in ipairs(result.crafted) do map[l.itemID] = l.n end
    for _, l in ipairs(result.raw) do map[l.itemID] = l.n end
  end
  return map
end

-- Largest qty whose requirement for itemID fits in amount. Requirements grow by
-- at least 1 per craft, so amount is an upper bound.
local function MaxCountFor(itemID, amount)
  local lo, hi = 0, amount
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if (NeedsFor(mid)[itemID] or 0) <= amount then lo = mid else hi = mid - 1 end
  end
  return lo
end

local function UpdateValues()
  needs = NeedsFor(current.count)
  local recipe = current.hit.recipe
  local suffix = recipe.made > 1 and (" - makes " .. current.count * recipe.made) or ""
  subtitle:SetText(current.hit.profName .. suffix)

  for _, row in ipairs(rows) do
    if row:IsShown() and row.itemID then
      local need = needs[row.itemID] or 0
      local bags = C_Item.GetItemCount(row.itemID)
      local total = C_Item.GetItemCount(row.itemID, true, false, true, true)
      local bank = total - bags
      -- Yellow: enough exists, but some of it is still in a bank.
      local color = bags >= need and GREEN_FONT_COLOR
        or total >= need and YELLOW_FONT_COLOR
        or RED_FONT_COLOR
      local text = tostring(bags)
      if bank > 0 then text = text .. " (+" .. bank .. ")" end
      row.have:SetText(color:WrapTextInColorCode(text) .. " /")
      if not row.editable then
        row.needText:SetText(need)
      elseif not row.input:HasFocus() then
        row.input:SetText(need)
      end
    end
  end
end

local function SetCount(count, fromQtyBox)
  current.count = count
  if not fromQtyBox then qtyBox:SetText(count) end
  UpdateValues()
end

local function GetRow(i)
  local row = rows[i]
  if row then return row end

  row = CreateFrame("Frame", nil, content)
  row:SetSize(330, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  row:EnableMouse(true)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", 4, 0)

  row.input = NumberBox(row)
  row.input:SetPoint("RIGHT", -4, 0)
  row.input:SetScript("OnTextChanged", function(self, userInput)
    if not userInput or not current then return end
    SetCount(MaxCountFor(row.itemID, tonumber(self:GetText()) or 0))
  end)
  row.input:SetScript("OnEditFocusLost", function(self)
    self:SetText(needs[row.itemID] or 0)
  end)

  row.needText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.needText:SetPoint("RIGHT", row.input, "RIGHT", -4, 0)
  row.needText:SetJustifyH("RIGHT")

  row.have = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.have:SetPoint("RIGHT", row.input, "LEFT", -8, 0)
  row.have:SetJustifyH("RIGHT")

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row.have, "LEFT", -6, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

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
  row.input:Hide()
  row.name:SetText("")
  row.have:SetText("")
  row.needText:SetText("")
  row.header:SetText(text)
  row:Show()
end

local function SetItem(i, itemID, editable)
  local row = GetRow(i)
  row.itemID = itemID
  row.editable = editable
  row.header:SetText("")
  row.icon:SetTexture(C_Item.GetItemIconByID(itemID))
  row.icon:Show()
  row.input:SetShown(editable)
  row.needText:SetText("")
  row.name:SetText(ns.ItemText(itemID))
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

  -- Layout comes from qty 1 so rows stay put when qty is 0.
  local layout = ns.Compute(current.hit, 1)
  local i = 0
  if #layout.crafted > 0 then
    i = i + 1; SetHeader(i, "Craft first")
    for _, l in ipairs(layout.crafted) do
      i = i + 1; SetItem(i, l.itemID, false)
    end
    i = i + 1; SetHeader(i, " ")
  end
  i = i + 1; SetHeader(i, "Raw materials")
  for _, l in ipairs(layout.raw) do
    i = i + 1; SetItem(i, l.itemID, true)
  end
  content:SetHeight(i * ROW_HEIGHT)
  UpdateValues()
end

qtyBox:SetScript("OnTextChanged", function(self, userInput)
  if not userInput or not current then return end
  SetCount(tonumber(self:GetText()) or 0, true)
end)
qtyBox:SetScript("OnEditFocusLost", function(self)
  if current then self:SetText(current.count) end
end)

local function Load(link)
  local matches = ns.FindRecipes(link)
  if #matches == 0 then
    ns.Print("No known recipe makes " .. link .. ". Open its profession window once so it can be scanned.")
    return
  end
  current = { hit = matches[1], count = math.max(tonumber(qtyBox:GetText()) or 1, 1) }
  qtyBox:SetText(current.count)
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
window:SetScript("OnEvent", function(_, event)
  if not window:IsShown() or not current then return end
  if event == "GET_ITEM_INFO_RECEIVED" then Render() else UpdateValues() end
end)
