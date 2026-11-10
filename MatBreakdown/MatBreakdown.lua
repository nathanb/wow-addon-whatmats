local ADDON = "MatBreakdown"
local BASIC = Enum.CraftingReagentType.Basic

local function Print(msg)
  print("|cff33ff99" .. ADDON .. "|r: " .. msg)
end

local function ItemText(itemID)
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
    MatBreakdownDB[prof.professionName] = recipes
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

local function FindRecipes(query)
  local wantItem = tonumber(query:match("|Hitem:(%d+)"))
  local wantRecipe = tonumber(query:match("|Henchant:(%d+)") or query:match("|Hspell:(%d+)"))
  local wantName = (query:match("%[(.-)%]") or query):lower()

  local exact, partial = {}, {}
  for profName, recipes in pairs(MatBreakdownDB) do
    for recipeID, r in pairs(recipes) do
      local hit = { profName = profName, recipe = r }
      local itemName = (C_Item.GetItemNameByID(r.outputItemID) or ""):lower()
      if recipeID == wantRecipe or r.outputItemID == wantItem
        or r.name:lower() == wantName or itemName == wantName then
        table.insert(exact, hit)
      elseif r.name:lower():find(wantName, 1, true) then
        table.insert(partial, hit)
      end
    end
  end
  return #exact > 0 and exact or partial
end

local function SortedLines(counts)
  local lines = {}
  for itemID, n in pairs(counts) do
    table.insert(lines, { text = ItemText(itemID), n = n })
  end
  table.sort(lines, function(a, b) return a.text < b.text end)
  return lines
end

local function Breakdown(query, count)
  local matches = FindRecipes(query)
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
  local byOutput = BuildProducerIndex(MatBreakdownDB[hit.profName])
  local raw, crafted, surplus = {}, {}, {}
  Expand(byOutput, hit.recipe.outputItemID, count * hit.recipe.made, raw, crafted, surplus, {})
  crafted[hit.recipe.outputItemID] = nil

  Print(string.format("%dx %s (%s):", count, hit.recipe.name, hit.profName))
  if next(crafted) then
    Print("Intermediates to craft:")
    for _, l in ipairs(SortedLines(crafted)) do
      Print(string.format("  %d x %s", l.n, l.text))
    end
  end
  Print("Raw materials:")
  for _, l in ipairs(SortedLines(raw)) do
    Print(string.format("  %d x %s", l.n, l.text))
  end
end

local function PrintHelp()
  Print("/mats <recipe name or shift-clicked link> [count]")
  Print("/mats scan  - rescan the open profession window")
  Print("/mats list  - show scanned professions")
end

SLASH_MATBREAKDOWN1 = "/mats"
SlashCmdList.MATBREAKDOWN = function(msg)
  msg = strtrim(msg or "")
  if msg == "" then
    PrintHelp()
  elseif msg == "scan" then
    local prof, n = ScanProfession()
    if prof then
      Print(string.format("Scanned %d %s recipes.", n, prof))
    else
      Print("Open your own profession window first.")
    end
  elseif msg == "list" then
    for profName, recipes in pairs(MatBreakdownDB) do
      local n = 0
      for _ in pairs(recipes) do n = n + 1 end
      Print(string.format("%s: %d recipes", profName, n))
    end
  else
    local query, count = msg:match("^(.-)%s+(%d+)$")
    Breakdown(query or msg, tonumber(count) or 1)
  end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("TRADE_SKILL_SHOW")
frame:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
frame:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" then
    if arg1 == ADDON then
      MatBreakdownDB = MatBreakdownDB or {}
    end
  else
    ScanProfession()
  end
end)
