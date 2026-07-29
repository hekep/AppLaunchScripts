# Use case: the GmailCommunications workspace (private, Chrome profiles)

One button opens Gmail twice on Desktop 2 — once per Chrome profile, split 50/50 (e.g. personal on the left, work on the right).

```bash
hs -c 'spoon.AppLaunchScripts:launchGmailCommunications()'
```

or generically, by file name:

```bash
hs -c 'spoon.AppLaunchScripts:launchWorkspace("privateCommunications")'
```

## Configuration

`AppLaunchScripts.spoon/workspaces/privateCommunications.json`

```json
{
  "name": "GmailCommunications",
  "space": {
    "display": "current",
    "index": 2
  },
  "layout": {
    "direction": "horizontal",
    "widths": [50, 50]
  },
  "apps": [
    {
      "name": "Chrome",
      "profile": "example_profile_one",
      "www": "https://www.gmail.com"
    },
    {
      "name": "Chrome",
      "profile": "example_profile_two",
      "www": "https://www.gmail.com"
    }
  ]
}
```

Replace `example_profile_one` / `example_profile_two` with your own Chrome profile names or directories — list them with `hs -c 'spoon.AppLaunchScripts:help()'`.

## Private workspaces

Workspace files whose names start with `personal` or `private` are excluded from git (see [.gitignore](../.gitignore)) — keep configs containing personal profile names, URLs, or app lists there.

Note the split identity: the **file name** (`privateCommunications`) marks it private and is the `launchWorkspace()` argument; the **`name` field** (`GmailCommunications`) provides the generated method name, `launchGmailCommunications()`.

## What happens on launch

1. Space 2 ("Desktop 2") on the current display is resolved — **created automatically** if the display doesn't have a second Space yet.
2. The Space is switched to first (requires the Accessibility permission — see the README prerequisites, including the restart-after-granting note).
3. For each app entry with a `profile` key: if a window of that Chrome profile already exists on the target Space it is re-used; otherwise a new window is opened with that profile and the `www` URL, landing directly on the target Space.
4. Windows are laid out 50/50.

> **macOS caveat:** on recent macOS versions, moving an *existing* window to another Space programmatically is unreliable (`hs.spaces.moveWindowToSpace` can report success without doing anything). That is why the Spoon switches Space before opening windows, and prefers a fresh window on the target Space over adopting one from another Space when the move fails.

## Triggering

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchGmailCommunications
```

From any shell-command launcher (full path recommended):

```bash
/opt/homebrew/bin/hs -c 'spoon.AppLaunchScripts:launchGmailCommunications()'
```

Pressing the button again is idempotent: it switches to Desktop 2, re-focuses the two profile windows, and re-asserts the 50/50 layout.
