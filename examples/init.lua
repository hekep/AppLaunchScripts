-- Example ~/.hammerspoon/init.lua using AppLaunchScripts

-- Enable the `hs` CLI so external tools (Stream Deck, scripts) can call in
require("hs.ipc")

hs.loadSpoon("AppLaunchScripts")

spoon.AppLaunchScripts:start()

-- Whole workspace on one key (generated from workspaces/Communications.json)
hs.hotkey.bind({ "cmd", "alt" }, "1", function()
    spoon.AppLaunchScripts:launchCommunications()
end)

-- Built-in helper: Terminal on the left 66% of the screen
hs.hotkey.bind({ "cmd", "alt" }, "t", function()
    spoon.AppLaunchScripts:terminal()
end)

-- Generic focus-or-launch with a layout
hs.hotkey.bind({ "cmd", "alt" }, "b", function()
    spoon.AppLaunchScripts:focusOrLaunch("Safari", "right34")
end)

hs.hotkey.bind({ "cmd", "alt" }, "m", function()
    spoon.AppLaunchScripts:focusOrLaunch("Mail", "center")
end)

-- Focus-or-launch without touching the window position
hs.hotkey.bind({ "cmd", "alt" }, "s", function()
    spoon.AppLaunchScripts:focusOrLaunch("Slack")
end)

-- Google Chrome with a preselected profile (directory or display name;
-- list yours with spoon.AppLaunchScripts:chromeProfiles() or :help())
hs.hotkey.bind({ "cmd", "alt" }, "c", function()
    spoon.AppLaunchScripts:chrome("example_profile_name", "rightHalf")
end)

hs.hotkey.bind({ "cmd", "alt", "shift" }, "c", function()
    spoon.AppLaunchScripts:chrome("Profile 1", "leftHalf")
end)

-- Add a custom layout and use it
spoon.AppLaunchScripts.layouts.topHalf = {
    x = 0.00,
    y = 0.00,
    w = 1.00,
    h = 0.50,
}

hs.hotkey.bind({ "cmd", "alt" }, "n", function()
    spoon.AppLaunchScripts:focusOrLaunch("Notes", "topHalf")
end)
