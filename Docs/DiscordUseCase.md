# Use case: Discord — one button per server, channel, person, or group DM

Press an Elgato Stream Deck button and Discord opens a specific destination — a server, a channel, a person's DM, or a group DM — window focused, message box ready: just start typing.

```bash
hs -c 'spoon.AppLaunchScripts:launchDiscordExampleGeneralChannel()'
```

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchdiscordexamplegeneralchannel
```

There is also a plain `launchDiscord()` / `hammerspoon://launchdiscord` that launches or focuses the app as-is, whatever state it is in.

## How it works

Discord keeps its server list, channels, and DMs in a local database that cannot be read from outside, so unlike Slack there is no auto-discovery — but each destination needs only **one pasted ID**; everything else fills itself. Destinations are **declared** in gitignored config files:

**One file per server** — `AppLaunchScripts.spoon/config/discord/<Server>.json`:

```json
{
  "server": "My Server",
  "id": "762900000000000000",
  "channels": [
    { "name": "general", "id": "762900000000000001" }
  ]
}
```

**DMs and group DMs** — `AppLaunchScripts.spoon/config/discordDM/DMs.json` (created empty on load; a separate folder, so a server file named `DMs.json` can never collide with it):

```json
{
  "dms":    [ { "name": "Alice", "id": "1480000000000000000" } ],
  "groups": [ { "name": "Weekend crew", "id": "1480000000000000001" } ]
}
```

Group DMs work exactly like DMs — they are channels in the same `@me` space, just listed under `groups` so their buttons get the `Group` suffix.

For every entry a method (and matching `hammerspoon://` URL) is generated into `availableDiscordComms.lua`:

| Entry | Generated method |
| --- | --- |
| the app itself | `launchDiscord()` |
| the server itself | `launchDiscordExample()` (opens its default channel) |
| channel `general` | `launchDiscordExampleGeneralChannel()` |
| DM `Alice` | `launchDiscordAlicePerson()` |
| group `Weekend crew` | `launchDiscordWeekendCrewGroup()` |

Run `hs -c 'spoon.AppLaunchScripts:help()'` to see them all as copy-pasteable commands.

> **No macOS permissions needed.** Everything works through `discord://` deep links and window titles.

## Finding the IDs

Two ways:

1. **Desktop app:** Settings → Advanced → **Developer Mode** ON. Then right-click a server, channel, or DM → *Copy ID* (server and channel IDs; a DM's ID is its channel ID).
2. **Web app:** open [discord.com/app](https://discord.com/app), click the destination, and read the address bar: `https://discord.com/channels/<serverId>/<channelId>` — DMs and group DMs show as `/channels/@me/<channelId>`.

## Minimal copy-paste: let the config fill itself

A server file with just `{ "id": "…" }` is already launchable — the button opens the server at its default channel, and the first press learns the **server name** from the window title. Bare `{ "id": "…" }` channel and DM entries get **provisional launchers** named after the ID; one press learns `name` and `title`, and the catalog regenerates under the real name. Or batch-fill everything at once:

```bash
hs -c 'spoon.AppLaunchScripts:discordScanTitles()'
```

The scan navigates Discord to every incomplete entry, harvests the window title, and writes the values back, bouncing through the Friends view between entries so every navigation is detectable. Existing values are never overwritten.

**`help()` scans too:** `hs -c 'spoon.AppLaunchScripts:help()'` completes all pending Discord name scans *before* printing, so the listed commands always carry real names instead of provisional IDs. This blocks for a few seconds per unfilled entry (instant when there is nothing to fill) — if the shell reply ever gets cut off by the long pause, just run `help()` again: the second run is instant and fully resolved.

> **Method names stay stable.** The server's method-name prefix comes from the explicit `"alias"` or the **file name** — never from the learned server name — so buttons you assigned before learning keep working.

> Scans and self-learning rewrite the config files — avoid hand-editing them while either is in flight.

### Dead IDs cannot poison the config

A wrong ID does not fail silently: Discord navigates to the *Friends* view instead. Its title is localized (e.g. `Kaverit - Discord` on a Finnish UI), which is exactly why learning only accepts titles matching the verified shapes — `#channel | Server - Discord` for channels, `@user - Discord` for DMs. A dead ID is reported, never learned. Learned **group** names are the one loose case (group titles carry no marker) — eyeball them once after learning.

## The naming convention

Same rules as [Slack](SlackUseCase.md#the-naming-convention): `name` is your free-form button alias (CamelCased, accents transliterated), `title` is the scanned truth used for window-title verification, and method-name uniqueness is foolproofed with incremental suffixes plus a catalog NOTE naming the first taker. Channels default to verifying against `#<name>`.

## What a press does

1. Focuses Discord, launching it if needed (Discord cold-starts through its updater — 15–20 s — and the wait budget covers it).
2. Navigates via a `discord://-/channels/…` deep link.
3. Verifies the window title against `title` and alerts if the wrong thing opened.
4. Focuses the window — the message box is active, ready for typing.

> **Single-window app:** Discord has exactly one main window, which these buttons navigate *in place*. Its position and size belong to your [workspaces](LaunchCommunicationsUseCase.md); Discord buttons never move it.

## Security note

The Discord config files store server, channel, and **people names with their IDs in plain text**. The folders are gitignored so they never reach the repository, but the files themselves are readable by any application (or automation) that can read your files. Be conscious about whose contact information you keep there.
