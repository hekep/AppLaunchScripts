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

    -- Turn {direction = "horizontal", widths = {33, 33, 34}} into one unit
    -- rect per app. Missing sizes fall back to an even split.
    local function layoutUnits(layout, count)
        local direction = (layout and layout.direction) or "horizontal"
        local sizes = layout and (layout.widths or layout.heights)

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
                hs.alert.show(
                    "macOS refused to move a window to the target Space")
            end
        end

        window:moveToScreen(screen)
        window:focus()

        if unit then
            enforceUnit(window, screen, unit)
        end
    end

    -- Wait until a window of the given Chrome profile exists (on the
    -- given Space, when spaceID is set). Falls back to the main window:
    -- with a single active profile Chrome puts no profile suffix in
    -- window titles, so no title ever matches.
    local function waitForProfileWindow(app, profileName, spaceID, callback, attempts)
        attempts = attempts or 80

        local window = obj._findProfileWindow(app, profileName, spaceID)

        if window then
            callback(window)
            return
        end

        if attempts <= 0 then
            local fallback = app:mainWindow()

            if fallback then
                callback(fallback)
            else
                hs.alert.show("No window found for Chrome profile " .. profileName)
            end

            return
        end

        hs.timer.doAfter(0.15, function()
            waitForProfileWindow(app, profileName, spaceID, callback, attempts - 1)
        end)
    end

    -- One app entry with a "profile" key means Google Chrome with that
    -- profile; "www" optionally opens a URL in the new window.
    local function launchChromeProfileIntoSpace(appConfig, screen, spaceID, unit)
        local dir, profileName = obj._resolveChromeProfile(
            obj:chromeProfiles(), appConfig.profile)

        if not dir then
            hs.alert.show("Unknown Chrome profile: " .. appConfig.profile)
            return
        end

        local app = obj._getApp("Google Chrome")

        if app then
            -- Prefer a profile window already on the target Space; a
            -- window elsewhere is used only if macOS lets us move it.
            local existing = obj._findProfileWindow(app, profileName, spaceID)

            if existing then
                placeWindow(existing, screen, spaceID, unit)
                return
            end

            local elsewhere = obj._findProfileWindow(app, profileName)

            if elsewhere then
                hs.spaces.moveWindowToSpace(elsewhere, spaceID)

                if onSpace(elsewhere, spaceID) then
                    placeWindow(elsewhere, screen, spaceID, unit)
                    return
                end
            end
        end

        -- Open a fresh window; it appears on the currently focused Space,
        -- which applyWorkspace() has already switched to.
        local args = {
            "-na", "Google Chrome",
            "--args",
            "--profile-directory=" .. dir,
            "--new-window",
        }

        if appConfig.www then
            table.insert(args, appConfig.www)
        end

        hs.task.new("/usr/bin/open", nil, args):start()

        obj._waitForApp("Google Chrome", function(chromeApp)
            waitForProfileWindow(chromeApp, profileName, spaceID, function(window)
                placeWindow(window, screen, spaceID, unit)
            end)
        end)
    end

    -- Find a window whose title contains the given text (for apps like
    -- VS Code that host several project windows in one process, the
    -- title is the only thing identifying the project).
    local function findTitledWindow(app, needle)
        local lowered = needle:lower()

        for _, window in ipairs(app:allWindows()) do
            local title = (window:title() or ""):lower()

            if title:find(lowered, 1, true) then
                return window
            end
        end

        return nil
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
                hs.alert.show("No window found matching: " .. needle)
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
    local function launchIntoSpace(appConfig, screen, spaceID, unit)
        if appConfig.profile then
            launchChromeProfileIntoSpace(appConfig, screen, spaceID, unit)
            return
        end

        local appName = realAppName(appConfig.name)
        local app = obj._getApp(appName)

        if app and appConfig.window then
            local window = findTitledWindow(app, appConfig.window)

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
                hs.alert.show("Could not launch " .. appName)
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
            hs.alert.show("No workspace config: " .. name)
            return nil
        end

        local config = hs.json.decode(file:read("*a"))
        file:close()

        if not config then
            hs.alert.show("Invalid JSON in workspace: " .. name)
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
    function obj:applyWorkspace(config)
        hs.alert.show("Launching " .. config.name)

        -- 1. Resolve the target display
        local screen = resolveDisplay(config.space and config.space.display)

        -- 2. Resolve the target Space, creating missing Spaces on demand
        -- so a config can declare an index beyond what exists yet
        local spaceIDs = hs.spaces.spacesForScreen(screen) or {}
        local index = (config.space and config.space.index) or 1

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
            hs.alert.show(string.format(
                "No Space %d on %s (%d available)",
                index, screen:name(), #spaceIDs))
            return false
        end

        -- 4.-6. Launch or focus each app, move its window to the Space,
        -- and apply its slot of the layout.
        local function launchApps()
            local units = layoutUnits(config.layout, #(config.apps or {}))

            for i, appConfig in ipairs(config.apps or {}) do
                launchIntoSpace(appConfig, screen, spaceID, units[i])
            end
        end

        -- 3. Switch to that Space FIRST and wait for the switch to
        -- settle: new windows open on the focused Space, and on recent
        -- macOS that is the only reliable way to get them onto the
        -- target Space (moveWindowToSpace() silently fails there).
        if hs.spaces.focusedSpace() == spaceID then
            launchApps()
            return true
        end

        local ok, err = hs.spaces.gotoSpace(spaceID)

        if not ok then
            -- Usually a missing Accessibility permission. Proceed on the
            -- current Space so apps and layout still come up.
            hs.alert.show("Could not switch Space: " .. tostring(err))
            launchApps()
            return true
        end

        local attempts = 20

        local function waitForSwitch()
            if hs.spaces.focusedSpace() == spaceID or attempts <= 0 then
                launchApps()
                return
            end

            attempts = attempts - 1
            hs.timer.doAfter(0.15, waitForSwitch)
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
            hs.alert.show("Cannot write " .. generatedFile())
            return self
        end

        file:write(table.concat(lines, "\n") .. "\n")
        file:close()

        dofile(generatedFile())(self)

        return self
    end

    obj:generateWorkspaceMethods()
end
