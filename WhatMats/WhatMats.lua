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
  local byOutput, recipeIDs = {}, {}
  for recipeID, r in pairs(recipes) do
    byOutput[r.outputItemID] = r
    recipeIDs[r.outputItemID] = recipeID
  end
  return byOutput, recipeIDs
end

-- Inventory (bags + bank) shared by every branch of a plan, loaded lazily.
local function NewPool()
  return setmetatable({}, { __index = function(t, itemID)
    local n = C_Item.GetItemCount(itemID, true, false, true, true)
    rawset(t, itemID, n)
    return n
  end })
end

local function CopyPool(pool)
  local copy = NewPool()
  for itemID, n in pairs(pool) do copy[itemID] = n end
  return copy
end

-- Sums each node's unmet amount (its own plus its subtree's) into node.short.
local function CollectGets(nodes, get)
  local total = 0
  for _, node in ipairs(nodes) do
    node.short = node.get + CollectGets(node.children, get)
    if node.get > 0 then get[node.itemID] = (get[node.itemID] or 0) + node.get end
    total = total + node.short
  end
  return total
end

local Plan

-- Surplus from multi-yield crafts goes back into the pool for later branches.
local function Craft(ctx, node, producer, crafts, rem, pool, visiting)
  local itemID = node.itemID
  visiting[itemID] = true
  for _, r in ipairs(producer.reagents) do
    table.insert(node.children, Plan(ctx, r.itemID, r.qty * crafts, pool, visiting, node.depth + 1))
  end
  visiting[itemID] = nil
  local made = crafts * producer.made
  pool[itemID] = pool[itemID] + math.max(made - rem, 0)
  node.made = made
  node.get = math.max(rem - made, 0)
  node.open = true
end

-- Most crafts whose whole reagent tree can come from inventory alone.
local function CoverableCrafts(ctx, itemID, producer, maxCrafts, pool, visiting, depth)
  local function covered(crafts)
    local probe = { itemID = itemID, depth = depth, children = {}, get = 0 }
    Craft(ctx, probe, producer, crafts, crafts * producer.made, CopyPool(pool), visiting)
    return CollectGets(probe.children, {}) == 0
  end
  local lo, hi = 0, maxCrafts
  while lo < hi do
    local mid = math.floor((lo + hi + 1) / 2)
    if covered(mid) then lo = mid else hi = mid - 1 end
  end
  return lo
end

-- expand[itemID]: true = always craft the shortfall, false = never craft,
-- nil = craft only what inventory fully covers.
Plan = function(ctx, itemID, qty, pool, visiting, depth)
  local node = { itemID = itemID, need = qty, depth = depth, children = {}, made = 0, get = 0 }
  node.used = math.min(pool[itemID], qty)
  pool[itemID] = pool[itemID] - node.used
  local rem = qty - node.used

  local producer = ctx.byOutput[itemID]
  if not producer or visiting[itemID] then
    node.get = rem
    return node
  end
  node.recipeID = ctx.recipeIDs[itemID]

  local mode = WhatMatsDB.expand[itemID]
  local crafts = 0
  if mode == true then
    crafts = math.ceil(rem / producer.made)
  elseif mode == nil and rem > 0 then
    crafts = CoverableCrafts(ctx, itemID, producer, math.ceil(rem / producer.made), pool, visiting, depth)
  end
  if mode == true or crafts > 0 then
    Craft(ctx, node, producer, crafts, rem, pool, visiting)
  else
    node.get = rem
  end
  return node
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

function ns.FindRecipeByID(recipeID)
  for profName, recipes in pairs(WhatMatsDB.recipes) do
    local r = recipes[recipeID]
    if r then return { profName = profName, recipe = r } end
  end
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
  local byOutput, recipeIDs = BuildProducerIndex(WhatMatsDB.recipes[hit.profName])
  local ctx = { byOutput = byOutput, recipeIDs = recipeIDs }
  local pool = NewPool()
  local visiting = { [hit.recipe.outputItemID] = true }
  local tree = {}
  for _, r in ipairs(hit.recipe.reagents) do
    table.insert(tree, Plan(ctx, r.itemID, r.qty * count, pool, visiting, 0))
  end
  local getMap = {}
  CollectGets(tree, getMap)
  local get = SortedList(getMap)
  for _, l in ipairs(get) do
    l.recipeID = recipeIDs[l.itemID]
  end
  return { tree = tree, get = get, getMap = getMap }
end

local function PrintTree(nodes, indent)
  for _, node in ipairs(nodes) do
    local line = string.format("%s%d x %s", indent, node.need, ns.ItemText(node.itemID))
    if node.made > 0 then line = line .. " - craft " .. node.made end
    Print(line)
    PrintTree(node.children, indent .. "  ")
  end
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
  PrintTree(result.tree, "  ")
  if #result.get == 0 then
    Print("Still need: nothing")
    return
  end
  Print("Still need:")
  for _, l in ipairs(result.get) do
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
      WhatMatsDB.expand = WhatMatsDB.expand or {}
      ns.InitMinimapButton()
    end
  else
    ScanProfession()
  end
end)
