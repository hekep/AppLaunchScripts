-- Slack integration for AppLaunchScripts.
--
-- Domains (workspaces) are scanned automatically from Slack's local
-- root-state.json; the channels, people, and groups you want buttons
-- for are DECLARED in config/slack/<Domain>.json (one file per domain,
-- gitignored — they contain personal names):
--
--   {
--     "domain": "example-team",
--     "alias": "Example",                     -- optional; filename proposes it
--     "channels": [ { "name": "general", "id": "C0123456" } ],
--     "people":   [ { "name": "Alice", "id": "D0123456", "title": "Alice Smith" } ],
--     "groups":   [ { "name": "Alice and Bob", "id": "C0987654", "title": "Alice Smith, Bob Jones" } ]
--   }
--
-- "name" is your button alias (free-form; CamelCased into the method
-- name), "title" an optional window-title fragment used to verify the
-- navigation. IDs come from Slack's "Copy link" (/archives/<ID> tail).
--
-- For every entry a method is generated into availableSlackComms.lua:
--   launchSlack<Alias>()                      -- the workspace itself
--   launchSlack<Alias><Name>Channel()
--   launchSlack<Alias><Name>Person()
--   launchSlack<Alias><Name>Group()
-- plus hammerspoon:// URL twins for Stream Deck.
--
-- Slack is a single-main-window app: buttons purely navigate that
-- window and focus it, so the message box is ready for typing. Window
-- geometry stays the job of workspaces.
--
-- Loaded from init.lua as: dofile(obj.spoonPath .. "slack.lua")(obj)

