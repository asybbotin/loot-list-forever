# Loot List

A lightweight **WoW: Forever** addon that shows acquired items without changing
Auto Loot or the default loot window. Installed in the existing `Loot_list` folder.

## Installation

Download or clone this repository into a folder named `Loot_list` under your
WoW: Forever client's `Interface/AddOns/` directory. `Loot_list/Loot_list.toc`
should be directly inside that folder, without an extra nested repository folder.
Restart the client if needed, then enable **Loot List** on the AddOns screen.

## Use

1. Enable **Loot List** in AddOns and keep the game's **Auto Loot** enabled.
2. Click the loot-bag minimap button or run `/lootlist` to open settings and unlock
   the list. Sample entries appear automatically (or run `/lootlist test`).
3. Drag the top handle to move the list. Drag **Resize** at the bottom-right of the
   full six-row area to scale the list, including text and icons (65–175%).
4. Click **Done**, press Escape, or run `/lootlist lock` when finished. Closing the
   panel locks the list. Settings, position, size, and minimap-button position are
   saved on reload/logout. Drag the minimap button to move it around the minimap.

Hover a notification for its standard item tooltip. Hovered entries stay visible;
after leaving an expired entry, it fades out over 0.7 seconds. Shift-click an entry
to insert its link into an open chat edit box.

## Commands

The primary command is `/lootlist`. Existing `/lootdisplay` and `/lloot` aliases
remain available with all subcommands, for example `/lloot test`.

| Command | Action |
| --- | --- |
| `/lootlist` | Open settings and unlock the list. |
| `/lootlist settings` | Open the same settings panel and unlock the list. |
| `/lootlist help` | Show the available commands. |
| `/lootlist unlock` | Show the move and resize handles. |
| `/lootlist lock` | Hide editing handles and save position/size. Preview entries receive a fresh configured lifetime. |
| `/lootlist reset` | Restore the right-side default position; keep the current size. |
| `/lootlist test` | Show real sample items across enabled rarities using client API metadata. Repeat enabled samples to fill at least five rows. Previews stay visible while unlocked. |
| `/lootlist debug` | Toggle temporary diagnostic chat output, including raw loot-link markup. |
| `/lootlist status` | Show event, parsing, display, filtering, pending-data, timeout and money-notification counters, plus the latest diagnostic result. |

Test previews are sorted from Legendary down to Junk, including samples whose
metadata loads later. Real loot uses the same descending rarity order. Money
remains pinned above all items; equal-rarity entries keep their arrival order. Test previews respect the same rarity filters as actual loot. No equipped gear is
needed. Examples are Broken Fang (junk), Linen Cloth (common), Malachite (uncommon),
Cruel Barb (rare), Flurry Axe (epic), and Thunderfury (legendary). Only example
IDs are fixed; displayed names, links, icons, quality, levels, and prices come from
the client API. Uncached samples use bounded metadata loading. Rare/Epic/Legendary samples have
alternate real item IDs if metadata is unavailable or the client reports a different
rarity. Epic alternatives include Bow of Searing Arrows, Krol Blade,
Underworld Band, and Edgemaster's Handguards. Preview requests candidate data once
and prefers alternatives already recognized by the client. Epic previews select a
fully cached example immediately to avoid waiting on an uncached sample; Staff
of Jordan is no longer used. The reported quality
is always verified, never overridden. Preview prints
which rarities are unchecked, and reports samples that cannot be loaded.
Previews never grant items or modify inventory. Repeating Preview replaces previous
preview rows. If all qualities are disabled, no item preview appears.

If loot does not appear, run `/lootlist test` to check the display and item-data
path. Run `/lootlist debug`, loot a non-gray item, then `/lootlist status`.
Debug output identifies unmatched messages, gray filtering, unavailable/restricted
metadata, and successful display. Run `/lootlist debug` again to turn it off.
Debugging is temporary and never saves chat text.

## Settings

