local ADDON, ns = ...

local ROW_HEIGHT = 22
local current -- { hit = ..., count = n }
local TabFocus

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
  box:SetScript("OnTabPressed", function(self) TabFocus(self) end)
  return box
end

local qtyBox = NumberBox(window)
qtyBox:SetPoint("TOPRIGHT", window, "TOPRIGHT", -34, -54)
qtyBox:SetText("1")

local qtyLabel = window:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
qtyLabel:SetPoint("RIGHT", qtyBox, "LEFT", -8, 0)
qtyLabel:SetText("Qty")

-- Don't reselect in an already-open profession window by calling CraftingPage:Init
-- ourselves: that taints the profession UI for the session and later blocks using
-- items from bags. When the open window sits on the base profession (no expansion
-- child), ProfessionsFrame defers OPEN_RECIPE_RESPONSE until a TRADE_SKILL_LIST_UPDATE
-- that never comes; reopening the profession sends one and Blizzard applies it.
-- Checked a frame later: the deferral isn't visible yet when OpenRecipe returns.
local function OpenRecipe(recipeID)
  local wasShown = ProfessionsFrame and ProfessionsFrame:IsShown()
  C_TradeSkillUI.OpenRecipe(recipeID)
  if not wasShown then return end
  C_Timer.After(0, function()
    if not (ProfessionsFrame:IsShown() and ProfessionsFrame.openRecipeResponse) then return end
    if C_TradeSkillUI.IsDataSourceChanging() then return end
    local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(recipeID)
    local base = info and (info.parentProfessionID or info.professionID)
    if base and base ~= 0 then C_TradeSkillUI.OpenTradeSkill(base) end
  end)
end

local function OpenOrLink(itemID, recipeID)
  if IsModifiedClick("CHATLINK") then
    local _, link = C_Item.GetItemInfo(itemID)
    if link then ChatFrameUtil.InsertLink(link) end
  else
    OpenRecipe(recipeID)
  end
end

local function AddClickHints()
  GameTooltip:AddLine("Click to open recipe", GREEN_FONT_COLOR:GetRGB())
  GameTooltip:AddLine("Shift-click to link in chat", GREEN_FONT_COLOR:GetRGB())
end

local titleButton = CreateFrame("Button", nil, window)
titleButton:SetPoint("TOPLEFT", icon, "TOPLEFT")
titleButton:SetPoint("BOTTOM", icon, "BOTTOM")
titleButton:SetPoint("RIGHT", qtyLabel, "LEFT", -8, 0)
titleButton:Hide()
titleButton:SetScript("OnClick", function()
  OpenOrLink(current.hit.recipe.outputItemID, current.hit.recipeID)
end)
titleButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(current.hit.recipe.outputItemID)
  GameTooltip:AddLine(" ")
  AddClickHints()
  GameTooltip:Show()
end)
titleButton:SetScript("OnLeave", GameTooltip_Hide)

local hint = window:CreateFontString(nil, "OVERLAY", "GameFontDisable")
hint:SetPoint("CENTER", window, "CENTER", 0, 0)
hint:SetWidth(300)
hint:SetText("Select a recipe in your profession window and click the WhatMats button to load it.")

local profitButton = CreateFrame("Button", nil, window)
profitButton:SetPoint("TOPLEFT", 14, -74)
profitButton:SetPoint("RIGHT", window, "RIGHT", -14, 0)
profitButton:SetHeight(18)
profitButton:Hide()
profitButton.toggle = profitButton:CreateTexture(nil, "ARTWORK")
profitButton.toggle:SetSize(14, 14)
profitButton.toggle:SetPoint("LEFT", 0, 0)
profitButton.text = profitButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
profitButton.text:SetPoint("LEFT", profitButton.toggle, "RIGHT", 6, 0)
profitButton.text:SetPoint("RIGHT")
profitButton.text:SetJustifyH("LEFT")

local panel = CreateFrame("Frame", nil, window)
panel:SetPoint("TOPLEFT", profitButton, "BOTTOMLEFT", 0, -2)
panel:SetPoint("RIGHT", window, "RIGHT", -14, 0)
panel:Hide()
local panelBg = panel:CreateTexture(nil, "BACKGROUND")
panelBg:SetAllPoints()
panelBg:SetColorTexture(0, 0, 0, 0.35)

