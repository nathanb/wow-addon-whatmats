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
local moved = false
window:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  moved = true
end)
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

local INDENT = 14

local rows = {}
local plan

local function Walk(nodes, path, fn)
  for _, node in ipairs(nodes) do
    local key = path .. ">" .. node.itemID
    fn(node, key)
    Walk(node.children, key, fn)
  end
end

local function Index(p)
  local byKey = {}
  Walk(p.tree, "", function(node, key) byKey[key] = node end)
  for _, l in ipairs(p.totals) do byKey["total:" .. l.itemID] = l end
  return byKey
end

-- Largest qty whose total for itemID fits in amount, keeping the tree's
-- current shape. Multi-yield crafts can need less than 1 per qty, so search
-- upward instead of assuming a bound.
local function MaxCountFor(itemID, amount)
  local crafted = plan.crafted
  local function fits(count)
    return (ns.Totals(current.hit, count, crafted)[itemID] or 0) <= amount
  end
  local hi = 1
  while hi < 99999 and fits(hi) do hi = hi * 2 end
  hi = math.min(hi, 99999)
  local lo = 0
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if fits(mid) then lo = mid else hi = mid - 1 end
  end
  return lo
end

-- covered defaults to whether bags + bank hold need.
local function HaveText(itemID, need, covered)
  local bags = C_Item.GetItemCount(itemID)
  local total = C_Item.GetItemCount(itemID, true, false, true, true)
  local bank = total - bags
  if covered == nil then covered = total >= need end
  -- Yellow: covered, but some of it is still in a bank.
  local color = not covered and RED_FONT_COLOR
    or bags >= need and GREEN_FONT_COLOR
    or YELLOW_FONT_COLOR
  local text = tostring(bags)
  if bank > 0 then text = text .. " (+" .. bank .. ")" end
  return color:WrapTextInColorCode(text) .. " /"
end

local function UpdateValues()
  local recipe = current.hit.recipe
  local suffix = recipe.made > 1 and (" - makes " .. current.count * recipe.made) or ""
  subtitle:SetText(current.hit.profName .. suffix)

  local byKey = Index(plan)
  for _, row in ipairs(rows) do
    if row:IsShown() and row.key then
      local data = byKey[row.key]
      if row.isTotal then
        local n = data and data.n or 0
        if not row.input:HasFocus() then row.input:SetText(n) end
        row.have:SetText(HaveText(row.itemID, n))
        local short = n - C_Item.GetItemCount(row.itemID, true, false, true, true)
        row.craftText:SetText(short > 0 and ("short " .. short) or "")
      else
        row.have:SetText(HaveText(row.itemID, data and data.used or 0, data ~= nil and data.short == 0))
        row.needText:SetText(data and data.need or 0)
        row.craftText:SetText(data and data.made > 0 and ("craft " .. data.made) or "")
      end
    end
  end
end

local Render

local function Editing()
  for _, row in ipairs(rows) do
    if row:IsShown() and row.input:HasFocus() then return true end
  end
  return false
end

-- Rebuilding rows mid-edit would move the focused input to another item.
local function Refresh()
  if Editing() then
    plan = ns.Compute(current.hit, current.count)
    UpdateValues()
  else
    Render()
  end
end

local function SetCount(count, fromQtyBox)
  current.count = count
  if not fromQtyBox then qtyBox:SetText(count) end
  Refresh()
end

local function SetToggle(button, open)
  local kind = open and "Minus" or "Plus"
  button:SetNormalTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Up")
  button:SetPushedTexture("Interface\\Buttons\\UI-" .. kind .. "Button-Down")
end

