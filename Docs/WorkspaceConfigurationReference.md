# Workspace configuration reference

Drop a `<Name>.json` file into `AppLaunchScripts.spoon/workspaces/`. On load, the Spoon scans that folder and generates `availableWorkspaces.lua` with one method per workspace. After adding or removing workspace files, reload Hammerspoon or run:

```bash
hs -c 'spoon.AppLaunchScripts:generateWorkspaceMethods()'
```

## Keys

| Key                | Meaning                                                                                        |
| ------------------ | ---------------------------------------------------------------------------------------------- |
| `name`             | Workspace name: used in the launch alert and as the generated method name (`launch<Name>()`); defaults to the file name |
| `space.display`    | `"current"` (default), `"primary"`, a screen index number, or a screen name                     |
| `space.desktop`    | 1-based desktop number on that display ("Desktop 1" is `1`); missing Spaces are created automatically. `space.index` is accepted as a legacy alias |
| `layout.direction` | `"horizontal"` (default) or `"vertical"`                                                        |
| `layout.widths`    | Percentages per app, in `apps` order (use `heights` with `"vertical"`); omit for an even split. Validated on launch: the value count must equal the app count, all values must be positive numbers, and the sum must not exceed 100 — otherwise an alert explains the problem and every app gets an equal share |
| `apps[].name`      | Application name, as used by `hs.application.launchOrFocus()` (`"Chrome"` is accepted for `"Google Chrome"`) |
| `apps[].profile`   | Optional Google Chrome profile (directory or display name); makes the entry a Chrome-with-profile window. `null` (or omitted, when `www` is set and the app is Chrome) falls back to the profile Chrome used most recently, then `Default` — so shared example configs need no personal profile names |
| `apps[].www`       | Optional URL **or array of URLs** for the Chrome profile window — one tab per URL. New windows open with all tabs; on repeated launches each missing tab is reopened and the first URL's tab is activated (state restore). Matching uses the URL without scheme/`www.` but **with the path**, so `x.com/UserA` and `x.com/UserB` are distinct tabs. Use post-redirect URLs (e.g. `https://mail.google.com/`, not `www.gmail.com`) so tabs stay recognizable. Tab control needs the macOS Automation permission (Hammerspoon → Google Chrome) — macOS prompts on first use. See [LaunchChromeWithMultipleTabs.md](LaunchChromeWithMultipleTabs.md) |
| `apps[].cmd`       | Optional shell command that launches the app instead of `launchOrFocus()` (run in a login shell, so CLIs like `code` are on `PATH`); `name` is still used to find the window. Runs **only when the app is not already running** (or when `window` is set and no matching window exists) — repeated workspace launches never spawn overlapping processes |
| `apps[].window`    | Optional window-title fragment (case-insensitive) identifying the wanted window — essential for apps like VS Code where one process hosts several project windows. If a matching window exists, launching is skipped and the window is placed; if not, `cmd` runs to open it. If the fragment matches several windows an alert asks you to make it more unique (the first match is used). Not used for Chrome entries with `profile` — those windows are identified by their `www` sites, since Chrome titles change with the active tab |
| —                  | An app that is not installed is reported with an alert: `"<Name>" not installed`                |

Example: a specific VS Code project, duplicate-proof:

```json
{
  "name": "Code",
  "cmd": "cd ~/my-project/ && code .",
  "window": "my-project"
}
```

The live window list is the source of truth for duplicate protection — deliberately not PID bookkeeping: the `code` CLI exits immediately (its PID never owns the window), all VS Code projects share one process (a PID cannot distinguish them), and stored PIDs go stale after app restarts. Window titles identify the project and are re-read fresh on every launch.

Example `cmd` entry — open a project in Visual Studio Code:

```json
{
  "name": "Code",
  "cmd": "cd ~/my-project/ && code ."
}
```

## Choosing desktops: one vs. many

> **Important for multi-desktop workspaces:** disable *System Settings → Desktop & Dock → Mission Control → "Automatically rearrange Spaces based on most recent use"*. With it enabled, macOS reorders desktops every time you switch, so `"desktop": 2` points at a different desktop from one launch to the next — windows end up scattered.

Two strategies:

- **All workspaces on `"desktop": 1`** — workspaces act as *scenes* that rearrange Desktop 1. Because windows never need to change Spaces, the macOS moved-window limitation (below) never triggers, and buttons behave identically whether apps are cold or already running. Recommended when you keep apps running all day.
- **One desktop per workspace** (`desktop` 1, 2, 3, …) — real desktop separation. Works perfectly when apps start fresh (windows are created on the target Space), but apps *already running* on another Space cannot be relocated by macOS: the workspace then arranges them where they are and an alert explains it.

## Behavior

Applying a workspace switches to the target Space first (new windows open on the focused Space), then launches or focuses each app and applies its slot of the layout.

Duplicate protection for Chrome site windows spans **all desktops**: before opening a new window, the Spoon checks (via AppleScript, which sees every Space) whether the workspace's site windows already exist somewhere. If they all live on a different desktop — e.g. after desktops were rearranged or deleted — the workspace **falls back to that desktop**: it announces `Unable to open apps on "Desktop 7" — using "Desktop 3" where the windows already are`, switches there, and applies the layout to the existing windows instead of duplicating them. Repeated presses within 10 seconds are ignored (`… is still launching — press ignored`) so a nervous finger cannot spawn duplicates either.

> **macOS caveat:** on recent macOS versions, moving an *existing* window to another Space programmatically is unreliable (`hs.spaces.moveWindowToSpace` can report success without doing anything). AppLaunchScripts therefore switches Space before opening windows, and prefers opening a fresh window on the target Space over adopting one from another Space when the move fails. When an app's window already exists on a different Space and cannot be moved (typical for `window`-matched apps like VS Code), an alert names the app — `"Code" already open on another Space — arranging it there` — and the layout is applied where the window lives. To truly relocate it, quit the app and press the workspace button again: freshly created windows land on the configured Space.

## Private workspaces

Workspace files whose names start with `personal` or `private` are excluded from git (see [.gitignore](../.gitignore)) — keep configs with personal profile names, URLs, or app lists there. Details and a full example: [LaunchGmailCommunications.md](LaunchGmailCommunications.md).

## Examples

- [Communications](LaunchCommunicationsUseCase.md) — three apps side by side on Desktop 1
- [GmailCommunications](LaunchGmailCommunications.md) — two Chrome profile windows on Desktop 2 (private workspace)
- [HealthTechNews](LaunchChromeWithMultipleTabs.md) — two Chrome windows with whole tab sets, state-restoring
