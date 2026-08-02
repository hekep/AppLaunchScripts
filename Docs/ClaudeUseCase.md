# Use case: Claude — one button per coding session

Press an Elgato Stream Deck button and the Claude desktop app comes up **with that coding session active** — not the app's front page, not whichever session you happened to leave open.

```bash
hs -c 'spoon.AppLaunchScripts:launchClaudeCodeMyProject()'
```

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchclaudecodemyproject
```

## Launching Claude on its own

Two things are separate, and you will want both:

| What you want | Method | Stream Deck address |
| --- | --- | --- |
| **Just the app**, exactly as you left it | `launchClaude()` | `hammerspoon://launchclaude` |
| The app **with a session active** | `launchClaudeCode<Session>()` | `hammerspoon://launchclaudecode<session>` |

`launchClaude()` is the plain one: it launches Claude, or focuses it if it is already running, and touches nothing else — no sidebar, no clicking, no session switching. Use it for a "bring me Claude" button when you do not care which session is open.

```bash
hs -c 'spoon.AppLaunchScripts:launchClaude()'
```

```
hammerspoon://launchclaude
```

Neither form needs a workspace. A workspace is only for arranging *several* apps together; a single button that opens Claude — with or without a session — is just the address above. The same addresses can *also* be planted into a workspace as [application state](WorkSpaceUseCaseWithApplicationState.md), which is a separate use case.

To see the current list of addresses on your machine:

```bash
hs -c 'spoon.AppLaunchScripts:help()'
```

## How it works

There is **no configuration file**. Coding sessions are read straight from Claude's own session store (`~/Library/Application Support/Claude/claude-code-sessions/`) — titles, working directories, and timestamps only. Transcripts are never opened.

Because your session titles are already human-given (you named them in Claude), there is no alias config to maintain: the catalog `availableClaudeComms.lua` regenerates on every Hammerspoon reload and every `help()` call. Create a session and its button exists; archive it and the button disappears.

Sessions are listed most-recently-used first, and archived ones are skipped.

## What a press does

1. Launches Claude, or focuses it if it is already running, and waits for its window.
2. **Opens the sidebar** if it is collapsed — the rows are what get clicked, and a collapsed sidebar's rows keep their old coordinates, so a click would land in the conversation area instead.
3. Finds the session's row, scrolls it into view, and **clicks it**.
4. Waits for Claude to record the switch, and alerts if it never does.
5. Puts your mouse pointer back where it was.

The sidebar is left as it ends up — opened if it had to be opened. Nothing closes it for you.

Cold start is handled: the press returns immediately and all waiting happens on timers, so a workspace press is never held up. If the sidebar has not rendered yet the launcher waits for the row to appear rather than clicking into empty space, and if Claude was still quitting when you pressed, the launch is re-issued until a window appears.

### Why clicking, not a URL

Claude ships a `claude://resume?session=…` deep link, and it is deliberately **not** used:

- It is an **import** mechanism, not a focus one — it re-imports the entire transcript on every press (megabytes), and the app itself warns that large ones may fail.
- It accepts only the *CLI* session id and resolves it to the desktop session keyed `local_<cliSessionId>`. Most sessions carry a **different** desktop id, and for those the link **forks a fresh untitled session** holding a stale copy of the transcript instead of opening the original.
- Passing the desktop id instead is rejected outright.
- The `…/epitaxy/<desktop id>` form that the app's own *Copy URL* produces is not recognised as a deep link at all.

Clicking the row has none of these problems: it reaches every session, imports nothing, and forks nothing. Accessibility is used only to *locate* the row — `AXPress` on it does nothing in Claude's web UI, so an actual mouse click is posted at the row's centre and the pointer is restored afterwards.

If a future Claude release makes the deep link focus an existing session, it should become the primary route and this clicking should become the fallback — a documented URL beats reverse-engineered UI internals.

### Verifying that it worked

A genuine switch bumps the session's `lastFocusedAt` in Claude's store, so the launcher watches that field and only reports success when it moves. If nothing is recorded it clicks once more, and only then alerts. Pressing a button for the session that is *already* active is recognised and reported as such, not as a failure.

Two situations produce an alert instead of silence: a row that cannot be found (renamed or archived session), and a click that never takes.

## Renaming a session

A generated launcher carries two things: the session title as the catalog knew it, and the **path to the session's JSON file**. The path is the session's stable identity — renaming a session in Claude changes the title inside that file, not the file itself — so the launcher reads the **current** title from the file at press time and clicks the row by that:

```lua
function obj:launchClaudeCodeMyProject()
    return self:launchClaudeComm("My Project", "…/local_0412e7cb-….json")
end
```

Rename *My Project* to *My Rewritten Project* and this button keeps working. The catalog title is only a fallback for when the file cannot be read, and the log says what happened:

```
session renamed: catalog says "My Project", Claude now says "My Rewritten Project"
— using the live title (run help() to regenerate the catalog, then update the
workspace url and Stream Deck button)
```

**The reprieve is temporary.** The method name and the `hammerspoon://` address are still derived from the title:

> `My Project` → `launchClaudeCodeMyProject()` → `hammerspoon://launchclaudecodemyproject`

The next `help()` or Hammerspoon reload regenerates the catalog under the **new** name, and at that moment two things break until you fix them by hand:

- a `url` in a workspace JSON — the press warns `matches no launcher`;
- a Stream Deck button — pressing it alerts `no longer exists — reassign`.

So a rename gives you a working button until the next reload, then needs manual updating. Neither failure is silent. This is a known shortcoming, accepted for now.

## Two sessions with the same name

**AppLaunchScripts cannot tell identically named sessions apart.** If two of your Claude sessions carry the same title, the sidebar shows two rows with the same label and there is nothing in the accessibility tree to choose between them — the launcher clicks whichever one it finds, which may not be the one you meant.

The catalog does *not* hide this: the second session gets a suffixed method (`launchClaudeCodeMyProject1()`) with a NOTE naming the first taker, so you can see the collision in `availableClaudeComms.lua`. But both methods click by title, so both may land on the same row.

Near-misses are handled — a title that merely *sits inside* another (`Docker setup review` inside `Primanda 2 Docker setup review`) resolves to the closest match, and the alternatives are logged. Exact duplicates are not resolvable. **Give your sessions distinct names in Claude** if you intend to put them on buttons.

## The naming convention

Same rules as [Slack](SlackUseCase.md#the-naming-convention): titles are CamelCased and accents transliterated (`Väinö` → `Vaino`), and method-name uniqueness is foolproofed with incremental suffixes plus a catalog NOTE naming the first taker. The generated `availableClaudeComms.lua` is the copy-paste catalog: description, shell command, and `hammerspoon://` address per session.

Two sessions with very similar names are handled too: because a title can sit inside a longer one (`Docker setup review` inside `Primanda 2 Docker setup review`), every matching row is collected and the closest match wins.

## Troubleshooting

Turn on run logging to see exactly where the time goes and what the sidebar contained:

```json
{ "workSpaceRunLogs": true }
```

in `AppLaunchScripts.spoon/config/config.json`. Logs land in `AppLaunchScripts.spoon/logs/` with millisecond timestamps, and Claude's own phases (window ready, row found, click, confirmation) appear in the same file as the workspace press that triggered them. The Hammerspoon console shows the same lines when no workspace is involved.

## Security note

`availableClaudeComms.lua` contains your **session titles and their working directory paths in plain text** — a map of what you are working on and where. The file is gitignored so it never reaches the repository, but it is readable by any application (or automation) that can read your files. Session *contents* are never read: the scan opens only the small session-metadata JSON files, never transcripts.
