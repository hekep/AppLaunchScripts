# Prerequisites: install Hammerspoon

Everything AppLaunchScripts needs before [installation](../README.md#installation).

## Hammerspoon

```bash
brew install --cask hammerspoon
```

## Accessibility permission

Required for switching Spaces (and general window control). Grant Hammerspoon access in *System Settings → Privacy & Security → Accessibility*, or trigger the prompt with:

```bash
hs -c 'hs.accessibilityState(true)'
```

**Restart Hammerspoon after granting** — macOS applies the permission only to freshly launched processes, so a running Hammerspoon keeps reporting `false` until relaunched:

```bash
hs -c 'hs.relaunch()'
```

Verify:

```bash
hs -c 'print(hs.accessibilityState())'
```


## Automation permission (Terminal tools only)

Needed only if you use the [Terminal integration](TerminalUseCase.md). The first press of a terminal button makes macOS ask:

> **"Hammerspoon.app" wants access to control "Terminal.app".**

Click **Allow**. It is *Hammerspoon* that needs the right, because the Spoon sends its Apple Events through it.

**Hammerspoon freezes while that dialog is unanswered** — the Apple Event blocks, so buttons and workspaces stop responding until you click. Answer it rather than leaving it on screen.

Denying it disables terminal buttons entirely: the accessibility API cannot read what a tab is running, nor set a window's title. Re-enable it under *System Settings → Privacy & Security → Automation → Hammerspoon → Terminal*.

## `luac`

Ships with Lua — used to syntax-check the Spoon:

```bash
brew install lua
```

## `hs.ipc` module

Enables the `hs` command-line tool. Add to your `~/.hammerspoon/init.lua`:

```lua
require("hs.ipc")
```

The Homebrew cask already links the `hs` binary to `/opt/homebrew/bin/hs`, so no further setup is needed. If you installed Hammerspoon another way, install the CLI once from the Hammerspoon console:

```lua
hs.ipc.cliInstall("/opt/homebrew")  -- Apple Silicon
hs.ipc.cliInstall()                 -- Intel (/usr/local)
```

Note: `cliInstall` returns `false` if the target `bin` directory isn't writable by your user — on Apple Silicon Macs, plain `cliInstall()` fails because `/usr/local/bin` is root-owned.
