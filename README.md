# AppLaunchScripts

A [Hammerspoon](https://www.hammerspoon.org/) Spoon that focuses an application — launching it first if it isn't running — and snaps its window to a named layout. One keystroke always gets you the app, unhidden, unminimized, and where you expect it on screen.

## Features

- **Focus or launch** — activates the app if running, launches it otherwise
- **Window rescue** — unhides the app and unminimizes its windows before focusing
- **Named layouts** — move the window to a unit rect (`leftHalf`, `right34`, `center`, …) in the same call
- **Launch-aware** — waits for the window to appear after a cold launch before applying the layout
- **Extensible** — add your own layouts and app helpers

## Prerequisites

- **[Hammerspoon](https://www.hammerspoon.org/)**

  ```bash
  brew install --cask hammerspoon
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

## Usage

Bind hotkeys to the built-in helper or the generic method:

```lua
-- Terminal on the left 66% of the screen
hs.hotkey.bind({ "cmd", "alt" }, "t", function()
    spoon.AppLaunchScripts:terminal()
end)

-- Any app, any layout
hs.hotkey.bind({ "cmd", "alt" }, "b", function()
    spoon.AppLaunchScripts:focusOrLaunch("Safari", "right34")
end)

-- Omit the layout to leave the window where it is
spoon.AppLaunchScripts:focusOrLaunch("Slack")
```

See [examples/init.lua](examples/init.lua) for a fuller configuration.

### Google Chrome profiles

Chrome keeps its profiles in `~/Library/Application Support/Google/Chrome/Local State`; each has a directory (`Default`, `Profile 1`, …) and a display name. List yours:

```bash
hs -c 'for dir, name in pairs(spoon.AppLaunchScripts:chromeProfiles()) do print(dir, name) end'
```

Launch or focus Chrome with a preselected profile — either the directory or the display name works, case-insensitively:

```lua
-- by display name
spoon.AppLaunchScripts:chrome("profile_display_name", "rightHalf")

-- by profile directory
spoon.AppLaunchScripts:chrome("Profile 1", "leftHalf")

-- no profile: behaves like focusOrLaunch("Google Chrome", ...)
spoon.AppLaunchScripts:chrome(nil, "full")
```

If a window of that profile is already open it is focused and laid out; otherwise a new window is opened via `open -na "Google Chrome" --args --profile-directory="<dir>"`.

> **Note:** recognizing existing windows relies on Chrome appending the profile name to window titles (e.g. `… - Google Chrome – Heikki`), which Chrome only does when more than one profile is in use. With a single active profile the method may open an extra window instead of focusing the current one.

### Generic help

The Spoon documents itself at runtime — methods, layouts, and Chrome profiles are discovered on the fly, so custom additions show up automatically:

```bash
hs -c 'spoon.AppLaunchScripts:help()'
```

```
AppLaunchScripts 0.1.0 — https://github.com/hekep/AppLaunchScripts

Methods:
  spoon.AppLaunchScripts:chrome()
  spoon.AppLaunchScripts:chromeProfiles()
  spoon.AppLaunchScripts:focusOrLaunch()
  spoon.AppLaunchScripts:help()
  spoon.AppLaunchScripts:start()
  spoon.AppLaunchScripts:terminal()

Layouts (plus dynamic left<N>/right<N>/top<N>/bottom<N>):
  center, full, left66, leftHalf, right34, rightHalf

Chrome profiles (directory / name — either works):
  Default      Person 1
  Profile 1    Heikki
  Profile 2    kanava.to
```

### Stream Deck (or any external launcher)

With `hs.ipc` loaded, any Spoon method can be called from a shell command, so an Elgato Stream Deck button (via the *System → Open* or a shell-command plugin), Keyboard Maestro, or a plain script can trigger it:

```bash
hs -c 'spoon.AppLaunchScripts:terminal()'
```

```bash
hs -c 'spoon.AppLaunchScripts:focusOrLaunch("Safari", "right34")'
```

```bash
hs -c 'spoon.AppLaunchScripts:chrome("kanava.to", "rightHalf")'
```

Use the full path `/opt/homebrew/bin/hs` if the launcher doesn't inherit your shell's `PATH`.

## API

### `spoon.AppLaunchScripts:focusOrLaunch(appName, layoutName)`

Focuses `appName`, launching it if necessary. `layoutName` is optional and resolved in this order:

1. A key in the `layouts` table (e.g. `center`)
2. A dynamic name — `left<N>`, `right<N>`, `top<N>`, or `bottom<N>` where `N` is a percentage of the screen (e.g. `right86` is a window covering the right 86%)
3. Anything else shows an "Unknown layout" alert and leaves the window where it is

Returns `true` when the app was found or launched, `false` otherwise.

### `spoon.AppLaunchScripts:chrome(profile, layoutName)`

Focuses or launches Google Chrome with a preselected profile. `profile` is a profile directory (`"Profile 2"`) or display name (`"kanava.to"`), case-insensitive; pass `nil` to skip profile handling. Unknown profiles show an alert and return `false`.

### `spoon.AppLaunchScripts:chromeProfiles()`

Returns a table mapping Chrome profile directories to display names, read from Chrome's `Local State` file. Empty table if Chrome isn't installed.

### `spoon.AppLaunchScripts:help()`

Prints (and returns) runtime-generated help: all methods, layouts, and Chrome profiles.

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
