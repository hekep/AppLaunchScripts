# Use case: launching dev apps (editor + terminal)

One button brings up a development workspace: your project open in Visual Studio Code on the left 66% of the screen, Terminal on the right 34% — the workspace Space pops up with both windows in place.

```bash
hs -c 'spoon.AppLaunchScripts:launchDevApps()'
```

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchDevApps
```

## Configuration

`AppLaunchScripts.spoon/workspaces/LaunchDevApps.json`

```json
{
  "name": "DevApps",
  "space": {
    "display": "current",
    "desktop": 3
  },
  "layout": {
    "direction": "horizontal",
    "widths": [66, 34]
  },
  "apps": [
    {
      "name": "Code",
      "cmd": "cd ~/my-project/ && code .",
      "window": "my-project"
    },
    {
      "name": "Terminal"
    }
  ]
}
```

- The `name` field (`DevApps`) provides the generated method `launchDevApps()`; the file name is the `launchWorkspace("LaunchDevApps")` argument.
- VS Code is launched by a shell **`cmd`** (run in a login shell, so the `code` CLI is on `PATH`) because `launchOrFocus()` cannot open a *specific project*.
- Replace `my-project` in both `cmd` and `window` with your project folder name. If the config contains private project names, prefix the file with `private` — it stays out of git (see [.gitignore](../.gitignore)).

## The Electron process check — why `window` matters

VS Code is an Electron app: **all project windows live in one `Code` process.** That makes naive duplicate-protection impossible:

- A PID tells you "VS Code is running" but never *which project* is open — one PID hosts them all.
- The `code .` CLI exits within a second; its PID never owns any window.
- Stored PIDs go stale after every restart.

So AppLaunchScripts uses the **live window list as its knowledge base** — the `window` key holds a title fragment (VS Code titles always contain the project folder, e.g. `README.md — my-project`), checked fresh on every launch:

1. **A window whose title matches `my-project` exists** → no launch at all: the window is focused and re-placed. Pressing the button repeatedly never spawns duplicate processes or windows — verified: zero lingering shell processes, window count unchanged.
2. **No matching window** (even if VS Code is running with *other* projects) → `cmd` runs, opening exactly the missing project window, which is then waited for by title and placed.
3. **App not running at all** → `cmd` cold-starts VS Code with the project.

Terminal needs no `window` key: it is a single-identity app, and plain focus-or-launch semantics are enough.

## Pop-up behavior

Launching switches to the workspace Space *first* (creating it if missing), so the Space visibly pops up and new windows open directly on it. Cold-started Electron apps like VS Code restore their own remembered window size a moment after launching; AppLaunchScripts re-asserts the layout every half second until it sticks, so the window may visibly snap from its restored size to the configured 66% — that is expected, not a glitch.

Pressing the button again is idempotent: switch to the Space, focus the two windows, re-assert the 66/34 layout.
