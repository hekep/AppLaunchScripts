-- Microsoft Teams integration for AppLaunchScripts.
--
-- Teams keeps its chats, contacts, and tenants in IndexedDB (not
-- scannable), so the people you want buttons for are DECLARED in
-- config/teams/Teams.json (gitignored — it contains personal names
-- and email addresses):
--
--   {
--     "people": [
--       { "name": "Alice", "email": "alice@example.com", "title": "Alice Smith" }
--     ]
--   }
--
-- "name" is your button alias (free-form; CamelCased into the method
-- name), "email" the address Teams opens the chat with, "title" an
-- optional window-title fragment used to verify the navigation
-- (learned automatically on first press when omitted).
--
-- For every entry a method is generated into availableTeamsComms.lua:
--   launchTeams()                             -- the app itself, as-is
--   launchTeams<Name>Person()
-- plus hammerspoon:// URL twins for Stream Deck.
--
-- Teams is a single-main-window app: buttons purely navigate that
-- window (msteams: deep link) and focus it, so the message box is
-- ready for typing. Window geometry stays the job of workspaces.
-- No macOS permissions are needed for any of this.
--
-- Group chats / chat rooms are deliberately NOT supported: launching
-- them requires thread IDs fished out of message "Copy link" URLs,
-- which is hacky and not end-user friendly. Revisit if Microsoft
-- ships proper chat deep links.
--
-- Loaded from init.lua as: dofile(obj.spoonPath .. "teams.lua")(obj)

