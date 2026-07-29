# Basic use cases

Single-app commands: launch or focus one application, optionally snapping its window to a layout. For whole workspaces see [LaunchCommunicationsUseCase.md](LaunchCommunicationsUseCase.md) and [LaunchGmailCommunications.md](LaunchGmailCommunications.md).

All commands work from the Hammerspoon console, from Lua hotkeys, or from any external launcher (Elgato Stream Deck, Keyboard Maestro, Raycast, a plain script) via the `hs` CLI.

## Generic help

The Spoon documents itself at runtime — methods, layouts, workspaces, and Chrome profiles are discovered on the fly, so custom additions show up automatically:

```bash
hs -c 'spoon.AppLaunchScripts:help()'
```

The output contains one copy-pasteable command per workspace launcher and per Chrome profile. When you forget a command, start here.

## Terminal

Focus or launch Terminal on the left 66% of the screen:

```bash
hs -c 'spoon.AppLaunchScripts:terminal()'
```

## Any app, any layout

```bash
hs -c 'spoon.AppLaunchScripts:focusOrLaunch("Safari", "right34")'
```

The layout name is resolved in this order:

1. A key in the `layouts` table: `full`, `leftHalf`, `rightHalf`, `left66`, `right34`, `center`, or one you added yourself
2. A dynamic name — `left<N>`, `right<N>`, `top<N>`, or `bottom<N>` where `N` is a percentage of the screen (e.g. `right86` is a window covering the right 86%)
3. Anything else shows an "Unknown layout" alert and leaves the window where it is

Omit the layout to leave the window where it is:

```bash
hs -c 'spoon.AppLaunchScripts:focusOrLaunch("Slack")'
```

Whatever state the app is in — not running, hidden, minimized — it comes up focused: the Spoon launches it if needed, unhides it, unminimizes its windows, and waits for the window to exist after a cold launch before applying the layout.

## Google Chrome profiles

Chrome keeps its profiles in `~/Library/Application Support/Google/Chrome/Local State`; each has a directory (`Default`, `Profile 1`, …) and a display name. List yours:

```bash
hs -c 'for dir, name in pairs(spoon.AppLaunchScripts:chromeProfiles()) do print(dir, name) end'
```

Launch or focus Chrome with a preselected profile — either the directory or the display name works, case-insensitively:

```bash
hs -c 'spoon.AppLaunchScripts:chrome("example_profile_name", "rightHalf")'
```

```lua
-- by profile directory
spoon.AppLaunchScripts:chrome("Profile 1", "leftHalf")

-- no profile: behaves like focusOrLaunch("Google Chrome", ...)
spoon.AppLaunchScripts:chrome(nil, "full")
```

If a window of that profile is already open it is focused and laid out; otherwise a new window is opened via `open -na "Google Chrome" --args --profile-directory="<dir>"`.

> **Note:** recognizing existing windows relies on Chrome appending the profile name to window titles (e.g. `… - Google Chrome – example_profile_name`), which Chrome only does when more than one profile is in use. With a single active profile the method may open an extra window instead of focusing the current one.

## Hotkeys

```lua
hs.hotkey.bind({ "cmd", "alt" }, "t", function()
    spoon.AppLaunchScripts:terminal()
end)

hs.hotkey.bind({ "cmd", "alt" }, "b", function()
    spoon.AppLaunchScripts:focusOrLaunch("Safari", "right34")
end)

hs.hotkey.bind({ "cmd", "alt" }, "c", function()
    spoon.AppLaunchScripts:chrome("example_profile_name", "rightHalf")
end)
```

See [examples/init.lua](../examples/init.lua) for a fuller configuration.

## Stream Deck (or any external launcher)

With `hs.ipc` loaded, any Spoon method can be called from a shell command, so an Elgato Stream Deck button (via the *System → Open* or a shell-command plugin), Keyboard Maestro, or a plain script can trigger it:

```bash
hs -c 'spoon.AppLaunchScripts:terminal()'
```

Use the full path `/opt/homebrew/bin/hs` if the launcher doesn't inherit your shell's `PATH` — GUI launchers usually don't.

All commands are idempotent: pressing a button again just re-focuses the window and re-asserts the layout.
