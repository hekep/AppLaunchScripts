-- Windows App (Microsoft Remote Desktop) integration for
-- AppLaunchScripts.
--
-- Saved PCs are AUTO-DISCOVERED from Windows App's local SQLite
-- bookmark database (hostnames and friendly names only — credentials
-- live in the Keychain and are never touched) and merged into
-- config/windowsapp/Pcs.json (gitignored — hostnames are personal):
--
--   {
--     "pcs": [
--       { "name": "Office PC", "host": "10.0.0.5", "title": "Office PC" },
--       { "name": "10009",     "host": "10.0.0.9" }
--     ]
--   }
--
-- "name" is your button alias (free-form; CamelCased into the method
-- name) and is ALWAYS written out ready to edit — prefilled from the
-- PC's friendly name, or from the address itself when Windows App has
-- none ("10.0.0.9" -> "10009"). "host" is the address (also how the
-- PC's tile is found), "title" an optional window-title fragment
-- identifying the session window. Discovery appends unseen PCs and
-- replaces only names still equal to that address-derived default; a
-- name you wrote is never overwritten. PCs the scan cannot see can be
-- declared by hand the same way.
--
-- Reading the database needs a one-time macOS "access data from
-- other apps" Allow for Hammerspoon; when denied, discovery silently
-- skips and declared entries keep working.
--
-- For every entry a method is generated into
-- availableWindowsAppComms.lua:
--   launchWindowsApp()                      -- the app itself, as-is
--   launchWindowsApp<Name>Pc()
-- plus hammerspoon:// URL twins for Stream Deck.
--
-- Windows App is MULTI-window: the hub window plus one window per
-- live connection, titled with the host (or the PC's friendly name).
-- A press focuses the existing session window when there is one,
-- otherwise it starts the connection by pressing that PC's tile in
-- the hub window's "Saved Devices" list, exactly as a click would.
-- Windows App then shows its own credential prompt when nothing is
-- saved.
--
-- WHY TILE PRESSING: every scriptable route is dead on macOS 26.
-- "rdp://full%20address=s:host" is rejected by NSURL before it
-- reaches the app; the plain "rdp://host" form makes Windows App
-- answer "The URL is not valid"; and opening a generated .rdp file
-- only adds it to the app's Open Recent menu without connecting.
-- Pressing the tile (hs.axuielement, AXPress) is the one route that
-- provably connects — so buttons exist for the PCs SAVED in Windows
-- App. A configured host with no saved PC is reported: add it in
-- Windows App once, and its button works from then on.
--
-- Tile pressing needs Accessibility permission for Hammerspoon
-- (already required by the workspace engine).
--
-- Loaded from init.lua as: dofile(obj.spoonPath .. "windowsapp.lua")(obj)

return function(obj)

    local appName = "Windows App"

    local function configDir()
        return obj.spoonPath .. "config/windowsapp/"
    end

    local function configFile()
        return configDir() .. "Pcs.json"
    end

    local function generatedFile()
        return obj.spoonPath .. "availableWindowsAppComms.lua"
    end

    local function notify(message)
        hs.alert.show(message, 8)
        print("AppLaunchScripts/windowsapp: " .. message)
    end

    -- Same rules as slack.lua: Lua identifiers are ASCII-only, so
    -- accented letters are transliterated ("Väinö Äikäs" -> "VainoAikas").
    local transliterations = {
        ["ä"] = "a", ["Ä"] = "A", ["ö"] = "o", ["Ö"] = "O",
        ["å"] = "a", ["Å"] = "A", ["ü"] = "u", ["Ü"] = "U",
        ["é"] = "e", ["è"] = "e", ["É"] = "E", ["ß"] = "ss",
        ["ø"] = "o", ["Ø"] = "O", ["æ"] = "ae", ["Æ"] = "Ae",
    }

    local function camelize(name)
        local ascii = tostring(name):gsub("[\xC0-\xFF][\x80-\xBF]*", function(seq)
            return transliterations[seq] or ""
        end)

        local parts = {}

        for word in ascii:gmatch("%w+") do
            table.insert(parts, word:sub(1, 1):upper() .. word:sub(2))
        end

        return table.concat(parts)
    end

    local function readJson(path)
        local file = io.open(path, "r")

        if not file then
            return nil
        end

        local config = hs.json.decode(file:read("*a"))
        file:close()

        return config
    end

    local function writeJson(path, config)
        local file = io.open(path, "w")

        if file then
            file:write(hs.json.encode(config, true) .. "\n")
            file:close()
        end
    end

    --- AppLaunchScripts:windowsAppDevices()
    --- Method
    --- List the PCs saved in Windows App, read from its local SQLite
    --- bookmark database (hostname and friendly name only).
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A list of `{ host, name }` entries (name may be nil); empty when Windows App is not installed or the database is not readable (e.g. the one-time "app data" permission was denied)
    function obj:windowsAppDevices()
        local devices = {}

        local ok = pcall(function()
            local sqlite3 = require("hs.sqlite3")
            local path = os.getenv("HOME")
                .. "/Library/Containers/com.microsoft.rdc.macos/Data"
                .. "/Library/Application Support/com.microsoft.rdc.macos"
                .. "/com.microsoft.rdc.application-data.sqlite"

            local db = sqlite3.open(path, sqlite3.OPEN_READONLY)

            if not db then
                return
            end

            for row in db:nrows(
                "SELECT ZHOSTNAME, ZFRIENDLYNAME FROM ZBOOKMARKENTITY") do
                if row.ZHOSTNAME and row.ZHOSTNAME ~= "" then
                    table.insert(devices, {
                        host = row.ZHOSTNAME,
                        name = (row.ZFRIENDLYNAME and row.ZFRIENDLYNAME ~= "")
                            and row.ZFRIENDLYNAME or nil,
                    })
                end
            end

            db:close()
        end)

        if not ok then
            return {}
        end

        return devices
    end

    --- AppLaunchScripts:windowsAppComms()
    --- Method
    --- Load the declared PCs from config/windowsapp/Pcs.json.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A list of `{ name, host, title }` entries
    function obj:windowsAppComms()
        local config = readJson(configFile())

        return config and config.pcs or {}
    end

    --- AppLaunchScripts:launchWindowsApp()
    --- Method
    --- Launch or focus Windows App as-is — whatever state it is in.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * `true` when Windows App was launched or focused, `false` when it is not installed
    function obj:launchWindowsApp()
        if not hs.application.launchOrFocus(appName) then
            notify('"' .. appName .. '" not installed')
            return false
        end

        return true
    end

    -- ONE usable Windows App application object, or nil.
    --
    -- obj._getApp falls back to hs.application.find(), which returns a
    -- LIST when several processes match — and quitting the app with
    -- Cmd+Q leaves the dying instance answering alongside the new one.
    -- A list has no :activate(), and a quit app is nil outright: both
    -- used to crash a press with "attempt to index a nil value".
    local function windowsApp()
        local found = obj._getApp(appName)

        local function usable(candidate)
            return candidate ~= nil and type(candidate.activate) == "function"
        end

        if usable(found) then
            return found
        end

        if type(found) == "table" then
            for _, candidate in ipairs(found) do
                if usable(candidate) then
                    return candidate
                end
            end
        end

        return nil
    end

    -- Find a live session window whose title contains the fragment.
    local function findSessionWindow(fragment)
        local app = windowsApp()

        if not app then
            return nil
        end

        for _, window in ipairs(app:allWindows()) do
            local title = window:title() or ""

            if title ~= "" and title:find(fragment, 1, true) then
                return app, window
            end
        end

        return app, nil
    end

    -- An element's visible label, wherever the app happens to put it.
    local function axLabel(element)
        for _, attribute in ipairs({ "AXTitle", "AXDescription", "AXValue" }) do
            local value = element:attributeValue(attribute)

            if type(value) == "string" and value ~= "" then
                return value
            end
        end

        return ""
    end

    -- Find the pressable "Saved Devices" tile whose label matches any
    -- of the given names (the friendly name shown on the tile, or the
    -- host when the PC has none).
    local function findDeviceTile(names)
        local ax = require("hs.axuielement")
        local app = windowsApp()

        if not app then
            return nil
        end

        local wanted = {}

        for _, name in ipairs(names) do
            if name and name ~= "" then
                wanted[name:lower()] = true
            end
        end

        local found

        local function search(element, depth)
            if found or depth > 14 then
                return
            end

            for _, child in ipairs(element:attributeValue("AXChildren") or {}) do
                if wanted[axLabel(child):lower()] then
                    for _, action in ipairs(child:actionNames() or {}) do
                        if action == "AXPress" then
                            found = child
                            return
                        end
                    end
                end

                search(child, depth + 1)
            end
        end

        search(ax.applicationElement(app), 1)

        return found
    end

    --- AppLaunchScripts:launchWindowsAppComm(host, label, titleFragment)
    --- Method
    --- Open one remote PC: focus its session window when the
    --- connection is already live, otherwise press that PC's tile in
    --- Windows App's "Saved Devices" list and focus the session
    --- window once it appears. Windows App shows its own credential
    --- prompt when no credentials are saved — the app is brought
    --- frontmost so typing lands in it.
    ---
    --- Parameters:
    ---  * host - the PC's hostname or IP address
    ---  * label - the PC's name as shown on its tile (falls back to `host`)
    ---  * titleFragment - optional window-title fragment identifying the session window (defaults to `label`, then `host`)
    ---
    --- Returns:
    ---  * `true` when the connection was focused or started, `false` when Windows App is missing or the PC is not saved in it
    function obj:launchWindowsAppComm(host, label, titleFragment)
        local fragment = titleFragment or label or host

        if not windowsApp() then
            if not hs.application.launchOrFocus(appName) then
                notify('"' .. appName .. '" not installed')
                return false
            end

            -- Wait for the hub window: the device tiles live in it.
            for _ = 1, 60 do
                local app = windowsApp()

                if app and app:mainWindow() then
                    break
                end

                hs.timer.usleep(250000)
            end
        end

        -- Already connected? Just focus the session window.
        local app, window = findSessionWindow(fragment)

        if app and window then
            app:activate(true)
            window:focus()
            return true
        end

        -- Connect by pressing the PC's tile — the only route that
        -- works (see the header).
        local tile = findDeviceTile({ label, host, titleFragment })

        if not tile then
            -- No tile can mean three different things, and blaming the
            -- configuration for all of them is wrong. Quitting the app
            -- with Cmd+Q (or closing its window with Cmd+W) leaves it
            -- starting up with no hub and no tiles yet — nothing to do
            -- with which PCs you have saved.
            local app = windowsApp()

            if not app then
                notify(string.format(
                    'Windows App is not running yet — "%s" was not connected, press the button again in a moment',
                    label or host))
                return false
            end

            if not app:mainWindow() then
                notify(string.format(
                    'Windows App is still starting up — "%s" was not connected, press the button again in a moment',
                    label or host))
                app:activate(true)
                return false
            end

            notify(string.format(
                '"%s" is not among Windows App\'s saved PCs — add it there once (Connections > Add PC), then this button works',
                label or host))
            app:activate(true)
            return false
        end

        tile:performAction("AXPress")

        -- Bring the app forward: a credential prompt may need typing,
        -- and the press alone does not front the app.
        local attempts = 120

        local function settle()
            local sessionApp, sessionWindow = findSessionWindow(fragment)

            if sessionApp and sessionWindow then
                sessionApp:activate(true)
                sessionWindow:focus()
                return
            end

            attempts = attempts - 1

            if attempts <= 0 then
                -- No session window: the server may be down, or a
                -- credential prompt is open. Stay quiet — the app is
                -- frontmost and speaks for itself.
                return
            end

            if sessionApp and attempts == 116 then
                sessionApp:activate(true)
            end

            hs.timer.doAfter(0.25, settle)
        end

        settle()

        return true
    end

    --- AppLaunchScripts:generateWindowsAppConfig()
    --- Method
    --- Create config/windowsapp/Pcs.json when missing and merge in
    --- the PCs discovered from Windows App's bookmark database: new
    --- hosts are appended, missing names are filled from friendly
    --- names, and nothing you wrote is ever overwritten.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateWindowsAppConfig()
        hs.fs.mkdir(obj.spoonPath .. "config/")
        hs.fs.mkdir(configDir())

        local config = readJson(configFile()) or { pcs = {} }
        config.pcs = config.pcs or {}

        local byHost = {}

        for _, pc in ipairs(config.pcs) do
            if pc.host then
                byHost[pc.host] = pc
            end
        end

        local changed = false
        local added = 0

        -- Every entry always carries a "name" key, ready to edit. It
        -- is prefilled from the PC's friendly name, or — when Windows
        -- App has none — from the address itself
        -- ("10.0.0.9" -> "10009"), so there is always a
        -- concrete value in front of you to replace with your own
        -- alias. A name you wrote is never touched; a still-default
        -- one is upgraded if you later set a friendly name in
        -- Windows App.
        local function defaultName(host)
            return camelize(host)
        end

        local function unedited(pc)
            return pc.name == nil or pc.name == ""
                or (pc.host and pc.name == defaultName(pc.host))
        end

        for _, device in ipairs(self:windowsAppDevices()) do
            local existing = byHost[device.host]

            if not existing then
                table.insert(config.pcs, {
                    host = device.host,
                    name = device.name or defaultName(device.host),
                })
                byHost[device.host] = config.pcs[#config.pcs]
                added = added + 1
                changed = true
            elseif unedited(existing) and device.name
                and existing.name ~= device.name then
                existing.name = device.name
                changed = true
            end
        end

        -- Hand-declared entries get the key too.
        for _, pc in ipairs(config.pcs) do
            if (pc.name == nil or pc.name == "") and pc.host then
                pc.name = defaultName(pc.host)
                changed = true
            end
        end

        if changed then
            writeJson(configFile(), config)

            if added > 0 then
                notify(string.format(
                    "App Launch Scripts: discovered %d saved PC%s (config/windowsapp/Pcs.json)",
                    added, added == 1 and "" or "s"))
            end
        elseif not io.open(configFile(), "r") then
            writeJson(configFile(), config)
            print("AppLaunchScripts/windowsapp: created empty config/windowsapp/Pcs.json")
        end

        return self
    end

    --- AppLaunchScripts:generateWindowsAppMethods()
    --- Method
    --- Regenerate availableWindowsAppComms.lua from
    --- config/windowsapp/Pcs.json and load it: launchWindowsApp()
    --- plus one launchWindowsApp<Name>Pc() per PC, each also bound as
    --- a hammerspoon:// URL. Runs automatically when the Spoon loads.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateWindowsAppMethods()
        -- Remove the previous generation's methods first, so renamed
        -- entries do not linger as stale methods until the next
        -- reload. (launchWindowsApp itself is a real method, never
        -- removed — _windowsAppGenerated only tracks catalog-defined
        -- launchers.)
        for _, method in ipairs(obj._windowsAppGenerated or {}) do
            obj[method] = nil
        end

        local pcs = self:windowsAppComms()
        local launchers = {}
        local generated = {}
        local lines = {
            "-- Generated by windowsapp.lua from config/windowsapp/Pcs.json",
            "-- — DO NOT EDIT.",
            "--",
            "-- This file is rewritten on every Hammerspoon reload and on",
            "-- every help() call; saved PCs are auto-discovered from",
            "-- Windows App's bookmark database and merged into the config",
            "-- (your edits are never overwritten). PCs the scan cannot",
            "-- see can be declared by hand: { \"name\": \"…\", \"host\": \"…\" }.",
            "--",
            "-- COPY-PASTE CATALOG: every function below is documented with",
            "-- its shell command and its hammerspoon:// address — paste the",
            "-- address into a Stream Deck \"Website\" action (Open with:",
            "-- Hammerspoon) to make a button.",
            "return function(obj)",
        }

        -- Method names must be unique. Different config names can
        -- collide after CamelCasing (duplicates, stray spaces/tabs,
        -- transliterated accents) — colliding entries get an
        -- incremental suffix in the name part (Make, Make1, Make2 …)
        -- and the catalog notes who took the name first.
        local usedMethods = {}

        local function addMethod(namePart, host, label, titleFragment, what)
            local requested = "launchWindowsApp" .. namePart .. "Pc"
            local method = requested
            local bump = 0

            while usedMethods[method] do
                bump = bump + 1
                method = "launchWindowsApp" .. namePart .. bump .. "Pc"
            end

            table.insert(launchers, method)
            table.insert(generated, method)
            table.insert(lines, "")
            table.insert(lines, "    -- " .. what)

            if bump > 0 then
                table.insert(lines, string.format(
                    '    -- NOTE: "%s" was not available — already taken by: %s.',
                    requested, usedMethods[requested]))
                table.insert(lines, string.format(
                    '    --       Names collide after CamelCasing (check for duplicates or stray spaces in config); renamed with suffix %d.',
                    bump))
            end

            usedMethods[method] = what

            table.insert(lines, string.format(
                "    -- shell:  hs -c 'spoon.AppLaunchScripts:%s()'", method))
            table.insert(lines, string.format(
                "    -- button: hammerspoon://%s", method:lower()))
            table.insert(lines, string.format([[
    function obj:%s()
        return self:launchWindowsAppComm(%q, %q, %s)
    end]], method, host, label,
                titleFragment and string.format("%q", titleFragment) or "nil"))
        end

        -- The app itself is always launchable, config or not.
        table.insert(launchers, "launchWindowsApp")
        table.insert(lines, "")
        table.insert(lines, "    -- Windows App — the app itself, whatever state it is in")
        table.insert(lines,
            "    -- shell:  hs -c 'spoon.AppLaunchScripts:launchWindowsApp()'")
        table.insert(lines, "    -- button: hammerspoon://launchwindowsapp")
        usedMethods["launchWindowsApp"] = "Windows App — the app itself"

        for _, pc in ipairs(pcs) do
            if pc.host then
                local name = (pc.name ~= "" and pc.name) or nil
                local displayName = name or pc.host

                local what

                -- A name still equal to the address-derived default
                -- says so, so the catalog invites renaming.
                if name and name ~= camelize(pc.host) then
                    what = string.format('Remote PC "%s" (%s)',
                        name, pc.host)
                else
                    what = string.format(
                        'Remote PC %s (default name — edit "name" in config/windowsapp/Pcs.json for a nicer button)',
                        pc.host)
                end

                addMethod(camelize(displayName), pc.host,
                    displayName, pc.title, what)
            end
        end

        table.insert(lines, "end")

        local file = io.open(generatedFile(), "w")

        if not file then
            notify("Cannot write " .. generatedFile())
            return self
        end

        file:write(table.concat(lines, "\n") .. "\n")
        file:close()

        dofile(generatedFile())(self)

        table.sort(launchers)
        obj._windowsAppLaunchers = launchers
        obj._windowsAppGenerated = generated

        -- Stream Deck: every launcher as a hammerspoon:// URL (plus the
        -- lowercase twin — browsers lowercase URL hosts). The handler
        -- looks the method up at press time, so a button assigned to a
        -- since-renamed launcher alerts instead of crashing.
        for _, method in ipairs(launchers) do
            local handler = function()
                if obj[method] then
                    obj[method](obj)
                else
                    notify(string.format(
                        'Launcher "%s" no longer exists (entry renamed?) — reassign the button from availableWindowsAppComms.lua',
                        method))
                end
            end

            hs.urlevent.bind(method, handler)
            hs.urlevent.bind(method:lower(), handler)
        end

        return self
    end

    obj:generateWindowsAppConfig()
    obj:generateWindowsAppMethods()
end
