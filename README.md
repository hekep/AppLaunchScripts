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
