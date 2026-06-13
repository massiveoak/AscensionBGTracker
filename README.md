# Ascension BG Tracker

A lightweight Project Ascension / WoW 3.3.5a addon for guilds leveling through
PvP. It scans the guild roster and groups online members by leveling bracket
and detected battleground.

## Download

Download the latest packaged addon from the
[GitHub Releases page](https://github.com/massiveoak/AscensionBGTracker/releases/latest).

## Features

- Tracks brackets 10-19 through 50-59.
- Excludes level 60 battlegrounds.
- Recognizes Temple of Kotmogu, Arathi Basin, and other battleground zones.
- Shows guild members detected in each battleground.
- Provides a movable tracker with adjustable width.
- Automatically fits its height to the rendered content and expands downward.
- Includes adjustable font size, background opacity, and character-name visibility.
- Provides separate colors for brackets, battlegrounds, and character names.
- Supports both a native color wheel and exact `#RRGGBB` hex colors.
- Can show or hide empty leveling brackets.
- Uses a configurable, performance-conscious guild scan interval.
- Expires stale observations after 20 minutes by default.

## Installation

1. Download `AscensionBGTracker-vX.Y.Z.zip` from the
   [latest release](https://github.com/massiveoak/AscensionBGTracker/releases/latest).
2. Extract the archive.
3. Place the extracted `AscensionBGTracker` folder in your Ascension client:

   `Interface\AddOns\AscensionBGTracker`

4. Restart the client or reload the UI.
5. Enable **Ascension BG Tracker** from the AddOns screen.

The final folder layout should contain:

```text
Interface
+-- AddOns
    +-- AscensionBGTracker
        +-- AscensionBGTracker.lua
        +-- AscensionBGTracker.toc
```

## Commands

- `/bgt` toggles the tracker window.
- `/bgt settings` opens addon settings.
- `/bgt scan` requests a roster refresh.
- `/bgt reset` shows and centers the window.

## Detection Limits

The Wrath guild roster API reports an online member's level and current zone.
It does not report queue state, battlegroup or instance identifiers, match start
time, or players outside your guild. The addon therefore detects a running
battleground only when an online guild member's roster zone is a recognized
battleground.

The default scan interval is 60 seconds. WoW ignores `GuildRoster()` requests
made less than 10 seconds apart, so the addon enforces a minimum configurable
interval of 30 seconds.

## License

[MIT](LICENSE)
