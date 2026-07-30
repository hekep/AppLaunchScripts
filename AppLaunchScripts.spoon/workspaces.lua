-- Workspace support for AppLaunchScripts.
--
-- A workspace is a JSON file in the Spoon's workspaces/ folder describing a
-- target display, a target macOS Space, the apps to launch or focus, and the
-- window layout to apply. For every workspaces/<Name>.json this module
-- generates a convenience method obj:launch<Name>() into
-- availableWorkspaces.lua and loads it.
--
-- Loaded from init.lua as: dofile(obj.spoonPath .. "workspaces.lua")(obj)

return function(obj)

    local function workspacesDir()
        return obj.spoonPath .. "workspaces/"
    end

    local function generatedFile()
        return obj.spoonPath .. "availableWorkspaces.lua"
    end

    -- "Communications" -> "Communications"; "My Workspace!" -> "MyWorkspace"
    local function methodSuffix(name)
        return (name:gsub("[^%w]", ""))
    end

    -- Alert + console print, so problems show up on screen AND in
    -- `hs -c` output / the Hammerspoon console. Error notifications
    -- stay visible for 8 seconds.
    local function warn(message)
        hs.alert.show(message, 8)
        print("AppLaunchScripts: " .. message)
    end

    local function contains(list, value)
        for _, item in ipairs(list or {}) do
            if item == value then
                return true
            end
        end

        return false
    end

    -- "current" (or nil) -> screen with the focused window, "primary" ->
    -- primary screen, a number -> index into allScreens(), anything else is
    -- matched against screen names.
    local function resolveDisplay(spec)
        if spec == nil or spec == "current" then
            return hs.screen.mainScreen()
        end

        if spec == "primary" then
            return hs.screen.primaryScreen()
        end

        if type(spec) == "number" then
            return hs.screen.allScreens()[spec] or hs.screen.mainScreen()
        end

        return hs.screen.find(spec) or hs.screen.mainScreen()
    end

    -- Validate the widths/heights array: it must be an array of positive
    -- numbers, one per app, summing to at most 100. Anything else is
    -- reported and every app gets an equal share instead.
    local function validatedSizes(layout, count, workspaceName)
        local direction = (layout and layout.direction) or "horizontal"
        local key = (direction == "vertical") and "heights" or "widths"
        local sizes = layout and (layout.widths or layout.heights)

        if sizes == nil then
            return nil -- even split is the documented default; no complaint
        end

        local problem

        if type(sizes) ~= "table" then
            problem = key .. " is not an array"
        elseif #sizes ~= count then
            problem = string.format(
                "%s has %d values for %d apps", key, #sizes, count)
        else
            local sum = 0

            for _, value in ipairs(sizes) do
                if type(value) ~= "number" or value <= 0 then
                    problem = key .. " must contain positive numbers only"
                    break
                end

                sum = sum + value
            end

            if not problem and sum > 100 then
                problem = string.format(
                    "%s sum to %d%% (over 100%%)", key, math.floor(sum + 0.5))
            end
        end

        if problem then
            warn(string.format('Workspace "%s": %s — using %d%% each',
                workspaceName or "?", problem, math.floor(100 / count)))
            return nil
        end

        return sizes
    end

    -- Turn {direction = "horizontal", widths = {33, 33, 34}} into one unit
    -- rect per app. Missing or invalid sizes fall back to an even split.
    local function layoutUnits(layout, count, workspaceName)
        local direction = (layout and layout.direction) or "horizontal"
        local sizes = validatedSizes(layout, count, workspaceName)

        local units = {}
        local offset = 0

        for i = 1, count do
            local size = ((sizes and sizes[i]) or (100 / count)) / 100

            if direction == "vertical" then
                units[i] = { x = 0, y = offset, w = 1, h = size }
            else
                units[i] = { x = offset, y = 0, w = size, h = 1 }
            end

            offset = offset + size
        end

        return units
    end

    -- Common names that differ from the real application name.
    local appAliases = {
        ["chrome"] = "Google Chrome",
    }

    local function realAppName(name)
        return appAliases[name:lower()] or name
    end

    local function onSpace(window, spaceID)
        return contains(hs.spaces.windowSpaces(window), spaceID)
    end

    local function unitFrameMatches(window, screen, unit)
        local frame = window:frame()
        local screenFrame = screen:frame()
        local tolerance = 20

        return math.abs(frame.x - (screenFrame.x + unit.x * screenFrame.w)) <= tolerance
            and math.abs(frame.y - (screenFrame.y + unit.y * screenFrame.h)) <= tolerance
            and math.abs(frame.w - unit.w * screenFrame.w) <= tolerance
            and math.abs(frame.h - unit.h * screenFrame.h) <= tolerance
    end

    -- Apps that restore their own window geometry during startup (VS
    -- Code and other Electron apps) override the first moveToUnit() a
    -- moment later, leaving the window at its remembered size. Apply the
    -- layout, then re-check and re-apply until it sticks.
    local function enforceUnit(window, screen, unit, attempts)
        attempts = attempts or 8

        window:moveToUnit(unit)

        if attempts <= 0 then
            return
        end

        hs.timer.doAfter(0.5, function()
            if not unitFrameMatches(window, screen, unit) then
                enforceUnit(window, screen, unit, attempts - 1)
            end
        end)
    end

    -- Move a window to the target Space and screen and apply its slot of
    -- the layout. On recent macOS hs.spaces.moveWindowToSpace() reports
    -- success but silently does nothing, so verify and warn — the real
    -- fix is switching to the Space BEFORE windows are created, which
    -- applyWorkspace() does.
    local function placeWindow(window, screen, spaceID, unit)
        if not onSpace(window, spaceID) then
            hs.spaces.moveWindowToSpace(window, spaceID)

            if not onSpace(window, spaceID) then
                -- macOS silently refuses to move established windows
                -- between Spaces; only freshly created windows move.
                -- The window is arranged where it is instead — quitting
                -- the app and relaunching the workspace puts it on the
                -- configured Space.
                local appName = window:application()
                    and window:application():name() or "window"

                warn(string.format(
                    '"%s" already open on another Space — arranging it there (quit the app and relaunch to relocate)',
                    appName))
            end
        end

        window:moveToScreen(screen)
        window:focus()

        if unit then
            enforceUnit(window, screen, unit)
        end
    end

    -- Mark a window as taken by one workspace entry, so a second entry
    -- using the same Chrome profile gets its own window instead.
    local function claimWindow(claimed, window)
        local id = window:id()

        if id then
            claimed[id] = true
        end
    end

    local function siteHost(url)
        local host = url:match("^%a[%w+.-]*://([^/]+)") or url

        return (host:gsub("^www%.", ""))
    end

    -- One AppleScript round-trip: every Chrome window's name (= active
    -- tab title) plus all its tab URLs. Used to tell same-profile
    -- windows apart by the site they hold.
    local function chromeWindowsInfo()
        local ok, result = hs.osascript.applescript([[
            set out to ""
            tell application "Google Chrome"
                repeat with w in every window
                    set urlList to ""
                    repeat with t in tabs of w
                        set urlList to urlList & (URL of t) & " "
                    end repeat
                    set out to out & (name of w) & "\t" & urlList & "\n"
                end repeat
            end tell
            return out
        ]])

        if not ok or type(result) ~= "string" then
            return nil
        end

        local info = {}

        for line in result:gmatch("[^\n]+") do
            local name, urls = line:match("^(.-)\t(.*)$")

            if name then
                table.insert(info, { name = name, urls = urls })
            end
        end

        return info
    end

    -- The hs window title is "<active tab> - Google Chrome – <profile>";
    -- the AppleScript window name is just "<active tab>".
    local function windowNamePrefix(window)
        local title = window:title() or ""
        local cut = title:find(" %- Google Chrome")

        return cut and title:sub(1, cut - 1) or title
    end

    local function windowHasSite(window, host, info)
        if not info then
            return false
        end

        local prefix = windowNamePrefix(window)

        for _, entry in ipairs(info) do
            if entry.name == prefix and entry.urls:find(host, 1, true) then
                return true
            end
        end

        return false
    end

    -- All unclaimed windows of a profile on a Space.
    local function profileWindowsOnSpace(app, profileName, spaceID, claimed)
        local windows = {}
        local excluded = {}

        for id in pairs(claimed) do
            excluded[id] = true
        end

        while true do
            local window = obj._findProfileWindow(
                app, profileName, spaceID, excluded)

            if not window then
                break
            end

            table.insert(windows, window)

            local id = window:id()

            if not id then
                break
            end

            excluded[id] = true
        end

        return windows
    end

    -- Pick the window that actually holds the wanted site; a window is
    -- "the Instagram window" only if one of its tabs is on instagram.
    local function pickSiteWindow(candidates, host)
        if #candidates == 0 then
            return nil
        end

        if not host then
            return candidates[1]
        end

        local info = chromeWindowsInfo()

        for _, window in ipairs(candidates) do
            if windowHasSite(window, host, info) then
                return window
            end
        end

        return nil
    end

    -- Wait until an unclaimed window of the given Chrome profile holding
    -- the given site exists on the Space. Site-aware so that two waiters
    -- for the same profile (e.g. Instagram and MeWe windows opening
    -- side by side) never grab each other's window. Falls back to any
    -- unclaimed profile window, then the main window.
    local function waitForProfileWindow(app, profileName, spaceID, claimed, host, callback, attempts)
        attempts = attempts or 60

        local candidates = profileWindowsOnSpace(app, profileName, spaceID, claimed)
        local pick = pickSiteWindow(candidates, host)

        if pick then
            claimWindow(claimed, pick)
            callback(pick)
            return
        end

        if attempts <= 0 then
            local fallback = candidates[1] or app:mainWindow()

            if fallback and not (fallback:id() and claimed[fallback:id()]) then
                claimWindow(claimed, fallback)
                callback(fallback)
            else
                warn("No window found for Chrome profile " .. profileName)
            end

            return
        end

        hs.timer.doAfter(0.25, function()
            waitForProfileWindow(app, profileName, spaceID, claimed, host, callback, attempts - 1)
        end)
    end

    -- Restore the configured site inside an existing Chrome window:
    -- activate the first tab whose URL contains the site's host, or open
    -- a new tab on the site when no such tab exists. The AppleScript
    -- window is identified by the active-tab title, which the macOS
    -- window title (as seen by Hammerspoon) starts with. Requires the
    -- macOS Automation permission (Hammerspoon -> Google Chrome).
    local function ensureChromeTab(window, url)
        local host = siteHost(url)

        -- Among windows whose name matches, prefer the one that already
        -- holds the site — duplicate names across desktops otherwise
        -- send the tab to the wrong window.
        local script = string.format([[
            set hsTitle to %q
            set siteHost to %q
            set targetURL to %q
            set targetIdx to 0
            set backupIdx to 0
            tell application "Google Chrome"
                repeat with i from 1 to count of windows
                    if hsTitle starts with (name of window i) then
                        set found to false
                        repeat with j from 1 to count of tabs of window i
                            if (URL of tab j of window i) contains siteHost then
                                set found to true
                            end if
                        end repeat
                        if found and targetIdx is 0 then
                            set targetIdx to i
                        end if
                        if backupIdx is 0 then
                            set backupIdx to i
                        end if
                    end if
                end repeat
                if targetIdx is 0 then
                    set targetIdx to backupIdx
                end if
                if targetIdx is 0 then
                    return "window not found"
                end if
                repeat with j from 1 to count of tabs of window targetIdx
                    if (URL of tab j of window targetIdx) contains siteHost then
                        set active tab index of window targetIdx to j
                        return "activated existing tab"
                    end if
                end repeat
                make new tab at end of tabs of window targetIdx with properties {URL:targetURL}
                return "opened new tab"
            end tell
        ]], window:title() or "", host, url)

        local ok, result = hs.osascript.applescript(script)

        if not ok then
            warn("Chrome tab restore failed — is the Automation permission "
                .. "(Hammerspoon → Google Chrome) granted?")
            return nil
        end

        return result
    end

    -- One app entry with a "profile" key means Google Chrome with that
    -- profile; "www" optionally opens a URL in the new window. Windows
    -- are managed per Space: a profile window on the target Space is
    -- re-used (tab restored), any other Space's windows are left alone
    -- and a fresh window is opened instead — macOS cannot move
    -- established windows between Spaces, and adopting one could steal
    -- a window that belongs to a different workspace's desktop.
    local function launchChromeProfileIntoSpace(appConfig, screen, spaceID, unit, context)
        local claimed = context.claimed
        local dir, profileName = obj._resolveChromeProfile(
            obj:chromeProfiles(), appConfig.profile)

        if not dir then
            warn("Unknown Chrome profile: " .. appConfig.profile)
            return "failed"
        end

        local host = appConfig.www and siteHost(appConfig.www) or nil
        local app = obj._getApp("Google Chrome")

        if app then
            local candidates = profileWindowsOnSpace(
                app, profileName, spaceID, claimed)
            local pick = pickSiteWindow(candidates, host)

            -- No window holds the site: adopting a generic window is
            -- only safe when this profile has a single entry in the
            -- workspace — with several entries, an empty-looking window
            -- may belong to a sibling site.
            if not pick and #candidates > 0
                and (context.profileCounts[dir] or 0) <= 1 then
                pick = candidates[1]
            end

            if pick then
                claimWindow(claimed, pick)

                if appConfig.www then
                    ensureChromeTab(pick, appConfig.www)
                end

                placeWindow(pick, screen, spaceID, unit)
                return "placed"
            end
        end

        -- Never duplicate a site window that already exists on another
        -- desktop: AppleScript sees every window regardless of Space
        -- (the accessibility API does not). If the whole config's quota
        -- for this site is already open somewhere, report it so
        -- applyWorkspace() can fall back to that desktop.
        if host then
            local info = chromeWindowsInfo()
            local existingCount = 0

            for _, entry in ipairs(info or {}) do
                if entry.urls:find(host, 1, true) then
                    existingCount = existingCount + 1
                end
            end

            if existingCount >= (context.hostCounts[host] or 1) then
                return "elsewhere"
            end
        end

        -- Open a fresh window; it appears on the currently focused Space,
        -- which applyWorkspace() has already switched to. Openings are
        -- staggered: near-simultaneous open commands can collapse into
        -- tabs of a single window.
        local args = {
            "-na", "Google Chrome",
            "--args",
            "--profile-directory=" .. dir,
            "--new-window",
        }

        if appConfig.www then
            table.insert(args, appConfig.www)
        end

        local delay = context.opens * 0.7
        context.opens = context.opens + 1

        hs.timer.doAfter(delay, function()
            hs.task.new("/usr/bin/open", nil, args):start()
        end)

        obj._waitForApp("Google Chrome", function(chromeApp)
            waitForProfileWindow(chromeApp, profileName, spaceID, claimed, host, function(window)
                placeWindow(window, screen, spaceID, unit)
            end)
        end)

        return "opened"
    end

    -- Find a window whose title contains the given text (for apps like
    -- VS Code that host several project windows in one process, the
    -- title is the only thing identifying the project). Also returns
    -- how many windows matched, so ambiguous fragments can be reported.
    local function findTitledWindow(app, needle)
        local lowered = needle:lower()
        local found = nil
        local matches = 0

        for _, window in ipairs(app:allWindows()) do
            local title = (window:title() or ""):lower()

            if title:find(lowered, 1, true) then
                matches = matches + 1
                found = found or window
            end
        end

        return found, matches
    end

    -- Wait until a window matching appConfig.window exists; falls back
    -- to the main window when the title never shows up.
    local function waitForTitledWindow(app, needle, callback, attempts)
        attempts = attempts or 80

        local window = findTitledWindow(app, needle)

        if window then
            callback(window)
            return
        end

        if attempts <= 0 then
            local fallback = app:mainWindow()

            if fallback then
                callback(fallback)
            else
                warn("No window found matching: " .. needle)
            end

            return
        end

        hs.timer.doAfter(0.15, function()
            waitForTitledWindow(app, needle, callback, attempts - 1)
        end)
    end

    -- Launch or focus one app, then move its window to the target screen
    -- and Space and apply its slot of the layout.
    --
    -- Duplicate-launch protection: the live window list is the source of
    -- truth (no PID bookkeeping — PIDs die with the `code` CLI, are
    -- shared between all VS Code project windows, and rot after
    -- restarts). When appConfig.window matches an existing window title
    -- the launch step is skipped entirely and the window is just placed.
    local function launchIntoSpace(appConfig, screen, spaceID, unit, context)
        if appConfig.profile then
            return launchChromeProfileIntoSpace(
                appConfig, screen, spaceID, unit, context)
        end

        local appName = realAppName(appConfig.name)
        local app = obj._getApp(appName)

        if app and appConfig.window then
            local window, matches = findTitledWindow(app, appConfig.window)

            if matches > 1 then
                warn(string.format(
                    'Window title "%s" matches %d %s windows — using the first; make it more unique',
                    appConfig.window, matches, appName))
            end

            if window then
                app:activate(true)
                placeWindow(window, screen, spaceID, unit)
                return
            end
        end

        local mustLaunch = not app
            -- App running but the wanted project window is missing:
            -- the cmd is what knows how to open it.
            or (appConfig.window and appConfig.cmd) ~= nil

        if mustLaunch then
            if appConfig.cmd then
                -- The configured shell command is responsible for
                -- launching the app ("name" is still needed to find its
                -- window). Run in a login shell so CLIs like `code` are
                -- on PATH. It runs ONLY when the app is not running or
                -- the wanted window is missing — repeated workspace
                -- launches must not spawn overlapping processes.
                hs.task.new("/bin/zsh", nil, { "-lc", appConfig.cmd }):start()
            elseif not app and not hs.application.launchOrFocus(appName) then
                warn('"' .. appName .. '" not installed')
                return
            end
        end

        obj._waitForApp(appName, function(launchedApp)
            launchedApp:unhide()

            for _, window in ipairs(launchedApp:allWindows()) do
                if window:isMinimized() then
                    window:unminimize()
                end
            end

            launchedApp:activate(true)

            if appConfig.window then
                waitForTitledWindow(launchedApp, appConfig.window, function(window)
                    placeWindow(window, screen, spaceID, unit)
                end)
                return
            end

            -- Slack and friends can be slow on cold launch: 80 * 0.15s
            obj._waitForWindow(launchedApp, function(window)
                placeWindow(window, screen, spaceID, unit)
            end, 80)
        end)
    end

    --- AppLaunchScripts:workspaces()
    --- Method
    --- List available workspace names (the base names of workspaces/*.json).
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A sorted table of workspace names
    function obj:workspaces()
        local names = {}

        local ok, iterator, dirObj = pcall(hs.fs.dir, workspacesDir())

        if ok then
            for entry in iterator, dirObj do
                local name = entry:match("^(.+)%.json$")

                if name then
                    table.insert(names, name)
                end
            end
        end

        table.sort(names)

        return names
    end

    --- AppLaunchScripts:loadWorkspace(name)
    --- Method
    --- Load and decode workspaces/<name>.json.
    ---
    --- Parameters:
    ---  * name - workspace name (file base name, e.g. "Communications")
    ---
    --- Returns:
    ---  * The decoded configuration table, or nil (with an alert) when the file is missing or invalid
    function obj:loadWorkspace(name)
        local path = workspacesDir() .. name .. ".json"
        local file = io.open(path, "r")

        if not file then
            warn("No workspace config: " .. name)
            return nil
        end

        local config = hs.json.decode(file:read("*a"))
        file:close()

        if not config then
            warn("Invalid JSON in workspace: " .. name)
            return nil
        end

        config.name = config.name or name

        return config
    end

    --- AppLaunchScripts:applyWorkspace(config)
    --- Method
    --- Apply a workspace configuration: switch to the target Space, launch
    --- or focus the apps, move their windows there, and lay them out.
    ---
    --- Parameters:
    ---  * config - a workspace configuration table (see loadWorkspace())
    ---
    --- Returns:
    ---  * `true` when the workspace was applied, `false` on a config error
    -- Repeated presses while a launch is still settling would spawn
    -- extra windows and tabs; ignore presses within the lockout window.
    local launchTimes = {}
    local LAUNCH_LOCKOUT = 10

    function obj:applyWorkspace(config)
        local now = hs.timer.secondsSinceEpoch()
        local last = launchTimes[config.name]

        if last and (now - last) < LAUNCH_LOCKOUT then
            warn(string.format(
                'Workspace "%s" is still launching — press ignored (wait %ds)',
                config.name, math.ceil(LAUNCH_LOCKOUT - (now - last))))
            return false
        end

        launchTimes[config.name] = now

        hs.alert.show("Launching " .. config.name)

        -- 1. Resolve the target display
        local screen = resolveDisplay(config.space and config.space.display)

        -- 2. Resolve the target Space, creating missing Spaces on demand
        -- so a config can declare a desktop beyond what exists yet.
        -- "desktop" is the preferred key; "index" is the legacy alias.
        local spaceIDs = hs.spaces.spacesForScreen(screen) or {}
        local index = (config.space
            and (config.space.desktop or config.space.index)) or 1

        while #spaceIDs < index do
            local ok = hs.spaces.addSpaceToScreen(screen, true)

            if not ok then
                break
            end

            hs.alert.show(string.format(
                "Created Space %d on %s", #spaceIDs + 1, screen:name()))

            spaceIDs = hs.spaces.spacesForScreen(screen) or {}
        end

        local spaceID = spaceIDs[index]

        if not spaceID then
            warn(string.format(
                "No Space %d on %s (%d available)",
                index, screen:name(), #spaceIDs))
            return false
        end

        -- 4.-6. Launch or focus each app, move its window to the Space,
        -- and apply its slot of the layout.
        local function launchApps(runSpaceID)
            local units = layoutUnits(
                config.layout, #(config.apps or {}), config.name)

            -- Per-run state: claimed windows (a second entry with the
            -- same Chrome profile gets its own window), how often each
            -- profile and site appears, and an open counter for
            -- staggering.
            local context = {
                claimed = {},
                profileCounts = {},
                hostCounts = {},
                opens = 0,
            }

            for _, appConfig in ipairs(config.apps or {}) do
                if appConfig.profile then
                    local dir = obj._resolveChromeProfile(
                        obj:chromeProfiles(), appConfig.profile)

                    if dir then
                        context.profileCounts[dir] =
                            (context.profileCounts[dir] or 0) + 1
                    end

                    if appConfig.www then
                        local host = siteHost(appConfig.www)
                        context.hostCounts[host] =
                            (context.hostCounts[host] or 0) + 1
                    end
                end
            end

            local wwwEntries = 0
            local elsewhereCount = 0

            for i, appConfig in ipairs(config.apps or {}) do
                local status = launchIntoSpace(
                    appConfig, screen, runSpaceID, units[i], context)

                if appConfig.profile and appConfig.www then
                    wwwEntries = wwwEntries + 1

                    if status == "elsewhere" then
                        elsewhereCount = elsewhereCount + 1
                    end
                end
            end

            return wwwEntries, elsewhereCount
        end

        -- Does this Space hold at least one of the workspace's site
        -- windows? (Checked while the Space is focused, because the
        -- accessibility API only sees the current Space.)
        local function probeSpace(sid)
            local app = obj._getApp("Google Chrome")

            if not app then
                return false
            end

            for _, appConfig in ipairs(config.apps or {}) do
                if appConfig.profile and appConfig.www then
                    local dir, profileName = obj._resolveChromeProfile(
                        obj:chromeProfiles(), appConfig.profile)

                    if dir then
                        local candidates = profileWindowsOnSpace(
                            app, profileName, sid, {})

                        if pickSiteWindow(candidates, siteHost(appConfig.www)) then
                            return true
                        end
                    end
                end
            end

            return false
        end

        -- The workspace's windows exist, but on some other desktop that
        -- macOS won't let us move them away from. Visit the desktops
        -- until they are found and apply the workspace there.
        local function fallbackSearch()
            local order = {}

            for i, sid in ipairs(spaceIDs) do
                if sid ~= spaceID then
                    table.insert(order, { index = i, id = sid })
                end
            end

            local pos = 0

            local function nextSpace()
                pos = pos + 1

                if pos > #order then
                    warn(string.format(
                        'Unable to open apps on "Desktop %d" — existing windows could not be located',
                        index))
                    return
                end

                local target = order[pos]

                hs.spaces.gotoSpace(target.id)

                hs.timer.doAfter(1.2, function()
                    if hs.spaces.focusedSpace() == target.id
                        and probeSpace(target.id) then
                        warn(string.format(
                            'Unable to open apps on "Desktop %d" — using "Desktop %d" where the windows already are',
                            index, target.index))
                        launchApps(target.id)
                    else
                        nextSpace()
                    end
                end)
            end

            nextSpace()
        end

        local function runOnTarget()
            local wwwEntries, elsewhereCount = launchApps(spaceID)

            if wwwEntries > 0 and elsewhereCount == wwwEntries then
                fallbackSearch()
            elseif elsewhereCount > 0 then
                warn(string.format(
                    'Workspace "%s": %d site window(s) already open on another desktop — not duplicated',
                    config.name, elsewhereCount))
            end
        end

        -- 3. Switch to that Space FIRST and wait for the switch to
        -- settle: new windows open on the focused Space, and on recent
        -- macOS that is the only reliable way to get them onto the
        -- target Space (moveWindowToSpace() silently fails there).
        if hs.spaces.focusedSpace() == spaceID then
            runOnTarget()
            return true
        end

        local ok, err = hs.spaces.gotoSpace(spaceID)

        if not ok then
            -- Usually a missing Accessibility permission. Better no
            -- action than windows created on the wrong desktop.
            warn("Could not switch Space: " .. tostring(err))
            return false
        end

        local attempts = 40

        local function waitForSwitch()
            if hs.spaces.focusedSpace() == spaceID then
                runOnTarget()
                return
            end

            attempts = attempts - 1

            if attempts <= 0 then
                warn(string.format(
                    'Workspace "%s": Space switch did not complete — aborting to avoid duplicate windows',
                    config.name))
                return
            end

            if attempts == 20 then
                hs.spaces.gotoSpace(spaceID)
            end

            hs.timer.doAfter(0.25, waitForSwitch)
        end

        waitForSwitch()

        return true
    end

    --- AppLaunchScripts:launchWorkspace(name)
    --- Method
    --- Load workspaces/<name>.json and apply it.
    ---
    --- Parameters:
    ---  * name - workspace name (file base name, e.g. "Communications")
    ---
    --- Returns:
    ---  * `true` when the workspace was applied, `false` otherwise
    function obj:launchWorkspace(name)
        local config = self:loadWorkspace(name)

        if not config then
            return false
        end

        return self:applyWorkspace(config)
    end

    --- AppLaunchScripts:generateWorkspaceMethods()
    --- Method
    --- Regenerate availableWorkspaces.lua from workspaces/*.json and load
    --- it, defining one launch<Name>() method per workspace. Runs
    --- automatically when the Spoon loads; call it again after adding or
    --- removing workspace files.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateWorkspaceMethods()
        local lines = {
            "-- Generated by workspaces.lua from workspaces/*.json — do not edit.",
            "return function(obj)",
        }

        -- The method name comes from the config's "name" field, so a
        -- private file like privateCommunications.json can still expose
        -- launchGmailCommunications(). The file base name stays the
        -- launchWorkspace() argument.
        local launchers = {}

        for _, fileName in ipairs(self:workspaces()) do
            local config = self:loadWorkspace(fileName)

            if config then
                local method = "launch" .. methodSuffix(config.name or fileName)

                table.insert(launchers, method)
                table.insert(lines, string.format([[
    function obj:%s()
        return self:launchWorkspace(%q)
    end]], method, fileName))
            end
        end

        table.sort(launchers)
        obj._workspaceLaunchers = launchers

        -- Expose each launcher as a hammerspoon:// URL, e.g.
        -- hammerspoon://launchCommunications — for launchers that cannot
        -- pass shell arguments (Stream Deck's "System → Open" cannot;
        -- its "Website" action can open these URLs). The event name is
        -- a URL host, which browsers normalize to lowercase, so bind
        -- the lowercase form as well.
        for _, method in ipairs(launchers) do
            local handler = function()
                obj[method](obj)
            end

            hs.urlevent.bind(method, handler)
            hs.urlevent.bind(method:lower(), handler)
        end

        table.insert(lines, "end")

        local file = io.open(generatedFile(), "w")

        if not file then
            warn("Cannot write " .. generatedFile())
            return self
        end

        file:write(table.concat(lines, "\n") .. "\n")
        file:close()

        dofile(generatedFile())(self)

        return self
    end

    obj:generateWorkspaceMethods()
end
