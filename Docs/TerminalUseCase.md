# Use case: Terminal — one dedicated window per tool

Press an Elgato Stream Deck button and `htop` is in front of you — in its own Terminal window, already running. Press it again an hour later and the same window comes forward. Quit `htop` by accident and the next press starts it again in that same window.

```bash
hs -c 'spoon.AppLaunchScripts:launchTerminalHtop()'
```

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchterminalhtop
```

## macOS permission: Automation for Terminal

The first time a terminal button runs, macOS asks:

> **"Hammerspoon.app" wants access to control "Terminal.app".**

Click **Allow**. This is the one permission the feature needs, and it is *Hammerspoon* that needs it — the Spoon sends its Apple Events through Hammerspoon, so Hammerspoon is the application macOS asks about.

Three things worth knowing:

- **Hammerspoon freezes until you answer.** The Apple Event blocks while the dialog is up, so buttons and workspaces stop responding until you click. Answer it rather than leaving it on screen.
- **Denying it disables the whole feature.** There is no fallback: the accessibility API cannot read what a tab is running, and cannot set a window's title. If you clicked *Don't Allow* by mistake, re-enable it under *System Settings → Privacy & Security → Automation → Hammerspoon → Terminal*.
- **Only Terminal is touched.** The events read each window's first-tab title, its busy flag and its process list, set a title, select tab 1, and run your configured command. Nothing else.

This is separate from the Accessibility permission the workspace engine already uses.

## Configuration

Files live in `AppLaunchScripts.spoon/config/terminal/` — as many as you like, each holding as many tools as you like. A `monitoringTools.json` with ten monitoring tools is written for you on first run.

```json
{
  "terminals": [
    {
      "name": "Htop",
      "title": "htop",
      "command": "htop",
      "description": "Processes, CPU and memory. Install: brew install htop"
    },
    {
      "name": "DockerStats",
      "title": "docker-stats",
      "command": "docker stats",
      "process": "docker",
      "description": "Live CPU and memory per container. Install: Docker Desktop"
    }
  ]
}
```

| Key | Meaning |
| --- | --- |
| `name` | The method name: `launchTerminalHtop()` and `hammerspoon://launchterminalhtop` |
| `title` | The window's identity — the *custom title* of its first tab. Defaults to `name` |
| `command` | What runs in the tab |
| `process` | What to look for in the tab's process list. Defaults to the command's first word; `docker stats` needs `docker` |
| `cwd` | Optional directory to `cd` into first |
| `description` | Shown in the catalog — end it with the install command, as above |

Do not use `Terminal` as a `title`: a window with no custom title of its own reports exactly that string, so it would match the wrong window.

### The ten monitoring tools

`htop`, `btop`, `glances`, `top -o cpu`, `vm_stat 2`, `iostat -w 2`, `ncdu /`, `nettop -P`, `docker stats`, `lazydocker`. Four are built into macOS, the rest tell you their `brew install` line in the catalog.

## What a press does

1. **Bring the window up** — found by the custom title of its first tab, created here if this desktop has none.
2. **Select tab 1** and show it.
3. **Then look at what is running in it:**
   - the tool is running → nothing to do, you are looking at it;
   - the tab is idle at a shell prompt → run the command again;
   - **something else is running there** → focus it and *leave it alone*.

That last rule is deliberate. If you left `vim` in that window, an interrupted editor is not recoverable, whereas a wrongly focused window costs you a keystroke.

Only **tab 1** is ever managed. Open more tabs by hand if you like — they are ignored, and tab 1 is selected before the window is shown.

## Workspaces: two levels of sync

Because the custom title becomes part of the window's title, a workspace places these windows with the `window` key it already has, while the `url` keeps their *contents* in sync. Both happen in one press:

```json
{
  "name": "SystemMonitoring",
  "space": { "display": "current", "desktop": 2 },
  "layout": { "direction": "horizontal", "widths": [34, 33, 33] },
  "apps": [
    { "name": "Terminal", "url": "hammerspoon://launchterminalhtop",   "window": "htop" },
    { "name": "Terminal", "url": "hammerspoon://launchterminaldiskio", "window": "iostat" },
    { "name": "Terminal", "url": "hammerspoon://launchterminalnettop", "window": "nettop" }
  ]
}
```

- **The workspace** syncs *where* — desktop, position and width.
- **Each `url`** syncs *what is inside* — creating the window, or restarting a tool that has exited.

Kill `iostat` and press the workspace: htop and nettop are left running, iostat restarts, and all three windows are re-placed.

## Spaces

Terminal windows behave like Chrome windows: each lives on a desktop, unless you assign it to all of them (Dock → right-click → Options → All Desktops).

A press looks for the tool's window **on the current desktop**, which during a workspace press is that workspace's desktop, because the engine switches first. A window belonging to a different desktop is never stolen — a new one is created here instead, so the same tool can run on several desktops at once. If Terminal is assigned to all desktops, there is simply one window and every desktop finds it.

Unlike the accessibility API, AppleScript sees Terminal windows on every Space, so a window parked elsewhere is found rather than silently duplicated.

## Known issues

- **The sync is superficial about parameters.** A tool is considered "running" when its *process name* appears in the tab — `iostat` matches `iostat`, whatever arguments it was given. Change `iostat -w 2` to `iostat -w 5` in the config and a press will **not** restart it with the new interval, because something called `iostat` is already there. Quit it in the window (or close the window) and press again to pick up changed arguments.
- **Terminal copies the custom title into new tabs and windows** opened from a window that has one. Press `Cmd+T` in the `htop` window and the result also calls itself `htop`. A press then prefers the window on this desktop that is actually running the tool, so it still does the right thing — but two identically titled windows may exist.
- **Two tools must not share a `title`.** They would each restart the other's command forever. The catalog warns about this at generation time, and an alert names the pair.

## Security note

`config/terminal/*.json` holds **command lines in plain text**, which may include paths, hostnames or flags you would rather not share. The folder is gitignored so it never reaches the repository, but it is readable by any application that can read your files. No credentials should ever be put in a command.
