local ADDON, ns = ...

local function Setup()
  local form = ProfessionsFrame.CraftingPage.SchematicForm
  local selectedID

  local button = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
  button:SetSize(90, 22)
  button:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 10, 10)
  button:SetText(ADDON)
  button:SetScript("OnClick", function()
    if selectedID then ns.LoadRecipe(selectedID, ProfessionsFrame) end
  end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Open this recipe in " .. ADDON)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", GameTooltip_Hide)
  button:SetMotionScriptsWhileDisabled(true)

  local function UpdateEnabled()
    button:SetEnabled(selectedID ~= nil and ns.FindRecipeByID(selectedID) ~= nil)
  end
  -- Selection can arrive before the profession scan has stored the recipe.
  button:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
  button:SetScript("OnEvent", UpdateEnabled)

  ProfessionsFrame:HookScript("OnHide", ns.CloseIfFromProfession)

  hooksecurefunc(form, "Init", function(_, recipeInfo)
    selectedID = recipeInfo and recipeInfo.recipeID
    UpdateEnabled()
  end)
end

if ProfessionsFrame then
  Setup()
else
  local f = CreateFrame("Frame")
  f:RegisterEvent("ADDON_LOADED")
  f:SetScript("OnEvent", function(self, _, name)
    if name == "Blizzard_Professions" then
      self:UnregisterAllEvents()
      Setup()
    end
  end)
end
