# Use case: the Communications workspace

One button brings up your communication tools — Thunderbird, Slack, and Discord side by side on Desktop 1 — no matter what state the Mac is in: apps not started, windows minimized, hidden, or scattered.

```bash
hs -c 'spoon.AppLaunchScripts:launchCommunications()'
```

or generically:

```bash
hs -c 'spoon.AppLaunchScripts:launchWorkspace("Communications")'
```

## Configuration

`AppLaunchScripts.spoon/workspaces/Communications.json`

```json
{
  "name": "Communications",
  "space": {
    "display": "current",
    "index": 1
  },
  "layout": {
    "direction": "horizontal",
    "widths": [33, 33, 34]
  },
  "apps": [
    {
      "name": "Thunderbird"
    },
    {
      "name": "Slack"
    },
    {
      "name": "Discord"
    }
  ]
}
```

Because the file exists, the Spoon generates the `launchCommunications()` method automatically on load (the method name comes from the `name` field).

## What happens on launch

1. The target display is resolved (`"current"` = the display with the focused window).
2. Space 1 ("Desktop 1") on that display is resolved — missing Spaces would be created automatically.
3. The Space is switched to first, so new windows open directly on it.
4. Each app is launched or focused; cold starts are waited for (Discord's updater can take 15+ seconds — the Spoon waits).
5. Each window is placed into its slot: Thunderbird 0–33%, Slack 33–66%, Discord 66–100%.

## Triggering

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchCommunications
```

From any shell-command launcher (full path recommended):

```bash
/opt/homebrew/bin/hs -c 'spoon.AppLaunchScripts:launchCommunications()'
```

Hotkey in `~/.hammerspoon/init.lua`:

```lua
hs.hotkey.bind({ "cmd", "alt" }, "1", function()
    spoon.AppLaunchScripts:launchCommunications()
end)
```

Pressing the button again is idempotent: it switches to the Space, re-focuses the windows, and re-asserts the 33/33/34 layout.