local function GetRow(i)
  local row = rows[i]
  if row then return row end

  row = CreateFrame("Frame", nil, content)
  row:SetSize(330, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
  row:EnableMouse(true)

  row.toggle = CreateFrame("Button", nil, row)
  row.toggle:SetSize(14, 14)
  row.toggle:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight", "ADD")
  row.toggle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  row.toggle:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
      WhatMatsDB.expand[row.itemID] = nil
    else
      WhatMatsDB.expand[row.itemID] = not row.open
    end
    Render()
  end)
  row.toggle:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Click to craft or get this item")
    GameTooltip:AddLine("Right-click to reset to suggested", GREEN_FONT_COLOR:GetRGB())
    GameTooltip:Show()
  end)
  row.toggle:SetScript("OnLeave", GameTooltip_Hide)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row.toggle, "RIGHT", 4, 0)

  row.input = NumberBox(row)
  row.input:SetPoint("RIGHT", -4, 0)
  row.input:SetScript("OnTextChanged", function(self, userInput)
    if not userInput or not current then return end
    SetCount(MaxCountFor(row.itemID, tonumber(self:GetText()) or 0))
  end)
  row.input:SetScript("OnEditFocusLost", function()
    if current then Render() end
  end)

  row.needText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.needText:SetPoint("RIGHT", row.input, "RIGHT", -4, 0)
  row.needText:SetJustifyH("RIGHT")

  row.have = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.have:SetPoint("RIGHT", row.input, "LEFT", -8, 0)
  row.have:SetJustifyH("RIGHT")

  row.craftText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.craftText:SetPoint("RIGHT", row.have, "LEFT", -6, 0)
  row.craftText:SetJustifyH("RIGHT")

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.name:SetPoint("RIGHT", row.craftText, "LEFT", -4, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  row.header = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  row.header:SetPoint("LEFT", 2, 0)

  row:SetScript("OnEnter", function(self)
    if not self.itemID then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetItemByID(self.itemID)
    if self.recipeID then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Click to open recipe", GREEN_FONT_COLOR:GetRGB())
      GameTooltip:AddLine("Shift-click to link in chat", GREEN_FONT_COLOR:GetRGB())
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" or not self.recipeID then return end
    if IsModifiedClick("CHATLINK") then
      local _, link = C_Item.GetItemInfo(self.itemID)
      if link then ChatFrameUtil.InsertLink(link) end
    else
      -- Keep showing the parent recipe when the profession window follows this click.
      ns.ignoreSelect = self.recipeID
      C_TradeSkillUI.OpenRecipe(self.recipeID)
    end
  end)

  rows[i] = row
  return row
end

local function SetHeader(i, text)
  local row = GetRow(i)
  row.key = nil
  row.itemID = nil
  row.recipeID = nil
  row.icon:Hide()
  row.toggle:Hide()
  row.input:Hide()
  row.name:SetText("")
  row.have:SetText("")
  row.needText:SetText("")
  row.craftText:SetText("")
  row.header:SetText(text)
  row:Show()
end

-- open: nil = no toggle (not craftable), true/false = expanded state.
local function SetItem(i, itemID, key, depth, recipeID, open, isTotal)
  local row = GetRow(i)
  row.key = key
  row.itemID = itemID
  row.recipeID = recipeID
  row.isTotal = isTotal
  row.open = open
  row.header:SetText("")
  row.toggle:ClearAllPoints()
  row.toggle:SetPoint("LEFT", depth * INDENT + 2, 0)
  row.toggle:SetShown(open ~= nil)
  if open ~= nil then SetToggle(row.toggle, open) end
  row.icon:SetTexture(C_Item.GetItemIconByID(itemID))
  row.icon:Show()
  row.input:SetShown(isTotal)
  row.have:SetText("")
  row.needText:SetText("")
  row.craftText:SetText("")
  row.name:SetText(ns.ItemText(itemID))
  row:Show()
end

Render = function()
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

  plan = ns.Compute(current.hit, current.count)
  local i = 1
  SetHeader(i, "Materials")
  Walk(plan.tree, "", function(node, key)
    local open
    if node.recipeID then open = node.open == true end
    i = i + 1; SetItem(i, node.itemID, key, node.depth, node.recipeID, open, false)
  end)
  i = i + 1; SetHeader(i, " ")
  i = i + 1; SetHeader(i, "Totals")
  for _, l in ipairs(plan.totals) do
    i = i + 1; SetItem(i, l.itemID, "total:" .. l.itemID, 0, l.recipeID, nil, true)
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

function ns.IsWindowShown()
  return window:IsShown()
end

-- Docks beside dockTo until the player drags the window somewhere else.
function ns.LoadRecipe(recipeID, dockTo)
  local hit = ns.FindRecipeByID(recipeID)
  if not hit then return false end
  current = { hit = hit, count = 1 }
  qtyBox:SetText(1)
  if dockTo and not moved then
    window:ClearAllPoints()
    -- Clears the profession tabs that hang off the frame's right edge.
    window:SetPoint("TOPLEFT", dockTo, "TOPRIGHT", 56, 0)
  end
  if window:IsShown() then Render() else window:Show() end
  return true
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
  if not window:IsShown() or not current then return end
  Refresh()
end)
