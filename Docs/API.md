# API

All methods live on `spoon.AppLaunchScripts` and are callable from Lua (hotkeys, the Hammerspoon console) or from a shell via `hs -c '…'`.

## Workspaces

### `spoon.AppLaunchScripts:launchWorkspace(name)`

Loads `workspaces/<name>.json` and applies it. Returns `true` when the workspace was applied, `false` otherwise.

### `spoon.AppLaunchScripts:launch<Name>()`

Generated shortcut per workspace file, e.g. `launchCommunications()`. The name comes from the config's `name` field. Equivalent to `launchWorkspace("<file base name>")`.

### `spoon.AppLaunchScripts:loadWorkspace(name)`

Loads and decodes a workspace JSON file. Returns the configuration table, or `nil` (with an alert) when missing or invalid.

### `spoon.AppLaunchScripts:applyWorkspace(config)`

Applies a workspace configuration table: resolves the display and Space, switches to it, launches or focuses the apps, moves their windows there, and lays them out. See the [workspace configuration reference](WorkspaceConfigurationReference.md).

### `spoon.AppLaunchScripts:workspaces()`

Returns a sorted list of available workspace names.

### `spoon.AppLaunchScripts:generateWorkspaceMethods()`

Regenerates `availableWorkspaces.lua` from `workspaces/*.json` and loads it. Runs automatically when the Spoon loads.

## Single apps

### `spoon.AppLaunchScripts:focusOrLaunch(appName, layoutName)`

Focuses `appName`, launching it if necessary. `layoutName` is optional and resolved in this order:

1. A key in the `layouts` table (e.g. `center`)
2. A dynamic name — `left<N>`, `right<N>`, `top<N>`, or `bottom<N>` where `N` is a percentage of the screen (e.g. `right86` is a window covering the right 86%)
3. Anything else shows an "Unknown layout" alert and leaves the window where it is

Returns `true` when the app was found or launched, `false` otherwise.

### `spoon.AppLaunchScripts:terminal()`

Shortcut for `focusOrLaunch("Terminal", "left66")`.

## Google Chrome

### `spoon.AppLaunchScripts:chrome(profile, layoutName)`

Focuses or launches Google Chrome with a preselected profile. `profile` is a profile directory (`"Profile 2"`) or display name (`"example_profile_name"`), case-insensitive; pass `nil` to skip profile handling. Unknown profiles show an alert and return `false`.

### `spoon.AppLaunchScripts:chromeProfiles()`

Returns a table mapping Chrome profile directories to display names, read from Chrome's `Local State` file. Empty table if Chrome isn't installed.

## Introspection

### `spoon.AppLaunchScripts:help()`

Returns runtime-generated help: all methods, layouts, workspaces, and Chrome profiles — as copy-pasteable commands where applicable.

### `spoon.AppLaunchScripts:start()`

Starts the Spoon (currently a no-op, kept for Spoon API conformance). Returns the Spoon object.

## Layouts

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
