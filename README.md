# AppLaunchScripts

AppLaunchScripts is a declarative workspace launcher for [Hammerspoon](https://www.hammerspoon.org/).

A workspace configuration describes:

- the target display;
- the target macOS Space;
- the applications to launch or focus;
- the window layout to apply.

One Stream Deck button or hotkey brings up the whole workspace — apps launched or focused, unhidden, unminimized, moved to the right Space, and laid out side by side:

```bash
hs -c 'spoon.AppLaunchScripts:launchCommunications()'
```

## Workspaces

A workspace is a JSON file in `AppLaunchScripts.spoon/workspaces/` describing a desktop full of apps, windows, tabs, and their layout — materialized, verified, and resized by repeated presses of one button.

- [Workspace configuration reference](Docs/WorkspaceConfigurationReference.md) — all JSON keys and workspace behavior

### Workspace use cases

- [The Communications workspace](Docs/LaunchCommunicationsUseCase.md) — `launchCommunications()`: three apps side by side on Desktop 1, with the example configuration
- [The GmailCommunications workspace](Docs/LaunchGmailCommunications.md) — `launchGmailCommunications()`: Gmail in two Chrome profiles on Desktop 2, kept out of git as a private workspace
- [Launching dev apps](Docs/UseCaseLaunchingDevApps.md) — `launchDevApps()`: a VS Code project (duplicate-proof via the Electron window-title check) plus Terminal, 66/34
- [Chrome windows with multiple tabs](Docs/LaunchChromeWithMultipleTabs.md) — `launchHealthTechNews()`: two tab-set windows side by side, with state restore — closed tabs reopen, nothing duplicates
- [Workspaces with application state](Docs/WorkSpaceUseCaseWithApplicationState.md) — *since 0.11.0*: `apps[].url` plants any `hammerspoon://` state address into a workspace, so one press opens Claude with a coding session active, Slack on a channel, Teams on a person

## Slack

One button per Slack conversation: press it and Slack opens that channel, person, or group with the message box focused — start typing. Workspaces (domains) are discovered automatically from Slack's local state; the conversations you want buttons for are **declared** in one gitignored config file per domain, `AppLaunchScripts.spoon/config/slack/<Domain>.json`, using IDs from Slack's *Copy link* (`/archives/<ID>`):

```json
{
  "domain": "example-team",
  "channels": [ { "name": "general", "id": "C0123ABCD" } ],
  "people":   [ { "name": "Alice", "id": "D0456EFGH", "title": "Alice Smith" } ]
}
```

Every entry becomes a generated method and Stream Deck URL, e.g. `launchSlackExampleGeneralChannel()` / `hammerspoon://launchslackexamplegeneralchannel`.

### Slack use case

- [Slack — one button per conversation](Docs/SlackUseCase.md) — configuration, the `name`/`title`/`alias` convention, finding IDs, and what a press does

## Microsoft Teams

One button per person: press it and Teams opens the chat with that person, message box focused — start typing. A person is just an email address, **declared** in one gitignored config file, `AppLaunchScripts.spoon/config/teams/Teams.json` — no IDs, no scanning, no macOS permissions:

```json
{
  "people": [ { "name": "Alice", "email": "alice@example.com" } ]
}
```

Every person becomes a generated method and Stream Deck URL, e.g. `launchTeamsAlicePerson()` / `hammerspoon://launchteamsaliceperson`, plus a plain `launchTeams()` for the app itself.

### Teams use case

- [Microsoft Teams — one button per person](Docs/MsTeamsUseCase.md) — configuration, self-filling names and titles, hidden contact details, why group chats are not supported, and the security note

## Discord

One button per server, channel, person, or group DM: press it and Discord opens that destination, message box focused — start typing. No auto-discovery is possible, but each destination needs only one pasted ID (Developer Mode → *Copy ID*), **declared** in gitignored config files — one per server, plus a separate `discordDM` folder for DMs:

```json
{
  "server": "My Server",
  "id": "762900000000000000",
  "channels": [ { "name": "general", "id": "762900000000000001" } ]
}
```

Every entry becomes a generated method and Stream Deck URL, e.g. `launchDiscordExampleGeneralChannel()` / `hammerspoon://launchdiscordexamplegeneralchannel`, plus a plain `launchDiscord()` for the app itself. Server names, channel names, and titles self-fill from window titles on first press or via `discordScanTitles()`.

### Discord use case

- [Discord — one button per destination](Docs/DiscordUseCase.md) — configuration, finding IDs with Developer Mode, self-filling configs, dead-ID foolproofing, and the security note

## Windows App (Remote Desktop)

One button per remote PC: press it and Windows App connects to that PC — or jumps straight to its session window when the connection is already live. The PCs you saved in Windows App are **auto-discovered** from its own bookmark database, so buttons usually appear with no configuration at all (hostnames and friendly names only — credentials are never touched):

```json
{
  "pcs": [ { "name": "Office PC", "host": "10.0.0.5" } ]
}
```

The `name` key is always written out ready to edit — prefilled from the PC's friendly name, or from the address itself (`10.0.0.5` → `"10005"`) when it has none, so there is always a value to replace with an alias of your choosing.

Every PC becomes a generated method and Stream Deck URL, e.g. `launchWindowsAppOfficePcPc()` / `hammerspoon://launchwindowsappofficepcpc`, plus a plain `launchWindowsApp()` for the app itself.

### Windows App use case

- [Windows App — one button per remote PC](Docs/WindowsAppUseCase.md) — auto-discovery, what a press does, why tile pressing replaces the dead `rdp://` routes, and the security note

## Claude

One button per coding session: press it and the Claude desktop app opens with that session active (it opens the sidebar if it is collapsed, then clicks the session's row). Sessions are **auto-discovered** from Claude's own session store (titles, folders, and timestamps only — never transcripts), so there is nothing to configure — rename or archive sessions in Claude and the buttons follow:

```
hammerspoon://launchclaudecode<sessiontitle>
```

Every session becomes a generated method and Stream Deck URL, e.g. `launchClaudeCodeMyProject()` / `hammerspoon://launchclaudecodemyproject`, plus a plain `launchClaude()` / `hammerspoon://launchclaude` that just opens the app as-is. The same addresses plug into workspaces as [application state](Docs/WorkSpaceUseCaseWithApplicationState.md).

### Claude use case

- [Claude — one button per coding session](Docs/ClaudeUseCase.md) — launching Claude on its own vs with a session active, auto-discovery, what a press does, why clicking replaces the `claude://` deep link, the renaming caveat, and the security note

## Terminal

One button per terminal tool: press it and `htop` is in front of you, in its own window, already running. Press it again and the same window comes forward; quit the tool by accident and the next press restarts it there. Ten monitoring tools are configured for you on first run:

```
hammerspoon://launchterminalhtop
```

Each tool owns one window, identified by the custom title of its first tab — which also lets a workspace place it. That gives two levels of sync in a single press: the workspace syncs *where* the windows are, each `url` syncs *what is running inside them*. Needs the one-time Automation permission for Terminal.

**Shell scripts** work the other way round: drop a script into `config/terminal/shells/` and it becomes a button, but they all share **one** window on Desktop 1 — always brought to the front so you can read the output, and refusing to start while another script is still running. The shared window is the lock that stops overlapping runs.

### Terminal use case

- [Terminal — one dedicated window per tool](Docs/TerminalUseCase.md) — the Automation permission, configuration, what a press does, the two-level workspace sync, Spaces behaviour, known issues, and the security note

## Documentation

- [Basic use cases](Docs/BasicUseCases.md) — `help()`, `terminal()`, `focusOrLaunch()` with layouts, Chrome profiles, hotkeys, Stream Deck
- [Prerequisites: install Hammerspoon](Docs/PrerequisitesInstallHammerspoon.md) — Hammerspoon, Accessibility permission, `luac`, `hs.ipc`
- [Terminology](Docs/Terminology.md) — Display, Space, Workspace, Layout
- [API](Docs/API.md) — every method and the layouts table

## Installation

Install the [prerequisites](Docs/PrerequisitesInstallHammerspoon.md), then clone this repository and symlink the Spoon into Hammerspoon's Spoons directory:

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

## License

MIT — see [LICENSE](LICENSE).