local scroll = CreateFrame("ScrollFrame", nil, window, "UIPanelScrollFrameTemplate")
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(330, 1)
scroll:SetScrollChild(content)

local INDENT = 14

local rows = {}
local plan

local expandButton = CreateFrame("Button", nil, content)
expandButton:SetHeight(ROW_HEIGHT)
expandButton:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, 0)
expandButton:SetNormalFontObject("GameFontNormalSmall")
expandButton:SetHighlightFontObject("GameFontHighlightSmall")
expandButton:Hide()

local trackCheck = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
trackCheck:SetSize(20, 20)
trackCheck:Hide()
trackCheck.label = trackCheck:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
trackCheck.label:SetPoint("RIGHT", trackCheck, "LEFT", -2, 0)
trackCheck.label:SetText("Track")
trackCheck:SetScript("OnClick", function(self)
  ns.SetTracked(current.hit.recipeID, current.count, self:GetChecked())
end)
trackCheck:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:AddLine("Track these totals")
  GameTooltip:AddLine("Shows them in the WhatMats tracker; shift-click it there to stop", HIGHLIGHT_FONT_COLOR:GetRGB())
  GameTooltip:Show()
end)
trackCheck:SetScript("OnLeave", GameTooltip_Hide)

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

local function Counts(itemID)
  local bags = C_Item.GetItemCount(itemID)
  return bags, C_Item.GetItemCount(itemID, true, false, true, true) - bags
end

-- covered defaults to whether bags + bank hold need.
local function HaveText(itemID, need, covered)
  local bags, bank = Counts(itemID)
  local total = bags + bank
  if covered == nil then covered = total >= need end
  -- Yellow: covered, but some of it is still in a bank.
  local color = not covered and RED_FONT_COLOR
    or bags >= need and GREEN_FONT_COLOR
    or YELLOW_FONT_COLOR
  local text = tostring(bags)
  if bank > 0 then text = text .. " (+" .. bank .. ")" end
  return color:WrapTextInColorCode(text) .. " /"
end

local PROFIT_ROW = 20
local FOOT_LINE = 16
local PANEL_TOP = 24
local panelOpen = false
local priceRows = {}
local UpdateProfit

local SOURCE_TAG = {
  manual = "set", ah = "AH", vendor = "vend", auctionator = "scan", ["auctionator-vendor"] = "vend",
  seen = "low", ["vendor-list"] = "vend",
}

local function DaysAgo(seconds)
  local days = math.floor(seconds / 86400)
  if days == 0 then return "today" end
  return days == 1 and "1 day ago" or (days .. " days ago")
end

local function SourceText(src, age, when, isOutput)
  if src == "manual" then return "Your price" end
  if src == "ah" then return "Last AH purchase, " .. DaysAgo(time() - when) end
  if src == "vendor" then return "Last vendor purchase, " .. DaysAgo(time() - when) end
  if src == "vendor-list" then return "Vendor price when you last visited, " .. DaysAgo(time() - when) end
  if src == "seen" then return "Lowest AH listing when you last viewed it, " .. DaysAgo(time() - when) end
  if src == "auctionator-vendor" then return "Auctionator vendor price" end
  if src == "auctionator" then
    return "Auctionator AH scan, " .. (age and DaysAgo(age * 86400) or "over 21 days ago")
  end
  if isOutput then return "No price yet. Search it on the AH or type one in " .. ns.UnitName() .. "." end
  return "No price yet. Visit a vendor that sells it, search it on the AH, or type one in " .. ns.UnitName() .. "."
end

local STALE_DAYS = 7

local function Stale(src, age, when)
  if src == "auctionator" then return age == nil or age > STALE_DAYS end
  if src == "seen" then return time() - when > STALE_DAYS * 86400 end
  return false
end

local function PriceDB(row)
  return row.isOutput and ns.prices.sale or ns.prices.cost
end

