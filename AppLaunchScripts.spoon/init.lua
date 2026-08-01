--- === AppLaunchScripts ===
---
--- Focus-or-launch applications and snap their windows to predefined layouts.
---
--- Download: [https://github.com/hekep/AppLaunchScripts](https://github.com/hekep/AppLaunchScripts)

local obj = {}

obj.name = "AppLaunchScripts"
obj.version = "0.9.0"
obj.author = "Heikki Pals"
obj.homepage = "https://github.com/hekep/AppLaunchScripts"
obj.license = "MIT"

--- AppLaunchScripts.layouts
--- Variable
--- Table of named unit-rect layouts (x, y, w, h as fractions of the screen).
--- Built-in layouts: `full`, `leftHalf`, `rightHalf`, `left66`, `right34`, `center`.
--- Add your own entries to use them with `focusOrLaunch()`.
obj.layouts = {
    full = {
        x = 0.00,
        y = 0.00,
        w = 1.00,
        h = 1.00,
    },

    leftHalf = {
        x = 0.00,
        y = 0.00,
        w = 0.50,
        h = 1.00,
    },

    rightHalf = {
        x = 0.50,
        y = 0.00,
        w = 0.50,
        h = 1.00,
    },

    left66 = {
        x = 0.00,
        y = 0.00,
        w = 0.66,
        h = 1.00,
    },

    right34 = {
        x = 0.66,
        y = 0.00,
        w = 0.34,
        h = 1.00,
    },

    center = {
        x = 0.10,
        y = 0.08,
        w = 0.80,
        h = 0.84,
    },
}

-- Resolve a layout name. Explicit entries in obj.layouts win; otherwise
-- names like "left70", "right86", "top40", "bottom25" are parsed as
-- side + percentage. Unknown names alert instead of failing silently.
local function resolveLayout(layouts, layoutName)
    if not layoutName then
        return nil
    end

    if layouts[layoutName] then
        return layouts[layoutName]
    end

    local side, pct = layoutName:match("^(%a+)(%d+)$")
    local size = tonumber(pct)

    if size and size > 0 and size <= 100 then
        local fraction = size / 100

        if side == "left" then
            return { x = 0, y = 0, w = fraction, h = 1 }
        elseif side == "right" then
            return { x = 1 - fraction, y = 0, w = fraction, h = 1 }
        elseif side == "top" then
            return { x = 0, y = 0, w = 1, h = fraction }
        elseif side == "bottom" then
            return { x = 0, y = 1 - fraction, w = 1, h = fraction }
        end
    end

    hs.alert.show("Unknown layout: " .. layoutName, 8)
    return nil
end

-- Look up the app by exact name only; a fuzzy find() can match helper
-- processes ("Safari Networking") whose handles break window operations.
local function getApp(appName)
    return hs.application.get(appName)
        or hs.application.find(appName, true)
end

-- After launchOrFocus() the app object may not exist yet (or only as a
-- half-initialized handle), so poll with a fresh lookup each attempt.
local function waitForApp(appName, callback, attempts)
    attempts = attempts or 50

    local app = getApp(appName)

    if app then
        callback(app)
        return
    end

    if attempts <= 0 then
        hs.alert.show("Could not find " .. appName, 8)
        return
    end

    hs.timer.doAfter(0.2, function()
        waitForApp(appName, callback, attempts - 1)
    end)
end

-- A cold launch can take several seconds before the first window exists.
local function waitForWindow(app, callback, attempts)
    attempts = attempts or 40

    local window = app:mainWindow()
        or app:focusedWindow()
        or app:allWindows()[1]

    if window then
        callback(window)
        return
    end

    if attempts <= 0 then
        hs.alert.show("No window found for " .. app:name(), 8)
        return
    end

    hs.timer.doAfter(0.15, function()
        waitForWindow(app, callback, attempts - 1)
    end)
end

--- AppLaunchScripts:focusOrLaunch(appName, layoutName)
--- Method
--- Focus an application, launching it if necessary, and optionally apply a layout.
---
--- Parameters:
---  * appName - name of the application, as used by `hs.application.launchOrFocus()`
---  * layoutName - optional layout: a key into `AppLaunchScripts.layouts`, or a dynamic name of the form `left<N>`, `right<N>`, `top<N>`, `bottom<N>` where N is a percentage (e.g. `right86`). Unknown names show an alert and leave the window in place.
---
--- Returns:
---  * `true` when the application was found or launched, `false` otherwise
function obj:focusOrLaunch(appName, layoutName)
    local layout = resolveLayout(self.layouts, layoutName)

    if not getApp(appName) then
        local launched = hs.application.launchOrFocus(appName)

        if not launched then
            hs.alert.show('"' .. appName .. '" not installed', 8)
            return false
        end
    end

    waitForApp(appName, function(app)
        app:unhide()

        for _, window in ipairs(app:allWindows()) do
            if window:isMinimized() then
                window:unminimize()
            end
        end

        app:activate(true)

        waitForWindow(app, function(window)
            window:focus()

            if layout then
                window:moveToUnit(layout)
            end
        end)
    end)

    return true
end

-- Match a Chrome profile hint against the profiles table, by directory
-- ("Profile 2") or display name ("Work"), case-insensitively.
local function resolveChromeProfile(profiles, hint)
    local lowered = hint:lower()

    for dir, name in pairs(profiles) do
        if dir:lower() == lowered or (name and name:lower() == lowered) then
            return dir, name
        end
    end

    return nil
end

-- Chrome appends the profile to window titles when more than one profile
-- is in use, e.g. "Page - Google Chrome – Alice" or, for a profile whose
-- account name differs from the profile name, "Page - Google Chrome –
-- Alice (Work)". Match the suffix only: a plain substring search for
-- "Alice" would also hit the parenthesised form of a different profile.
-- The optional spaceID restricts the search to windows on that Space;
-- the optional excluded set ({[windowID] = true}) skips windows already
-- claimed by another workspace entry.
local function findProfileWindow(app, name, spaceID, excluded)
    local bare = "– " .. name
    local parenthesised = "(" .. name .. ")"

    for _, window in ipairs(app:allWindows()) do
        local title = window:title() or ""

        if (title:sub(-#bare) == bare
            or title:sub(-#parenthesised) == parenthesised)
            and not (excluded and window:id() and excluded[window:id()]) then
            if not spaceID then
                return window
            end

            -- Minimized windows belong to no Space; treat them as
            -- matching so a workspace state with a minimized window is
            -- still recognized instead of relaunched.
            if window:isMinimized() then
                return window
            end

            for _, space in ipairs(hs.spaces.windowSpaces(window) or {}) do
                if space == spaceID then
                    return window
                end
            end
        end
    end

    return nil
end

--- AppLaunchScripts:chromeProfiles()
--- Method
--- List Google Chrome profiles from Chrome's `Local State` file.
---
--- Parameters:
---  * None
---
--- Returns:
---  * A table mapping profile directory (e.g. `Profile 2`) to display name (e.g. `Work`); empty if Chrome is not installed
function obj:chromeProfiles()
    local path = os.getenv("HOME")
        .. "/Library/Application Support/Google/Chrome/Local State"

    local file = io.open(path, "r")

    if not file then
        return {}
    end

    local state = hs.json.decode(file:read("*a"))
    file:close()

    local profiles = {}

    for dir, info in pairs(((state or {}).profile or {}).info_cache or {}) do
        profiles[dir] = info.name
    end

    return profiles
end

--- AppLaunchScripts:chrome(profile, layoutName)
--- Method
--- Focus or launch Google Chrome, optionally with a specific profile.
---
--- Parameters:
---  * profile - optional profile directory (`"Profile 2"`) or display name (`"Work"`), case-insensitive. If a window of that profile is already open it is focused; otherwise a new window is opened with that profile. Omit to treat Chrome like any other app.
---  * layoutName - optional layout, same as `focusOrLaunch()`
---
--- Returns:
---  * `true` when Chrome was found or launched, `false` on an unknown profile or launch failure
function obj:chrome(profile, layoutName)
    if not profile then
        return self:focusOrLaunch("Google Chrome", layoutName)
    end

    local dir, name = resolveChromeProfile(self:chromeProfiles(), profile)

    if not dir then
        hs.alert.show("Unknown Chrome profile: " .. profile, 8)
        return false
    end

    local layout = resolveLayout(self.layouts, layoutName)

    local app = getApp("Google Chrome")
    local existing = app and findProfileWindow(app, name)

    if existing then
        app:activate(true)
        existing:focus()

        if layout then
            existing:moveToUnit(layout)
        end

        return true
    end

    -- No window for this profile yet: open one. This also launches
    -- Chrome itself when it isn't running.
    hs.task.new("/usr/bin/open", nil, {
        "-na", "Google Chrome",
        "--args", "--profile-directory=" .. dir,
    }):start()

    waitForApp("Google Chrome", function(chromeApp)
        chromeApp:activate(true)

        waitForWindow(chromeApp, function(window)
            local target = findProfileWindow(chromeApp, name) or window

            target:focus()

            if layout then
                target:moveToUnit(layout)
            end
        end)
    end)

    return true
end

--- AppLaunchScripts:terminal()
--- Method
--- Focus or launch Terminal and place it in the `left66` layout.
---
--- Parameters:
---  * None
---
--- Returns:
---  * `true` when Terminal was found or launched, `false` otherwise
function obj:terminal()
    return self:focusOrLaunch("Terminal", "left66")
end

--- AppLaunchScripts:help()
--- Method
--- Generic help: available methods, layouts, workspaces, and Chrome
--- profiles. Everything is discovered at runtime, so custom layouts and
--- new methods show up automatically. Handy from the shell:
--- `hs -c 'spoon.AppLaunchScripts:help()'`
---
--- Parameters:
---  * None
---
--- Returns:
---  * The help text as a string
function obj:help()
    -- Hidden feature: refresh Slack and Teams state first — rescan
    -- domains, regenerate configs and the available*Comms.lua files —
    -- so the printed commands are always up to date without a reload.
    if self.generateSlackDomainConfigs then
        self:generateSlackDomainConfigs()
        self:generateSlackMethods()
    end

    if self.generateTeamsConfig then
        self:generateTeamsConfig()
        self:generateTeamsMethods()
    end

    if self.generateDiscordConfigs then
        self:generateDiscordConfigs()
        -- Complete pending name scans first (blocks briefly per
        -- unfilled entry, no-op otherwise) so the printed commands
        -- carry real names instead of provisional IDs.
        self:discordScanTitlesSync()
        self:generateDiscordMethods()
    end

    local lines = {
        self.name .. " " .. self.version .. " — " .. self.homepage,
        "",
        "Methods:",
    }

    local methods = {}

    for key, value in pairs(self) do
        if type(value) == "function" and not key:match("^_") then
            table.insert(methods, key)
        end
    end

    table.sort(methods)

    for _, method in ipairs(methods) do
        table.insert(lines, "  spoon." .. self.name .. ":" .. method .. "()")
    end

    local layoutNames = {}

    for key in pairs(self.layouts) do
        table.insert(layoutNames, key)
    end

    table.sort(layoutNames)

    table.insert(lines, "")
    table.insert(lines, "Layouts (plus dynamic left<N>/right<N>/top<N>/bottom<N>):")
    table.insert(lines, "  " .. table.concat(layoutNames, ", "))

    if self._workspaceLaunchers and #self._workspaceLaunchers > 0 then
        table.insert(lines, "")
        table.insert(lines, "Workspaces:")

        for _, method in ipairs(self._workspaceLaunchers) do
            table.insert(lines, string.format(
                "  spoon.%s:%s()", self.name, method))
        end
    end

    if self._slackLaunchers and #self._slackLaunchers > 0 then
        table.insert(lines, "")
        table.insert(lines, "Slack (config/slack/*.json):")

        for _, method in ipairs(self._slackLaunchers) do
            table.insert(lines, string.format(
                "  spoon.%s:%s()", self.name, method))
        end
    end

    if self._teamsLaunchers and #self._teamsLaunchers > 0 then
        table.insert(lines, "")
        table.insert(lines, "Microsoft Teams (config/teams/Teams.json):")

        for _, method in ipairs(self._teamsLaunchers) do
            table.insert(lines, string.format(
                "  spoon.%s:%s()", self.name, method))
        end
    end

    if self._discordLaunchers and #self._discordLaunchers > 0 then
        table.insert(lines, "")
        table.insert(lines, "Discord (config/discord/*.json + config/discordDM/*.json):")

        for _, method in ipairs(self._discordLaunchers) do
            table.insert(lines, string.format(
                "  spoon.%s:%s()", self.name, method))
        end
    end

    local profileLines = {}

    for dir, name in pairs(self:chromeProfiles()) do
        local command = string.format(
            '  spoon.%s:chrome("%s", "rightHalf")', self.name, name)

        table.insert(profileLines,
            string.format("%-58s -- %s", command, dir))
    end

    if #profileLines > 0 then
        table.sort(profileLines)
        table.insert(lines, "")
        table.insert(lines, "Chrome profiles (profile directory works too):")

        for _, line in ipairs(profileLines) do
            table.insert(lines, line)
        end
    end

    return table.concat(lines, "\n")
end

-- Internal helpers shared with workspaces.lua (leading underscore keeps
-- them out of help()).
obj._getApp = getApp
obj._waitForApp = waitForApp
obj._waitForWindow = waitForWindow
obj._resolveChromeProfile = resolveChromeProfile
obj._findProfileWindow = findProfileWindow
obj._resolveLayout = resolveLayout

obj.spoonPath = hs.spoons.scriptPath()

dofile(obj.spoonPath .. "workspaces.lua")(obj)
dofile(obj.spoonPath .. "slack.lua")(obj)
dofile(obj.spoonPath .. "teams.lua")(obj)
dofile(obj.spoonPath .. "discord.lua")(obj)

--- AppLaunchScripts:start()
--- Method
--- Start the Spoon: binds hammerspoon:// URL events for the basic
--- methods and the generic workspace launcher (workspace-specific URLs
--- are bound when the launchers are generated). Available URLs:
---  * hammerspoon://terminal
---  * hammerspoon://focusOrLaunch?app=Safari&layout=right34
---  * hammerspoon://chrome?profile=X&layout=rightHalf
---  * hammerspoon://launchWorkspace?name=X
---
--- Parameters:
---  * None
---
--- Returns:
---  * The AppLaunchScripts object
function obj:start()
    -- For launchers that cannot run shell commands with arguments
    -- (e.g. Stream Deck's "Website" action). Browsers and some
    -- dispatchers lowercase the URL host, so bind both spellings; the
    -- query string keeps its case.
    local urlHandlers = {
        terminal = function()
            self:terminal()
        end,

        focusOrLaunch = function(_, params)
            if params and params.app then
                self:focusOrLaunch(params.app, params.layout)
            else
                hs.alert.show("focusOrLaunch URL needs ?app=<name>", 8)
            end
        end,

        chrome = function(_, params)
            params = params or {}
            self:chrome(params.profile, params.layout)
        end,

        launchWorkspace = function(_, params)
            if params and params.name then
                self:launchWorkspace(params.name)
            else
                hs.alert.show("launchWorkspace URL needs ?name=<workspace>", 8)
            end
        end,
    }

    for name, handler in pairs(urlHandlers) do
        hs.urlevent.bind(name, handler)
        hs.urlevent.bind(name:lower(), handler)
    end

    return self
end

return obj
