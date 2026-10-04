# Loot List Forever

A lightweight **WoW: Forever** addon that displays collected items and money in a
compact list. Item rows show rarity, quantity, item level, and vendor value. Money
adds up in one row, with bronze, silver, or gold coloring based on the total.
The addon leaves Auto Loot and the default loot window unchanged.

Fully vibe-coded. The loot is real; the engineering runs on vibes (and tests).

## Install and use

1. Place this repository in `Interface/AddOns/loot_list_forever` inside your WoW: Forever
   client folder. `loot_list_forever.toc` must be directly inside `loot_list_forever`.
2. Enable **Loot List Forever** on the AddOns screen.
3. Click the loot-bag minimap button or type `/lootlist` to open settings.
   A sample list appears automatically. Choose item rarities, duration, and opacity,
   or drag the handles to move and resize the list.
4. Click **Done** or press Escape. Your settings are saved between sessions.

Upgrading from the old `Loot_list` folder? Close the game and rename that folder
to `loot_list_forever`. To retain existing settings, back up your account's
`WTF/Account/<account>/SavedVariables/Loot_list.lua` and copy it as
`loot_list_forever.lua` in the same SavedVariables directory before restarting.

Hover an item to keep it in place and show its tooltip. Shift-click to insert its
link into chat. Type `/lootlist help` for additional commands.

## Group loot

Open `/lootlist` and use **Enable group loot** to turn this module on or off.
It is enabled by default, and the choice is saved across sessions. Disabling it
immediately clears its rows and stops its animations, sounds, and roll handling.
Blizzard's group-roll window remains available. Re-enabling handles new rolls;
`/lootlist grouptest` respects this setting.

Items requiring a group roll appear in a separate list to the left of the loot
notifications, with the same rarity colors, icons, and tooltips.
Each row has **Need**, **Greed**, and **Pass** buttons with distinct Blizzard
roll icons beside their labels. Unavailable choices are
disabled. The status line shows **Voting ongoing**, the countdown, and vote
progress when loot history provides it. Vendor prices are omitted from this list.
An amber line pulses gently while voting is in progress; a brief green highlight
marks a finished result. The animations stop when a row is removed.
Confirmed winners play Blizzard's positive group-roll sound once per item,
using your normal sound settings. Everyone-passed and unavailable results stay silent.
When voting finishes, larger text shows the **class icon and winner name**, with
**Need/Greed • Roll value**, with the matching roll icon, on the next line. The item name moves to a smaller
secondary line. If everyone passes, the row shows **Everyone passed**.
Finished rows hide the voting buttons. Results remain visible for
at least 10 seconds (or your notification duration, if longer). Drag the **Group
loot — drag to move** header to reposition this list independently; its position
is saved between sessions. Drag the **Resize** handle below the list to scale it
from 65–175%. Its size is saved independently; the initial size matches the loot list.
Blizzard's roll window and confirmation dialogs remain available.
Only an explicit button click submits a roll; Auto Loot is unchanged.

After `/reload`, run **`/lootlist grouptest`** to show three sample items for
60 seconds. Click Need or Greed to preview a sample winner and roll value; click
Pass to preview everyone passing. Finished samples stay visible for at least 10 seconds.
Test choices never submit real rolls. Running the command again refreshes the samples.

API reference inspected: `Gethe/wow-ui-source` branch `forever`, commit
`e3ecc27b64d30fdc735a3f6579b866858f9f9df1`, version **1.60.1.70205**:
`Blizzard_APIDocumentationGenerated/LootDocumentation.lua` and
`Blizzard_APIDocumentationGenerated/LootHistoryDocumentation.lua`, plus
`Blizzard_UIPanels_Game/Mainline/GroupLootFrame.lua` / `.xml`. The roll functions
and optional loot-history functions are feature-detected. Verified client output
from `/dump GetBuildInfo()`: **1.60.1, build 70205, Oct 2 2026, Interface 16001**.
This matches the reference source. Actual in-game behavior still needs validation.

History identifies drops by encounter/drop keys rather than roll IDs. Results
are matched using a unique recent full item hyperlink; stale or ambiguous
simultaneous identical drops never get an assumed winner. If no reliable result
arrives by the full voting deadline provided by WoW plus 5 seconds, the row says
**result unavailable**. Submitting your vote or closing the local roll window
does not shorten this wait; the timer starts when WoW announces the roll.

In-game checks: enable `/console scriptErrors 1`, test the sample command, hover
tooltips, move/resize the loot list, and test during combat. In a group, verify
eligible/ineligible choices, selecting through either list, declining and accepting
bind-on-pickup confirmation, simultaneous rolls, expiry, cancellation, and reload.

## Settings

Open settings with `/lootlist` or the minimap button. The sample list stays visible
while you adjust it, and changes apply immediately.

- **Item qualities:** choose which rarities appear, from Junk to Legendary.
  Junk is hidden by default; money always appears.
- **Display duration:** keep notifications visible for 1–30 seconds (default: 5).
- **List opacity:** adjust text, borders, and backgrounds from 10–100%.
  Icons remain fully opaque.
- **Enable group loot:** show or hide the separate group-roll module.
- **Position and size:** drag the top handle to move the list and the Resize
  handle to scale it. Click **Done** or press Escape to finish and lock the list.

## Contribute

- Create a branch in this repository if you have write access, or fork it and
  create a branch there. Both approaches are welcome; keep changes focused.
- Follow [AGENTS.md](AGENTS.md) for code and client compatibility guidelines.
- Run `luajit tests/run.lua` (or `lua5.1 tests/run.lua`) from the repository root.
- Test affected behavior in game, including reload and combat where relevant.
  Mocked tests do not prove in-game compatibility.
- Open a pull request in this repository describing the change and testing performed. Include
  screenshots for UI changes; for bugs, include reproduction steps and the output
  of `/dump GetBuildInfo()`.

GitHub Actions runs tests on every push and pull request. Any failing test fails
the workflow. Successful tag pushes also create a GitHub release with generated
release notes after both test jobs pass.

Licensed under the [MIT License](LICENSE). Copyright (c) 2026 asybbotin.
