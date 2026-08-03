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

## Shell scripts: one window, one script at a time

Monitoring tools each own a window. **Shell scripts are the opposite: they all share one**, on Desktop 1. Drop a script into `config/terminal/shells/` and it becomes a button:

```
deploy-staging.sh   ->  launchShellDeployStaging()
                        hammerspoon://launchshelldeploystaging
```

Nothing to configure — the file name is the button name, CamelCased with accents transliterated, exactly like every other integration. Rename a script and its address follows; delete it and the button disappears on the next `help()` or reload. Any executable file counts, as does anything named `*.sh` that has lost its executable bit.

Make the first comment line of the script a description and it appears in the catalog beside the button address:

```bash
#!/bin/zsh
# Sync the aliases across to the laptop
```

### Why one shared window

Two reasons, and both are the point of the feature rather than a limitation.

**You need to watch the output.** These are scripts whose result you have to read — what synced, what failed, what the remote host said. So the window is always brought to the front, on Desktop 1, and left there with the output on screen. It is not a background job runner: if you want silent execution, run the script from a shell.

**Overlapping runs must be impossible.** Scripts that touch the same machine, the same files or the same remote host must never run two at a time. The single window enforces that: a press while a script is still running is **refused**, with the name of what is holding the window —

> Shell window is busy running rsync — "deploy-staging" was not started, try again later

— and the launcher returns `false`. Nothing is typed into a running program, nothing is queued behind your back, and two scripts cannot interleave. The window *is* the lock, and because it is in front of you, you can see exactly what holds it.

### What a press does

1. Switch to **Desktop 1** — the first Space of the screen you are on.
2. Bring the shared window up, creating it there if it does not exist.
3. If the window is **idle**, run the script in it.
4. If the window is **busy**, report what is running and cancel.

The shared window's title is `shells`, so a workspace can place it like any other terminal window: `{ "name": "Terminal", "window": "shells" }`.

### Privacy

The `shells/` **folder** is committed so the feature is discoverable, but **the scripts inside it are not** — they routinely hold hostnames, paths and account details. `.gitignore` publishes the folder's README and hides everything else. Keep credentials out of the scripts regardless: anything there is readable by any application that can read your files.

## Known issues

- **The sync is superficial about parameters.** A tool is considered "running" when its *process name* appears in the tab — `iostat` matches `iostat`, whatever arguments it was given. Change `iostat -w 2` to `iostat -w 5` in the config and a press will **not** restart it with the new interval, because something called `iostat` is already there. Quit it in the window (or close the window) and press again to pick up changed arguments.
- **Terminal copies the custom title into new tabs and windows** opened from a window that has one. Press `Cmd+T` in the `htop` window and the result also calls itself `htop`. A press then prefers the window on this desktop that is actually running the tool, so it still does the right thing — but two identically titled windows may exist.
- **Two tools must not share a `title`.** They would each restart the other's command forever. The catalog warns about this at generation time, and an alert names the pair.
- **A shell script that leaves something running holds the window.** The lock is released when the tab returns to a prompt, so a script ending in `tail -f` or an interactive prompt keeps every other script locked out until you deal with it. That is deliberate — but it is the one way to block yourself.

## Security note

`config/terminal/*.json` holds **command lines in plain text**, which may include paths, hostnames or flags you would rather not share. The folder is gitignored so it never reaches the repository, but it is readable by any application that can read your files. No credentials should ever be put in a command.