local function PriceRowTooltip(self)
  local row = self.itemID and self or self:GetParent()
  if not row.itemID then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetItemByID(row.itemID)
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(SourceText(row.src, row.age, row.when, row.isOutput), HIGHLIGHT_FONT_COLOR:GetRGB())
  if row.short and row.short > 0 and not row.self then
    GameTooltip:AddLine("Need to buy " .. row.short, HIGHLIGHT_FONT_COLOR:GetRGB())
  end
  GameTooltip:AddLine("Type a price in " .. ns.UnitName() .. "; right-click the box to clear it", GREEN_FONT_COLOR:GetRGB())
  if not row.isOutput then
    GameTooltip:AddLine("Check the box if you gather or make it yourself", GREEN_FONT_COLOR:GetRGB())
  end
  GameTooltip:Show()
end

local function GetPriceRow(i)
  local row = priceRows[i]
  if row then return row end

  row = CreateFrame("Frame", nil, panel)
  row:SetHeight(PROFIT_ROW)
  row:SetPoint("TOPLEFT", 4, -PANEL_TOP - (i - 1) * PROFIT_ROW)
  row:SetPoint("RIGHT", panel, "RIGHT", -4, 0)
  row:EnableMouse(true)
  row:SetScript("OnEnter", PriceRowTooltip)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnMouseUp", function(self, button)
    if button == "LeftButton" and self.itemID and IsModifiedClick("CHATLINK") then
      OpenOrLink(self.itemID)
    end
  end)

  row.check =CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
  row.check:SetSize(20, 20)
  row.check:SetPoint("LEFT", 0, 0)
  row.check:SetScript("OnClick", function(self)
    ns.prices.self[row.itemID] = self:GetChecked() or nil
    UpdateProfit()
  end)
  row.check:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Self-sourced")
    GameTooltip:AddLine("Leave this material out of the cost", HIGHLIGHT_FONT_COLOR:GetRGB())
    GameTooltip:Show()
  end)
  row.check:SetScript("OnLeave", GameTooltip_Hide)

  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(14, 14)
  row.icon:SetPoint("LEFT", row.check, "RIGHT", 2, 0)

  row.subtotal = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.subtotal:SetPoint("RIGHT", -2, 0)
  row.subtotal:SetWidth(62)
  row.subtotal:SetJustifyH("RIGHT")

  row.tag = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.tag:SetPoint("RIGHT", row.subtotal, "LEFT", -2, 0)
  row.tag:SetWidth(30)
  row.tag:SetJustifyH("LEFT")

  row.box = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
  row.box:SetSize(52, 18)
  row.box:SetPoint("RIGHT", row.tag, "LEFT", -4, 0)
  row.box:SetAutoFocus(false)
  row.box:SetMaxLetters(9)
  row.box:SetJustifyH("RIGHT")
  row.box:SetTextInsets(0, 6, 0, 0)
  row.box:SetScript("OnEnterPressed", row.box.ClearFocus)
  row.box:SetScript("OnEscapePressed", row.box.ClearFocus)
  row.box:SetScript("OnTabPressed", function(self) TabFocus(self) end)
  row.box:SetScript("OnTextChanged", function(self, userInput)
    if not userInput then return end
    local text = strtrim(self:GetText())
    if text == "" then
      PriceDB(row)[row.itemID] = nil
    else
      local copper = ns.ParseMoney(text)
      if not copper then return end
      PriceDB(row)[row.itemID] = copper
    end
    UpdateProfit()
  end)
  row.box:SetScript("OnEditFocusLost", function() UpdateProfit() end)
  row.box:SetScript("OnMouseDown", function(self, button)
    if button ~= "RightButton" then return end
    PriceDB(row)[row.itemID] = nil
    self:ClearFocus()
    UpdateProfit()
  end)
  row.box:SetScript("OnEnter", PriceRowTooltip)
  row.box:SetScript("OnLeave", GameTooltip_Hide)

  row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.name:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
  row.name:SetPoint("RIGHT", row.box, "LEFT", -10, 0)
  row.name:SetJustifyH("LEFT")
  row.name:SetWordWrap(false)

  priceRows[i] = row
  return row
end

local function FootLine()
  local left = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  local right = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  left:SetJustifyH("LEFT")
  right:SetJustifyH("RIGHT")
  return { left = left, right = right }
end

local foot = { revenue = FootLine(), cost = FootLine(), net = FootLine(), ratio = FootLine() }
foot.revenue.left:SetText("Revenue")
foot.cost.left:SetText("Cost")
foot.net.left:SetText("Net")
foot.ratio.left:SetText("Ratio")
local FOOT_ORDER = { foot.revenue, foot.cost, foot.net, foot.ratio }

