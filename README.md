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

## Documentation

- [Prerequisites: install Hammerspoon](Docs/PrerequisitesInstallHammerspoon.md) — Hammerspoon, Accessibility permission, `luac`, `hs.ipc`
- [Terminology](Docs/Terminology.md) — Display, Space, Workspace, Layout
- [Basic use cases](Docs/BasicUseCases.md) — `help()`, `terminal()`, `focusOrLaunch()` with layouts, Chrome profiles, hotkeys, Stream Deck
- [The Communications workspace](Docs/LaunchCommunicationsUseCase.md) — `launchCommunications()`: three apps side by side on Desktop 1, with the example configuration
- [The GmailCommunications workspace](Docs/LaunchGmailCommunications.md) — `launchGmailCommunications()`: Gmail in two Chrome profiles on Desktop 2, kept out of git as a private workspace
- [Workspace configuration reference](Docs/WorkspaceConfigurationReference.md) — all JSON keys and workspace behavior
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
