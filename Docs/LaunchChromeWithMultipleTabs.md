# Use case: Chrome windows with multiple tabs

One button opens a reading station: two Chrome windows side by side, each holding a whole set of tabs — for example a news window with your industry sources and a social window with the people you follow. Pressing the button again **restores the state**: closed tabs are reopened, the first tab is re-activated, and nothing is ever duplicated.

```bash
hs -c 'spoon.AppLaunchScripts:launchHealthTechNews()'
```

Stream Deck — *Website* action, **Open with: Hammerspoon** (see [button setup](BasicUseCases.md#setting-up-a-button-on-an-elgato-stream-deck)):

```
hammerspoon://launchHealthTechNews
```

## Configuration

`apps[].www` accepts an **array of URLs** — one Chrome window with one tab per URL. See the full example in [workspaces/HealthTechNews.json](../AppLaunchScripts.spoon/workspaces/HealthTechNews.json); the shape:

```json
{
  "name": "HealthTechNews",
  "space": { "display": "current", "desktop": 8 },
  "layout": { "direction": "horizontal", "widths": [50, 50] },
  "apps": [
    {
      "name": "Chrome",
      "profile": "example_profile_name",
      "www": [
        "https://www.massdevice.com/",
        "https://www.medtechdive.com/",
        "https://www.medgadget.com/"
      ]
    },
    {
      "name": "Chrome",
      "profile": "example_profile_name",
      "www": [
        "https://x.com/EricTopol",
        "https://x.com/statnews"
      ]
    }
  ]
}
```

Both entries may use the **same profile**: each window is identified by the sites it holds, not by the profile — no `window` key is needed for Chrome entries. (Chrome window titles change with the active tab, so a title fragment could never identify them; tab content is the reliable identity, and that is what the Spoon matches on.) URLs on one host are told apart by their path — `x.com/EricTopol` and `x.com/statnews` are different tabs.

## State restore

On every press, per configured URL:

1. A tab matching the URL (scheme and `www.` ignored, path included) already exists → it is kept.
2. The tab is missing — you closed it → a new tab is opened on the URL.
3. Finally the **first** URL's tab is activated, and the window is re-placed into its layout slot.

The target window is chosen by tab content: the window holding the most of the entry's sites receives the missing tabs. A window holding none of them is never used for a multi-URL entry — that guarantees one entry's tabs cannot leak into another entry's window.

## Rules for reliable URLs

- **Use post-redirect URLs.** If a configured site redirects (e.g. `www.med-technews.com` → `med-techinsights.com`), its tab never matches the configured URL and gets reopened on every press. Check with:

  ```bash
  curl -sIL -o /dev/null -w '%{url_effective}\n' https://www.example.com/
  ```

- **Keep URL sets of same-profile windows disjoint** — the sites are what identifies each window.

## Duplicate protection

- Tabs: a URL with a matching tab is never opened again.
- Windows: adopted per desktop and per site set; presses within 10 seconds are ignored while the launch settles.
- Desktops: if the windows already live on another desktop that macOS won't move them from, the workspace falls back to that desktop with an alert (see the [configuration reference](WorkspaceConfigurationReference.md)).
