# WhatMats

World of Warcraft addon that answers "what do I need to make this?". It breaks a profession recipe down into raw materials across every level of crafted parts, subtracts what the player already has in bags and bank, and prices the craft (cost, revenue, net, ratio).

## Directives

- **Correctness comes first.** The point of the addon is a shopping list the player can trust. Material counts, totals and prices must be exact: no off-by-one craft counts, no double-counted inventory, no lost surplus from multi-yield crafts. A wrong number does more harm than a missing feature.
- Prefer what the game client actually reports over assumptions. When unsure how a Blizzard API or frame behaves on this client, read the source (see Target client).
- Keep the UI simple and in the game's own style (stock templates and textures, no custom art).
- Only change what the issue asks for. Small, focused diffs.

## Target client

- **WoW "Forever"** (`## Interface: 16001`, client 1.60.x). Not retail, not Classic Era.
- It uses the retail-style `C_TradeSkillUI` / ProfessionsFrame API but has its own FrameXML. Read Blizzard source from `Gethe/wow-ui-source` at ref `forever`, e.g.:
  `gh api "repos/Gethe/wow-ui-source/contents/Interface/AddOns/Blizzard_Professions/<file>?ref=forever" -H "Accept: application/vnd.github.raw"`
- Lua 5.1 (WoW sandbox). No `require`, no external libraries, no build step.

## Layout

All addon code lives in `WhatMats/`. **The game only loads files listed in `WhatMats/WhatMats.toc`.** Edit files in that folder; a file created anywhere else (e.g. a `UI.lua` at the repo root) is never loaded. A new Lua file must be added to the `.toc` file list.

| File | Role |
| --- | --- |
| `WhatMats/WhatMats.toc` | Interface version, addon version, SavedVariables, load order |
| `WhatMats/WhatMats.lua` | Recipe scanning, producer index, breakdown math (`ns.Compute`, `ns.Totals`, `Plan`/`Craft`/`Expand`), vendor learning, `/mats` slash command, SavedVariables init/migration |
| `WhatMats/Pricing.lua` | Price sources (manual, vendor, AH purchases, AH listings seen, optional Auctionator), profit math, money formatting |
| `WhatMats/UI.lua` | Main window: recipe header, Qty box, Materials tree, Totals, profit panel |
| `WhatMats/MinimapButton.lua` | Draggable minimap button |
| `WhatMats/ProfessionButton.lua` | Button in the profession window |
| `WhatMats/README.md` | User-facing README (CurseForge/GitHub). Root `README.md` is a symlink to it |
| `WhatMats/CHANGELOG.md` | User-facing changelog, also used for release notes |
| `install.bat` | Windows: junctions the game's AddOns folder to this clone |
| `.pkgmeta`, `.github/workflows/release.yml` | Packaging and release |

## How the breakdown works

- Scanning (`ScanProfession`) stores each learned recipe's required basic reagents and minimum yield in `WhatMatsDB.recipes[professionName]`. Players must open each profession window once.
- `BuildProducerIndex` maps output item -> recipe across all scanned professions; the recipe's own profession wins ties.
- `Plan` builds the inventory-aware Materials tree. `WhatMatsDB.expand[itemID]`: `true` always crafts the shortfall, `false` never crafts, `nil` crafts only what inventory fully covers (`CoverableCrafts` binary search).
- Surplus from multi-yield crafts goes back into the pool for later branches. `visiting` prevents recipe cycles.
- `ns.Totals` / `Expand` compute the inventory-free base-material totals for a fixed set of crafted parts. Profit uses only player-expanded parts so it doesn't shift as bags change.
- Craft count is always >= 1 (`SetCount` in `UI.lua`).

When changing any of this, work through a multi-level recipe with a multi-yield part and partial inventory by hand and check the numbers.

## SavedVariables

- `WhatMatsDB` (per character): `recipes`, `expand`, `prices` (`cost`, `sale`, `bought`, `vendor`, `self`, `seen`).
- `WhatMatsVendorDB` (account): learned gold-purchasable vendor items.
- `WhatMatsPriceDB` (account): settings such as `ahCut`; old account-wide price tables are cleared on load.
- Init and migrations happen in the `ADDON_LOADED` handler in `WhatMats.lua`. Any schema change needs a migration there and a changelog note if players lose data.

## Code conventions

- Each file starts with `local ADDON, ns = ...`. Cross-file functions go on `ns` (`ns.Compute`, `ns.RefreshWindow`); everything else is `local`.
- Two-space indent, `PascalCase` function names, `camelCase` locals, `UPPER_CASE` constants.
- UI is built in Lua with `CreateFrame` and stock templates (`BasicFrameTemplateWithInset`, `InputBoxTemplate`) and stock textures (`Interface\\Buttons\\...`). Reuse existing helpers (`NumberBox`, `GetRow`, `SetToggle`, `TabFocus`) before adding new ones.
- Guard optional or version-specific APIs (`if SOUNDKIT then`, `api and api.RegisterForDBUpdate`). Auctionator is optional and only reached through `AuctionatorAPI()`.
- Comments only for non-obvious game/client behavior or math; keep them short.
- No new dependencies or libraries.

## Verifying changes

There are no automated tests. Verification is in game:

- The game runs on a separate Windows machine whose clone is linked into `_forever_\Interface\AddOns\WhatMats` by `install.bat`. A change made on another machine isn't in game until the branch is checked out on the Windows clone.
- `/reload` picks up Lua changes; restart the client if the `.toc` or file list changed.
- If in-game results don't match a change, first ask whether the branch is checked out on the game machine.
- Agree on what to check in game (acceptance criteria) before implementing when it isn't obvious from the issue.

## install.bat and local install paths

`install.bat [WoW dir]` creates a junction from `<WoW dir>\_forever_\Interface\AddOns\WhatMats` to this clone's `WhatMats\` folder. The default path in the script is the maintainer's. Passing the folder as an argument is the simplest option. If a machine needs a different default, edit `install.bat` locally and **never commit that edit**. Keep it out of the way with a stash:

```
git stash push -m "local install path" -- install.bat
git checkout <branch>      # or git pull
git stash pop
```

Stash it before any checkout, pull, rebase or commit that would pick it up, and pop it afterwards. Check `git status` before committing so `install.bat` isn't staged. `.bat` files are CRLF (`.gitattributes`).

## Docs and changelog

- User-facing features get a bullet in `WhatMats/README.md` ("What it does", commands table, etc.) in plain, non-technical language for players.
- Every user-visible change gets a changelog entry. Add it under `## Unreleased` at the top of `WhatMats/CHANGELOG.md`.
- Changelog bullets start with ` - ` (one leading space). Headers are `## X.Y.Z - YYYY-MM-DD`, then a blank line, then the bullets. Add the issue number in parentheses, e.g. `(#20)`.

## Commits and releases

- Commit summary is imperative and under 80 chars, with the issue number when there is one (`Add Expand all button to the Materials list (#20)`), then a blank line and a short explanation of why.
- Feature work goes on a branch. Don't commit or push unless asked.
- Release: a separate `Release X.Y.Z` commit bumps `## Version` in `WhatMats/WhatMats.toc` and renames `## Unreleased` to `## X.Y.Z - <date>`.
- A push to `main` runs `.github/workflows/release.yml`. If the `.toc` version has no tag yet, it tags, zips `WhatMats/` and creates a GitHub release from the matching changelog section (and fails if that section is missing). A CurseForge webhook on the tag then packages the addon using `.pkgmeta`. Never create tags by hand. Merging to `main` with a new version publishes to players.
