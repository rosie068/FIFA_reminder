# World Cup Reminder ⚽

A small macOS app for the 2026 FIFA World Cup. Pick the teams you follow and, one hour before each of their matches, a soccer ball rolls across the bottom of your screen into a goal and pops up the matchup with win / draw / lose odds.

## Features

- Team picker for all 48 teams (grouped by group, searchable, with FIFA rank).
- Match list for all 72 group-stage games with probability bars, upcoming vs played.
- Goal animation 1 hour before kickoff for followed teams; system notification as a fallback if the app isn't running.
- Lives in the Dock and the menu bar.

## Build & run

Requires macOS 13+ and the Xcode command-line tools (Swift). No Xcode project needed.

```bash
cd WorldCupReminder
./build.sh
open "build/World Cup Reminder.app"
```

`build.sh` compiles `Sources/main.swift`, builds the ⚽ icon, bundles resources and ad-hoc signs the app (signing is required for notifications).

## Data

- `FIFA.md` — research snapshot (June 12, 2026): schedule in Pacific time, venues, bookmaker odds, team form, and the JSON dataset.
- `WorldCupReminder/Resources/matches.json` — the JSON block from `FIFA.md` that the app loads.

To refresh after editing `FIFA.md`:

```bash
awk '/^```json$/{f=1;next}/^```$/{f=0}f' FIFA.md > WorldCupReminder/Resources/matches.json
```

then rebuild. Odds are a static snapshot, not live. Group stage only.

## Layout

```
FIFA.md                         research dataset (source of truth)
WorldCupReminder/
├── Sources/main.swift          the whole app (SwiftUI + AppKit)
├── Resources/                  matches.json, goal.png, Info.plist
├── make_icon.swift             renders the ⚽ app icon
└── build.sh                    build script
```
