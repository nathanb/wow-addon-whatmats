local ADDON, ns = ...

-- Our own frame styled like a tracker module. Running inside Blizzard's
-- ObjectiveTracker update taints it (quest item buttons), so we stay out of it.
local WIDTH = 260
local BLOCK_X = 20
local HEADER_GAP = 10
local BLOCK_GAP = 10
local LINE_SPACING = 4
local DEFAULT_POINT = { "TOPRIGHT", UIParent, "TOPRIGHT", -330, -240 }

local frame
local blocks = {}
local collapsed = false
local queued = false

local function Find(recipeID)
  for i, t in ipairs(WhatMatsDB.tracked) do
    if t.recipeID == recipeID then return i, t end
  end
end

function ns.IsTracked(recipeID)
  return Find(recipeID) ~= nil
end

local Layout

-- Bag and item-info events come in bursts; lay out once per frame.
function ns.RefreshTracker()
  if not frame or queued then return end
  queued = true
  C_Timer.After(0, function()
    queued = false
    Layout()
  end)
end

function ns.SetTracked(recipeID, count, on)
  local i = Find(recipeID)
  if on and not i then
    table.insert(WhatMatsDB.tracked, { recipeID = recipeID, count = count })
  elseif not on and i then
    table.remove(WhatMatsDB.tracked, i)
  end
  ns.RefreshTracker()
end

function ns.SetTrackedCount(recipeID, count)
  local _, t = Find(recipeID)
  if t and t.count ~= count then
    t.count = count
    ns.RefreshTracker()
  end
end

local function Untrack(recipeID)
  ns.SetTracked(recipeID, nil, false)
  ns.RefreshWindow()
end

local function Open(recipeID)
  local _, t = Find(recipeID)
  ns.LoadRecipe(recipeID, nil, t and t.count)
end

local function OnHeaderClick(self, mouseButton)
  local recipeID = self:GetParent().recipeID
  if IsModifiedClick("CHATLINK") and ChatFrameUtil.GetActiveWindow() then
    local hit = ns.FindRecipeByID(recipeID)
    if hit then
      local _, link = C_Item.GetItemInfo(hit.recipe.outputItemID)
      if link then ChatFrameUtil.InsertLink(link) end
    end
  elseif mouseButton == "RightButton" then
    MenuUtil.CreateContextMenu(frame, function(_, root)
      root:CreateButton("Open in " .. ADDON, function() Open(recipeID) end)
      root:CreateButton(PROFESSIONS_UNTRACK_RECIPE, function() Untrack(recipeID) end)
    end)
  elseif IsModifiedClick("RECIPEWATCHTOGGLE") then
    Untrack(recipeID)
  else
    Open(recipeID)
  end
end

local function SetText(fontString, text, color)
  fontString:SetHeight(0)
  fontString:SetText(text)
  fontString:SetTextColor(color.r, color.g, color.b)
  return fontString:GetHeight()
end

local function NewFontString(parent)
  local fs = parent:CreateFontString(nil, "ARTWORK")
  fs:SetFontObject(ObjectiveTrackerLineFont)
  fs:SetMaxLines(2)
  return fs
end

local function GetBlock(i)
  local block = blocks[i]
  if not block then
    block = CreateFrame("Frame", nil, frame)
    block.HeaderText = NewFontString(block)
    block.HeaderText:SetPoint("TOPLEFT")
    block.HeaderText:SetPoint("RIGHT")
    local button = CreateFrame("Button", nil, block)
    button:SetPoint("TOPLEFT", block.HeaderText)
    button:SetPoint("BOTTOMRIGHT", block.HeaderText)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", OnHeaderClick)
    block.lines = {}
    blocks[i] = block
  end
  return block
end

local function GetLine(block, i)
  local line = block.lines[i]
  if not line then
    line = CreateFrame("Frame", nil, block)
    line.Dash = NewFontString(line)
    line.Dash:SetText(QUEST_DASH)
    line.Dash:SetPoint("TOPLEFT", 0, 1)
    line.Text = NewFontString(line)
    line.Text:SetPoint("TOP")
    line.Text:SetPoint("LEFT", line.Dash, "RIGHT")
    line.Text:SetPoint("RIGHT")
    line.Icon = line:CreateTexture(nil, "ARTWORK")
    line.Icon:SetAtlas("ui-questtracker-tracker-check", false)
    line.Icon:SetSize(16, 16)
    line.Icon:SetPoint("TOPLEFT", -10, 2)
    block.lines[i] = line
  end
  return line
