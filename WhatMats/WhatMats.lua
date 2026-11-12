local ADDON, ns = ...
local BASIC = Enum.CraftingReagentType.Basic

function ns.Print(msg)
  print("|cff33ff99" .. ADDON .. "|r: " .. msg)
end
local Print = ns.Print

function ns.ItemText(itemID)
  local _, link = C_Item.GetItemInfo(itemID)
  return link or C_Item.GetItemNameByID(itemID) or ("item:" .. itemID)
end

local function ScanProfession()
  if not C_TradeSkillUI.IsTradeSkillReady() then return end
  if C_TradeSkillUI.IsTradeSkillLinked() or C_TradeSkillUI.IsTradeSkillGuild() or C_TradeSkillUI.IsNPCCrafting() then return end

  local prof = C_TradeSkillUI.GetBaseProfessionInfo()
  if not prof or not prof.professionName then return end

  local ids = C_TradeSkillUI.GetAllRecipeIDs and C_TradeSkillUI.GetAllRecipeIDs() or C_TradeSkillUI.GetFilteredRecipeIDs()
  local recipes = {}
  local count = 0
  for _, recipeID in ipairs(ids or {}) do
    local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
    if info and info.learned then
      local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
      if schematic and schematic.outputItemID then
        local reagents = {}
        for _, slot in ipairs(schematic.reagentSlotSchematics) do
          local first = slot.reagents[1]
          if slot.required and slot.reagentType == BASIC and first and first.itemID then
            table.insert(reagents, { itemID = first.itemID, qty = slot.quantityRequired })
          end
        end
        recipes[recipeID] = {
          name = info.name,
          outputItemID = schematic.outputItemID,
          made = math.max(schematic.quantityMin or 1, 1),
          reagents = reagents,
        }
        count = count + 1
      end
    end
  end

  if count > 0 then
    WhatMatsDB.recipes[prof.professionName] = recipes
  end
  return prof.professionName, count
end

local function BuildProducerIndex(recipes)
  local byOutput = {}
  for _, r in pairs(recipes) do
    byOutput[r.outputItemID] = r
  end
  return byOutput
end

-- Surplus from multi-yield crafts is reused before crafting another batch.
local function Expand(byOutput, itemID, qty, raw, crafted, surplus, visiting)
  local producer = byOutput[itemID]
  if not producer or visiting[itemID] then
    raw[itemID] = (raw[itemID] or 0) + qty
    return
  end

  local fromSurplus = math.min(surplus[itemID] or 0, qty)
  surplus[itemID] = (surplus[itemID] or 0) - fromSurplus
  qty = qty - fromSurplus
  if qty <= 0 then return end

  local crafts = math.ceil(qty / producer.made)
  surplus[itemID] = surplus[itemID] + crafts * producer.made - qty
  crafted[itemID] = (crafted[itemID] or 0) + crafts * producer.made

  visiting[itemID] = true
  for _, r in ipairs(producer.reagents) do
    Expand(byOutput, r.itemID, r.qty * crafts, raw, crafted, surplus, visiting)
  end
  visiting[itemID] = nil
end

function ns.FindRecipes(query)
  local wantItem = tonumber(query:match("|Hitem:(%d+)"))
  local wantRecipe = tonumber(query:match("|Henchant:(%d+)") or query:match("|Hspell:(%d+)"))
  local isLink = query:find("|H", 1, true) ~= nil
  local wantName = (query:match("%[(.-)%]") or query):lower()
  -- Recipe links may be titled "Engineering: Moonsight Rifle".
  local unprefixed = wantName:match("^.-:%s*(.+)$") or wantName

  local exact, partial = {}, {}
  for profName, recipes in pairs(WhatMatsDB.recipes) do
    for recipeID, r in pairs(recipes) do
      local hit = { profName = profName, recipe = r }
      local recipeName = r.name:lower()
      local itemName = (C_Item.GetItemNameByID(r.outputItemID) or ""):lower()
      if recipeID == wantRecipe or r.outputItemID == wantItem
        or recipeName == wantName or itemName == wantName
        or recipeName == unprefixed or itemName == unprefixed then
        table.insert(exact, hit)
      elseif not isLink and recipeName:find(wantName, 1, true) then
        table.insert(partial, hit)
      end
    end
  end
  return #exact > 0 and exact or partial
end

local function SortedList(counts)
  local list = {}
  for itemID, n in pairs(counts) do
    table.insert(list, { itemID = itemID, n = n, name = C_Item.GetItemNameByID(itemID) or "" })
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

function ns.Compute(hit, count)
  local byOutput = BuildProducerIndex(WhatMatsDB.recipes[hit.profName])
  local raw, crafted, surplus = {}, {}, {}
  Expand(byOutput, hit.recipe.outputItemID, count * hit.recipe.made, raw, crafted, surplus, {})
  crafted[hit.recipe.outputItemID] = nil
  return { crafted = SortedList(crafted), raw = SortedList(raw) }
end

local function PrintBreakdown(query, count)
  local matches = ns.FindRecipes(query)
  if #matches == 0 then
    Print("No known recipe matches '" .. query .. "'. Open the profession window once so it can be scanned.")
    return
  end
  if #matches > 1 then
    Print("Multiple matches, be more specific:")
    for i = 1, math.min(#matches, 10) do
      Print("  " .. matches[i].recipe.name)
    end
    return
  end

  local hit = matches[1]
  local result = ns.Compute(hit, count)
  Print(string.format("%dx %s (%s):", count, hit.recipe.name, hit.profName))
  if #result.crafted > 0 then
    Print("Intermediates to craft:")
    for _, l in ipairs(result.crafted) do
      Print(string.format("  %d x %s", l.n, ns.ItemText(l.itemID)))
    end
  end
  Print("Raw materials:")
  for _, l in ipairs(result.raw) do
    Print(string.format("  %d x %s", l.n, ns.ItemText(l.itemID)))
  end
end

local function PrintHelp()
  Print("/mats  - toggle the window")
  Print("/mats <recipe name or shift-clicked link> [count]  - print breakdown to chat")
  Print("/mats scan  - rescan the open profession window")
  Print("/mats list  - show scanned professions")
  Print("/mats help  - this help")
end

SLASH_WHATMATS1 = "/mats"
SlashCmdList.WHATMATS = function(msg)
  msg = strtrim(msg or "")
  if msg == "" then
    ns.ToggleWindow()
  elseif msg == "help" then
    PrintHelp()
  elseif msg == "scan" then
    local prof, n = ScanProfession()
    if prof then
      Print(string.format("Scanned %d %s recipes.", n, prof))
    else
      Print("Open your own profession window first.")
    end
  elseif msg == "list" then
    for profName, recipes in pairs(WhatMatsDB.recipes) do
      local n = 0
      for _ in pairs(recipes) do n = n + 1 end
      Print(string.format("%s: %d recipes", profName, n))
    end
  else
    local query, count = msg:match("^(.-)%s+(%d+)$")
    PrintBreakdown(query or msg, tonumber(count) or 1)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      if type(WhatMatsDB) ~= "table" then
        WhatMatsDB = { recipes = {} }
      end
      ns.InitMinimapButton()
    end
  else
    ScanProfession()
  end
end)
