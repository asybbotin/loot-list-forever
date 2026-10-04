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

## Settings

Open settings with `/lootlist` or the minimap button. The sample list stays visible
while you adjust it, and changes apply immediately.

- **Item qualities:** choose which rarities appear, from Junk to Legendary.
  Junk is hidden by default; money always appears.
- **Display duration:** keep notifications visible for 1–30 seconds (default: 5).
- **List opacity:** adjust text, borders, and backgrounds from 10–100%.
  Icons remain fully opaque.
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
