-- Claude (Anthropic desktop app) integration for AppLaunchScripts.
--
-- Coding sessions are AUTO-DISCOVERED from Claude's local session
-- store (title, working directory, and timestamps only — transcripts
-- are never read) and turned straight into launchers:
--
--   launchClaude()                          -- the app itself, as-is
--   launchClaudeCode<SessionTitle>()        -- app up, THAT session active
--
-- plus hammerspoon:// URL twins for Stream Deck:
--   hammerspoon://launchclaudecode<sessiontitle>
--
-- There is no config file: session titles are already human-given
-- (you named them in Claude), so the catalog regenerates from the
-- scan on every reload and help() call. Archived sessions are
-- skipped. Cowork sessions will join as launchClaudeCowork<Name>()
-- once there are any to scan.
--
-- HOW ACTIVATION WORKS: a session's row in Claude's sidebar is a real
-- accessibility button ("Idle <title>", "Running <title>", "#1 ·
-- Merged <title>" …). The launcher finds that row and CLICKS it.
-- AXPress does nothing here — Claude's web UI ignores it — so a
-- synthetic click is posted at the row's centre and the mouse pointer
-- is put back where it was. The sidebar must be open for the click to
-- land, so a collapsed one is opened first (its rows stay in the
-- accessibility tree with their old coordinates, which would send the
-- click into the conversation area instead).
--
-- Nothing here blocks: the press hands back control immediately and
-- timers do the waiting. A blocking wait freezes Hammerspoon, and
-- with it the whole workspace press that triggered us.
--
-- WHY NOT THE claude:// DEEP LINK (tested to destruction 2026-08-02):
-- claude://resume?session=<id> IMPORTS a transcript rather than
-- focusing a session — it re-imports megabytes on every press, and
-- for most sessions it forks a fresh untitled copy ("General coding
-- session") instead of opening the original, because it resolves the
-- CLI id to a desktop session keyed "local_<cliSessionId>" that most
-- sessions do not have. Passing the desktop id is rejected outright,
-- and the ".../epitaxy/<id>" form the app's own "Copy URL" produces
-- is not recognised at all. If a future release makes the deep link
-- focus an existing session, it should replace all of this.
--
-- RENAMING A SESSION: a launcher carries the catalog's title AND the
-- path to the session's JSON file. The PATH is the stable identity, so
-- the live title is read from that file at press time and the catalog
-- title is only a fallback — a renamed session keeps working until the
-- next help()/reload regenerates the catalog under its new name, at
-- which point a workspace `url` or Stream Deck button pointing at the
-- old address must be updated by hand. Both failures are loud.
--
-- TWO SESSIONS WITH THE SAME TITLE cannot be told apart: their rows
-- carry identical labels. Titles that merely overlap are fine — every
-- candidate row is collected and the shortest label wins.
--
-- Verification: a genuine switch bumps the session's lastFocusedAt in
-- the store, so the launcher watches that field for up to 8s and only
-- then alerts. It polls because the write latency varies with the
-- session (~1.2s idle, ~3.3s for the running one). Timings for every
-- phase go to the workspace run log (enable with
-- { "workSpaceRunLogs": true } in config/config.json) and to the
-- Hammerspoon console.
--
-- Needs only Hammerspoon's Accessibility permission (already
-- required by the workspace engine).
--
-- Loaded from init.lua as: dofile(obj.spoonPath .. "claude.lua")(obj)

return function(obj)

    local appName = "Claude"

    local function generatedFile()
        return obj.spoonPath .. "availableClaudeComms.lua"
    end

    -- Phase timings and diagnostics: into the run log of the workspace
    -- press that triggered us (when run logs are on), and always to the
    -- Hammerspoon console.
    local function trace(message)
        if obj._runLog then
            obj._runLog("claude: " .. message)
        end

        print("AppLaunchScripts/claude: " .. message)
    end

    local function notify(message)
        hs.alert.show(message, 8)
        print("AppLaunchScripts/claude: " .. message)

        if obj._runLog then
            obj._runLog("claude ALERT: " .. message)
        end
    end

    -- ONE usable Claude application object, or nil. obj._getApp falls
    -- back to hs.application.find(), which returns a LIST when several
    -- processes match — and during a relaunch they do: the instance
    -- quitting and the one starting both answer to "Claude". A list has
    -- no :mainWindow(), and calling it used to abort the whole
    -- workspace press. Prefer a candidate that already has a window.
    local function claudeApp()
        local found = obj._getApp(appName)

        local function usable(candidate)
            return candidate ~= nil and type(candidate.mainWindow) == "function"
        end

        if usable(found) then
            return found
        end

        if type(found) == "table" then
            local fallback

            for _, candidate in ipairs(found) do
                if usable(candidate) then
                    fallback = fallback or candidate

                    if candidate:mainWindow() then
                        return candidate
                    end
                end
            end

            return fallback
        end

        return nil
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

    --- AppLaunchScripts:claudeCodeSessions()
    --- Method
    --- List Claude's coding sessions from its local session store.
    --- Reads title, working directory, and timestamps only —
    --- transcripts are never touched. Archived sessions are skipped.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A list of `{ title, cwd, file, lastFocusedAt }` entries, most recently focused first; empty when the Claude app is not installed or has no sessions
    function obj:claudeCodeSessions()
        local sessions = {}
        local base = os.getenv("HOME")
            .. "/Library/Application Support/Claude/claude-code-sessions/"

        local function scan(dir)
            local ok, iterator, dirObj = pcall(hs.fs.dir, dir)

            if not ok then
                return
            end

            for entry in iterator, dirObj do
                if entry ~= "." and entry ~= ".." then
                    local path = dir .. entry
                    local attributes = hs.fs.attributes(path)

                    if attributes and attributes.mode == "directory" then
                        scan(path .. "/")
                    elseif entry:match("^local_.*%.json$") then
                        local file = io.open(path, "r")
                        local session = file and hs.json.decode(file:read("*a"))

                        if file then
                            file:close()
                        end

                        if session and session.title and session.title ~= ""
                            and not session.isArchived then
                            table.insert(sessions, {
                                title = session.title,
                                cwd = session.cwd,
                                file = path,
                                lastFocusedAt = session.lastFocusedAt or 0,
                            })
                        end
                    end
                end
            end
        end

        scan(base)

        table.sort(sessions, function(a, b)
            return a.lastFocusedAt > b.lastFocusedAt
        end)

        return sessions
    end

    --- AppLaunchScripts:launchClaude()
    --- Method
    --- Launch or focus the Claude app as-is — whatever state it is in.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * `true` when Claude was launched or focused, `false` when it is not installed
    function obj:launchClaude()
        if not hs.application.launchOrFocus(appName) then
            notify('"' .. appName .. '" not installed')
            return false
        end

        return true
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

    -- First AXButton whose label satisfies `matches`.
    local function findButton(matches)
        local ax = require("hs.axuielement")
        local app = claudeApp()

        if not app then
            return nil
        end

        local found

        local function search(element, depth)
            if found or depth > 24 then
                return
            end

            for _, child in ipairs(element:attributeValue("AXChildren") or {}) do
                if tostring(child:attributeValue("AXRole")) == "AXButton"
                    and matches(axLabel(child)) then
                    found = child
                    return
                end

                search(child, depth + 1)
            end
        end

        search(ax.applicationElement(app), 1)

        return found
    end

    -- The sidebar row for a session. Rows label themselves
    -- "<status> <title>", so the title is a SUFFIX. One title can sit
    -- inside another ("Docker setup review" inside "Primanda 2 Docker
    -- setup review"), so collect every candidate and take the SHORTEST
    -- label — least text in front of the title is the exact match.
    local function findSessionRow(title)
        local ax = require("hs.axuielement")
        local app = claudeApp()

        if not app then
            return nil
        end

        local candidates = {}

        local function search(element, depth)
            if depth > 24 then
                return
            end

            for _, child in ipairs(element:attributeValue("AXChildren") or {}) do
                if tostring(child:attributeValue("AXRole")) == "AXButton" then
                    local label = axLabel(child)

                    if #label >= #title
                        and label:sub(-#title) == title
                        and not label:find("^More options") then
                        table.insert(candidates, { element = child, label = label })
                    end
                end

                search(child, depth + 1)
            end
        end

        search(ax.applicationElement(app), 1)

        if #candidates == 0 then
            return nil
        end

        table.sort(candidates, function(a, b)
            return #a.label < #b.label
        end)

        if #candidates > 1 then
            trace(string.format('several rows end with "%s" — taking "%s"',
                title, candidates[1].label))
        end

        return candidates[1].element
    end

    -- Claude's sidebar toggle labels itself by what it will DO:
    -- "Open sidebar" when collapsed, "Collapse sidebar" when open.
    local function sidebarToggle(wanted)
        return findButton(function(label)
            return label:lower():find(wanted) ~= nil
        end)
    end

    -- One read of the session file, for BOTH the session's CURRENT
    -- title (the path is the stable identity, the title is not) and the
    -- lastFocusedAt baseline that confirms the switch.
    local function readSession(sessionFile)
        if not sessionFile then
            return nil
        end

        local file = io.open(sessionFile, "r")
        local session = file and hs.json.decode(file:read("*a"))

        if file then
            file:close()
        end

        if not session then
            return nil
        end

        return {
            title = session.title,
            lastFocusedAt = session.lastFocusedAt or 0,
        }
    end

    -- Is this already the session Claude is showing? Clicking a row
    -- that is already selected records nothing, which would otherwise
    -- look exactly like a lost click. The most recently focused session
    -- is the active one.
    local function isActiveSession(stamp)
        if not stamp then
            return false
        end

        for _, session in ipairs(obj:claudeCodeSessions()) do
            if (session.lastFocusedAt or 0) > stamp then
                return false
            end
        end

        return true
    end

    -- Watch the store until the switch is recorded, or give up. Polls
    -- rather than checking once: the app's write latency varies with
    -- the session (~1.2s idle, ~3.3s running), and a single early check
    -- reports failures that never happened.
    local function watchForSwitch(sessionFile, before, timeout, whenDone)
        local waited = 0
        local timer

        timer = hs.timer.doEvery(0.5, function()
            waited = waited + 0.5

            local session = readSession(sessionFile)

            if session and session.lastFocusedAt > before then
                timer:stop()
                whenDone(true)
            elseif waited >= timeout then
                timer:stop()
                whenDone(false)
            end
        end)
    end

    -- Click an element at its centre: raise the app, scroll the element
    -- into view, re-read its position, click, restore the pointer.
    local function clickRow(row, what, app)
        if app then
            local front = hs.application.frontmostApplication()
            local alreadyFront = front and front:bundleID() == app:bundleID()

            app:activate(true)

            for _ = 1, 60 do
                local now = hs.application.frontmostApplication()

                if now and now:bundleID() == app:bundleID() then
                    break
                end

                hs.timer.usleep(50000)
            end

            -- The first click after a raise is swallowed as the
            -- activating click, so give the window a moment.
            if not alreadyFront then
                hs.timer.usleep(400000)
            end
        end

        row:performAction("AXScrollToVisible")

        local position = row:attributeValue("AXPosition")
        local size = row:attributeValue("AXSize")

        if not position or not size then
            notify(string.format('Claude: "%s" has no position — cannot click it',
                what))
            return false
        end

        local centre = hs.geometry.point(
            position.x + size.w / 2, position.y + size.h / 2)

        local window = app and app:mainWindow()
        local frame = window and window:frame()

        if frame and not centre:inside(frame) then
            notify(string.format('Claude: "%s" is outside the window — not clicking',
                what))
            return false
        end

        trace(string.format('clicking "%s" at %.0f,%.0f (row "%s")',
            what, centre.x, centre.y, axLabel(row)))

        local mouseBefore = hs.mouse.absolutePosition()

        hs.eventtap.leftClick(centre)

        hs.timer.doAfter(0.3, function()
            hs.mouse.absolutePosition(mouseBefore)
        end)

        if window then
            window:focus()
        end

        return true
    end

    --- AppLaunchScripts:launchClaudeComm(title, sessionFile)
    --- Method
    --- Open one Claude coding session: launch or focus the app and
    --- click that session's row in the sidebar. Returns immediately —
    --- all waiting happens on timers, so a workspace press is never
    --- held up. A row that cannot be found, or a click that does not
    --- take, is reported with an alert.
    ---
    --- Parameters:
    ---  * title - the session's title as the catalog knew it; a fallback, since the live title is read from sessionFile
    ---  * sessionFile - path to the session's JSON file, read once for the live title and the confirmation baseline (optional)
    ---
    --- Returns:
    ---  * `true` once the press is under way, `false` when Claude is not installed
    function obj:launchClaudeComm(title, sessionFile)
        if not claudeApp()
            and not hs.application.launchOrFocus(appName) then
            notify('"' .. appName .. '" not installed')
            return false
        end

        local started = hs.timer.secondsSinceEpoch()

        local function since()
            return hs.timer.secondsSinceEpoch() - started
        end

        trace(string.format('open "%s" — app %s', title,
            claudeApp() and "already running" or "cold start"))

        local withWindow

        -- Wait for a window without blocking. An app that is still
        -- QUITTING swallows the launch request — exactly the case when
        -- you quit Claude and press the button straight away — so the
        -- launch is re-issued a few times rather than waiting it out.
        local function waitForWindow()
            local app = claudeApp()

            if app and app:mainWindow() then
                trace(string.format("window ready after %.2fs", since()))
                withWindow(app)
                return
            end

            local relaunches = 0
            local timer

            timer = hs.timer.doEvery(0.5, function()
                local ready = claudeApp()

                if ready and ready:mainWindow() then
                    timer:stop()
                    trace(string.format("window ready after %.2fs", since()))
                    withWindow(ready)
                    return
                end

                if since() > (relaunches + 1) * 6 and relaunches < 4 then
                    relaunches = relaunches + 1
                    trace(string.format(
                        "still no Claude window at %.1fs — re-issuing the launch",
                        since()))
                    hs.application.launchOrFocus(appName)
                end

                if since() > 60 then
                    timer:stop()
                    notify(string.format(
                        "Claude did not open a window within %.0fs — press the button again",
                        since()))
                end
            end)
        end

        withWindow = function(app)
            -- The live title AND the confirmation baseline, from one
            -- read: a session renamed in Claude still resolves, because
            -- the file path does not change when the title does.
            local session = readSession(sessionFile)

            if session and session.title and session.title ~= ""
                and session.title ~= title then
                trace(string.format(
                    'session renamed: catalog says "%s", Claude now says "%s" — using the live title (run help() to regenerate the catalog)',
                    title, session.title))

                title = session.title
            end

            local before = session and session.lastFocusedAt
            local wasActive = isActiveSession(before)

            app:activate(true)

            local function clickWhenFound(row)
                -- The sidebar must be OPEN for the click to land: its
                -- rows stay in the accessibility tree when collapsed and
                -- keep their old coordinates, so the click would go into
                -- the conversation area instead. Checked here, not
                -- earlier — on a cold start the toggle does not exist
                -- until the UI has rendered.
                if sidebarToggle("open sidebar") then
                    trace("sidebar is collapsed — opening it before clicking")

                    if clickRow(sidebarToggle("open sidebar"), "sidebar toggle",
                        claudeApp()) then
                        hs.timer.usleep(800000)
                        row = findSessionRow(title) or row
                    end
                end

                if not clickRow(row, title, claudeApp()) then
                    return
                end

                trace(string.format("row clicked at %.2fs%s", since(),
                    wasActive and " (already the active session)" or ""))

                if not sessionFile or not before then
                    return
                end

                watchForSwitch(sessionFile, before, 8, function(switched)
                    if switched then
                        trace(string.format(
                            'switched to "%s", confirmed at %.2fs', title, since()))
                        return
                    end

                    -- Nothing recorded because nothing needed to change.
                    if wasActive then
                        trace(string.format(
                            '"%s" was already the active session — nothing to record',
                            title))
                        return
                    end

                    trace(string.format(
                        "no switch recorded after %.2fs — clicking once more",
                        since()))

                    local retryRow = findSessionRow(title)

                    if not retryRow
                        or not clickRow(retryRow, title, claudeApp()) then
                        notify(string.format(
                            'Claude did not switch to "%s" — check the app', title))
                        return
                    end

                    watchForSwitch(sessionFile, before, 8, function(again)
                        if again then
                            trace(string.format(
                                'switched to "%s" on the second click, confirmed at %.2fs',
                                title, since()))
                        else
                            notify(string.format(
                                'Claude did not switch to "%s" (clicked twice) — check the app',
                                title))
                        end
                    end)
                end)
            end

            local row = findSessionRow(title)

            if row then
                clickWhenFound(row)
                return
            end

            -- Cold start: the sidebar has not rendered yet. Wait for the
            -- row on a timer and let the workspace press carry on.
            trace(string.format('no row for "%s" yet at %.2fs — waiting',
                title, since()))

            local timer

            timer = hs.timer.doEvery(0.5, function()
                local waiting = findSessionRow(title)

                if waiting then
                    timer:stop()
                    clickWhenFound(waiting)
                    return
                end

                if since() > 60 then
                    timer:stop()
                    notify(string.format(
                        'Claude session "%s" not found in the sidebar after %.0fs — run help() to refresh the catalog',
                        title, since()))
                end
            end)
        end

        waitForWindow()

        return true
    end

    --- AppLaunchScripts:generateClaudeMethods()
    --- Method
    --- Regenerate availableClaudeComms.lua from the scanned coding
    --- sessions and load it: launchClaude() plus one
    --- launchClaudeCode<Title>() per session, each also bound as a
    --- hammerspoon:// URL. Runs automatically when the Spoon loads
    --- and on every help() call, so new and renamed sessions appear
    --- by themselves.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateClaudeMethods()
        -- Remove the previous generation's methods first, so renamed
        -- or archived sessions do not linger as stale methods until
        -- the next reload. (launchClaude itself is a real method,
        -- never removed — _claudeGenerated only tracks catalog-defined
        -- launchers.)
        for _, method in ipairs(obj._claudeGenerated or {}) do
            obj[method] = nil
        end

        local sessions = self:claudeCodeSessions()
        local launchers = {}
        local generated = {}
        local lines = {
            "-- Generated by claude.lua from Claude's own session store",
            "-- — DO NOT EDIT.",
            "--",
            "-- This file is rewritten on every Hammerspoon reload and on",
            "-- every help() call: coding sessions are scanned from the",
            "-- Claude app (titles, folders, and timestamps only) and each",
            "-- becomes a launcher. Rename or archive sessions in Claude",
            "-- and the catalog follows. There is nothing to configure.",
            "--",
            "-- A press opens the session by clicking its row in Claude's",
            "-- sidebar (opening the sidebar first if it is collapsed);",
            "-- nothing is imported, copied, or duplicated.",
            "--",
            "-- COPY-PASTE CATALOG: every function below is documented with",
            "-- its shell command and its hammerspoon:// address — paste the",
            "-- address into a Stream Deck \"Website\" action (Open with:",
            "-- Hammerspoon) to make a button.",
            "return function(obj)",
        }

        -- Method names must be unique. Different session titles can
        -- collide after CamelCasing (duplicates, stray spaces/tabs,
        -- transliterated accents) — colliding entries get an
        -- incremental suffix (Make, Make1, Make2 …) and the catalog
        -- notes who took the name first.
        local usedMethods = {}

        -- The app itself is always launchable, sessions or not.
        table.insert(launchers, "launchClaude")
        table.insert(lines, "")
        table.insert(lines, "    -- Claude — the app itself, whatever state it is in")
        table.insert(lines,
            "    -- shell:  hs -c 'spoon.AppLaunchScripts:launchClaude()'")
        table.insert(lines, "    -- button: hammerspoon://launchclaude")
        usedMethods["launchClaude"] = "Claude — the app itself"

        for _, session in ipairs(sessions) do
            local requested = "launchClaudeCode" .. camelize(session.title)
            local method = requested
            local bump = 0

            while usedMethods[method] do
                bump = bump + 1
                method = requested .. bump
            end

            local what = string.format(
                'Claude coding session "%s" (%s)',
                session.title, session.cwd or "?")

            table.insert(launchers, method)
            table.insert(generated, method)
            table.insert(lines, "")
            table.insert(lines, "    -- " .. what)

            if bump > 0 then
                table.insert(lines, string.format(
                    '    -- NOTE: "%s" was not available — already taken by: %s.',
                    requested, usedMethods[requested]))
                table.insert(lines, string.format(
                    '    --       Session titles collide after CamelCasing; renamed with suffix %d. Rename a session in Claude to untangle.',
                    bump))
            end

            usedMethods[method] = what

            table.insert(lines, string.format(
                "    -- shell:  hs -c 'spoon.AppLaunchScripts:%s()'", method))
            table.insert(lines, string.format(
                "    -- button: hammerspoon://%s", method:lower()))
            table.insert(lines, string.format([[
    function obj:%s()
        return self:launchClaudeComm(%q, %q)
    end]], method, session.title, session.file))
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

        obj._claudeLaunchers = launchers
        obj._claudeGenerated = generated

        -- Stream Deck: every launcher as a hammerspoon:// URL (plus the
        -- lowercase twin — browsers lowercase URL hosts). The handler
        -- looks the method up at press time, so a button assigned to a
        -- since-renamed session alerts instead of crashing.
        for _, method in ipairs(launchers) do
            local handler = function()
                if obj[method] then
                    obj[method](obj)
                else
                    notify(string.format(
                        'Launcher "%s" no longer exists (session renamed or archived?) — reassign the button from availableClaudeComms.lua',
                        method))
                end
            end

            hs.urlevent.bind(method, handler)
            hs.urlevent.bind(method:lower(), handler)
        end

        return self
    end

    obj:generateClaudeMethods()
end
