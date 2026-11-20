# Changelog

## 0.5.13 - 2026-11-20

 - Expand all button on the Materials list breaks down every part the recipe's profession makes, so Totals show the real raw materials. Once everything is expanded it turns into Reset, which puts parts back the way they were. Expanded parts are also priced as their materials in the profit panel. (#20)

## 0.5.12 - 2026-11-15

 - Prices with nothing known yet show an orange "?" in the profit panel; hover for how to get one. (#15)
 - Prices are now kept per character, so each character's reputation discounts and auction house don't overwrite another's. Prices learned before this update are cleared; visit vendors and the AH again to relearn them.

## 0.5.11 - 2026-11-15

 - Net and ratio now count every material at its price, including ones already in your bags, so they no longer read "no cost" or change as you craft. What you still need to buy is shown in brackets next to the cost. (#16)
 - Profit prices a craftable material as its own item unless you expand it in the Materials list, instead of switching depending on what's in your bags.

## 0.5.10 - 2026-11-15

 - Clearing or lowering a quantity box no longer drops the count to 0, which hid crafted materials from Totals.
 - Tab and Shift-Tab move between the WhatMats input boxes.

## 0.5.9 - 2026-11-15

 - When Auctionator and your own auction house searches both have a price for an item, WhatMats now uses the newer one.

## 0.5.8 - 2026-11-15

 - Profit line at the top of the WhatMats window. Click it to see revenue, cost to buy, net and ratio for the recipe shown.
 - Material costs come from your last vendor or AH purchase, a price you type in (silver or gold, picked at the top of the panel), or Auctionator's scan if it's installed.
 - Materials sold by a vendor always use the vendor price: your last vendor purchase, else the price listed when you last visited one.
 - Check a material as self-sourced to leave it out of the cost.
 - Set a sale price for the crafted item, or use Auctionator's AH price. The 5% AH cut can be deducted.
 - Without Auctionator, WhatMats remembers the lowest AH listing each time an item shows up in your auction house searches and uses it for sale prices and material costs.
 - Shift-click any item in the WhatMats window to link it in chat, or to search for it when the auction house is open.

## 0.5.7 - 2026-11-15

 - Clicking a recipe in WhatMats now selects it in the profession window even when that profession is already open.

## 0.5.6 - 2026-11-14

 - Click the recipe title in the WhatMats window to open it in its profession window; shift-click to link it.
 - /mats <recipe> now sends to party, raid, guild, officer, whisper, channel or Battle.net whisper when that chat mode is active. Say and yell still print locally.

## 0.5.5 - 2026-11-13

 - Packaged for CurseForge via .pkgmeta (no addon changes).

## 0.5.4 - 2026-11-13
 - release to test auto-publish pipeline

## 0.5.3 - 2026-11-12

 - Materials made by your other professions (e.g. Bronze Bar in an Engineering recipe, Medium Leather in a Leatherworking recipe) now break down too. Open each profession once so it can be scanned.
 - Selecting a different recipe in the profession window no longer replaces the one shown in WhatMats. Use the WhatMats button to load it.

## 0.5.2 - 2026-11-12

 - WhatMats is now licensed under the BSD 3-Clause License.

## 0.5.1 - 2026-11-11

 - WhatMats now closes along with the profession window when you opened it from there.

## 0.5.0 - 2026-11-11

 - The "Still need" list is replaced by **Totals**, which shows only the base materials you still need to get.
 - Materials you can buy from a vendor with gold are marked in Totals. WhatMats learns these as you visit vendors.
 - When docked beside the profession window, WhatMats sits clear of its tabs and matches its height.

## 0.4.0 - 2026-11-11

 - The material tree now checks your bags and bank and only crafts parts you can actually make.
 - New WhatMats button in the profession window opens the selected recipe.
 - Click a crafted part in the tree to open its recipe.
 - Shift-click item links in chat to load them.
 - Number boxes no longer cut off their text.

## 0.3.0 - 2026-11-11

 - Renamed to WhatMats.
 - Quantity boxes are linked, so changing one updates the rest.
 - Shows how many of each material you have in your bank.

## 0.2.0 - 2026-11-11

 - New breakdown window.
 - New minimap button. Drag it to move it.

## 0.1.0 - 2026-11-10

 - First release: break a recipe down into its raw materials from chat.