end

local function LayoutBlock(block, hit, count)
  local color = OBJECTIVE_TRACKER_COLOR
  local height = SetText(block.HeaderText, count > 1 and (hit.recipe.name .. " x" .. count) or hit.recipe.name, color.Header)
  local anchor = block.HeaderText
  local n = 0
  for _, l in ipairs(ns.Compute(hit, count).totals) do
    n = n + 1
    local line = GetLine(block, n)
    local have = C_Item.GetItemCount(l.itemID, true, false, true, true)
    local name = C_Item.GetItemNameByID(l.itemID) or ("item " .. l.itemID)
    local met = have >= l.n
    local text = PROFESSIONS_TRACKER_REAGENT_FORMAT:format(PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT:format(have, l.n), name)
    line:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -LINE_SPACING)
    line:SetPoint("RIGHT", block)
    line.Dash:SetShown(not met)
    line.Icon:SetShown(met)
    local h = SetText(line.Text, text, met and color.Complete or color.Normal)
    line:SetHeight(h)
    line:Show()
    height = height + LINE_SPACING + h
    anchor = line
  end
  for i = n + 1, #block.lines do
    block.lines[i]:Hide()
  end
  block:SetHeight(height)
  return height
end

Layout = function()
  local height = frame.Header:GetHeight()
  local shown, any = 0, false
  for _, t in ipairs(WhatMatsDB and WhatMatsDB.tracked or {}) do
    local hit = ns.FindRecipeByID(t.recipeID)
    if hit then
      any = true
      if not collapsed then
        shown = shown + 1
        local block = GetBlock(shown)
        block.recipeID = t.recipeID
        block:ClearAllPoints()
        if shown == 1 then
          block:SetPoint("TOPLEFT", frame.Header, "BOTTOMLEFT", BLOCK_X, -HEADER_GAP)
          height = height + HEADER_GAP
        else
          block:SetPoint("TOPLEFT", blocks[shown - 1], "BOTTOMLEFT", 0, -BLOCK_GAP)
          height = height + BLOCK_GAP
        end
        block:SetPoint("RIGHT", frame)
        height = height + LayoutBlock(block, hit, t.count)
        block:Show()
      end
    end
  end
  for i = shown + 1, #blocks do
    blocks[i]:Hide()
  end
  frame:SetHeight(height)
  frame:SetShown(any)
end

local function SavePosition()
  WhatMatsDB.trackerPos = { x = frame:GetLeft(), y = frame:GetTop() }
end

local function RestorePosition()
  frame:ClearAllPoints()
  local pos = WhatMatsDB.trackerPos
  if pos then
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", pos.x, pos.y)
  else
    frame:SetPoint(unpack(DEFAULT_POINT))
  end
end

local function Create()
  frame = CreateFrame("Frame", nil, UIParent)
  frame:SetSize(WIDTH, 26)
  frame:SetFrameStrata("LOW")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:Hide()

  -- The header template's minimize button calls its parent's ToggleCollapsed.
  function frame:ToggleCollapsed()
    collapsed = not collapsed
    self.Header:SetCollapsed(collapsed)
    Layout()
  end

  frame.Header = CreateFrame("Frame", nil, frame, "ObjectiveTrackerModuleHeaderTemplate")
  frame.Header:SetPoint("TOPLEFT")
  frame.Header.Text:SetText(ADDON)
  frame.Header:EnableMouse(true)
  frame.Header:RegisterForDrag("LeftButton")
  frame.Header:SetScript("OnDragStart", function() frame:StartMoving() end)
  frame.Header:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    SavePosition()
  end)

  -- Text size changes resize the shared fonts but only re-lay Blizzard's own modules.
  if ObjectiveTrackerManager and ObjectiveTrackerManager.SetTextSize then
    hooksecurefunc(ObjectiveTrackerManager, "SetTextSize", ns.RefreshTracker)
  end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event)
  if not WhatMatsDB then return end
  if event == "PLAYER_LOGIN" then
    EventUtil.ContinueOnAddOnLoaded("Blizzard_ObjectiveTracker", function()
      Create()
      RestorePosition()
      ns.RefreshTracker()
    end)
  elseif #WhatMatsDB.tracked > 0 then
    ns.RefreshTracker()
  end
end)