return function(obj)

    local appName = "Microsoft Teams"

    local function teamsConfigDir()
        return obj.spoonPath .. "config/teams/"
    end

    local function generatedFile()
        return obj.spoonPath .. "availableTeamsComms.lua"
    end

    local function notify(message)
        hs.alert.show(message, 8)
        print("AppLaunchScripts/teams: " .. message)
    end

    -- Teams deep links use the canonical single-slash form
    -- (msteams:/l/…), which hs.urlevent.openURL() rejects for lacking
    -- "://" — dispatch through /usr/bin/open instead.
    local function openDeepLink(email)
        hs.task.new("/usr/bin/open", nil, {
            "msteams:/l/chat/0/0?users=" .. hs.http.encodeForQuery(email),
        }):start()
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

    --- AppLaunchScripts:teamsComms()
    --- Method
    --- Load all config/teams/*.json files.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A sorted list of `{ file, people }` entries (invalid JSON is reported and skipped)
    function obj:teamsComms()
        local comms = {}

        local ok, iterator, dirObj = pcall(hs.fs.dir, teamsConfigDir())

        if not ok then
            return comms
        end

        for entry in iterator, dirObj do
            if entry:match("%.json$") then
                local file = io.open(teamsConfigDir() .. entry, "r")
                local config = file and hs.json.decode(file:read("*a"))

                if file then
                    file:close()
                end

                if not config then
                    notify("Invalid JSON in config/teams/" .. entry)
                else
                    table.insert(comms, {
                        file = entry,
                        people = config.people or {},
                    })
                end
            end
        end

        table.sort(comms, function(a, b)
            return a.file < b.file
        end)

        return comms
    end

    -- Forward declarations (defined below, used by launchTeamsComm).
    local stripTitle
    local storeScannedData

    --- AppLaunchScripts:launchTeams()
    --- Method
    --- Launch or focus Microsoft Teams as-is — whatever state it is in.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * `true` when Teams was launched or focused, `false` when it is not installed
    function obj:launchTeams()
        if not hs.application.launchOrFocus(appName) then
            notify('"' .. appName .. '" not installed')
            return false
        end

        return true
    end

    --- AppLaunchScripts:launchTeamsComm(email, label, titleFragment)
    --- Method
    --- Open one Teams person chat: focus or launch Teams, navigate its
    --- main window via an msteams: deep link, verify by window title,
    --- and focus the window so the message box is ready for typing.
    ---
    --- Parameters:
    ---  * email - the person's email address
    ---  * label - human-readable name, used in alerts
    ---  * titleFragment - optional window-title fragment to verify the navigation against
    ---
    --- Returns:
    ---  * `true` when the deep link was dispatched, `false` when Teams is not installed
    function obj:launchTeamsComm(email, label, titleFragment)
        if not obj._getApp(appName) then
            if not hs.application.launchOrFocus(appName) then
                notify('"' .. appName .. '" not installed')
                return false
            end
        end

        local pre = obj._getApp(appName)
        local preTitle = pre and pre:mainWindow()
            and pre:mainWindow():title() or ""

        openDeepLink(email)

        -- With a title fragment we wait until it appears. Without one
        -- we wait for the title to CHANGE (so the freshly shown title
        -- can be learned); if it never changes the chat was already
        -- open — focus and move on after a short grace period. Cold
        -- starts get a generous wait.
        local attempts = titleFragment and 60 or 14

        local function settle()
            local teams = obj._getApp(appName)
            local window = teams and teams:mainWindow()
            local title = window and window:title() or ""

            local arrived

            if titleFragment then
                arrived = title:find(titleFragment, 1, true) ~= nil
            else
                arrived = title ~= preTitle
            end

            if window and arrived then
                teams:activate(true)
                window:focus()

                -- Opportunistic learning: an entry without a "title"
                -- just showed us its true one — store it (never
                -- overwriting) and regenerate. Teams loads its view in
                -- stages, so re-read after the title has had time to
                -- stabilize and harvest THAT.
                if titleFragment == nil and title ~= preTitle then
                    hs.timer.doAfter(2.5, function()
                        local app = obj._getApp(appName)
                        local win = app and app:mainWindow()
                        local settled = win and win:title() or ""

                        local fragment = stripTitle(settled)

                        if settled ~= preTitle and fragment then
                            storeScannedData(email, {
                                name = fragment,
                                title = fragment,
                            })
                        end
                    end)
                end

                return
            end

            attempts = attempts - 1

            if attempts <= 0 then
                if titleFragment then
                    notify(string.format(
                        'Teams did not open "%s" (window shows: %s)',
                        label or titleFragment, title))
                elseif window then
                    -- No title change: already open (or a dead email) —
                    -- focus without learning anything.
                    teams:activate(true)
                    window:focus()
                end

                return
            end

            hs.timer.doAfter(0.25, settle)
        end

        settle()

        return true
    end

    -- Strip "Chat | <fragment> | Microsoft Teams" down to the fragment
    -- used for titles and names; nil when the title is not a chat view.
    stripTitle = function(title)
        return title:match("^Chat | (.+) | Microsoft Teams$")
    end

    --- AppLaunchScripts:generateTeamsConfig()
    --- Method
    --- Create a minimal config/teams/Teams.json when none exists yet,
    --- so there is always a file to paste people into. Existing files
    --- are never touched.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateTeamsConfig()
        hs.fs.mkdir(obj.spoonPath .. "config/")
        hs.fs.mkdir(teamsConfigDir())

        local filePath = teamsConfigDir() .. "Teams.json"

        if not io.open(filePath, "r") then
            local file = io.open(filePath, "w")

            if file then
                file:write(hs.json.encode({ people = {} }, true) .. "\n")
                file:close()
                print("AppLaunchScripts/teams: created empty config/teams/Teams.json")
            end
        end

        return self
    end

    -- Write scanned data back into the config entry that owns the
    -- given email. `data` is { name = ..., title = ... }; each field
    -- fills its config counterpart only when missing. Saves the file
    -- and regenerates the launcher methods.
    storeScannedData = function(email, data)
        local ok, iterator, dirObj = pcall(hs.fs.dir, teamsConfigDir())

        if not ok then
            return
        end

        for entry in iterator, dirObj do
            if entry:match("%.json$") then
                local file = io.open(teamsConfigDir() .. entry, "r")
                local config = file and hs.json.decode(file:read("*a"))

                if file then
                    file:close()
                end

                if config then
                    for _, item in ipairs(config.people or {}) do
                        if item.email == email and (not item.title or not item.name) then
                            local learned = {}

                            if not item.title and data.title then
                                item.title = data.title
                                table.insert(learned, 'title "' .. data.title .. '"')
                            end

                            if not item.name and data.name then
                                item.name = data.name
                                table.insert(learned, 'name "' .. data.name .. '"')
                            end

                            if #learned == 0 then
                                return
                            end

                            local out = io.open(teamsConfigDir() .. entry, "w")

                            if out then
                                out:write(hs.json.encode(config, true) .. "\n")
                                out:close()
                            end

                            notify(string.format(
                                'App Launch Scripts: learned %s (config/teams/%s)',
                                table.concat(learned, " and "), entry))
                            obj:generateTeamsMethods()

                            return
                        end
                    end
                end
            end
        end
    end

    --- AppLaunchScripts:teamsScanTitles()
    --- Method
    --- Enrich config/teams/*.json in place: for every person missing a
    --- "title" (or "name"), navigate Teams to their email, read the
    --- window title, and write the fragment back. Existing values are
    --- never overwritten; "name" is never normalized. Emails that do
    --- not navigate are reported. Regenerates the launcher methods
    --- when anything changed.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:teamsScanTitles()
        local ok, iterator, dirObj = pcall(hs.fs.dir, teamsConfigDir())

        if not ok then
            notify("No config/teams/ folder")
            return self
        end

        -- Build the work list: one job per person lacking title or name.
        local jobs = {}
        local files = {}

        for entry in iterator, dirObj do
            if entry:match("%.json$") then
                local file = io.open(teamsConfigDir() .. entry, "r")
                local config = file and hs.json.decode(file:read("*a"))

                if file then
                    file:close()
                end

                if config then
                    files[entry] = { config = config, changed = false }

                    for _, item in ipairs(config.people or {}) do
                        if item.email and (not item.title or not item.name) then
                            table.insert(jobs, { file = entry, item = item })
                        end
                    end
                end
            end
        end

        if #jobs == 0 then
            notify("Teams scan: nothing to fill — all people have name and title")
            return self
        end

        local index = 0
        local filled = 0

        local function finish()
            for name, holder in pairs(files) do
                if holder.changed then
                    local file = io.open(teamsConfigDir() .. name, "w")

                    if file then
                        file:write(hs.json.encode(holder.config, true) .. "\n")
                        file:close()
                    end
                end
            end

            notify(string.format(
                "App Launch Scripts: scan filled %d field(s)", filled))

            if filled > 0 then
                self:generateTeamsMethods()
            end
        end

        local function nextJob()
            index = index + 1
            local job = jobs[index]

            if not job then
                finish()
                return
            end

            local teams = obj._getApp(appName)
            local before = teams and teams:mainWindow()
                and teams:mainWindow():title() or ""

            openDeepLink(job.item.email)

            hs.timer.doAfter(3, function()
                local app = obj._getApp(appName)
                local window = app and app:mainWindow()
                local title = window and window:title() or ""
                local fragment = stripTitle(title)

                if title == before or not fragment then
                    -- No navigation seen: a dead email, or the chat was
                    -- already the visible one (indistinguishable — Teams
                    -- has no neutral view to bounce through).
                    notify(string.format(
                        'Teams scan: "%s" did not navigate — check the email (or the chat was already open)',
                        job.item.email))
                else
                    if not job.item.title then
                        job.item.title = fragment
                        filled = filled + 1
                    end

                    if not job.item.name then
                        job.item.name = fragment
                        filled = filled + 1
                    end

                    files[job.file].changed = true
                end

                nextJob()
            end)
        end

        nextJob()

        return self
    end

    --- AppLaunchScripts:generateTeamsMethods()
    --- Method
    --- Regenerate availableTeamsComms.lua from config/teams/*.json and
    --- load it: launchTeams() plus one launchTeams<Name>Person() per
    --- declared person, each also bound as a hammerspoon:// URL. Runs
    --- automatically when the Spoon loads.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateTeamsMethods()
        -- Remove the previous generation's methods first, so renamed
        -- entries (e.g. a provisional email-launcher after learning)
        -- do not linger as stale methods until the next reload.
        -- (launchTeams itself is a real method, never removed —
        -- _teamsGenerated only tracks catalog-defined launchers.)
        for _, method in ipairs(obj._teamsGenerated or {}) do
            obj[method] = nil
        end

        local comms = self:teamsComms()
        local launchers = {}
        local generated = {}
        local lines = {
            "-- Generated by teams.lua from config/teams/*.json — DO NOT EDIT.",
            "--",
            "-- This file is rewritten on every Hammerspoon reload, after",
            "--   hs -c 'spoon.AppLaunchScripts:teamsScanTitles()'",
            "-- and whenever a launched chat teaches us its title.",
            "-- To enrich it: add { \"email\": \"…\" } entries to the people",
            "-- list in config/teams/Teams.json, then run the scan command",
            "-- above — names and titles fill themselves.",
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

        local function addMethod(namePart, kindSuffix, email, label, titleFragment, what)
            local requested = "launchTeams" .. namePart .. kindSuffix
            local method = requested
            local bump = 0

            while usedMethods[method] do
                bump = bump + 1
                method = "launchTeams" .. namePart .. bump .. kindSuffix
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
        return self:launchTeamsComm(%q, %q, %s)
    end]], method, email, label,
                titleFragment and string.format("%q", titleFragment) or "nil"))
        end

        -- The app itself is always launchable, config or not.
        table.insert(launchers, "launchTeams")
        table.insert(lines, "")
        table.insert(lines, "    -- Microsoft Teams — the app itself, whatever state it is in")
        table.insert(lines,
            "    -- shell:  hs -c 'spoon.AppLaunchScripts:launchTeams()'")
        table.insert(lines, "    -- button: hammerspoon://launchteams")
        usedMethods["launchTeams"] = "Microsoft Teams — the app itself"

        for _, comm in ipairs(comms) do
            for _, item in ipairs(comm.people) do
                if item.email then
                    -- A bare-email entry gets a PROVISIONAL launcher
                    -- named after the email; pressing it once (or
                    -- running teamsScanTitles) learns the real name
                    -- and title, and the catalog regenerates under
                    -- the proper name.
                    local displayName = item.name
                        or item.email:match("^([^@]+)") or item.email

                    local what

                    if item.name then
                        what = string.format('Teams — person "%s"', item.name)

                        if item.title and item.title ~= item.name then
                            what = what .. " (" .. item.title .. ")"
                        end
                    else
                        what = string.format(
                            'Teams — person %s (unnamed — press once, or run teamsScanTitles(), to learn their name)',
                            item.email)
                    end

                    addMethod(camelize(displayName), "Person",
                        item.email, displayName, item.title, what)
                end
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
        obj._teamsLaunchers = launchers
        obj._teamsGenerated = generated

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
                        'Launcher "%s" no longer exists (entry renamed after learning?) — reassign the button from availableTeamsComms.lua',
                        method))
                end
            end

            hs.urlevent.bind(method, handler)
            hs.urlevent.bind(method:lower(), handler)
        end

        return self
    end

    obj:generateTeamsConfig()
    obj:generateTeamsMethods()
end
