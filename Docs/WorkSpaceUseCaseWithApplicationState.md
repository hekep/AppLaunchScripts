# Use case: workspaces with application state (since 0.11.0)

A workspace used to answer *which apps, where*. With `apps[].url` it also answers ***in what state***: press one Stream Deck button and the whole desktop materializes with each application already navigated to the right place — Claude open **with your coding session active**, Slack on the right channel, Teams on the right person.

## The `url` key

Any `hammerspoon://` address from the generated catalogs (see `help()`, or the `available*Comms.lua` files) can be planted into a workspace's `apps` list:

```json
{
  "name": "DevAppLaunchScripts",
  "space": { "desktop": 1 },
  "apps": [
    {
      "name": "Claude",
      "url": "hammerspoon://launchclaudecodehammerspoonapplaunchscriptsplugin"
    },
    { 
      "name": "Code", 
      "cmd": "cd ~/AppLaunchScripts/ && code .",
      "window": "AppLaunchScripts" 
    },
    { "name": "Terminal" }
  ],
  "layout": { "direction": "horizontal", "widths": [40, 40, 20] }
}
```

Pressing the workspace button launches Claude **with the AppLaunchScripts coding session activated**, next to VS Code and Terminal — the whole working context in one press.

## The rules

- **`url` overrides `name`** for launching: when both are present, the url does the launching (with its predefined state), not a plain `launchOrFocus`.
- **`name` is no longer mandatory** when `url` is present.
- When `name` **is** given, it serves two purposes: it is the **installed-check** — if the application is not installed, the url is **not** launched (you get an alert instead) — and it identifies the window so the workspace can place it in the layout as usual.
- Without `name`, the entry is **launch-only**: the url fires, but the entry owns no window — it takes no slot in `layout.widths`, and the workspace's repair/resize stages ignore it.
- State urls fire **once per press, on every press** — including a press on an already-complete workspace that only repairs or resizes windows. The state is part of the workspace, so pressing the button always re-asserts it: Claude goes back to the right session even when every window was already open.
- Other schemes work too: any URL your system can open is accepted (`slack://…`, custom app schemes). `hammerspoon://` addresses are resolved internally — no browser, no round-trip.

## Where the addresses come from

Every integration generates its own catalog of state urls, one per destination — session, channel, person, chat, PC:

| Integration | Address shape | Catalog |
| --- | --- | --- |
| Claude coding sessions | `hammerspoon://launchclaudecode<session>` | `availableClaudeComms.lua` |
| Slack | `hammerspoon://launchslack<domain><name>channel/person/group` | `availableSlackComms.lua` |
| Microsoft Teams | `hammerspoon://launchteams<name>person` | `availableTeamsComms.lua` |
| Discord | `hammerspoon://launchdiscord…channel/person/group` | `availableDiscordComms.lua` |
| Windows App | `hammerspoon://launchwindowsapp<name>pc` | `availableWindowsAppComms.lua` |

Each catalog entry carries its `button:` address ready to copy — the same address works in a Stream Deck button and in a workspace `url`.

## Claude sessions specifically

Claude's coding sessions are scanned automatically from the app's own session store (titles, folders, and timestamps only — never transcripts), so `hammerspoon://launchclaudecode<session>` addresses appear and disappear as you create, rename, and archive sessions in Claude. Run `hs -c 'spoon.AppLaunchScripts:help()'` to see the current list.

Activation clicks the session's row in Claude's sidebar: the sidebar is opened if it happens to be collapsed, the row is scrolled into view and clicked, and your mouse pointer is put back where it was. A row that cannot be found, or a click that does not take, is reported with an alert. The press returns immediately — all waiting happens on timers, so the rest of the workspace launches in parallel rather than queuing behind Claude.

**Renaming a session eventually breaks the address.** The launcher itself survives a rename — it reads the session's current title from the session file at press time, and the file path does not change when you rename. But the method name and the `hammerspoon://` address are derived from the title, so the next reload or `help()` regenerates the catalog under the new name, and from then on any `url` in a workspace JSON and any Stream Deck button still point at the old address and must be updated by hand. Two sessions sharing the same title cannot be told apart at all — see [the Claude use case](ClaudeUseCase.md#two-sessions-with-the-same-name). Neither fails silently: the workspace press warns `matches no launcher`, and a stale button alerts `no longer exists — reassign`. The `claude://resume?…` deep link is deliberately not used: it is an *import* mechanism that re-imports the whole transcript on every press and, for most sessions, forks an untitled copy instead of opening the original.

For Claude on its own — a button that just opens the app, or opens it on one session without a workspace — see [Claude — one button per coding session](ClaudeUseCase.md).