return function(obj)

    local function slackConfigDir()
        return obj.spoonPath .. "config/slack/"
    end

    local function generatedFile()
        return obj.spoonPath .. "availableSlackComms.lua"
    end

    local function notify(message)
        hs.alert.show(message, 8)
        print("AppLaunchScripts/slack: " .. message)
    end

    -- "project_chat" -> "ProjectChat",
    -- "Alice and Bob" -> "AliceAndBob" (inner capitals preserved).
    -- Lua identifiers are ASCII-only, so accented letters are
    -- transliterated ("Väinö Äikäs" -> "VainoAikas").
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

    --- AppLaunchScripts:slackDomains()
    --- Method
    --- List signed-in Slack workspaces from Slack's local root-state.json.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A table mapping Slack domain (e.g. `example-team`) to `{ id, name, url }`; empty if Slack is not installed or has no workspaces
    function obj:slackDomains()
        local path = os.getenv("HOME")
            .. "/Library/Application Support/Slack/storage/root-state.json"

        local file = io.open(path, "r")

        if not file then
            return {}
        end

        local state = hs.json.decode(file:read("*a"))
        file:close()

        local domains = {}

        for id, team in pairs((state or {}).workspaces or {}) do
            if type(team) == "table" and team.domain then
                domains[team.domain] = {
                    id = team.id or id,
                    name = team.name or team.domain,
                    url = team.url,
                }
            end
        end

        return domains
    end

    -- Resolve one config's team: match "domain" against the scanned
    -- domains, falling back to a workspace-name match.
    local function resolveTeam(config, domains)
        if config.domain and domains[config.domain] then
            return domains[config.domain]
        end

        local wanted = tostring(config.domain or config.name or ""):lower()

        for _, team in pairs(domains) do
            if team.name:lower() == wanted then
                return team
            end
        end

        return nil
    end

    --- AppLaunchScripts:slackComms()
    --- Method
    --- Load all config/slack/<Domain>.json files, resolved against the
    --- scanned Slack domains.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A sorted list of `{ alias, team, channels, people, groups }` entries (unresolvable domains are reported and skipped)
    function obj:slackComms()
        local domains = self:slackDomains()
        local comms = {}

        local ok, iterator, dirObj = pcall(hs.fs.dir, slackConfigDir())

        if not ok then
            return comms
        end

        for entry in iterator, dirObj do
            local base = entry:match("^(.+)%.json$")

            if base then
                local file = io.open(slackConfigDir() .. entry, "r")
                local config = file and hs.json.decode(file:read("*a"))

                if file then
                    file:close()
                end

                if not config then
                    notify("Invalid JSON in config/slack/" .. entry)
                else
                    local team = resolveTeam(config, domains)

                    if not team then
                        notify(string.format(
                            'Slack domain "%s" (config/slack/%s) is not signed in',
                            tostring(config.domain), entry))
                    else
                        table.insert(comms, {
                            alias = camelize(config.alias or base),
                            team = team,
                            channels = config.channels or {},
                            people = config.people or {},
                            groups = config.groups or {},
                        })
                    end
                end
            end
        end

        table.sort(comms, function(a, b)
            return a.alias < b.alias
        end)

        return comms
    end

    -- Forward declarations (defined below, used by launchSlackComm).
    local stripTitle
    local storeScannedData

    --- AppLaunchScripts:launchSlackComm(teamId, id, label, titleFragment)
    --- Method
    --- Open one Slack conversation: focus or launch Slack, navigate its
    --- main window via a slack:// deep link, verify by window title,
    --- and focus the window so the message box is ready for typing.
    ---
    --- Parameters:
    ---  * teamId - the Slack team ID (e.g. `T0123456`)
    ---  * id - conversation ID (`C…`/`G…`/`D…`) or member ID (`U…`); nil opens the workspace itself
    ---  * label - human-readable name, used in alerts
    ---  * titleFragment - optional window-title fragment to verify the navigation against
    ---
    --- Returns:
    ---  * `true` when the deep link was dispatched, `false` when Slack is not installed
    function obj:launchSlackComm(teamId, id, label, titleFragment)
        if not obj._getApp("Slack") then
            if not hs.application.launchOrFocus("Slack") then
                notify('"Slack" not installed')
                return false
            end
        end

        local link

        if not id then
            link = "slack://open?team=" .. teamId
        elseif id:sub(1, 1) == "U" then
            link = string.format("slack://user?team=%s&id=%s", teamId, id)
        else
            link = string.format("slack://channel?team=%s&id=%s", teamId, id)
        end

        local pre = obj._getApp("Slack")
        local preTitle = pre and pre:mainWindow()
            and pre:mainWindow():title() or ""

        hs.urlevent.openURL(link)

        -- Verify by title (when a fragment is known) and put the window
        -- in focus so typing lands in the message box. Cold starts get
        -- a generous wait.
        -- With a title fragment we wait until it appears. Without one
        -- we wait for the title to CHANGE (so the freshly shown title
        -- can be learned); if it never changes the conversation was
        -- already open — focus and move on after a short grace period.
        local attempts = titleFragment and 60 or 14

        local function settle()
            local slack = obj._getApp("Slack")
            local window = slack and slack:mainWindow()
            local title = window and window:title() or ""

            local arrived

            if titleFragment then
                arrived = title:find(titleFragment, 1, true) ~= nil
            else
                arrived = id == nil or title ~= preTitle
            end

            if window and arrived then
                slack:activate(true)
                window:focus()

                -- Opportunistic learning: an entry without a "title"
                -- just showed us its true one — store it (never
                -- overwriting) and regenerate. Only when the title
                -- actually changed, so a dead ID cannot teach us the
                -- previous conversation's title. Cross-workspace
                -- navigation is two-stage (workspace first, then the
                -- conversation), so re-read after the title has had
                -- time to stabilize and harvest THAT.
                if titleFragment == nil and id ~= nil
                    and title ~= preTitle and title:find(" %- Slack$") then
                    hs.timer.doAfter(2.5, function()
                        local app = obj._getApp("Slack")
                        local win = app and app:mainWindow()
                        local settled = win and win:title() or ""

                        if settled ~= preTitle
                            and settled:find(" %- Slack$") then
                            local teamName

                            for _, team in pairs(obj:slackDomains()) do
                                if team.id == teamId then
                                    teamName = team.name
                                    break
                                end
                            end

                            if teamName then
                                local fragment = stripTitle(settled, teamName)

                                storeScannedData(teamId, id, {
                                    name = fragment,
                                    title = fragment,
                                })
                            end
                        end
                    end)
                end

                return
            end

            attempts = attempts - 1

            if attempts <= 0 then
                if titleFragment then
                    notify(string.format(
                        'Slack did not open "%s" (window shows: %s)',
                        label or titleFragment, title))
                elseif window then
                    -- No title change: already open (or a dead ID) —
                    -- focus without learning anything.
                    slack:activate(true)
                    window:focus()
                end

                return
            end

            hs.timer.doAfter(0.25, settle)
        end

        settle()

        return true
    end

    -- Strip "<fragment> (Channel|DM) - <Workspace> - Slack" down to the
    -- fragment used for titles and names.
    stripTitle = function(title, teamName)
        local fragment = title

        local teamTail = " - " .. teamName .. " - Slack"

        if fragment:sub(-#teamTail) == teamTail then
            fragment = fragment:sub(1, #fragment - #teamTail)
        end

        fragment = fragment:gsub(" %(Channel%)$", ""):gsub(" %(DM%)$", "")

        return fragment
    end

    --- AppLaunchScripts:generateSlackDomainConfigs()
    --- Method
    --- Create a minimal config/slack/<Alias>.json for every signed-in
    --- Slack domain that has no config file yet, so every domain is
    --- launchable without any deeper configuration. Existing files are
    --- never touched.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateSlackDomainConfigs()
        local domains = self:slackDomains()

        if next(domains) == nil then
            return self
        end

        hs.fs.mkdir(slackConfigDir())

        -- Domains already covered by any existing config file.
        local covered = {}
        local ok, iterator, dirObj = pcall(hs.fs.dir, slackConfigDir())

        if ok then
            for entry in iterator, dirObj do
                if entry:match("%.json$") then
                    local file = io.open(slackConfigDir() .. entry, "r")
                    local config = file and hs.json.decode(file:read("*a"))

                    if file then
                        file:close()
                    end

                    if config then
                        local team = resolveTeam(config, domains)

                        if team then
                            covered[team.id] = true
                        end
                    end
                end
            end
        end

        local created = 0

        for domain, team in pairs(domains) do
            if not covered[team.id] then
                local alias = camelize(team.name)
                local filePath = slackConfigDir() .. alias .. ".json"

                -- Never overwrite anything, even on an alias collision.
                if not io.open(filePath, "r") then
                    local file = io.open(filePath, "w")

                    if file then
                        file:write(hs.json.encode({
                            domain = domain,
                            alias = alias,
                            channels = {},
                            people = {},
                            groups = {},
                        }, true) .. "\n")
                        file:close()
                        created = created + 1
                    end
                end
            end
        end

        if created > 0 then
            print(string.format(
                "AppLaunchScripts/slack: created %d empty domain config(s)",
                created))
        end

        return self
    end

    -- Write scanned data back into the config entry that owns the
    -- given conversation ID. `data` is { name = ..., title = ... };
    -- each field fills its config counterpart only when missing. Saves
    -- the file and regenerates the launcher methods.
    storeScannedData = function(teamId, id, data)
        local ok, iterator, dirObj = pcall(hs.fs.dir, slackConfigDir())

        if not ok then
            return
        end

        for entry in iterator, dirObj do
            if entry:match("%.json$") then
                local file = io.open(slackConfigDir() .. entry, "r")
                local config = file and hs.json.decode(file:read("*a"))

                if file then
                    file:close()
                end

                if config then
                    for _, listName in ipairs({ "channels", "people", "groups" }) do
                        for _, item in ipairs(config[listName] or {}) do
                            if item.id == id and (not item.title or not item.name) then
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

                                local out = io.open(slackConfigDir() .. entry, "w")

                                if out then
                                    out:write(hs.json.encode(config, true) .. "\n")
                                    out:close()
                                end

                                notify(string.format(
                                    'App Launch Scripts: learned %s (config/slack/%s)',
                                    table.concat(learned, " and "), entry))
                                obj:generateSlackMethods()

                                return
                            end
                        end
                    end
                end
            end
        end
    end

    --- AppLaunchScripts:slackScanTitles()
    --- Method
    --- Enrich config/slack/*.json in place: for every entry missing a
    --- "title" (or "name"), navigate Slack to its ID, read the window
    --- title, and write the fragment back. Existing values are never
    --- overwritten; "name" is never normalized. IDs that do not
    --- navigate are reported. Regenerates the launcher methods when
    --- anything changed.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:slackScanTitles()
        local domains = self:slackDomains()

        local ok, iterator, dirObj = pcall(hs.fs.dir, slackConfigDir())

        if not ok then
            notify("No config/slack/ folder")
            return self
        end

        -- Build the work list: one job per entry lacking title or name.
        local jobs = {}
        local files = {}

        for entry in iterator, dirObj do
            local base = entry:match("^(.+)%.json$")

            if base then
                local file = io.open(slackConfigDir() .. entry, "r")
                local config = file and hs.json.decode(file:read("*a"))

                if file then
                    file:close()
                end

                local team = config and resolveTeam(config, domains)

                if config and team then
                    files[entry] = { config = config, changed = false }

                    for _, listName in ipairs({ "channels", "people", "groups" }) do
                        for _, item in ipairs(config[listName] or {}) do
                            if item.id and (not item.title or not item.name) then
                                table.insert(jobs, {
                                    file = entry,
                                    item = item,
                                    team = team,
                                })
                            end
                        end
                    end
                end
            end
        end

        if #jobs == 0 then
            notify("Slack scan: nothing to fill — all entries have name and title")
            return self
        end

        -- A "bouncer" team to reset the window between jobs, so an ID
        -- that fails to navigate is detected instead of inheriting the
        -- previous conversation's title.
        local bouncer

        for _, team in pairs(domains) do
            local used = false

            for _, job in ipairs(jobs) do
                if job.team.id == team.id then
                    used = true
                end
            end

            if not used then
                bouncer = team.id
                break
            end
        end

        local index = 0
        local filled = 0

        local function finish()
            for name, holder in pairs(files) do
                if holder.changed then
                    local file = io.open(slackConfigDir() .. name, "w")

                    if file then
                        file:write(hs.json.encode(holder.config, true) .. "\n")
                        file:close()
                    end
                end
            end

            notify(string.format(
                "App Launch Scripts: scan filled %d field(s)", filled))

            if filled > 0 then
                self:generateSlackMethods()
            end
        end

        local function nextJob()
            index = index + 1
            local job = jobs[index]

            if not job then
                finish()
                return
            end

            local slack = obj._getApp("Slack")
            local before = slack and slack:mainWindow()
                and slack:mainWindow():title() or ""

            -- Member IDs (U…) need the user deep link, conversations
            -- (C…/G…/D…) the channel one — same rule as launching.
            if job.item.id:sub(1, 1) == "U" then
                hs.urlevent.openURL(string.format(
                    "slack://user?team=%s&id=%s", job.team.id, job.item.id))
            else
                hs.urlevent.openURL(string.format(
                    "slack://channel?team=%s&id=%s", job.team.id, job.item.id))
            end

            hs.timer.doAfter(3, function()
                local app = obj._getApp("Slack")
                local window = app and app:mainWindow()
                local title = window and window:title() or ""

                if title == "" or (title == before and not bouncer) then
                    notify(string.format(
                        'Slack scan: ID "%s" did not navigate — check it',
                        job.item.id))
                elseif title == before and bouncer then
                    notify(string.format(
                        'Slack scan: ID "%s" did not navigate — check it',
                        job.item.id))
                else
                    local fragment = stripTitle(title, job.team.name)

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

                -- Reset via the bouncer so the next job's navigation is
                -- detectable.
                if bouncer then
                    hs.urlevent.openURL("slack://open?team=" .. bouncer)
                    hs.timer.doAfter(2, nextJob)
                else
                    nextJob()
                end
            end)
        end

        nextJob()

        return self
    end

    --- AppLaunchScripts:generateSlackMethods()
    --- Method
    --- Regenerate availableSlackComms.lua from config/slack/*.json and
    --- load it: one launchSlack<Alias>…() method per domain, channel,
    --- person, and group, each also bound as a hammerspoon:// URL.
    --- Runs automatically when the Spoon loads.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateSlackMethods()
        local comms = self:slackComms()
        local launchers = {}
        local lines = {
            "-- Generated by slack.lua from config/slack/*.json — DO NOT EDIT.",
            "--",
            "-- This file is rewritten on every Hammerspoon reload, after",
            "--   hs -c 'spoon.AppLaunchScripts:slackScanTitles()'",
            "-- and whenever a launched conversation teaches us its title.",
            "-- To enrich it: add { \"id\": \"C…\" } entries to the JSON files",
            "-- in config/slack/ (IDs via Slack's Copy link), then run the",
            "-- scan command above — names and titles fill themselves.",
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

        local function addMethod(namePrefix, namePart, kindSuffix, teamId, id, label, titleFragment, what)
            local requested = namePrefix .. namePart .. kindSuffix
            local method = requested
            local bump = 0

            while usedMethods[method] do
                bump = bump + 1
                method = namePrefix .. namePart .. bump .. kindSuffix
            end

            table.insert(launchers, method)
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
        return self:launchSlackComm(%q, %s, %q, %s)
    end]], method, teamId,
                id and string.format("%q", id) or "nil",
                label,
                titleFragment and string.format("%q", titleFragment) or "nil"))
        end

        for _, comm in ipairs(comms) do
            local prefix = "launchSlack" .. comm.alias

            addMethod(prefix, "", "", comm.team.id, nil, comm.team.name, nil,
                string.format('%s — the workspace itself', comm.team.name))

            local sections = {
                { list = comm.channels, suffix = "Channel",
                  kind = "channel", defaultTitle = true },
                { list = comm.people, suffix = "Person", kind = "person" },
                { list = comm.groups, suffix = "Group", kind = "group" },
            }

            for _, section in ipairs(sections) do
                for _, item in ipairs(section.list) do
                    if item.id then
                        -- A bare-ID entry gets a PROVISIONAL launcher
                        -- named after the ID; pressing it once (or
                        -- running slackScanTitles) learns the real name
                        -- and title, and the catalog regenerates under
                        -- the proper name.
                        local displayName = item.name or item.id

                        -- Channels default to verifying against their
                        -- own name (Slack titles show it verbatim);
                        -- people/groups verify only when "title" given.
                        local fragment = item.title
                            or (section.defaultTitle and item.name or nil)

                        local what

                        if item.name then
                            what = string.format('%s — %s "%s"',
                                comm.team.name, section.kind, item.name)

                            if item.title and item.title ~= item.name then
                                what = what .. " (" .. item.title .. ")"
                            end
                        else
                            what = string.format(
                                '%s — %s %s (unnamed — press once, or run slackScanTitles(), to learn its name)',
                                comm.team.name, section.kind, item.id)
                        end

                        addMethod(
                            prefix, camelize(displayName), section.suffix,
                            comm.team.id, item.id, displayName, fragment, what)
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
        obj._slackLaunchers = launchers

        -- Stream Deck: every launcher as a hammerspoon:// URL (plus the
        -- lowercase twin — browsers lowercase URL hosts).
        for _, method in ipairs(launchers) do
            local handler = function()
                obj[method](obj)
            end

            hs.urlevent.bind(method, handler)
            hs.urlevent.bind(method:lower(), handler)
        end

        return self
    end

    obj:generateSlackDomainConfigs()
    obj:generateSlackMethods()
end