local ahCut = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
ahCut:SetSize(20, 20)
ahCut.label = ahCut:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ahCut.label:SetPoint("LEFT", ahCut, "RIGHT", 2, 0)
ahCut.label:SetText("Deduct 5% AH cut from revenue")
ahCut:SetScript("OnClick", function(self)
  WhatMatsPriceDB.ahCut = self:GetChecked()
  UpdateProfit()
end)

local function UnitRadio(unit, label)
  local radio = CreateFrame("CheckButton", nil, panel, "UIRadioButtonTemplate")
  radio.text:SetText(label)
  radio.text:SetFontObject("GameFontHighlightSmall")
  radio:SetScript("OnClick", function()
    WhatMatsPriceDB.unit = unit
    for _, row in ipairs(priceRows) do row.box:ClearFocus() end
    UpdateProfit()
  end)
  return radio
end

local goldRadio = UnitRadio("gold", "Gold")
goldRadio:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -34, -5)
local silverRadio = UnitRadio("silver", "Silver")
silverRadio:SetPoint("RIGHT", goldRadio, "LEFT", -40, 0)
local unitLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
unitLabel:SetPoint("RIGHT", silverRadio, "LEFT", -6, 0)
unitLabel:SetText("Prices in")

local function Layout()
  local open = current ~= nil and panelOpen
  panel:SetShown(open)
  profitButton.toggle:SetTexture("Interface\\Buttons\\UI-" .. (open and "Minus" or "Plus") .. "Button-Up")
  scroll:ClearAllPoints()
  if current == nil then
    scroll:SetPoint("TOPLEFT", 12, -82)
  else
    scroll:SetPoint("TOPLEFT", open and panel or profitButton, "BOTTOMLEFT", -2, -6)
  end
  scroll:SetPoint("BOTTOMRIGHT", -32, 10)
end

profitButton:SetScript("OnClick", function()
  panelOpen = not panelOpen
  Layout()
end)

local function RenderProfit()
  for _, row in ipairs(priceRows) do row:Hide() end
  local i = 1
  local out = GetPriceRow(i)
  out.itemID = current.hit.recipe.outputItemID
  out.isOutput = true
  out.check:Hide()
  out:Show()
  for _, l in ipairs(plan.priceTotals) do
    i = i + 1
    local row = GetPriceRow(i)
    row.itemID = l.itemID
    row.isOutput = false
    row.check:Show()
    row:Show()
  end

  local y = -PANEL_TOP - i * PROFIT_ROW - 4
  for _, line in ipairs(FOOT_ORDER) do
    line.left:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, y)
    line.right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -6, y)
    y = y - FOOT_LINE
  end
  ahCut:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, y + 2)
  panel:SetHeight(-y + 22)
end

local function Money(copper, signed)
  if not copper then return RED_FONT_COLOR:WrapTextInColorCode("?") end
  if not signed then return ns.FormatMoney(copper) end
  local text = (copper >= 0 and "+" or "-") .. ns.FormatMoney(math.abs(copper))
  return (copper >= 0 and GREEN_FONT_COLOR or RED_FONT_COLOR):WrapTextInColorCode(text)
end

local function SetPriceRow(row, n, unit, src, age, when, subtotal)
  row.src, row.age, row.when = src, age, when
  row.icon:SetTexture(C_Item.GetItemIconByID(row.itemID))
  row.name:SetText(n .. " x " .. ns.ItemText(row.itemID))
  if not row.box:HasFocus() then
    row.box:SetText(unit and ns.FormatAmount(unit) or "")
    if src == "manual" then row.box:SetTextColor(1, 1, 1) else row.box:SetTextColor(0.6, 0.6, 0.6) end
  end
  local tag = src and SOURCE_TAG[src] or ORANGE_FONT_COLOR:WrapTextInColorCode("?")
  row.tag:SetText(Stale(src, age, when) and ORANGE_FONT_COLOR:WrapTextInColorCode(tag) or tag)
  row.subtotal:SetText(subtotal)
end

