# AppLaunchScripts

AppLaunchScripts is a declarative workspace launcher for [Hammerspoon](https://www.hammerspoon.org/).

A workspace configuration describes:

- the target display;
- the target macOS Space;
- the applications to launch or focus;
- the window layout to apply.

One Stream Deck button or hotkey brings up the whole workspace: apps launched or focused, unhidden, unminimized, moved to the right Space, and laid out side by side.

## Example

`AppLaunchScripts.spoon/workspaces/Communications.json`

```json
{
  "name": "Communications",
  "space": {
    "display": "current",
    "index": 1
  },
  "layout": {
    "direction": "horizontal",
    "widths": [33, 33, 34]
  },
  "apps": [
    {
      "name": "Thunderbird"
    },
    {
      "name": "Slack"
    },
    {
      "name": "Discord"
    }
  ]
}
```

Launch it:

```bash
hs -c 'spoon.AppLaunchScripts:launchCommunications()'
```

## Use cases

- [Basic use cases](Docs/BasicUseCases.md) — `help()`, `terminal()`, `focusOrLaunch()` with layouts, Chrome profiles, hotkeys, and Stream Deck integration
- [The Communications workspace](Docs/LaunchCommunicationsUseCase.md) — `launchCommunications()`: three apps side by side on Desktop 1
- [The GmailCommunications workspace](Docs/LaunchGmailCommunications.md) — `launchGmailCommunications()`: Gmail in two Chrome profiles on Desktop 2, kept out of git as a private workspace

## Terminology

### Display

A physical or virtual monitor recognized by macOS.

Examples include a built-in MacBook display, an external monitor, or a virtual Visor display.

### Space

A macOS virtual desktop associated with a Display.

When "Displays have separate Spaces" is enabled, each Display has its own ordered collection of Spaces.

### Workspace

A named, declarative configuration containing applications, a target Display and Space, and a window layout.

A Workspace is an AppLaunchScripts concept. It is not a native macOS Space name.

## Features

- **Declarative workspaces** — one JSON file per workspace in `workspaces/`; a `launch<Name>()` method is generated for each
- **Focus or launch** — activates the app if running, launches it otherwise
- **Window rescue** — unhides the app and unminimizes its windows before focusing
- **Named layouts** — move a window to a unit rect (`leftHalf`, `right34`, `center`, …) or a dynamic one (`right86`)
- **Launch-aware** — waits for the app and its window to appear after a cold launch before applying the layout
- **Chrome profiles** — launch or focus Google Chrome with a preselected profile
- **Self-documenting** — `help()` lists methods, layouts, workspaces, and Chrome profiles at runtime

## Prerequisites

- **[Hammerspoon](https://www.hammerspoon.org/)**

  ```bash
  brew install --cask hammerspoon
  ```

- **Accessibility permission** — required for switching Spaces (and general window control). Grant Hammerspoon access in *System Settings → Privacy & Security → Accessibility*, or trigger the prompt with:

  ```bash
  hs -c 'hs.accessibilityState(true)'
  ```

  **Restart Hammerspoon after granting** — macOS applies the permission only to freshly launched processes, so a running Hammerspoon keeps reporting `false` until relaunched:

  ```bash
  hs -c 'hs.relaunch()'
  ```

  Verify:

  ```bash
  hs -c 'print(hs.accessibilityState())'
  ```

- **`luac`** (ships with Lua) — used to syntax-check the Spoon:

  ```bash
  brew install lua
  ```

- **`hs.ipc` module** — enables the `hs` command-line tool. Add to your `~/.hammerspoon/init.lua`:

  ```lua
  require("hs.ipc")
  ```

  The Homebrew cask already links the `hs` binary to `/opt/homebrew/bin/hs`, so no further setup is needed. If you installed Hammerspoon another way, install the CLI once from the Hammerspoon console:

  ```lua
  hs.ipc.cliInstall("/opt/homebrew")  -- Apple Silicon
  hs.ipc.cliInstall()                 -- Intel (/usr/local)
  ```

  Note: `cliInstall` returns `false` if the target `bin` directory isn't writable by your user — on Apple Silicon Macs, plain `cliInstall()` fails because `/usr/local/bin` is root-owned.

## Installation

Clone this repository and symlink the Spoon into Hammerspoon's Spoons directory:

```bash
git clone https://github.com/hekep/AppLaunchScripts.git ~/AppLaunchScripts
```

```bash
mkdir -p ~/.hammerspoon/Spoons
```

```bash
ln -s ~/AppLaunchScripts/AppLaunchScripts.spoon ~/.hammerspoon/Spoons/AppLaunchScripts.spoon
```

Then add to your `~/.hammerspoon/init.lua`:

```lua
require("hs.ipc")

hs.loadSpoon("AppLaunchScripts")

spoon.AppLaunchScripts:start()
```

Reload your Hammerspoon config. Verify the Spoon is loaded from a shell:

```bash
hs -c 'print(spoon.AppLaunchScripts.version)'
```

> **Note:** the `spoon` global only exists after `hs.loadSpoon("AppLaunchScripts")` has run inside Hammerspoon. An error like `attempt to index a nil value (global 'spoon')` means the Spoon isn't loaded — check that the symlink exists in `~/.hammerspoon/Spoons/` and that `init.lua` contains the lines above.

## Workspace configuration reference

Drop a `<Name>.json` file into `AppLaunchScripts.spoon/workspaces/`. On load, the Spoon scans that folder and generates `availableWorkspaces.lua` with one method per workspace. After adding or removing workspace files, reload Hammerspoon or run:

```bash
hs -c 'spoon.AppLaunchScripts:generateWorkspaceMethods()'
```

| Key                | Meaning                                                                                        |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| `name`             | Workspace name: used in the launch alert and as the generated method name (`launch<Name>()`); defaults to the file name |
| `space.display`    | `"current"` (default), `"primary"`, a screen index number, or a screen name                     |
| `space.index`      | 1-based index into that display's Spaces ("Desktop 1" is index 1); missing Spaces are created automatically |
| `layout.direction` | `"horizontal"` (default) or `"vertical"`                                                        |
| `layout.widths`    | Percentages per app, in `apps` order (use `heights` with `"vertical"`); omit for an even split  |
| `apps[].name`      | Application name, as used by `hs.application.launchOrFocus()` (`"Chrome"` is accepted for `"Google Chrome"`) |
| `apps[].profile`   | Optional Google Chrome profile (directory or display name); makes the entry a Chrome-with-profile window |
| `apps[].www`       | Optional URL opened in the new Chrome profile window                                            |

Applying a workspace switches to the target Space first (new windows open on the focused Space), then launches or focuses each app and applies its slot of the layout.

Workspace files whose names start with `personal` or `private` are excluded from git (see [.gitignore](.gitignore)) — details in [LaunchGmailCommunications.md](Docs/LaunchGmailCommunications.md).

> **macOS caveat:** on recent macOS versions, moving an *existing* window to another Space programmatically is unreliable (`hs.spaces.moveWindowToSpace` can report success without doing anything). AppLaunchScripts therefore switches Space before opening windows, and prefers opening a fresh window on the target Space over adopting one from another Space when the move fails.

## API

### `spoon.AppLaunchScripts:launchWorkspace(name)`

Loads `workspaces/<name>.json` and applies it. Returns `true` when the workspace was applied, `false` otherwise.

### `spoon.AppLaunchScripts:launch<Name>()`

Generated shortcut per workspace file, e.g. `launchCommunications()`. Equivalent to `launchWorkspace("<Name>")`.

### `spoon.AppLaunchScripts:loadWorkspace(name)`

Loads and decodes a workspace JSON file. Returns the configuration table, or `nil` (with an alert) when missing or invalid.

### `spoon.AppLaunchScripts:applyWorkspace(config)`

Applies a workspace configuration table: resolves the display and Space, switches to it, launches or focuses the apps, moves their windows there, and lays them out.

### `spoon.AppLaunchScripts:workspaces()`

Returns a sorted list of available workspace names.

### `spoon.AppLaunchScripts:generateWorkspaceMethods()`

Regenerates `availableWorkspaces.lua` from `workspaces/*.json` and loads it. Runs automatically when the Spoon loads.

### `spoon.AppLaunchScripts:focusOrLaunch(appName, layoutName)`

Focuses `appName`, launching it if necessary. `layoutName` is optional and resolved in this order:

1. A key in the `layouts` table (e.g. `center`)
2. A dynamic name — `left<N>`, `right<N>`, `top<N>`, or `bottom<N>` where `N` is a percentage of the screen (e.g. `right86` is a window covering the right 86%)
3. Anything else shows an "Unknown layout" alert and leaves the window where it is

Returns `true` when the app was found or launched, `false` otherwise.

### `spoon.AppLaunchScripts:chrome(profile, layoutName)`

Focuses or launches Google Chrome with a preselected profile. `profile` is a profile directory (`"Profile 2"`) or display name (`"example_profile_name"`), case-insensitive; pass `nil` to skip profile handling. Unknown profiles show an alert and return `false`.

### `spoon.AppLaunchScripts:chromeProfiles()`

Returns a table mapping Chrome profile directories to display names, read from Chrome's `Local State` file. Empty table if Chrome isn't installed.

### `spoon.AppLaunchScripts:help()`

Returns runtime-generated help: all methods, layouts, workspaces, and Chrome profiles — as copy-pasteable commands where applicable.

### `spoon.AppLaunchScripts:terminal()`

Shortcut for `focusOrLaunch("Terminal", "left66")`.

### `spoon.AppLaunchScripts:start()`

Starts the Spoon (currently a no-op, kept for Spoon API conformance). Returns the Spoon object.

### `spoon.AppLaunchScripts.layouts`

Table of named layouts as unit rects — `x`, `y`, `w`, `h` are fractions of the screen frame.

| Name        | Position                        |
| ----------- | ------------------------------- |
| `full`      | entire screen                   |
| `leftHalf`  | left 50%                        |
| `rightHalf` | right 50%                       |
| `left66`    | left 66%                        |
| `right34`   | right 34%                       |
| `center`    | centered, 80% × 84% of screen   |

Add your own:

```lua
spoon.AppLaunchScripts.layouts.topHalf = { x = 0.00, y = 0.00, w = 1.00, h = 0.50 }
```

For plain edge-anchored sizes you don't need to define anything — dynamic names like `left70`, `right86`, `top40`, `bottom25` are parsed on the fly.

## License

MIT — see [LICENSE](LICENSE).
