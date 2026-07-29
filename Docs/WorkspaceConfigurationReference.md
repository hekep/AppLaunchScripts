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
| `space.index`      | 1-based index into that display's Spaces ("Desktop 1" is index 1); missing Spaces are created automatically |
| `layout.direction` | `"horizontal"` (default) or `"vertical"`                                                        |
| `layout.widths`    | Percentages per app, in `apps` order (use `heights` with `"vertical"`); omit for an even split  |
| `apps[].name`      | Application name, as used by `hs.application.launchOrFocus()` (`"Chrome"` is accepted for `"Google Chrome"`) |
| `apps[].profile`   | Optional Google Chrome profile (directory or display name); makes the entry a Chrome-with-profile window |
| `apps[].www`       | Optional URL opened in the new Chrome profile window                                            |
| `apps[].cmd`       | Optional shell command that launches the app instead of `launchOrFocus()` (run in a login shell, so CLIs like `code` are on `PATH`); `name` is still used to find the window. Runs **only when the app is not already running** (or when `window` is set and no matching window exists) — repeated workspace launches never spawn overlapping processes |
| `apps[].window`    | Optional window-title fragment (case-insensitive) identifying the wanted window — essential for apps like VS Code where one process hosts several project windows. If a matching window exists, launching is skipped and the window is placed; if not, `cmd` runs to open it |

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

## Behavior

Applying a workspace switches to the target Space first (new windows open on the focused Space), then launches or focuses each app and applies its slot of the layout.

> **macOS caveat:** on recent macOS versions, moving an *existing* window to another Space programmatically is unreliable (`hs.spaces.moveWindowToSpace` can report success without doing anything). AppLaunchScripts therefore switches Space before opening windows, and prefers opening a fresh window on the target Space over adopting one from another Space when the move fails.

## Private workspaces

Workspace files whose names start with `personal` or `private` are excluded from git (see [.gitignore](../.gitignore)) — keep configs with personal profile names, URLs, or app lists there. Details and a full example: [LaunchGmailCommunications.md](LaunchGmailCommunications.md).

## Examples

- [Communications](LaunchCommunicationsUseCase.md) — three apps side by side on Desktop 1
- [GmailCommunications](LaunchGmailCommunications.md) — two Chrome profile windows on Desktop 2 (private workspace)