UpdateProfit = function()
  if not current then return end
  local p = ns.Profit(current.hit, current.count, plan.priceTotals)

  for _, row in ipairs(priceRows) do
    if row:IsShown() then
      if row.isOutput then
        row.short = nil
        SetPriceRow(row, p.made, p.sale, p.saleSrc, p.saleAge, p.saleTime, Money(p.revenue))
      else
        local l = p.lines[row.itemID] or { n = 0, short = 0 }
        row.short, row.self = l.short, l.self
        row.check:SetChecked(l.self)
        local subtotal = l.self and GRAY_FONT_COLOR:WrapTextInColorCode("self") or Money(l.market)
        SetPriceRow(row, l.n, l.unit, l.src, l.age, l.time, subtotal)
      end
    end
  end

  ahCut:SetChecked(WhatMatsPriceDB.ahCut)
  goldRadio:SetChecked(ns.UnitName() == "gold")
  silverRadio:SetChecked(ns.UnitName() == "silver")
  foot.revenue.right:SetText(Money(p.revenue))
  foot.cost.right:SetText(Money(p.market) .. GRAY_FONT_COLOR:WrapTextInColorCode("  (to buy " .. ns.FormatMoney(p.cash) .. ")"))
  foot.net.right:SetText(p.net and Money(p.net, true) or Money(nil))
  local ratio = p.ratio and string.format("%.2f", p.ratio) or (p.revenue and "no cost" or "?")
  foot.ratio.right:SetText(ratio)

  local summary
  if not p.revenue then
    summary = GRAY_FONT_COLOR:WrapTextInColorCode("Profit: set a sale price")
  else
    summary = "Profit " .. Money(p.net, true) .. "   ratio " .. ratio
    if p.missing then summary = summary .. GRAY_FONT_COLOR:WrapTextInColorCode("  (missing prices)") end
  end
  profitButton.text:SetText(summary)
end

local function UpdateValues()
  local recipe = current.hit.recipe
  local suffix = recipe.made > 1 and (" - makes " .. current.count * recipe.made) or ""
  subtitle:SetText(current.hit.profName .. suffix)
  trackCheck:SetChecked(ns.IsTracked(current.hit.recipeID))

  local byKey = Index(plan)
  for _, row in ipairs(rows) do
    if row:IsShown() and row.key then
      local data = byKey[row.key]
      if row.isTotal then
        local n = data and data.n or 0
        if not row.input:HasFocus() then row.input:SetText(n) end
        row.countNeed = n
        row.have:SetText(HaveText(row.itemID, n))
        local short = n - C_Item.GetItemCount(row.itemID, true, false, true, true)
        row.craftText:SetText(short > 0 and ("short " .. short) or "")
      else
        row.countNeed = data and data.need or 0
        row.have:SetText(HaveText(row.itemID, data and data.used or 0, data ~= nil and data.short == 0))
        row.needText:SetText(data and data.need or 0)
        row.craftText:SetText(data and data.made > 0 and ("craft " .. data.made) or "")
      end
    end
  end
  UpdateProfit()
end

local Render

local function Editing()
  for _, row in ipairs(rows) do
    if row:IsShown() and row.input:HasFocus() then return true end
  end
  for _, row in ipairs(priceRows) do
    if row:IsShown() and row.box:HasFocus() then return true end
  end
  return false
end

-- Visible inputs in screen order; the price boxes drop out while the profit panel is collapsed.
local function Inputs()
  local list = { qtyBox }
  for _, row in ipairs(priceRows) do
    if row.box:IsVisible() then table.insert(list, row.box) end
  end
  for _, row in ipairs(rows) do
    if row.input:IsVisible() then table.insert(list, row.input) end
  end
  return list
end