Opening settings automatically shows the sample loot list for enabled qualities.
Samples stay visible while settings are open; closing settings releases them for
normal expiration. Reopening settings refreshes the samples without duplicating them.

Changes apply immediately. Choose **Poor / Junk, Common, Uncommon, Rare, Epic,
or Legendary**. The menu excludes Artifact, Heirloom, and WoW Token categories.
Check individual item qualities, including **Poor / Junk**,
to choose what appears. The default enables Common through higher qualities and
excludes junk. Disabling a quality also removes its currently visible loot entries;
previews are filtered too; money remains unaffected.

The **Display duration** slider selects 1–30 seconds (default: 5) for both item and
money rows. Changing it restarts currently visible rows with the selected delay.
Newly collected money continues to reset only its own timer. Hover retention still
works regardless of the selected delay.

## Behavior

- Shows the item qualities enabled in settings; excludes Poor/Gray by default.
- The **List opacity** slider selects 10–100% (default: 100%) and immediately
  adjusts row text, borders, and backgrounds. Icons retain full opacity.
  The setting persists after reload; row fading still works independently.
- Item backgrounds use a dark tint of their quality color at the original 0.9 alpha,
  multiplied by the configured list opacity.
  Money backgrounds use a dark tint of their denomination color. All rows use color styling only;
  glow effects are disabled.
- Collected money uses bronze for copper-only totals, silver for totals of at least
  one silver, and gold for totals of at least one gold, with matching text, border,
  and tinted background. It appears with a coin icon, for example
  `2g 15s 44c`. Money rows have no item level or vendor price and share the same
  six-row limit, hover retention, and saved size/position. Additional money loot
  updates the same row, adds to its total, restores full opacity, and resets its
  configured timer. The color follows the summed total: for example, `66c` followed
  by `1s 20c` displays `1s 86c` and changes from bronze to silver.
  Money stays pinned through item overflow; displaced items are queued. Once its row disappears, the next
  collection starts a new total. Item timers are unaffected by money updates.
  Group loot shows your share; guild-bank deposits are excluded. Money is detected
  from loot chat events, so sales, purchases, and other wallet changes are not shown.
- Money occupies the top row. Real and preview items are sorted below it from
  Legendary down to Junk. Equal-rarity entries keep their arrival order; each
  entry still has its own independent lifetime. At most six rows are visible (one money
  row plus up to five items while money is shown). Bursts queue up to 48 additional
  entries, giving each its full display time when a visible slot opens. Extra
  entries beyond this bound are discarded to keep memory usage predictable.
- Each item entry lasts the configured delay **from display**; the money row lasts
  the configured delay from its latest collection (five seconds by default), fading during its final
  0.7 seconds. Hover prevents expiration and overflow eviction without extending
  other entries. Leaving an expired entry starts its final fade; leaving earlier
  preserves its original deadline (with at least 0.7 seconds to fade).
- Displays icon, quality-colored name, quantity, item level, and vendor value.
- **Vendor value is the total for the displayed quantity**, not the unit price.
  Items with no vendor value show `Vendor: -`.
- Identical item links received within a 0.1-second burst share one quantity.
  Later acquisitions create separate entries. Variants with different links stay separate.
- Uses the client's localized self-loot chat formats, retaining native and later
  addon-translated formats. Recognizes legacy and named-quality link colors.
  Unrecognized wording is accepted only when the event GUID confirms the player;
  other players' loot is ignored.
  The same self-received chat messages can also occur for items delivered outside
  a corpse loot window; these are displayed as well.
- Uncached metadata is requested and retried for up to ten seconds. Notifications
  with unavailable or restricted metadata are then discarded. Pending work is bounded.
- Reuses six rows. An update handler runs only while rows are visible, for smooth
  repositioning and fading; no inventory scanning or idle polling occurs.

## Compatibility

