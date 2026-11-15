local ADDON, ns = ...

local AH_CUT = 0.05

-- Auctionator is optional; every lookup goes through this.
local function AuctionatorAPI()
  local a = _G.Auctionator
  return a and a.API and a.API.v1
end

local function Record(itemID, copper, src)
  WhatMatsPriceDB.last[itemID] = { copper = copper, src = src, time = time() }
  ns.RefreshWindow()
end

local function Seen(itemID)
  local seen = WhatMatsPriceDB.seen[itemID]
  if seen then return seen.copper, "seen", nil, seen.time end
end

-- Returns copper per unit, source, Auctionator's days-since-seen (nil past 21),
-- and when we recorded it ourselves.
-- Sources: "manual", "ah", "vendor" (last purchases), "auctionator",
-- "auctionator-vendor", "seen" (lowest listing when we last viewed it on the AH).
function ns.UnitPrice(itemID)
  local manual = WhatMatsPriceDB.cost[itemID]
  if manual then return manual, "manual" end
  local last = WhatMatsPriceDB.last[itemID]
  if last then return last.copper, last.src, nil, last.time end
  local api = AuctionatorAPI()
  if api then
    local ah = api.GetAuctionPriceByItemID(ADDON, itemID)
    if ah then return ah, "auctionator", api.GetAuctionAgeByItemID(ADDON, itemID) end
    local vendor = api.GetVendorPriceByItemID(ADDON, itemID)
    if vendor then return vendor, "auctionator-vendor" end
  end
  return Seen(itemID)
end

function ns.SalePrice(itemID)
  local manual = WhatMatsPriceDB.sale[itemID]
  if manual then return manual, "manual" end
  local api = AuctionatorAPI()
  if api then
    local ah = api.GetAuctionPriceByItemID(ADDON, itemID)
    if ah then return ah, "auctionator", api.GetAuctionAgeByItemID(ADDON, itemID) end
  end
  return Seen(itemID)
end

-- Cash cost prices only what bags + bank can't cover; market cost prices all of it.
-- Self-sourced materials count toward neither.
function ns.Profit(hit, count, totals)
  local db = WhatMatsPriceDB
  local outputID = hit.recipe.outputItemID
  local p = { outputID = outputID, made = count * hit.recipe.made, lines = {}, cash = 0, market = 0 }
  p.sale, p.saleSrc, p.saleAge = ns.SalePrice(outputID)
  p.missing = p.sale == nil
  if p.sale then
    p.revenue = p.sale * p.made * (db.ahCut and (1 - AH_CUT) or 1)
  end

  for _, l in ipairs(totals) do
    local line = { itemID = l.itemID, n = l.n, self = db.self[l.itemID] == true }
    line.short = math.max(l.n - C_Item.GetItemCount(l.itemID, true, false, true, true), 0)
    line.unit, line.src, line.age, line.time = ns.UnitPrice(l.itemID)
    if not line.self and l.n > 0 then
      if line.unit then
        line.market = line.unit * l.n
        line.cash = line.unit * line.short
        p.market = p.market + line.market
        p.cash = p.cash + line.cash
      else
        p.missing = true
      end
    end
    p.lines[l.itemID] = line
  end

  if p.revenue then
    p.net = p.revenue - p.cash
    if p.cash > 0 then p.ratio = p.revenue / p.cash end
  end
  return p
end

function ns.FormatSilver(copper)
  return string.format("%.2fs", copper / 100)
end

function ns.ParseSilver(text)
  local silver = tonumber(text)
  if silver and silver >= 0 then return math.floor(silver * 100 + 0.5) end
end

-- Item auctions are bought on PlaceBid and confirmed by AUCTION_HOUSE_PURCHASE_COMPLETED.
-- Only buyouts count; bids won later arrive by mail and aren't tracked.
local pendingAuctions = {}
-- Commodities: StartCommoditiesPurchase, then COMMODITY_PRICE_UPDATED quotes the
-- total, then COMMODITY_PURCHASE_SUCCEEDED.
local pendingCommodity

local function HookAuctionHouse()
  if not (C_AuctionHouse and C_AuctionHouse.PlaceBid) then return end
  hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, amount)
    local info = C_AuctionHouse.GetAuctionInfoByID(auctionID)
    if info and info.buyoutAmount and amount >= info.buyoutAmount then
      pendingAuctions[auctionID] = { itemID = info.itemKey.itemID, copper = info.buyoutAmount }
    end
  end)
  hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, quantity)
    pendingCommodity = { itemID = itemID, quantity = quantity }
  end)
end

-- The hook runs when the purchase is requested, so a buy that then fails
-- (full bags, too little gold) is still recorded.
local function HookMerchant()
  hooksecurefunc("BuyMerchantItem", function(index)
    local itemID = GetMerchantItemID(index)
    local _, _, price, stack, _, _, _, extendedCost = GetMerchantItemInfo(index)
    if itemID and price and price > 0 and not extendedCost and GetMerchantItemCostInfo(index) == 0 then
      Record(itemID, price / math.max(stack or 1, 1), "vendor")
    end
  end)
end

-- Search results page in over several events; each recomputes the low from
-- everything loaded so far. Our own listings are skipped. No listings keeps the old price.
local function RecordSeen(itemID, copper)
  if not copper then return end
  WhatMatsPriceDB.seen[itemID] = { copper = copper, time = time() }
  ns.RefreshWindow()
end

local function LowestCommodity(itemID)
  local low
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    if r and r.numOwnerItems < r.quantity and (not low or r.unitPrice < low) then
      low = r.unitPrice
    end
  end
  return low
end

-- buyoutAmount is treated as per unit, as Blizzard's sell frame does when it
-- copies a result's buyout into its price input.
local function LowestItem(itemKey)
  local low
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
    local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and not r.containsOwnerItem and (not low or r.buyoutAmount < low) then
      low = r.buyoutAmount
    end
  end
  return low
end

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
  if event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    RecordSeen(arg1, LowestCommodity(arg1))
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    RecordSeen(arg1.itemID, LowestItem(arg1))
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    local bought = pendingAuctions[arg1]
    pendingAuctions[arg1] = nil
    if bought then Record(bought.itemID, bought.copper, "ah") end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if pendingCommodity then pendingCommodity.total = arg2 end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    local c = pendingCommodity
    pendingCommodity = nil
    if c and c.total and c.quantity > 0 then Record(c.itemID, c.total / c.quantity, "ah") end
  elseif event == "COMMODITY_PURCHASE_FAILED" then
    pendingCommodity = nil
  end
end)

function ns.InitPricing()
  HookAuctionHouse()
  HookMerchant()
  for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
    "AUCTION_HOUSE_PURCHASE_COMPLETED", "COMMODITY_PRICE_UPDATED",
    "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED" }) do
    events:RegisterEvent(e)
  end
  -- RegisterForDBUpdate lives in Auctionator's AH-specific code, which may not load on every client.
  local api = AuctionatorAPI()
  if api and api.RegisterForDBUpdate then
    api.RegisterForDBUpdate(ADDON, ns.RefreshWindow)
  end
end