-- Clear focus first: a Totals input's focus loss re-renders and rehides rows,
-- which would drop focus already moved to the next box.
TabFocus = function(self)
  self:ClearFocus()
  local list = Inputs()
  local i = tIndexOf(list, self)
  if not i then return end
  local nextBox = list[(i - 1 + (IsShiftKeyDown() and -1 or 1)) % #list + 1]
  nextBox:SetFocus()
  nextBox:HighlightText()
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
  current.count = math.max(count, 1)
  if not fromQtyBox then qtyBox:SetText(count) end
  ns.SetTrackedCount(current.hit.recipeID, current.count)
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

  -- Totals rows have no toggle, so the vendor marker takes its slot.
  row.vendor = row:CreateTexture(nil, "ARTWORK")
  row.vendor:SetSize(14, 14)
  row.vendor:SetPoint("CENTER", row.toggle, "CENTER")
  row.vendor:SetTexture("Interface\\GossipFrame\\VendorGossipIcon")

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
    if self.isTotal and ns.IsVendorItem(self.itemID) then
      GameTooltip:AddLine(" ")
      GameTooltip:AddLine("Sold by a vendor", HIGHLIGHT_FONT_COLOR:GetRGB())
    end
    if self.recipeID then
      GameTooltip:AddLine(" ")
      if self.profName and self.profName ~= current.hit.profName then
        GameTooltip:AddLine("Crafted with " .. self.profName, HIGHLIGHT_FONT_COLOR:GetRGB())
      end
      AddClickHints()
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", GameTooltip_Hide)
  row:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" or not self.itemID then return end
    if self.recipeID or IsModifiedClick("CHATLINK") then
      OpenOrLink(self.itemID, self.recipeID)
    end
  end)

  row.counts = CreateFrame("Frame", nil, row)
  row.counts:SetHeight(ROW_HEIGHT)
  row.counts:EnableMouse(true)
  row.counts:SetScript("OnEnter", function(self)
    local bags, bank = Counts(row.itemID)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine("In your bags / bank")
    GameTooltip:AddLine("Bags: " .. bags, HIGHLIGHT_FONT_COLOR:GetRGB())
    GameTooltip:AddLine("Bank: " .. bank, HIGHLIGHT_FONT_COLOR:GetRGB())
    GameTooltip:AddLine((row.isTotal and "Needed in total: " or "Needed: ") .. (row.countNeed or 0), HIGHLIGHT_FONT_COLOR:GetRGB())
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Enough in your bags", GREEN_FONT_COLOR:GetRGB())
    GameTooltip:AddLine("Enough, but some is in your bank", YELLOW_FONT_COLOR:GetRGB())
    GameTooltip:AddLine("Not enough yet", RED_FONT_COLOR:GetRGB())
    GameTooltip:Show()
  end)
  row.counts:SetScript("OnLeave", GameTooltip_Hide)
  row.counts:SetScript("OnMouseUp", function(_, button)
    row:GetScript("OnMouseUp")(row, button)
  end)

  rows[i] = row
  return row
end

-- itemID -> { mode = prior expand state } from the last Expand all, so Reset
-- restores hand-set collapses instead of dropping them to suggested.
local beforeExpand

expandButton:SetScript("OnClick", function(self)
  if self.allOpen then
    for _, itemID in ipairs(self.parts) do
      local saved = beforeExpand and beforeExpand[itemID]
      if saved then WhatMatsDB.expand[itemID] = saved.mode else WhatMatsDB.expand[itemID] = nil end
    end
    beforeExpand = nil
  else
    beforeExpand = {}
    for _, itemID in ipairs(self.parts) do
      beforeExpand[itemID] = { mode = WhatMatsDB.expand[itemID] }
      WhatMatsDB.expand[itemID] = true
    end
  end
  Render()
end)
expandButton:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if self.allOpen then
    GameTooltip:AddLine("Put parts back the way they were")
  else
    GameTooltip:AddLine("Break down every part " .. current.hit.profName .. " makes")
  end
  GameTooltip:Show()
end)
expandButton:SetScript("OnLeave", GameTooltip_Hide)