Target installation inspected: **1.60.1.70205**, interface **16001** (also used by
installed Forever addon manifests). The exact runtime interface can be checked with
`/dump GetBuildInfo()`. The player has confirmed basic looting and move/lock
commands work in game; hover retention and resizing still need in-game verification.

API reference: the [Forever/classic beta Blizzard UI source mirror](https://github.com/Gethe/wow-ui-source/tree/classic_beta),
including generated `ItemDocumentation.lua` and `ChatInfoDocumentation.lua`.
Item APIs prefer `C_Item` and feature-detect legacy fallbacks. The addon neither
calls looting APIs nor modifies game CVars or protected UI.

## Development checks

Run from this directory with LuaJIT or Lua 5.1:

```sh
luajit tests/run.lua
# Alternatively:
lua5.1 tests/run.lua
```

The GitHub Actions workflow in `.github/workflows/tests.yml` runs on every push
and pull request, and can be started manually from the Actions tab. It runs the
suite separately under LuaJIT and Lua 5.1. A failed test exits with a nonzero code
and fails its job and the workflow; failures are not ignored.

Tests mock WoW APIs and cover parsing/localization, filtering, metadata loading,
quantities, pricing, money parsing/localization, mixed item/coin rows, pooling/overflow, expiration/fading, hover retention, five-row
previews, rarity tints and pooled resets, resizing, settings/quality controls, minimap interactions, and saved configuration.
They cannot validate rendering, actual event delivery, or client restrictions.

## In-game acceptance checklist

Enable errors with `/console scriptErrors 1`, then check:

- Auto Loot remains enabled; by default gray loot is hidden and white/green/blue loot appears.
- The loot-bag minimap button opens settings and unlocks the list; Done/Escape locks it.
- Enable junk and verify gray loot appears; disable a quality and verify it stops
  appearing. Check these choices survive reload and logout/login.
- Change the delay to ten seconds and verify item and money rows use it; restore
  five seconds for the checks below. The selected delay persists between sessions.
- A cloth stack shows its correct quantity and total vendor value.
- Looted coins show the collected amount with a coin icon and no item-only details.
  Check copper-only loot, mixed gold/silver/copper, and your share in a group.
- Money rows remain on hover and expire independently alongside item rows;
  item tooltips and Shift-click links still work after a row has displayed money.
- Icons, name colors, item levels, and tooltips match the actual items.
- Preview shows examples for enabled rarities, including Rare and Epic, using
  quality-colored names, borders, and backgrounds without glow. Check readability
  and unchanged background opacity at different list scales.
- Rapid loot fills a list of at most six rows; money stays at the top and items
  sort by descending rarity. Equal-rarity items keep their arrival order.
  Queued overflow items join the sorted list as visible slots become available.
- Collect `66c`, then `1s 20c` before the money row disappears: it shows `1s 86c`
  and remains for five seconds after the second collection. Item timers remain unchanged.
- Collect `99c`, then `1c`: the same row changes from bronze to silver. Add `99s`:
  it changes to gold. After it expires, collect copper and verify bronze returns.
- Adjust List opacity with preview and real loot visible; verify all row contents
  except icons change together, fading and hover still work, and the value survives `/reload`.
  Repeat during and outside combat.
- Staggered acquisitions fade and expire independently after five seconds.
- Uncached items appear after metadata arrives, without Lua errors.
- A hovered row remains visible past five seconds and survives rapid incoming loot;
  its position stays fixed while hovered, even when other rows expire or new loot arrives.
  leaving it starts its final fade. Other rows continue to expire independently.
- `/lootlist unlock` followed by `/lootlist test` shows five rows that remain
  visible while editing; locking releases previews for normal expiration.
- The bottom-right resize handle scales the entire list only while unlocked.
- Dragging/resizing, `/reload`, logout/login, and a client restart retain position and size.
- Looting and tooltip interactions work during and outside combat.

Report the exact `/dump GetBuildInfo()` output and reproduction steps for failures.
