# Use case: Windows App — one button per remote PC

Press an Elgato Stream Deck button and Windows App (Microsoft Remote Desktop) connects to a specific PC — or, when that connection is already live, jumps straight to its session window.

```bash
hs -c 'spoon.AppLaunchScripts:launchWindowsAppOfficePcPc()'
```

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchwindowsappofficepcpc
```

There is also a plain `launchWindowsApp()` / `hammerspoon://launchwindowsapp` that launches or focuses the app as-is.

## How it works

This is the first integration with **real auto-discovery**: the PCs you saved in Windows App are read straight from its own bookmark database and merged into `AppLaunchScripts.spoon/config/windowsapp/Pcs.json` (gitignored). Buttons appear by themselves — usually there is nothing to configure at all.

```json
{
  "pcs": [
    { "name": "Office PC", "host": "10.0.0.5" },
    { "name": "10009",     "host": "10.0.0.9" }
  ]
}
```

- **`name`** — your button alias, and it is **always written out, ready to edit**. Discovery prefills it from the PC's friendly name in Windows App; when there is none, the address itself becomes the default name (`10.0.0.9` → `"10009"`), so there is always a concrete value in front of you to replace. It is free-form: type `"Työkone Kellarissa"` and the button becomes `launchWindowsAppTyokoneKellarissaPc()` (CamelCased, accents transliterated).
- **`host`** — the address, used to find the PC's tile and its session window.
- **`title`** (optional) — window-title fragment identifying the session window, when it differs from the name.

Editing is a one-way street in your favour: type a name, run `help()` (or reload), and the button is renamed. Discovery **never overwrites a name you wrote** — it appends PCs it has not seen, and only replaces a name that is still the address-derived default (so setting a friendly name in Windows App later still reaches your config). Only hostnames and friendly names are read — **credentials are never touched** (they live in the Keychain and stay Windows App's business).

> Renaming a PC renames its method, so re-copy the `hammerspoon://` address into any Stream Deck button you already assigned. Press the old button and you get a "no longer exists — reassign" alert rather than an error.

> Your alias does not have to match anything in Windows App: the launcher finds the PC's tile by name **or** address, so a freely renamed PC still connects.

Reading the database needs the one-time macOS *"Hammerspoon would like to access data from other apps"* prompt. Decline it and discovery simply stays empty — declared entries keep working.

## What a press does

1. Launches or focuses Windows App (waiting for its hub window on a cold start).
2. **Already connected?** Focuses that PC's session window — no reconnect, no duplicate session.
3. Otherwise, presses the PC's tile in the hub window's *Saved Devices* list, exactly as a click would.
4. Brings Windows App forward and focuses the session window when it appears. If Windows App asks for credentials or shows a certificate warning, that prompt has keyboard focus — the automation deliberately stops there and hands over to you.

> **Only saved PCs can be launched.** A configured host that is not among Windows App's saved PCs is reported with an alert — add it once in Windows App (*Connections → Add PC*), and its button works from then on.

### Why tile pressing, not a URL

Every scriptable route is dead on current macOS:

| Route | Result |
| --- | --- |
| `rdp://full%20address=s:<host>` (Microsoft's documented URI) | rejected by macOS before it reaches the app |
| `rdp://<host>` | Windows App answers *"The URL is not valid"* |
| generated `.rdp` file opened with the app | lands in *Open Recent*, never connects |
| **pressing the PC's tile (Accessibility)** | **connects** |

So the launcher does what you would do: it presses the tile. This needs Hammerspoon's Accessibility permission, which the workspace engine already requires.

## Multi-window, unlike the chat apps

Windows App keeps a hub window plus **one window per live connection**, titled with the PC — so sessions are individually focusable, and several remote PCs can be open at once. Session windows can be placed by your [workspaces](LaunchCommunicationsUseCase.md) like any other window.

> A session window living on another macOS Space is invisible to the accessibility API (a macOS limitation). The button then presses the tile again; Windows App focuses the existing session rather than duplicating it.

## The naming convention

Same rules as [Slack](SlackUseCase.md#the-naming-convention): `name` is your free-form alias (CamelCased, accents transliterated), and method-name uniqueness is foolproofed with incremental suffixes plus a catalog NOTE naming the first taker. The generated `availableWindowsAppComms.lua` is the copy-paste catalog: description, shell command, and `hammerspoon://` address per PC. `help()` refreshes discovery before printing.

## Security note

`config/windowsapp/Pcs.json` stores PC names and **hostnames or IP addresses in plain text** — a map of machines you can reach. The folder is gitignored so it never reaches the repository, but the file is readable by any application (or automation) that can read your files. Be conscious about what you keep there. No credentials are ever written to it.