local function UpdateExpandButton()
  local parts = current and ns.CraftableParts(current.hit) or {}
  expandButton:SetShown(#parts > 0)
  if #parts == 0 then return end
  -- Rows are mouse-enabled siblings; keep the button above the header row.
  expandButton:SetFrameLevel(content:GetFrameLevel() + 5)
  local allOpen = true
  for _, itemID in ipairs(parts) do
    if WhatMatsDB.expand[itemID] ~= true then allOpen = false end
  end
  expandButton.parts = parts
  expandButton.allOpen = allOpen
  expandButton:SetText(allOpen and "Reset" or "Expand all")
  expandButton:SetWidth(expandButton:GetFontString():GetStringWidth() + 8)
end

local function SetHeader(i, text)
  local row = GetRow(i)
  row.key = nil
  row.itemID = nil
  row.recipeID = nil
  row.icon:Hide()
  row.vendor:Hide()
  row.toggle:Hide()
  row.input:Hide()
  row.counts:Hide()
  row.countNeed = nil
  row.name:SetText("")
  row.have:SetText("")
  row.needText:SetText("")
  row.craftText:SetText("")
  row.header:SetText(text)
  row:Show()
end

-- open: nil = no toggle (not craftable), true/false = expanded state.
local function SetItem(i, itemID, key, depth, recipeID, open, isTotal, profName)
  local row = GetRow(i)
  row.key = key
  row.itemID = itemID
  row.recipeID = recipeID
  row.profName = profName
  row.isTotal = isTotal
  row.open = open
  row.header:SetText("")
  row.toggle:ClearAllPoints()
  row.toggle:SetPoint("LEFT", depth * INDENT + 2, 0)
  row.toggle:SetShown(open ~= nil)
  if open ~= nil then SetToggle(row.toggle, open) end
  row.vendor:SetShown(isTotal and ns.IsVendorItem(itemID))
  row.icon:SetTexture(C_Item.GetItemIconByID(itemID))
  row.icon:Show()
  row.input:SetShown(isTotal)
  row.countNeed = nil
  row.counts:ClearAllPoints()
  row.counts:SetPoint("LEFT", row.have, "LEFT")
  row.counts:SetPoint("RIGHT", isTotal and row.have or row.needText, "RIGHT")
  row.counts:Show()
  row.have:SetText("")
  row.needText:SetText("")
  row.craftText:SetText("")
  row.name:SetText(ns.ItemText(itemID))
  row:Show()
end

Render = function()
  for _, row in ipairs(rows) do row:Hide() end
  titleButton:SetShown(current ~= nil)
  profitButton:SetShown(current ~= nil)
  trackCheck:SetShown(current ~= nil)
  UpdateExpandButton()
  Layout()
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
    i = i + 1; SetItem(i, node.itemID, key, node.depth, node.recipeID, open, false, node.profName)
  end)
  i = i + 1; SetHeader(i, " ")
  i = i + 1; SetHeader(i, "Totals")
  trackCheck:ClearAllPoints()
  trackCheck:SetPoint("RIGHT", rows[i], "RIGHT", -4, 0)
  -- Rows are mouse-enabled siblings; keep the checkbox above the header row.
  trackCheck:SetFrameLevel(content:GetFrameLevel() + 5)
  for _, l in ipairs(plan.totals) do
    i = i + 1; SetItem(i, l.itemID, "total:" .. l.itemID, 0, l.recipeID, nil, true)
  end
  content:SetHeight(i * ROW_HEIGHT)
  RenderProfit()
  UpdateValues()
  ns.RefreshTracker()
end

qtyBox:SetScript("OnTextChanged", function(self, userInput)
  if not userInput or not current then return end
  SetCount(tonumber(self:GetText()) or 0, true)
end)
qtyBox:SetScript("OnEditFocusLost", function(self)
  if current then self:SetText(current.count) end
end)

function ns.ToggleWindow()
  window:SetShown(not window:IsShown())
end

-- Only a window the profession button opened closes with the profession frame.
local fromProfession = false

function ns.CloseIfFromProfession()
  if fromProfession then window:Hide() end
end

-- Docks beside dockTo until the player drags the window somewhere else.
function ns.LoadRecipe(recipeID, dockTo, count)
  local hit = ns.FindRecipeByID(recipeID)
  if not hit then return false end
  current = { hit = hit, count = count or 1 }
  qtyBox:SetText(current.count)
  if dockTo and not moved then
    window:ClearAllPoints()
    -- Clears the profession tabs that hang off the frame's right edge.
    window:SetPoint("TOPLEFT", dockTo, "TOPRIGHT", 56, 0)
    window:SetHeight(dockTo:GetHeight())
  end
  if window:IsShown() then
    Render()
  else
    fromProfession = dockTo ~= nil
    window:Show()
  end
  return true
end

window:SetScript("OnShow", Render)
window:SetScript("OnHide", function() fromProfession = false end)

window:RegisterEvent("BAG_UPDATE_DELAYED")
window:RegisterEvent("GET_ITEM_INFO_RECEIVED")
function ns.RefreshWindow()
  if not window:IsShown() or not current then return end
  Refresh()
end

window:SetScript("OnEvent", ns.RefreshWindow)
