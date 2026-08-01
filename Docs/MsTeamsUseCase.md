# Use case: Microsoft Teams — one button per person

Press an Elgato Stream Deck button and Microsoft Teams opens the chat with a specific person — window focused, message box ready: just start typing.

```bash
hs -c 'spoon.AppLaunchScripts:launchTeamsAlicePerson()'
```

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchteamsaliceperson
```

There is also a plain `launchTeams()` / `hammerspoon://launchteams` that launches or focuses the app as-is, whatever state it is in.

## How it works

Teams keeps its chats and contacts in a local database that cannot be read from outside, so unlike Slack there is nothing to discover automatically — and nothing that needs to be. The people you want buttons for are **declared** in one config file, `AppLaunchScripts.spoon/config/teams/Teams.json` (created empty on load; the whole folder is gitignored). A person is just an email address:

```json
{
  "people": [
    { "name": "Alice", "email": "alice@example.com", "title": "Alice Smith" }
  ]
}
```

For every person a method (and matching `hammerspoon://` URL) is generated into `availableTeamsComms.lua`:

| Entry | Generated method |
| --- | --- |
| the app itself | `launchTeams()` |
| person `Alice` | `launchTeamsAlicePerson()` |

Run `hs -c 'spoon.AppLaunchScripts:help()'` to see them all as copy-pasteable commands.

> **No macOS permissions needed.** Everything works through `msteams:` deep links and window titles — end users are never asked to grant Teams data access, Accessibility beyond Hammerspoon's own, or anything else.

## Assigning Stream Deck buttons — the copy-paste catalog

The generated file `AppLaunchScripts.spoon/availableTeamsComms.lua` doubles as a **copy-paste catalog**: every function carries a comment block naming who it opens, its shell command, and its `hammerspoon://` address:

```lua
-- Teams — person "Alice" (Alice Smith)
-- shell:  hs -c 'spoon.AppLaunchScripts:launchTeamsAlicePerson()'
-- button: hammerspoon://launchteamsaliceperson
```

To assign a button: open that file, find the person, copy the `button:` address into a Stream Deck *Website* action (**Open with: Hammerspoon**). The file regenerates on every Hammerspoon reload and after `teamsScanTitles()`, so it always reflects your current config.

## The naming convention

Same rules as [Slack](SlackUseCase.md#the-naming-convention):

- **`name`** is *your button alias* — free-form, CamelCased into the method name (accents transliterated).
- **`title`** (optional) is *the scanned truth* — a fragment the Teams window title must contain after navigation (`Chat | Alice Smith | Microsoft Teams`), used purely for verification. On a mismatch you get an alert naming what the window actually shows.
- **Names must be unique — and the generator foolproofs it.** Uniqueness is checked after CamelCasing; colliding entries get an incremental suffix (`Make` → `Make1` …) and a catalog NOTE naming which entry took the name first.

## Minimal copy-paste: let the config fill itself

A bare `{ "email": "alice@example.com" }` entry is enough. Then run:

```bash
hs -c 'spoon.AppLaunchScripts:teamsScanTitles()'
```

The scan navigates Teams to every person missing a `title` (or a `name`), reads the window title, and writes the fragment back. Existing values are never overwritten, and an email that fails to navigate is reported instead of guessed.

Buttons also **learn on their own**: pressing a launcher whose entry has no `title` harvests it from the chat it just opened. A bare-email entry gets a **provisional launcher named after the email** (marked *unnamed* in the catalog); press it once and it learns both `name` and `title`, and the catalog regenerates under the person's real display name.

> Scans and self-learning rewrite `config/teams/*.json` — avoid hand-editing the file while either is in flight.

## What a press does

1. Focuses Teams, launching it if needed (cold starts are waited for).
2. Navigates via an `msteams:` deep link to the chat with that email address.
3. Verifies the window title against `title` and alerts if the wrong thing opened.
4. Focuses the window — the message box is active, ready for typing.

> **Single-window app:** Teams has exactly one main window, which these buttons navigate *in place*. Its position and size belong to your [workspaces](LaunchCommunicationsUseCase.md); Teams buttons never move it.

## People whose contact details are hidden

Teams sometimes shows *"…'s contact details are hidden in Teams"* — the person's organization or privacy settings hide their profile from you. The deep links here don't care: they work by **email address**, not by profile visibility. Simply **ask the person which email address they use in Teams** and add it to the `people` list — that is all you need; the other person does not have to change any settings.

## Group chats / chat rooms — deliberately not supported

Multi-person chats have no user-friendly way in: Teams offers no "copy chat address" for a room, and the only workaround is fishing internal thread IDs out of message *Copy link* URLs — hacky, fragile, and not something we ask end users to do. Group chat buttons are therefore **not part of this integration**. If Microsoft ships proper chat deep links in the future, this is worth revisiting.

## Security note

`config/teams/Teams.json` stores names and **email addresses in plain text**. The folder is gitignored so it never reaches the repository, but the file itself is readable by any application (or automation) that can read your files. Be conscious about whose contact information you keep there.
