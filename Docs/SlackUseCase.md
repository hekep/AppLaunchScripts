# Use case: Slack — one button per channel, person, or group

Press an Elgato Stream Deck button and Slack opens with a specific conversation active — channel, person, or group chat — window focused, message box ready: just start typing.

```bash
hs -c 'spoon.AppLaunchScripts:launchSlackExampleGeneralChannel()'
```

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchslackexamplegeneralchannel
```

## How it works

Slack **workspaces (domains) are discovered automatically** from Slack's local state — nothing to configure and nothing personal in the repo. On load, an **empty config file is generated for every signed-in domain** (`AppLaunchScripts.spoon/config/slack/<Alias>.json`; the whole folder is gitignored), so every domain is launchable immediately — `launchSlack<Alias>()` — with zero setup. The conversations you want buttons for are **declared** by filling those files (existing files are never touched by the generator).

```json
{
  "domain": "example-team",
  "alias": "Example",
  "channels": [
    { "name": "general", "id": "C0123ABCD" }
  ],
  "people": [
    { "name": "Alice", "id": "D0456EFGH", "title": "Alice Smith" }
  ],
  "groups": [
    { "name": "Alice and Bob", "id": "C0789IJKL", "title": "Alice Smith, Bob Jones" }
  ]
}
```

For every entry a method (and matching `hammerspoon://` URL) is generated:

| Entry | Generated method |
| --- | --- |
| the domain itself | `launchSlackExample()` |
| channel `general` | `launchSlackExampleGeneralChannel()` |
| person `Alice` | `launchSlackExampleAlicePerson()` |
| group `Alice and Bob` | `launchSlackExampleAliceAndBobGroup()` |

Run `hs -c 'spoon.AppLaunchScripts:help()'` to see them all as copy-pasteable commands.

## Assigning Stream Deck buttons — the copy-paste catalog

The generated file `AppLaunchScripts.spoon/availableSlackComms.lua` doubles as a **copy-paste catalog**: every function carries a comment block naming what it opens, its shell command, and its `hammerspoon://` address:

```lua
-- Example — person "Alice" (Alice Smith)
-- shell:  hs -c 'spoon.AppLaunchScripts:launchSlackExampleAlicePerson()'
-- button: hammerspoon://launchslackexamplealiceperson
```

To assign a button: open that file, find the conversation, copy the `button:` address into a Stream Deck *Website* action (**Open with: Hammerspoon** — see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)). The file regenerates on every Hammerspoon reload and after `slackScanTitles()`, so it always reflects your current configs.

## The naming convention

- **`name`** is *your button alias* — free-form; it is CamelCased into the method name, so `"project_chat"` and `"ProjectChat"` generate the same method. Keep the natural spelling for readability.
- **`title`** (optional) is *the scanned truth* — a fragment the Slack window title must contain after navigation, used purely for verification. Channels verify against their own `name` by default (Slack shows channel names verbatim in the title); add `title` for people and groups, whose full display names differ from your short alias. On a mismatch you get an alert naming what the window actually shows.
- **`alias`** (optional, per domain) overrides the method-name prefix; the file name proposes it (`My.Team.json` → `MyTeam`).
- **Names must be unique — and the generator foolproofs it.** Uniqueness is checked *after* CamelCasing, so entries that only differ by stray spaces, tabs, or accents (`"Make"`, `"Make "`, `"Mäke"` all become `Make`) still collide. Colliding entries keep working: the second one gets an incremental suffix in the name part (`Make` → `Make1` → `Make2` …), and the generated catalog carries a NOTE on the renamed entry saying which entry took the name first — check your config for duplicates or stray whitespace when you see one.

## Finding the IDs

Right-click any conversation in Slack's sidebar → *Copy* → *Copy link*. The ID is the tail of the URL: `https://<domain>.slack.com/archives/<ID>` — channels give `C…`, person DMs give `D…`, group chats give `C…` or `G…`. All of them work. (Persons alternatively: profile → *Copy member ID* → a `U…` id, also supported.)

### Minimal copy-paste: let the scan fill the rest

You only ever need to paste the ID — even a bare `{ "id": "C0123ABCD" }` entry is enough. Then run:

```bash
hs -c 'spoon.AppLaunchScripts:slackScanTitles()'
```

The scan navigates Slack to every entry that is missing a `title` (or a `name`), reads the window title, and writes the fragment back into the config file. Existing values are never overwritten, `name` is never rewritten or normalized, and an ID that fails to navigate is reported instead of guessed. When anything was filled, the launcher methods regenerate automatically. (Slack visibly flips through the scanned conversations — that is the scan working.)

Buttons also **learn on their own**: pressing a launcher whose entry has no `title` harvests the title from the conversation it just opened, stores it, and regenerates the methods — so even without running the scan, the config enriches itself through normal use. A bare `{ "id": "…" }` entry gets a **provisional launcher named after the ID** (marked *unnamed* in the catalog); press it once and it learns both `name` and `title`, and the catalog regenerates under the proper name.

## What a press does

1. Focuses Slack, launching it if needed (cold starts are waited for).
2. Navigates via a `slack://` deep link to the exact conversation.
3. Verifies the window title against `title`/`name` and alerts if the wrong thing opened (a deep link with a wrong team or ID is silently ignored by Slack — verification catches it).
4. Focuses the window — the message box is active, ready for typing.

> **Single-window app:** Slack has exactly one main window, which these buttons navigate *in place*. Its position and size belong to your [workspaces](LaunchCommunicationsUseCase.md); Slack buttons never move it, and Slack cannot spread across multiple macOS Spaces.

## Security note

`config/slack/*.json` stores workspace, channel, and **people names in plain text**. The folder is gitignored so it never reaches the repository, but the files themselves are readable by any application (or automation) that can read your files. Be conscious about whose contact information you keep there.
