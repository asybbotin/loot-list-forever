# Repository Guidelines

## Target Client & API Compatibility

Build this addon for **WoW: Forever**, using the installed `_classic_beta_` client. Record the exact client version, build, and interface number with `/dump GetBuildInfo()` before setting compatibility metadata or diagnosing API differences.

Verify API signatures, events, and restrictions against the target build’s Blizzard UI source and generated API documentation. A [WoW UI source mirror](https://github.com/Gethe/wow-ui-source) is available; select a matching branch/build. Do not assume Classic Era or Retail examples work unchanged. Keep uncertain compatibility assumptions explicit and feature-detect optional APIs.

Respect protected actions, combat lockdown, and secret/restricted values. Do not bypass restrictions or compare, calculate with, or persist values unless the target API permits it. Defer protected UI changes until combat ends.

## Project Structure & Loading

`loot_list_forever.lua` handles events, item parsing and metadata; `loot_list_forever_money.lua` parses localized money loot; `loot_list_forever_ui.lua` manages pooled notifications; `loot_list_forever_settings.lua` owns saved filters/duration, the settings panel, and the minimap button. `loot_list_forever.toc` loads UI, settings, and money parsing before core logic. `tests/run.lua` contains API-mocked regression tests; `README.md` briefly describes the addon and usage; `DEVELOPMENT.md` contains compatibility notes and in-game checks. Keep the addon display-only; never call looting APIs or alter Auto Loot.

Maintain `loot_list_forever.toc` with a verified `## Interface` value, metadata, and explicit file load order. Declare persisted globals with `## SavedVariables` or `## SavedVariablesPerCharacter`. Initialize addon data on its own `ADDON_LOADED` event; wait for appropriate player/world events for gameplay state.

## Lua Style & Runtime Behavior

Use four-space indentation, local variables/functions, `camelCase` names, and `UPPER_SNAKE_CASE` constants. Prefix unavoidable globals with `LootList`; prefer a private addon namespace shared between modules.

Use Lua syntax supported by the client. Prefer event-driven updates over continuous `OnUpdate` polling. Handle unavailable item data asynchronously, guard missing API results, and use item IDs rather than localized names as keys. Version saved-data schemas, preserve user settings, and provide safe defaults.

## Development & Testing

No build system or linter is configured. Run `luajit tests/run.lua` (or `lua5.1 tests/run.lua`) from the addon directory for mocked regression tests. These do not prove in-game compatibility.

- `luac -p loot_list_forever.lua`: syntax check when a compatible compiler is installed; cannot validate WoW APIs.
- `/console scriptErrors 1`: enable in-game error reporting.
- `/reload`: reload addon changes; verify manifest changes after restarting the client if needed.

Test login, reload, saved-data persistence, empty/new settings, uncached items, and affected loot/group behavior. Exercise UI changes during and outside combat. Report exact build, reproduction steps, and results; distinguish static checks from actual in-game validation.

## Contributions & Agent Instructions

Keep the player-facing `README.md` very short while clearly describing the addon, its main features, and essential installation and usage steps. Put detailed technical notes, API references, and testing procedures in separate developer documentation.

Use imperative commit subjects, such as `Add loot list window`. Describe behavior changes and validation; include screenshots for UI changes.

Keep edits within this addon. Preserve user data and unrelated addons. Avoid introducing dependencies without a clear need and documented loading requirements.
