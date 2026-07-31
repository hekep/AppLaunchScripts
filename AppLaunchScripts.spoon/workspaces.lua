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

    -- ====================== per-run logging ==========================
    -- Every workspace press writes its own log file:
    -- logs/<Name>_WS_<unixTimestamp>.log — every alert verbatim, each
    -- stage activation/pass, and the process exit reason.
    local currentRunLog = nil

    local function logsDir()
        return obj.spoonPath .. "logs/"
    end

    -- Run logging is opt-in via config/config.json:
    --   { "workSpaceRunLogs": true }
    -- Ships as false; set true locally while developing workspaces.
    -- Read fresh on every run so toggling needs no reload.
    local function runLogsEnabled()
        local file = io.open(obj.spoonPath .. "config/config.json", "r")

        if not file then
            return false
        end

        local config = hs.json.decode(file:read("*a"))
        file:close()

        return config ~= nil and config.workSpaceRunLogs == true
    end

    local function runLog(message)
        if not currentRunLog then
            return
        end

        local file = io.open(currentRunLog, "a")

        if not file then
            return
        end

        file:write(os.date("%Y-%m-%d %H:%M:%S") .. "  " .. message .. "\n")
        file:close()
    end

    local function startRunLog(name)
        if not runLogsEnabled() then
            currentRunLog = nil
            return
        end

        local now = hs.timer.secondsSinceEpoch()
        local seconds = math.floor(now)
        local micro = math.floor((now - seconds) * 1000000)

        currentRunLog = string.format("%s%s_WS_%d_%06d.log",
            logsDir(), methodSuffix(name or "Workspace"), seconds, micro)
        runLog(string.format('=== Workspace "%s" run started ===', name))
    end

    local function endRunLog(reason)
        runLog("PROCESS EXIT: " .. reason)
    end

    -- Alert + console print, so problems show up on screen AND in
    -- `hs -c` output / the Hammerspoon console. Error notifications
    -- stay visible for 8 seconds. Every alert also goes verbatim into
    -- the current run log.
    local function warn(message)
        hs.alert.show(message, 8)
        print("AppLaunchScripts: " .. message)
        runLog("ALERT: " .. message)
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

    -- Normalize a URL to its identifying fragment: scheme and "www."
    -- stripped, path kept — "https://www.x.com/SomeUser" becomes
    -- "x.com/SomeUser". The path matters: many tabs can share one host
    -- (e.g. several profiles on a social network) and must be told
    -- apart.
    local function siteKey(url)
        local key = url:gsub("^%a[%w+.-]*://", "")

        return (key:gsub("^www%.", ""))
    end

    -- apps[].www accepts a single URL or an array of URLs (one Chrome
    -- window holding one tab per URL).
    local function wwwList(www)
        if www == nil then
            return nil
        end

        if type(www) == "table" then
            return #www > 0 and www or nil
        end

        return { www }
    end

    local function siteKeys(urls)
        local keys = {}

        for _, url in ipairs(urls) do
            table.insert(keys, siteKey(url))
        end

        return keys
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

    -- How many of the entry's sites does the window hold, and how many
    -- tabs does it have in total?
    local function windowSiteHits(window, keys, info)
        if not info then
            return 0, 0
        end

        local prefix = windowNamePrefix(window)
        local bestHits = 0
        local bestTabs = 0

        for _, entry in ipairs(info) do
            if entry.name == prefix then
                local hits = 0

                for _, key in ipairs(keys) do
                    if entry.urls:find(key, 1, true) then
                        hits = hits + 1
                    end
                end

                local _, tabs = entry.urls:gsub(" ", "")

                if hits > bestHits then
                    bestHits = hits
                    bestTabs = tabs
                end
            end
        end

        return bestHits, bestTabs
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

    -- Pick the window that actually holds the wanted site(s); a window
    -- is "the Instagram window" only if one of its tabs is on instagram.
    local function pickSiteWindow(candidates, keys)
        if #candidates == 0 then
            return nil
        end

        if not keys then
            return candidates[1]
        end

        -- Score the candidates: the window holding the most of the
        -- entry's sites wins; ties go to the window with the fewest
        -- total tabs, so a dedicated site window beats a personal
        -- window that merely contains one matching tab.
        local info = chromeWindowsInfo()
        local best, bestHits, bestTabs

        for _, window in ipairs(candidates) do
            local hits, tabs = windowSiteHits(window, keys, info)

            if hits > 0 and (not best or hits > bestHits
                or (hits == bestHits and tabs < bestTabs)) then
                best = window
                bestHits = hits
                bestTabs = tabs
            end
        end

        return best
    end

    -- Wait until an unclaimed window of the given Chrome profile holding
    -- the given site exists on the Space. Site-aware so that two waiters
    -- for the same profile (e.g. Instagram and MeWe windows opening
    -- side by side) never grab each other's window. Falls back to any
    -- unclaimed profile window, then the main window.
    local function waitForProfileWindow(app, profileName, spaceID, claimed, keys, callback, attempts)
        attempts = attempts or 60

        local candidates = profileWindowsOnSpace(app, profileName, spaceID, claimed)
        local pick = pickSiteWindow(candidates, keys)

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
            waitForProfileWindow(app, profileName, spaceID, claimed, keys, callback, attempts - 1)
        end)
    end

    -- Restore the configured site inside an existing Chrome window:
    -- activate the first tab whose URL contains the site's host, or open
    -- a new tab on the site when no such tab exists. The AppleScript
    -- window is identified by the active-tab title, which the macOS
    -- window title (as seen by Hammerspoon) starts with. Requires the
    -- macOS Automation permission (Hammerspoon -> Google Chrome).
    -- Restore the configured tabs inside an existing Chrome window: for
    -- every configured URL, keep the tab matching its site key or open a
    -- new tab when it is missing; finally activate the first URL's tab.
    -- The target window is matched by its screen bounds (Hammerspoon
    -- knows the exact frame — deterministic even when several windows
    -- share a title like "New Tab"), then by tab content (most matching
    -- site keys wins), then — for single-URL entries only — by title.
    -- ABSOLUTE TEMPLATE SYNC: the workspace config is a strict
    -- template — tab position N must be URL N. Out-of-sync tabs are
    -- rewritten in place, missing tabs are created, extra tabs are
    -- deleted. Quarantined positions (chronically unstable sites) are
    -- accepted as-is so the stages can still complete.
    local function ensureChromeTabs(window, urls, skipKeys)
        local keyItems = {}
        local urlItems = {}
        local skipItems = {}

        for _, url in ipairs(urls) do
            local key = siteKey(url)

            table.insert(keyItems, string.format("%q", key))
            table.insert(urlItems, string.format("%q", url))
            table.insert(skipItems,
                (skipKeys and skipKeys[key]) and '"1"' or '"0"')
        end

        if #keyItems == 0 then
            return "synced"
        end

        local frame = window:frame()

        local script = string.format([[
            set hsTitle to %q
            set siteKeys to {%s}
            set siteURLs to {%s}
            set skipFlags to {%s}
            set allowNameFallback to %s
            set fLeft to %d
            set fTop to %d
            set fRight to %d
            set fBottom to %d
            set targetIdx to 0
            set boundsIdx to 0
            set bestHits to 0
            set nameIdx to 0
            tell application "Google Chrome"
                repeat with i from 1 to count of windows
                    try
                        set b to bounds of window i
                        if boundsIdx is 0 and (item 1 of b) > fLeft - 6 and (item 1 of b) < fLeft + 6 and (item 2 of b) > fTop - 6 and (item 2 of b) < fTop + 6 and (item 3 of b) > fRight - 6 and (item 3 of b) < fRight + 6 and (item 4 of b) > fBottom - 6 and (item 4 of b) < fBottom + 6 then
                            set boundsIdx to i
                        end if
                        set hits to 0
                        repeat with j from 1 to count of tabs of window i
                            try
                                set tabURL to URL of tab j of window i
                                repeat with k from 1 to count of siteKeys
                                    if tabURL contains (item k of siteKeys) then
                                        set hits to hits + 1
                                    end if
                                end repeat
                            end try
                        end repeat
                        if hits > bestHits then
                            set bestHits to hits
                            set targetIdx to i
                        end if
                        if nameIdx is 0 and (name of window i) is not "" and hsTitle starts with (name of window i) then
                            set nameIdx to i
                        end if
                    end try
                end repeat
                set matchMethod to "content"
                if boundsIdx is not 0 then
                    set targetIdx to boundsIdx
                    set matchMethod to "bounds"
                end if
                if targetIdx is 0 and allowNameFallback then
                    set targetIdx to nameIdx
                    set matchMethod to "title"
                end if
                if targetIdx is 0 then
                    return "window not found"
                end if
                set changes to ""
                repeat with k from 1 to count of siteKeys
                    if (item k of skipFlags) is "1" then
                        set changes to changes & "|skip:" & (item k of siteKeys)
                    else if (count of tabs of window targetIdx) < k then
                        make new tab at end of tabs of window targetIdx with properties {URL:(item k of siteURLs)}
                        set changes to changes & "|new:" & (item k of siteKeys)
                        delay 1
                    else
                        set inSync to false
                        try
                            if (URL of tab k of window targetIdx) contains (item k of siteKeys) then
                                set inSync to true
                            end if
                        end try
                        if inSync then
                            set changes to changes & "|ok:" & (item k of siteKeys)
                        else
                            set URL of tab k of window targetIdx to (item k of siteURLs)
                            set changes to changes & "|set:" & (item k of siteKeys)
                            delay 1
                        end if
                    end if
                end repeat
                set extraCount to (count of tabs of window targetIdx) - (count of siteKeys)
                repeat while (count of tabs of window targetIdx) > (count of siteKeys)
                    close tab ((count of siteKeys) + 1) of window targetIdx
                end repeat
                if extraCount > 0 then
                    set changes to changes & "|closed:" & extraCount
                end if
                set active tab index of window targetIdx to 1
                return "synced[window " & targetIdx & " via " & matchMethod & "]" & changes
            end tell
        ]], window:title() or "",
            table.concat(keyItems, ", "),
            table.concat(urlItems, ", "),
            table.concat(skipItems, ", "),
            -- With several URLs, a window without any matching tab is
            -- never a valid target — a blind name fallback once sent a
            -- whole tab set into the wrong window. A single-URL entry
            -- may legitimately have its only site tab closed, so the
            -- name fallback stays allowed there.
            (#urls == 1) and "true" or "false",
            math.floor(frame.x), math.floor(frame.y),
            math.floor(frame.x + frame.w), math.floor(frame.y + frame.h))

        local ok, result = hs.osascript.applescript(script)

        if not ok then
            local detail = type(result) == "table"
                and (result.NSLocalizedDescription or hs.inspect(result))
                or tostring(result)
            runLog("ERROR: tab restore AppleScript failed: "
                .. tostring(detail):sub(1, 300))
            warn("Chrome tab restore failed — see run log")
            return "failed"
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

        local urls = wwwList(appConfig.www)
        local keys = urls and siteKeys(urls) or nil
        local primaryKey = keys and keys[1] or nil
        local app = obj._getApp("Google Chrome")

        if app then
            local candidates = profileWindowsOnSpace(
                app, profileName, spaceID, claimed)
            local pick = pickSiteWindow(candidates, keys)

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

                if urls then
                    ensureChromeTabs(pick, urls)
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
        if primaryKey then
            local info = chromeWindowsInfo()
            local existingCount = 0

            for _, entry in ipairs(info or {}) do
                if entry.urls:find(primaryKey, 1, true) then
                    local hits = 0

                    for _, key in ipairs(keys) do
                        if entry.urls:find(key, 1, true) then
                            hits = hits + 1
                        end
                    end

                    local _, tabs = entry.urls:gsub(" ", "")

                    -- Only count windows that are mostly this entry's
                    -- sites — a personal window that merely contains
                    -- one matching tab must not block the workspace
                    -- window from opening.
                    if tabs > 0 and hits / tabs > 0.5 then
                        existingCount = existingCount + 1
                    end
                end
            end

            if existingCount >= (context.hostCounts[primaryKey] or 1) then
                return "elsewhere"
            end
        end

        -- Open a fresh window; it appears on the currently focused Space,
        -- which applyWorkspace() has already switched to. Openings are
        -- staggered: near-simultaneous open commands can collapse into
        -- tabs of a single window. When Chrome is already running, its
        -- second-instance handoff sometimes routes the URLs into an
        -- existing window — open with only the FIRST URL then (small
        -- blast radius) and let the post-open tab restore add the rest,
        -- bounds-targeted, into the right window.
        -- Windows always open with exactly ONE URL: Chrome shreds
        -- multi-URL open commands across arbitrary windows (verified
        -- even on cold starts). The remaining tabs are built afterwards
        -- by the AppleScript tab restore, which is deterministic.
        local function fireOpen()
            local args = {
                "-na", "Google Chrome",
                "--args",
                "--profile-directory=" .. dir,
                "--new-window",
            }

            if urls then
                table.insert(args, urls[1])
            end

            hs.task.new("/usr/bin/open", nil, args):start()
        end

        -- SERIALIZED opens: overlapping open commands during Chrome's
        -- startup get shredded across arbitrary windows, so each entry's
        -- open fires only after the previous entry's window exists.
        context.openQueue = context.openQueue or { jobs = {}, running = false }
        local queue = context.openQueue

        local function runNext()
            if queue.running then
                return
            end

            local job = table.remove(queue.jobs, 1)

            if not job then
                if (queue.startedJobs or 0) > 0 then
                    queue.startedJobs = 0

                    if context.onQueueDrained then
                        local chained = context.onQueueDrained
                        context.onQueueDrained = nil
                        chained()
                    else
                        endRunLog("Cold launch successful")
                    end
                end

                return
            end

            queue.startedJobs = (queue.startedJobs or 0) + 1
            queue.running = true

            job(function()
                queue.running = false
                runNext()
            end)
        end

        table.insert(queue.jobs, function(done)
            local finished = false
            local windowFound = false

            local function finish()
                if not finished then
                    finished = true
                    done()
                end
            end

            fireOpen()
            runLog(string.format("open fired: profile %s, url %s",
                tostring(profileName), urls and urls[1] or "-"))

            -- Re-issue once if the handoff dropped the command — but
            -- never after the window has been found (it is claimed by
            -- then, so re-checking the unclaimed candidates would
            -- always look empty and spawn an extra window).
            hs.timer.doAfter(8, function()
                if finished or windowFound then
                    return
                end

                local chromeNow = obj._getApp("Google Chrome")
                local candidates = chromeNow and profileWindowsOnSpace(
                    chromeNow, profileName, spaceID, claimed) or {}

                if not pickSiteWindow(candidates, keys) then
                    runLog("open re-issued (command appears dropped): "
                        .. tostring(profileName))
                    fireOpen()
                end
            end)

            obj._waitForApp("Google Chrome", function(chromeNow)
                waitForProfileWindow(chromeNow, profileName, spaceID, claimed, keys, function(window)
                    windowFound = true
                    runLog("window found: " .. tostring(profileName)
                        .. " — placing")
                    -- One window at a time: place it, fill its tabs,
                    -- give Chrome a second to settle — only then does
                    -- the next window open.
                    placeWindow(window, screen, spaceID, unit)

                    hs.timer.doAfter(1.5, function()
                        if urls and #urls > 1 then
                            local result = ensureChromeTabs(window, urls)
                            runLog("tabs filled: " .. tostring(profileName)
                                .. " -> " .. tostring(result))
                        end

                        hs.timer.doAfter(1, finish)
                    end)
                end)
            end)

            -- Never gate the queue forever.
            hs.timer.doAfter(40, function()
                if not finished then
                    runLog("job timeout (40s) — releasing open queue: "
                        .. tostring(profileName))
                end

                finish()
            end)
        end)

        runNext()

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

    -- ================= window size toggling (config/windowSizes.json) =
    -- A workspace whose layout widths match a profile's initialSizes
    -- gains a size-cycling button: once everything is launched, tabs
    -- are complete, and the desktop is already focused, each press
    -- moves the windows to the next entry of toggleSizes (a 0 minimizes
    -- that window), wrapping back to initialSizes.

    local function loadSizeProfiles()
        local file = io.open(obj.spoonPath .. "config/windowSizes.json", "r")

        if not file then
            return nil
        end

        local data = hs.json.decode(file:read("*a"))
        file:close()

        if not data then
            warn("Invalid JSON in config/windowSizes.json")
        end

        return data
    end

    local function vectorsEqual(a, b)
        if #a ~= #b then
            return false
        end

        for i = 1, #a do
            if a[i] ~= b[i] then
                return false
            end
        end

        return true
    end

    -- The workspace's widths select the profile whose initialSizes match.
    local function findSizesProfile(widths)
        if not widths then
            return nil
        end

        for _, profile in ipairs(loadSizeProfiles() or {}) do
            if type(profile.initialSizes) == "table"
                and vectorsEqual(profile.initialSizes, widths) then
                local toggles = {}

                for _, toggle in ipairs(profile.toggleSizes or {}) do
                    if type(toggle) == "table" and #toggle == #widths then
                        table.insert(toggles, toggle)
                    else
                        warn("windowSizes.json: skipped a toggle with the wrong value count")
                    end
                end

                if #toggles > 0 then
                    return { initial = profile.initialSizes, toggles = toggles }
                end
            end
        end

        return nil
    end

    -- Current sizes of the workspace windows as percentages of the
    -- screen (minimized windows count as 0).
    local function measureSizes(windows, screen, direction)
        local screenFrame = screen:frame()
        local sizes = {}

        for _, window in ipairs(windows) do
            if window:isMinimized() then
                table.insert(sizes, 0)
            else
                local frame = window:frame()

                if direction == "vertical" then
                    table.insert(sizes, frame.h / screenFrame.h * 100)
                else
                    table.insert(sizes, frame.w / screenFrame.w * 100)
                end
            end
        end

        return sizes
    end

    local function sizesMatch(measured, expected)
        for i = 1, #expected do
            local want = expected[i]
            local have = measured[i] or -100

            if want <= 0 then
                if have > 5 then
                    return false
                end
            elseif math.abs(have - want) > 6 then
                return false
            end
        end

        return true
    end

    -- Which known state are the windows in? 0 = initialSizes,
    -- N = toggleSizes[N], nil = unrecognized.
    local function matchSizesState(measured, profile)
        if sizesMatch(measured, profile.initial) then
            return 0
        end

        for i, toggle in ipairs(profile.toggles) do
            if sizesMatch(measured, toggle) then
                return i
            end
        end

        return nil
    end

    -- Apply one sizes vector: zero-size windows are minimized, the rest
    -- are laid out in order (zeros take no room).
    local function applySizes(windows, screen, direction, sizes)
        local offset = 0

        for i, window in ipairs(windows) do
            local size = sizes[i] or 0

            if size <= 0 then
                if not window:isMinimized() then
                    window:minimize()
                end
            else
                if window:isMinimized() then
                    window:unminimize()
                end

                local unit

                if direction == "vertical" then
                    unit = { x = 0, y = offset, w = 1, h = size / 100 }
                else
                    unit = { x = offset, y = 0, w = size / 100, h = 1 }
                end

                window:focus()
                enforceUnit(window, screen, unit)
                offset = offset + size / 100
            end
        end
    end

    -- Find the already-open window for one app entry on the Space (a
    -- minimized window counts), or nil when the entry still needs
    -- launching. Used to decide between launch, repair, and size-toggle
    -- presses.
    local function resolveEntryWindow(appConfig, spaceID, claimed, context)
        if appConfig.profile then
            local dir, profileName = obj._resolveChromeProfile(
                obj:chromeProfiles(), appConfig.profile)

            if not dir then
                return nil
            end

            local app = obj._getApp("Google Chrome")

            if not app then
                return nil
            end

            local urls = wwwList(appConfig.www)
            local keys = urls and siteKeys(urls) or nil
            local candidates = profileWindowsOnSpace(
                app, profileName, spaceID, claimed)
            local pick = pickSiteWindow(candidates, keys)

            if not pick and #candidates > 0
                and (context.profileCounts[dir] or 0) <= 1 then
                pick = candidates[1]
            end

            if pick then
                claimWindow(claimed, pick)
            end

            return pick, urls
        end

        local app = obj._getApp(realAppName(appConfig.name))

        if not app then
            return nil
        end

        local window

        if appConfig.window then
            window = findTitledWindow(app, appConfig.window)
        else
            window = app:mainWindow()
        end

        if window and (window:isMinimized() or onSpace(window, spaceID)) then
            claimWindow(claimed, window)
            return window
        end

        return nil
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

    -- A cold launch in progress must never be overlapped by another
    -- process for the same workspace (duplicate windows). Timestamped
    -- so a crashed launch cannot lock the workspace forever.
    local launchInFlight = {}
    local LAUNCH_IN_FLIGHT_MAX = 120

    -- Site keys that reopened on two consecutive presses never match
    -- their tab (the site redirects elsewhere) — they get skipped with
    -- a warning so the repair stage can finish instead of looping.
    local unmatchableKeys = {}
    local lastReopenedKeys = {}

    function obj:applyWorkspace(config)
        local now = hs.timer.secondsSinceEpoch()
        local last = launchTimes[config.name]

        if last and (now - last) < LAUNCH_LOCKOUT then
            -- Each ignored press still gets its own log file, without
            -- hijacking the in-flight run's log.
            local inFlightLog = currentRunLog

            startRunLog(config.name)
            warn(string.format(
                'Workspace "%s" is still launching — press ignored (wait %ds)',
                config.name, math.ceil(LAUNCH_LOCKOUT - (now - last))))
            endRunLog("ABORTED: press ignored — previous launch still in progress (lockout)")
            currentRunLog = inFlightLog

            return false
        end

        local inFlightSince = launchInFlight[config.name]

        if inFlightSince and (now - inFlightSince) < LAUNCH_IN_FLIGHT_MAX then
            local prevLog = currentRunLog

            startRunLog(config.name)
            warn(string.format(
                'Workspace "%s": cold launch still in progress — press ignored',
                config.name))
            endRunLog("ABORTED: cold launch already in progress (duplicate process avoided)")
            currentRunLog = prevLog

            return false
        end

        launchTimes[config.name] = now

        startRunLog(config.name)

        hs.alert.show("Launching " .. config.name)
        runLog('NOTIFY: Launching ' .. (config.name or "?"))

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
            runLog(string.format(
                "NOTIFY: Created Space %d on %s", #spaceIDs + 1, screen:name()))

            spaceIDs = hs.spaces.spacesForScreen(screen) or {}
        end

        local spaceID = spaceIDs[index]

        -- Captured at press time: a press that still has to switch
        -- desktops never toggles sizes. Compared against the desktop
        -- the workspace actually runs on (which the fallback search may
        -- change).
        local pressFocusedSpace = hs.spaces.focusedSpace()

        runLog(string.format(
            "target desktop %d (space %s); focused space at press: %s",
            index, tostring(spaceID), tostring(pressFocusedSpace)))

        if not spaceID then
            warn(string.format(
                "No Space %d on %s (%d available)",
                index, screen:name(), #spaceIDs))
            endRunLog("ABORTED: target desktop does not exist")
            return false
        end

        -- 4.-6. Launch or focus each app, move its window to the Space,
        -- and apply its slot of the layout.
        local function launchApps(runSpaceID, isValidation)
            runLog(string.format("launchApps: start (space %s, validation=%s)",
                tostring(runSpaceID), tostring(isValidation or false)))

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

                    local urls = wwwList(appConfig.www)

                    if urls then
                        local primaryKey = siteKey(urls[1])
                        context.hostCounts[primaryKey] =
                            (context.hostCounts[primaryKey] or 0) + 1
                    end
                end
            end

            -- Press state machine: when every window of the workspace
            -- already exists on the desktop, the press repairs missing
            -- tabs, activates the desktop, or toggles the window sizes
            -- (config/windowSizes.json) — instead of launching.
            local apps = config.apps or {}
            local preClaimed = {}
            local windows = {}
            local urlsPerEntry = {}
            local complete = #apps > 0

            -- Chrome windows are linked to entries by POSITION: the
            -- user keeps window order, so within each profile the
            -- workspace's windows map to its entries left-to-right.
            -- Content only helps to exclude personal windows (they hold
            -- none of the workspace's sites) and to slot minimized
            -- windows, whose x-position is meaningless.
            local groups = {}

            for i, appConfig in ipairs(apps) do
                if appConfig.profile then
                    local dir, profileName = obj._resolveChromeProfile(
                        obj:chromeProfiles(), appConfig.profile)

                    if dir then
                        groups[dir] = groups[dir]
                            or { name = profileName, entries = {} }
                        table.insert(groups[dir].entries, i)
                        urlsPerEntry[i] = wwwList(appConfig.www)
                    else
                        complete = false
                    end
                end
            end

            local chromeApp = obj._getApp("Google Chrome")

            runLog("launchApps: context built, resolving windows")

            for _, group in pairs(groups) do
                local candidates = chromeApp and profileWindowsOnSpace(
                    chromeApp, group.name, runSpaceID, preClaimed) or {}
                local visible = {}
                local minimized = {}

                for _, w in ipairs(candidates) do
                    if w:isMinimized() then
                        table.insert(minimized, w)
                    else
                        table.insert(visible, w)
                    end
                end

                -- Drop personal windows: with more windows than entries,
                -- keep only windows holding at least one workspace site.
                if #visible + #minimized > #group.entries then
                    local unionKeys = {}

                    for _, i in ipairs(group.entries) do
                        for _, key in ipairs(siteKeys(urlsPerEntry[i] or {})) do
                            table.insert(unionKeys, key)
                        end
                    end

                    if #unionKeys > 0 then
                        local info = chromeWindowsInfo()
                        local keep = {}

                        for _, w in ipairs(visible) do
                            if windowSiteHits(w, unionKeys, info) > 0 then
                                table.insert(keep, w)
                            end
                        end

                        if #keep + #minimized >= #group.entries then
                            visible = keep
                        end
                    end
                end

                table.sort(visible, function(a, b)
                    return a:frame().x < b:frame().x
                end)

                -- CONTENT FIRST: a window's tabs are the ground truth
                -- of its identity — if the windows ever physically swap
                -- places, position-mapping would enforce the swap by
                -- cross-filling tabs. Position only assigns windows
                -- that hold none of their entry's sites; the placement
                -- step then moves every window back to its proper slot.
                local leftoverEntries = {}

                for _, i in ipairs(group.entries) do
                    local pick = chromeApp and pickSiteWindow(
                        profileWindowsOnSpace(chromeApp, group.name,
                            runSpaceID, preClaimed),
                        siteKeys(urlsPerEntry[i] or {})) or nil

                    if pick then
                        windows[i] = pick
                        claimWindow(preClaimed, pick)
                        runLog(string.format(
                            "resolve: entry %d matched by tab content", i))
                    else
                        table.insert(leftoverEntries, i)
                    end
                end

                local leftoverWindows = {}

                for _, w in ipairs(visible) do
                    if not (w:id() and preClaimed[w:id()]) then
                        table.insert(leftoverWindows, w)
                    end
                end

                for _, w in ipairs(minimized) do
                    if not (w:id() and preClaimed[w:id()]) then
                        table.insert(leftoverWindows, w)
                    end
                end

                if #leftoverWindows >= #leftoverEntries then
                    for k, i in ipairs(leftoverEntries) do
                        windows[i] = leftoverWindows[k]
                        claimWindow(preClaimed, leftoverWindows[k])
                        runLog(string.format(
                            "resolve: entry %d assigned by position (no content match)", i))
                    end
                else
                    complete = false
                end
            end

            -- Non-Chrome entries keep the title/main-window resolution.
            for i, appConfig in ipairs(apps) do
                if not appConfig.profile then
                    local window = resolveEntryWindow(
                        appConfig, runSpaceID, preClaimed, context)
                    windows[i] = window

                    if not window then
                        complete = false
                    end
                end
            end

            for i in ipairs(apps) do
                if not windows[i] then
                    complete = false
                    break
                end
            end

            for i in ipairs(apps) do
                runLog(string.format("resolve: entry %d -> %s", i,
                    windows[i] and "window found" or "MISSING"))
            end

            runLog("Stage 1 (windows) " .. (complete
                and "PASSED: all windows present"
                or "ACTIVATED: windows missing, launching"))

            if complete then
                local focusedAtPress = pressFocusedSpace == runSpaceID
                local direction = (config.layout and config.layout.direction)
                    or "horizontal"
                local widths = config.layout
                    and (config.layout.widths or config.layout.heights)
                local profile = findSizesProfile(widths)
                local measured = measureSizes(windows, screen, direction)

                -- Repair pass: reopen missing tabs. A press that had to
                -- repair does not toggle sizes. Keys that reopen twice
                -- in a row never match their tab (redirecting site):
                -- warn once, then skip them so the stage can complete.
                local wsName = config.name or "?"
                local skip = unmatchableKeys[wsName] or {}
                local openedNow = {}
                local reopened = 0

                local repairFailed = false

                for i in ipairs(apps) do
                    if urlsPerEntry[i] and windows[i] then
                        local result = ensureChromeTabs(
                            windows[i], urlsPerEntry[i], skip) or ""

                        local targetInfo = result:match("^synced(%b[])")

                        if targetInfo then
                            runLog(string.format(
                                "entry %d restore target %s", i, targetInfo))
                        end

                        if result == "failed" or result == "window not found" then
                            runLog(string.format(
                                "entry %d tab restore: %s", i, result))
                            repairFailed = true
                        end

                        local position = 0

                        for status, key in result:gmatch("|(%a+):([^|]+)") do
                            position = position + 1

                            if status == "ok" then
                                runLog(string.format(
                                    'Testing: App %d, tab %d expecting "%s": IN SYNC',
                                    i, position, key))
                            elseif status == "skip" then
                                runLog(string.format(
                                    'Testing: App %d, tab %d "%s": SKIPPED (accepted — unstable site)',
                                    i, position, key))
                            elseif status == "set" then
                                runLog(string.format(
                                    'REPAIR: App %d, tab %d rewritten to "%s" (was out of sync)',
                                    i, position, key))
                                openedNow[key] = true
                                reopened = reopened + 1
                            elseif status == "new" then
                                runLog(string.format(
                                    'REPAIR: App %d, tab %d created "%s"',
                                    i, position, key))
                                openedNow[key] = true
                                reopened = reopened + 1
                            elseif status == "closed" then
                                position = position - 1
                                runLog(string.format(
                                    'REPAIR: App %d, deleted %s extra tab(s)',
                                    i, key))
                                reopened = reopened + (tonumber(key) or 1)
                            end
                        end

                        if result ~= "failed" and result ~= "window not found" then
                            runLog(string.format(
                                "Testing: App %d, template check complete", i))
                        end
                    end
                end

                if repairFailed then
                    endRunLog("Repair stage FAILED — tab restore error (see above); not advancing")
                    return 0, 0
                end

                -- Cumulative per-session counting: sites that keep
                -- mutating their tab URL (e.g. rate-limited profile
                -- pages) get restored at most twice, then skipped.
                local counts = lastReopenedKeys[wsName] or {}

                for key in pairs(openedNow) do
                    counts[key] = (counts[key] or 0) + 1

                    if counts[key] >= 2 then
                        unmatchableKeys[wsName] = unmatchableKeys[wsName] or {}
                        unmatchableKeys[wsName][key] = true
                        warn(string.format(
                            'Tab keeps losing its URL (site redirects/rate-limits?) — skipping from now on: %s',
                            key))
                    end
                end

                lastReopenedKeys[wsName] = counts

                if reopened > 0 then
                    warn(string.format('Workspace "%s": %d tab(s) restored',
                        wsName, reopened))
                    runLog(string.format(
                        "Stage 2 (tabs) ACTIVATED: %d tab(s) restored", reopened))
                    runLog("STAGE 2 had repairing tasks, SO EXITING now.")
                    endRunLog(isValidation
                        and string.format(
                            "Cold launch successful — validation repaired %d tab(s)",
                            reopened)
                        or "Repair stage successful, exit")
                    return 0, 0
                end

                runLog("STAGE 2 passed")

                if isValidation then
                    -- Cold-launch validation verifies only — never
                    -- toggles sizes.
                    endRunLog("Cold launch successful — all windows and tabs verified")
                    return 0, 0
                end

                -- Repair and toggle presses finish synchronously — no
                -- async launch to protect. Clear the lockout so sizes
                -- can be cycled with quick repeated presses.
                launchTimes[config.name] = nil

                if profile then
                    local state = matchSizesState(measured, profile)
                    local targetSizes

                    if reopened > 0 or not focusedAtPress then
                        -- Repair or desktop-activation press: keep a
                        -- recognized size state, normalize anything else
                        -- to the initial sizes.
                        if state == nil or state == 0 then
                            targetSizes = profile.initial
                        else
                            targetSizes = profile.toggles[state]
                        end
                    elseif state == nil then
                        targetSizes = profile.initial
                    elseif state == 0 then
                        targetSizes = profile.toggles[1]
                    elseif state == #profile.toggles then
                        targetSizes = profile.initial
                    else
                        targetSizes = profile.toggles[state + 1]
                    end

                    runLog(string.format(
                        "Stage 3 (resize): current state=%s -> target=[%s]",
                        tostring(state), table.concat(targetSizes, ", ")))

                    for _, window in ipairs(windows) do
                        if not window:isMinimized() then
                            if not onSpace(window, runSpaceID) then
                                hs.spaces.moveWindowToSpace(window, runSpaceID)
                            end

                            window:moveToScreen(screen)
                        end
                    end

                    applySizes(windows, screen, direction, targetSizes)

                    if reopened > 0 then
                        endRunLog("Repair stage successful, exit")
                    elseif not focusedAtPress then
                        endRunLog("Desktop activated, sizes kept/normalized — exit")
                    else
                        endRunLog("Resize stage successful — all 3 stages checked, valid, done")
                    end

                    return 0, 0
                end

                -- No sizes profile: classic placement of the adopted
                -- windows.
                for i, window in ipairs(windows) do
                    placeWindow(window, screen, runSpaceID, units[i])
                end

                if reopened > 0 then
                    endRunLog("Repair stage successful, exit")
                else
                    endRunLog("All stages valid — layout re-asserted, done")
                end

                return 0, 0
            end

            -- Launch pass: at least one window is missing.
            if isValidation then
                endRunLog("Cold launch FAILED — window(s) still missing after launch; not relaunching")
                return 0, 0
            end

            -- A fresh launch gives every site a fresh chance.
            unmatchableKeys[config.name or "?"] = nil
            lastReopenedKeys[config.name or "?"] = nil
            runLog("quarantine reset (cold launch)")

            -- Chain stage 2 validation onto the end of the open queue.
            context.onQueueDrained = function()
                launchInFlight[config.name or "?"] = nil
                runLog("Cold launch: all windows opened — validating (stage 2)")

                local okRun, errRun = pcall(launchApps, runSpaceID, true)

                if not okRun then
                    runLog("ERROR: internal failure: " .. tostring(errRun))
                    endRunLog("FAILED: internal error — see log")
                end
            end

            local wwwEntries = 0
            local elsewhereCount = 0

            for i, appConfig in ipairs(apps) do
                local status = launchIntoSpace(
                    appConfig, screen, runSpaceID, units[i], context)

                runLog(string.format(
                    "entry %d launch status: %s", i, tostring(status)))

                if status == "opened" then
                    launchInFlight[config.name or "?"] =
                        hs.timer.secondsSinceEpoch()
                end

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

                        if pickSiteWindow(candidates,
                            siteKeys(wwwList(appConfig.www))) then
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
                    endRunLog("ABORTED: existing windows could not be located")
                    return
                end

                local target = order[pos]

                hs.spaces.gotoSpace(target.id)

                hs.timer.doAfter(1.2, function()
                    runLog("fallback: probing desktop " .. target.index)

                    if hs.spaces.focusedSpace() == target.id
                        and probeSpace(target.id) then
                        warn(string.format(
                            'Unable to open apps on "Desktop %d" — using "Desktop %d" where the windows already are',
                            index, target.index))

                        local okRun, errRun = pcall(launchApps, target.id)

                        if not okRun then
                            runLog("ERROR: internal failure: " .. tostring(errRun))
                            endRunLog("FAILED: internal error — see log")
                        end
                    else
                        nextSpace()
                    end
                end)
            end

            nextSpace()
        end

        local function runOnTarget()
            local ok, wwwEntries, elsewhereCount = pcall(launchApps, spaceID)

            if not ok then
                runLog("ERROR: internal failure: " .. tostring(wwwEntries))
                endRunLog("FAILED: internal error — see log")
                return
            end

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
            runLog("already on target desktop")
            runOnTarget()
            return true
        end

        local ok, err = hs.spaces.gotoSpace(spaceID)

        if not ok then
            -- Usually a missing Accessibility permission. Better no
            -- action than windows created on the wrong desktop.
            warn("Could not switch Space: " .. tostring(err))
            endRunLog("ABORTED: could not switch Space")
            return false
        end

        local attempts = 40

        local function waitForSwitch()
            if hs.spaces.focusedSpace() == spaceID then
                runLog("desktop switch settled")
                runOnTarget()
                return
            end

            attempts = attempts - 1

            if attempts <= 0 then
                warn(string.format(
                    'Workspace "%s": Space switch did not complete — aborting to avoid duplicate windows',
                    config.name))
                endRunLog("ABORTED: Space switch did not complete")
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
