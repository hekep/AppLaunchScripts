-- Discord integration for AppLaunchScripts.
--
-- Discord keeps its servers, channels, and DMs in a local database
-- that cannot be read from outside, so everything you want buttons
-- for is DECLARED in config files (gitignored — they contain personal
-- names and IDs):
--
--   config/discord/<Server>.json     -- one file per server
--     {
--       "server": "My Server",           -- self-learns when omitted
--       "alias": "MyServer",             -- optional; filename proposes it
--       "id": "762900000000000000",
--       "channels": [ { "name": "general", "id": "762900000000000001" } ]
--     }
--
--   config/discordDM/DMs.json        -- the @me space (separate folder,
--     {                               -- so a server named "DM" cannot
--       "dms":    [ { "name": "Alice", "id": "1480000000000000000" } ],
--       "groups": [ ]                 -- group DMs work exactly like DMs
--     }
--
-- IDs come from Discord's Developer Mode (Settings -> Advanced ->
-- Developer Mode, then right-click -> Copy ID) or from web-app URLs
-- (discord.com/channels/<serverId>/<channelId>).
--
-- For every entry a method is generated into availableDiscordComms.lua:
--   launchDiscord()                       -- the app itself, as-is
--   launchDiscord<Alias>()                -- the server (default channel)
--   launchDiscord<Alias><Name>Channel()
--   launchDiscord<Name>Person()
--   launchDiscord<Name>Group()
-- plus hammerspoon:// URL twins for Stream Deck.
--
-- Discord is a single-main-window app: buttons purely navigate that
-- window (discord://-/channels/... deep links) and focus it, so the
-- message box is ready for typing. Window geometry stays the job of
-- workspaces. No macOS permissions are needed for any of this.
--
-- A DEAD ID is not ignored (as in Slack) — Discord navigates to the
-- Friends view instead, whose title is LOCALIZED ("Kaverit - Discord"
-- on a Finnish UI). Learning therefore only accepts titles matching
-- the verified shapes ("#channel | Server - Discord", "@user -
-- Discord"), so a dead ID can never teach a wrong name.
--
-- Loaded from init.lua as: dofile(obj.spoonPath .. "discord.lua")(obj)

return function(obj)

    local appName = "Discord"

    local function serverConfigDir()
        return obj.spoonPath .. "config/discord/"
    end

    local function dmConfigDir()
        return obj.spoonPath .. "config/discordDM/"
    end

    local function generatedFile()
        return obj.spoonPath .. "availableDiscordComms.lua"
    end

    local function notify(message)
        hs.alert.show(message, 8)
        print("AppLaunchScripts/discord: " .. message)
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

    --- AppLaunchScripts:discordComms()
    --- Method
    --- Load all config/discord/*.json server files and
    --- config/discordDM/*.json DM files.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A table `{ servers, dmFiles }`: servers is a sorted list of `{ file, alias, id, server, channels }`, dmFiles a sorted list of `{ file, dms, groups }` (invalid JSON is reported and skipped)
    function obj:discordComms()
        local servers = {}
        local dmFiles = {}

        local ok, iterator, dirObj = pcall(hs.fs.dir, serverConfigDir())

        if ok then
            for entry in iterator, dirObj do
                local base = entry:match("^(.+)%.json$")

                if base then
                    local config = readJson(serverConfigDir() .. entry)

                    if not config then
                        notify("Invalid JSON in config/discord/" .. entry)
                    elseif not config.id then
                        notify("config/discord/" .. entry .. ' has no server "id"')
                    else
                        -- Alias comes from the explicit "alias" or the
                        -- FILENAME — never from the learned server
                        -- name, so method names (and assigned Stream
                        -- Deck buttons) stay stable when learning
                        -- fills "server" in later.
                        table.insert(servers, {
                            file = entry,
                            alias = camelize(config.alias or base),
                            id = config.id,
                            server = config.server,
                            channels = config.channels or {},
                        })
                    end
                end
            end
        end

        local ok2, iterator2, dirObj2 = pcall(hs.fs.dir, dmConfigDir())

        if ok2 then
            for entry in iterator2, dirObj2 do
                if entry:match("%.json$") then
                    local config = readJson(dmConfigDir() .. entry)

                    if not config then
                        notify("Invalid JSON in config/discordDM/" .. entry)
                    else
                        table.insert(dmFiles, {
                            file = entry,
                            dms = config.dms or {},
                            groups = config.groups or {},
                        })
                    end
                end
            end
        end

        table.sort(servers, function(a, b)
            return a.alias < b.alias
        end)

        table.sort(dmFiles, function(a, b)
            return a.file < b.file
        end)

        return { servers = servers, dmFiles = dmFiles }
    end

    -- Forward declaration (defined below, used by launchDiscordComm).
    local storeScannedData

    --- AppLaunchScripts:launchDiscord()
    --- Method
    --- Launch or focus Discord as-is — whatever state it is in.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * `true` when Discord was launched or focused, `false` when it is not installed
    function obj:launchDiscord()
        if not hs.application.launchOrFocus(appName) then
            notify('"' .. appName .. '" not installed')
            return false
        end

        return true
    end

    --- AppLaunchScripts:launchDiscordComm(serverId, channelId, label, titleFragment)
    --- Method
    --- Open one Discord destination: focus or launch Discord, navigate
    --- its main window via a discord:// deep link, verify by window
    --- title, and focus the window so the message box is ready for
    --- typing.
    ---
    --- Parameters:
    ---  * serverId - the server ID, or `"@me"` for DMs and group DMs
    ---  * channelId - channel/DM channel ID; nil opens the server at its default channel
    ---  * label - human-readable name, used in alerts
    ---  * titleFragment - optional window-title fragment to verify the navigation against
    ---
    --- Returns:
    ---  * `true` when the deep link was dispatched, `false` when Discord is not installed
    function obj:launchDiscordComm(serverId, channelId, label, titleFragment)
        if not obj._getApp(appName) then
            if not hs.application.launchOrFocus(appName) then
                notify('"' .. appName .. '" not installed')
                return false
            end
        end

        local pre = obj._getApp(appName)
        local preTitle = pre and pre:mainWindow()
            and pre:mainWindow():title() or ""

        hs.urlevent.openURL("discord://-/channels/" .. serverId
            .. (channelId and ("/" .. channelId) or ""))

        -- With a title fragment we wait until it appears. Without one
        -- we wait for the title to CHANGE (so the freshly shown title
        -- can be learned); if it never changes the destination was
        -- already open — focus and move on after a short grace period.
        -- Discord cold-starts through its updater (~15-20s), so the
        -- budgets are generous.
        local attempts = titleFragment and 120 or 30

        local function settle()
            local discord = obj._getApp(appName)
            local window = discord and discord:mainWindow()
            local title = window and window:title() or ""

            local arrived

            if titleFragment then
                arrived = title:find(titleFragment, 1, true) ~= nil
            else
                arrived = title ~= preTitle
            end

            if window and arrived then
                discord:activate(true)
                window:focus()

                -- Opportunistic learning: an entry without a "title"
                -- just showed us its true one — store it (never
                -- overwriting) and regenerate. Re-read after the title
                -- has had time to stabilize and harvest THAT; shape
                -- checks in storeScannedData keep dead IDs (which land
                -- on the localized Friends view) from teaching wrong
                -- names.
                if titleFragment == nil and title ~= preTitle then
                    hs.timer.doAfter(2.5, function()
                        local app = obj._getApp(appName)
                        local win = app and app:mainWindow()
                        local settled = win and win:title() or ""

                        if settled ~= preTitle then
                            storeScannedData(channelId or serverId, settled)
                        end
                    end)
                end

                return
            end

            attempts = attempts - 1

            if attempts <= 0 then
                if titleFragment then
                    notify(string.format(
                        'Discord did not open "%s" (window shows: %s)',
                        label or titleFragment, title))
                elseif window then
                    -- No title change: already open (or a dead ID) —
                    -- focus without learning anything.
                    discord:activate(true)
                    window:focus()
                end

                return
            end

            hs.timer.doAfter(0.25, settle)
        end

        settle()

        return true
    end

    --- AppLaunchScripts:generateDiscordConfigs()
    --- Method
    --- Create the config folders and a minimal config/discordDM/DMs.json
    --- when none exists yet. Server files cannot be discovered (Discord
    --- keeps its server list unreadable), so they are created by hand —
    --- one paste of the server ID is enough, the rest self-learns.
    --- Existing files are never touched.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateDiscordConfigs()
        hs.fs.mkdir(obj.spoonPath .. "config/")
        hs.fs.mkdir(serverConfigDir())
        hs.fs.mkdir(dmConfigDir())

        local filePath = dmConfigDir() .. "DMs.json"

        if not io.open(filePath, "r") then
            writeJson(filePath, { dms = {}, groups = {} })
            print("AppLaunchScripts/discord: created empty config/discordDM/DMs.json")
        end

        return self
    end

    -- Derive { name, title } (and for the server itself { server })
    -- from a raw window title, according to which list owns the ID.
    -- Returns nil when the title does not match the expected shape —
    -- this is the dead-ID guard.
    local function harvest(kind, rawTitle)
        if kind == "channel" or kind == "server" then
            local channel, server = rawTitle:match("^#(.-) | (.-) %- Discord$")

            if not channel then
                return nil
            end

            if kind == "server" then
                return { server = server }
            end

            return { name = channel, title = "#" .. channel .. " | " .. server }
        end

        if kind == "dm" then
            local user = rawTitle:match("^@(.-) %- Discord$")

            if not user then
                return nil
            end

            return { name = user, title = "@" .. user }
        end

        -- Group DM titles have no marker; accept anything that is not
        -- channel-shaped. The docs advise eyeballing learned group
        -- names once.
        local group = rawTitle:match("^(.-) %- Discord$")

        if not group or group:sub(1, 1) == "#" or group == "" then
            return nil
        end

        return { name = group, title = group }
    end

    -- Write scanned data back into the config entry that owns the
    -- given ID (a server ID, channel ID, or DM channel ID). Each field
    -- fills its config counterpart only when missing. Saves the file
    -- and regenerates the launcher methods. Returns true when
    -- something was filled.
    storeScannedData = function(id, rawTitle)
        local function fill(item, data, path, config, entry)
            local learned = {}

            if data.server and not item.server then
                item.server = data.server
                table.insert(learned, 'server "' .. data.server .. '"')
            end

            if data.title and not item.title then
                item.title = data.title
                table.insert(learned, 'title "' .. data.title .. '"')
            end

            if data.name and not item.name then
                item.name = data.name
                table.insert(learned, 'name "' .. data.name .. '"')
            end

            if #learned == 0 then
                return false
            end

            writeJson(path, config)
            notify(string.format(
                'App Launch Scripts: learned %s (%s)',
                table.concat(learned, " and "), entry))
            obj:generateDiscordMethods()

            return true
        end

        local ok, iterator, dirObj = pcall(hs.fs.dir, serverConfigDir())

        if ok then
            for entry in iterator, dirObj do
                if entry:match("%.json$") then
                    local path = serverConfigDir() .. entry
                    local config = readJson(path)

                    if config then
                        if config.id == id and not config.server then
                            local data = harvest("server", rawTitle)

                            if data then
                                return fill(config, data, path, config,
                                    "config/discord/" .. entry)
                            end
                        end

                        for _, item in ipairs(config.channels or {}) do
                            if item.id == id and (not item.title or not item.name) then
                                local data = harvest("channel", rawTitle)

                                if data then
                                    return fill(item, data, path, config,
                                        "config/discord/" .. entry)
                                end

                                return false
                            end
                        end
                    end
                end
            end
        end

        local ok2, iterator2, dirObj2 = pcall(hs.fs.dir, dmConfigDir())

        if ok2 then
            for entry in iterator2, dirObj2 do
                if entry:match("%.json$") then
                    local path = dmConfigDir() .. entry
                    local config = readJson(path)

                    if config then
                        for _, listName in ipairs({ "dms", "groups" }) do
                            for _, item in ipairs(config[listName] or {}) do
                                if item.id == id and (not item.title or not item.name) then
                                    local data = harvest(
                                        listName == "dms" and "dm" or "group",
                                        rawTitle)

                                    if data then
                                        return fill(item, data, path, config,
                                            "config/discordDM/" .. entry)
                                    end

                                    return false
                                end
                            end
                        end
                    end
                end
            end
        end

        return false
    end

    --- AppLaunchScripts:discordScanTitles()
    --- Method
    --- Enrich the Discord configs in place: for every entry missing a
    --- "title" or "name" (or a server file missing "server"), navigate
    --- Discord to its ID, read the window title, and write the learned
    --- values back. Existing values are never overwritten; "name" is
    --- never normalized. IDs that do not navigate to the expected kind
    --- of view are reported. Bounces through the Friends view between
    --- jobs so every navigation is detectable. Regenerates the
    --- launcher methods when anything changed.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    -- One scan job per entry lacking title or name (or a server file
    -- lacking its server name). Shared by the async scan and the
    -- synchronous help()-time scan.
    local function buildScanJobs(comms)
        local jobs = {}

        for _, server in ipairs(comms.servers) do
            if not server.server then
                table.insert(jobs, {
                    id = server.id, serverId = server.id, channelId = nil,
                })
            end

            for _, item in ipairs(server.channels) do
                if item.id and (not item.title or not item.name) then
                    table.insert(jobs, {
                        id = item.id, serverId = server.id, channelId = item.id,
                    })
                end
            end
        end

        for _, dmFile in ipairs(comms.dmFiles) do
            for _, listName in ipairs({ "dms", "groups" }) do
                for _, item in ipairs(dmFile[listName]) do
                    if item.id and (not item.title or not item.name) then
                        table.insert(jobs, {
                            id = item.id, serverId = "@me", channelId = item.id,
                        })
                    end
                end
            end
        end

        return jobs
    end

    function obj:discordScanTitles()
        local jobs = buildScanJobs(self:discordComms())

        if #jobs == 0 then
            notify("Discord scan: nothing to fill — all entries have name and title")
            return self
        end

        if not obj._getApp(appName) then
            if not hs.application.launchOrFocus(appName) then
                notify('"' .. appName .. '" not installed')
                return self
            end
        end

        local index = 0
        local filled = 0

        local function nextJob()
            index = index + 1
            local job = jobs[index]

            if not job then
                notify(string.format(
                    "App Launch Scripts: scan filled %d entr%s",
                    filled, filled == 1 and "y" or "ies"))
                return
            end

            hs.urlevent.openURL("discord://-/channels/" .. job.serverId
                .. (job.channelId and ("/" .. job.channelId) or ""))

            hs.timer.doAfter(3, function()
                local app = obj._getApp(appName)
                local window = app and app:mainWindow()
                local title = window and window:title() or ""

                if storeScannedData(job.id, title) then
                    filled = filled + 1
                else
                    notify(string.format(
                        'Discord scan: ID "%s" did not navigate to the expected view (window shows: %s) — check it',
                        job.id, title))
                end

                -- Bounce through Friends so the next job's navigation
                -- is detectable and never inherits this title.
                hs.urlevent.openURL("discord://-/channels/@me")
                hs.timer.doAfter(2, nextJob)
            end)
        end

        nextJob()

        return self
    end

    --- AppLaunchScripts:discordScanTitlesSync()
    --- Method
    --- Synchronous variant of discordScanTitles(), used by help() so
    --- the printed catalog carries every learnable name. Blocks
    --- Hammerspoon for ~5s per unfilled entry (returns immediately
    --- when there is nothing to fill), navigating Discord and
    --- harvesting titles inline instead of on timers.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:discordScanTitlesSync()
        local jobs = buildScanJobs(self:discordComms())

        if #jobs == 0 then
            return self
        end

        if not obj._getApp(appName) then
            if not hs.application.launchOrFocus(appName) then
                notify('"' .. appName .. '" not installed')
                return self
            end

            -- Cold start goes through Discord's updater (~15-20s).
            for _ = 1, 100 do
                local app = obj._getApp(appName)

                if app and app:mainWindow() then
                    break
                end

                hs.timer.usleep(250000)
            end
        end

        local filled = 0

        for _, job in ipairs(jobs) do
            -- os.execute + open(1): dispatch must not depend on the
            -- (blocked) Hammerspoon event loop.
            os.execute(string.format("open 'discord://-/channels/%s%s'",
                job.serverId,
                job.channelId and ("/" .. job.channelId) or ""))
            hs.timer.usleep(3000000)

            local app = obj._getApp(appName)
            local window = app and app:mainWindow()
            local title = window and window:title() or ""

            if storeScannedData(job.id, title) then
                filled = filled + 1
            else
                notify(string.format(
                    'Discord scan: ID "%s" did not navigate to the expected view (window shows: %s) — check it',
                    job.id, title))
            end

            -- Bounce through Friends so the next job's navigation is
            -- detectable and never inherits this title.
            os.execute("open 'discord://-/channels/@me'")
            hs.timer.usleep(2000000)
        end

        if filled > 0 then
            notify(string.format(
                "App Launch Scripts: help() scan filled %d entr%s",
                filled, filled == 1 and "y" or "ies"))
        end

        return self
    end

    --- AppLaunchScripts:generateDiscordMethods()
    --- Method
    --- Regenerate availableDiscordComms.lua from the Discord configs
    --- and load it: launchDiscord() plus one launcher per server,
    --- channel, DM, and group DM, each also bound as a hammerspoon://
    --- URL. Runs automatically when the Spoon loads.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateDiscordMethods()
        -- Remove the previous generation's methods first, so renamed
        -- entries (e.g. a provisional ID-launcher after learning) do
        -- not linger as stale methods until the next reload.
        for _, method in ipairs(obj._discordGenerated or {}) do
            obj[method] = nil
        end

        local comms = self:discordComms()
        local launchers = {}
        local generated = {}
        local lines = {
            "-- Generated by discord.lua from config/discord/*.json and",
            "-- config/discordDM/*.json — DO NOT EDIT.",
            "--",
            "-- This file is rewritten on every Hammerspoon reload, after",
            "--   hs -c 'spoon.AppLaunchScripts:discordScanTitles()'",
            "-- on every help() call (which completes pending name scans",
            "-- first), and whenever a launched destination teaches us",
            "-- its title.",
            "-- To enrich it: add { \"id\": \"…\" } entries to the config files",
            "-- (IDs via Developer Mode -> Copy ID), then run the scan",
            "-- command above — names and titles fill themselves.",
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

        local function addMethod(namePrefix, namePart, kindSuffix, serverId, channelId, label, titleFragment, what)
            local requested = namePrefix .. namePart .. kindSuffix
            local method = requested
            local bump = 0

            while usedMethods[method] do
                bump = bump + 1
                method = namePrefix .. namePart .. bump .. kindSuffix
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
        return self:launchDiscordComm(%q, %s, %q, %s)
    end]], method, serverId,
                channelId and string.format("%q", channelId) or "nil",
                label,
                titleFragment and string.format("%q", titleFragment) or "nil"))
        end

        -- The app itself is always launchable, config or not.
        table.insert(launchers, "launchDiscord")
        table.insert(lines, "")
        table.insert(lines, "    -- Discord — the app itself, whatever state it is in")
        table.insert(lines,
            "    -- shell:  hs -c 'spoon.AppLaunchScripts:launchDiscord()'")
        table.insert(lines, "    -- button: hammerspoon://launchdiscord")
        usedMethods["launchDiscord"] = "Discord — the app itself"

        for _, server in ipairs(comms.servers) do
            local serverLabel = server.server or server.alias

            addMethod("launchDiscord", server.alias, "",
                server.id, nil, serverLabel, nil,
                string.format('%s — the server itself (default channel)%s',
                    serverLabel,
                    server.server and ""
                        or " (unnamed — press once, or run discordScanTitles(), to learn the server name)"))

            for _, item in ipairs(server.channels) do
                if item.id then
                    -- A bare-ID entry gets a PROVISIONAL launcher named
                    -- after the ID; pressing it once (or running
                    -- discordScanTitles) learns the real name and
                    -- title, and the catalog regenerates under the
                    -- proper name.
                    local displayName = item.name or item.id

                    -- Channels default to verifying against "#<name>"
                    -- (Discord titles show "#channel | Server").
                    local fragment = item.title
                        or (item.name and ("#" .. item.name) or nil)

                    local what

                    if item.name then
                        what = string.format('%s — channel "#%s"',
                            serverLabel, item.name)
                    else
                        what = string.format(
                            '%s — channel %s (unnamed — press once, or run discordScanTitles(), to learn its name)',
                            serverLabel, item.id)
                    end

                    addMethod("launchDiscord" .. server.alias,
                        camelize(displayName), "Channel",
                        server.id, item.id, displayName, fragment, what)
                end
            end
        end

        for _, dmFile in ipairs(comms.dmFiles) do
            local sections = {
                { list = dmFile.dms, suffix = "Person", kind = "person" },
                { list = dmFile.groups, suffix = "Group", kind = "group DM" },
            }

            for _, section in ipairs(sections) do
                for _, item in ipairs(section.list) do
                    if item.id then
                        local displayName = item.name or item.id

                        local what

                        if item.name then
                            what = string.format('Discord — %s "%s"',
                                section.kind, item.name)

                            if item.title and item.title ~= item.name then
                                what = what .. " (" .. item.title .. ")"
                            end
                        else
                            what = string.format(
                                'Discord — %s %s (unnamed — press once, or run discordScanTitles(), to learn its name)',
                                section.kind, item.id)
                        end

                        addMethod("launchDiscord", camelize(displayName),
                            section.suffix, "@me", item.id,
                            displayName, item.title, what)
                    end
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
        obj._discordLaunchers = launchers
        obj._discordGenerated = generated

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
                        'Launcher "%s" no longer exists (entry renamed after learning?) — reassign the button from availableDiscordComms.lua',
                        method))
                end
            end

            hs.urlevent.bind(method, handler)
            hs.urlevent.bind(method:lower(), handler)
        end

        return self
    end

    obj:generateDiscordConfigs()
    obj:generateDiscordMethods()
end
