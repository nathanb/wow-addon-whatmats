local ADDON, ns = ...

local module
local pending = false

-- Our module runs inside Blizzard's tracker update, so stay out of it in
-- combat to keep taint away from quest item buttons and frame layout.
function ns.RefreshTracker()
  if not module then return end
  if InCombatLockdown() then
    pending = true
  else
    module:MarkDirty()
  end
end

local function Find(recipeID)
  for i, t in ipairs(WhatMatsDB.tracked) do
    if t.recipeID == recipeID then return i, t end
  end
end

function ns.IsTracked(recipeID)
  return Find(recipeID) ~= nil
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

local overrides = {
  headerText = ADDON,
  blockTemplate = "ObjectiveTrackerAnimBlockTemplate",
  lineTemplate = "ObjectiveTrackerAnimLineTemplate",
}

function overrides:LayoutContents()
  for _, t in ipairs(WhatMatsDB.tracked) do
    local hit = ns.FindRecipeByID(t.recipeID)
    if hit then
      local block = self:GetBlock(t.recipeID)
      block:SetHeader(t.count > 1 and (hit.recipe.name .. " x" .. t.count) or hit.recipe.name)
      for _, l in ipairs(ns.Compute(hit, t.count).totals) do
        local have = C_Item.GetItemCount(l.itemID, true, false, true, true)
        local name = C_Item.GetItemNameByID(l.itemID) or ("item " .. l.itemID)
        local text = PROFESSIONS_TRACKER_REAGENT_FORMAT:format(PROFESSIONS_TRACKER_REAGENT_COUNT_FORMAT:format(have, l.n), name)
        local met = have >= l.n
        local line = block:AddObjective(l.itemID, text, nil, nil,
          met and OBJECTIVE_DASH_STYLE_HIDE or OBJECTIVE_DASH_STYLE_SHOW,
          OBJECTIVE_TRACKER_COLOR[met and "Complete" or "Normal"])
        line.Icon:SetShown(met)
        if met then line.Icon:SetAtlas("ui-questtracker-tracker-check", false) end
      end
      if not self:LayoutBlock(block) then return end
    end
  end
end

function overrides:OnBlockHeaderClick(block, mouseButton)
  local recipeID = block.id
  if IsModifiedClick("CHATLINK") and ChatFrameUtil.GetActiveWindow() then
    local hit = ns.FindRecipeByID(recipeID)
    if hit then
      local _, link = C_Item.GetItemInfo(hit.recipe.outputItemID)
      if link then ChatFrameUtil.InsertLink(link) end
    end
  elseif mouseButton == "RightButton" then
    MenuUtil.CreateContextMenu(self:GetContextMenuParent(), function(_, root)
      root:CreateButton("Open in " .. ADDON, function() Open(recipeID) end)
      root:CreateButton(PROFESSIONS_UNTRACK_RECIPE, function() Untrack(recipeID) end)
    end)
  elseif IsModifiedClick("RECIPEWATCHTOGGLE") then
    Untrack(recipeID)
  else
    Open(recipeID)
  end
end

-- The module's OnEvent script is bound to the template mixin's method when the
-- frame is created, so a Mixin override never receives events; listen here instead.
local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
  if not module then return end
  if event == "PLAYER_REGEN_ENABLED" then
    if pending then
      pending = false
      module:MarkDirty()
    end
  elseif WhatMatsDB and #WhatMatsDB.tracked > 0 then
    ns.RefreshTracker()
  end
end)

-- Ordered after every Blizzard module so a tainted update has nothing of theirs left to run.
local function Register()
  if ObjectiveTrackerManager:GetContainerForModule(module) then return end
  local last = 0
  for _, m in ipairs(ObjectiveTrackerFrame.modules) do
    last = math.max(last, m.uiOrder or 0)
  end
  module.uiOrder = last + 1
  ObjectiveTrackerManager:SetModuleContainer(module, ObjectiveTrackerFrame)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_ObjectiveTracker", function()
  module = CreateFrame("Frame", nil, nil, "ObjectiveTrackerModuleTemplate")
  Mixin(module, overrides)
  module:SetHeader(ADDON)
  -- Manager Init waits for PLAYER_ENTERING_WORLD and VARIABLES_LOADED and was
  -- queued as a closure over the original Init, so hooking Init never fires.
  -- Init ends with self:UpdateAll(), which is looked up at call time.
  if ObjectiveTrackerManager.containers[ObjectiveTrackerFrame] then
    Register()
  else
    hooksecurefunc(ObjectiveTrackerManager, "UpdateAll", function()
      if ObjectiveTrackerManager.containers[ObjectiveTrackerFrame] then Register() end
    end)
  end
end)
