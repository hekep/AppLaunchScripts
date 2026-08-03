-- Terminal integration for AppLaunchScripts.
--
-- One button per terminal tool: press it and a DEDICATED Terminal
-- window for that tool comes up — created if it does not exist,
-- re-synced if the tool has exited, left strictly alone if it is busy
-- with something else.
--
--   launchTerminalHtop()      -- hammerspoon://launchterminalhtop
--   launchTerminalDockerStats()
--
-- WHAT IDENTIFIES A WINDOW: the AppleScript "custom title" of its
-- FIRST TAB. Terminal folds that title into the window's name, which
-- ends up looking like "you — htop — htop — 80×36", so a workspace
-- entry places it with the existing `window` key — which matches on a
-- title FRAGMENT — and needs no new code:
--
--   { "name": "Terminal", "window": "htop" }
--
-- Do not use "Terminal" as a tool title: a window with no custom
-- title of its own reports exactly that, so it would match the wrong
-- window.
--
-- ONLY TAB 1 IS EVER MANAGED. Open more tabs by hand if you like —
-- they are ignored, and tab 1 is selected before the window is shown
-- so the window title (and therefore workspace matching) stays put.
-- AppleScript counts tabs from 1.
--
-- WHAT A PRESS DOES, in this order:
--   1. Bring the window up (creating it if there is none here).
--   2. Select tab 1 and show it.
--   3. THEN look at what is running in that tab:
--        * the tool is running        -> nothing to do, you are looking at it
--        * the tab is idle at a shell -> re-run the command (the "sync":
--          quit htop by accident and the next press brings it back)
--        * something ELSE is busy     -> focus and LEAVE IT ALONE. An
--          interrupted program is not recoverable; a wrongly focused
--          window is.
--
-- SPACES: Terminal windows behave like Chrome windows — each lives on
-- a Space (or on all of them, if you assigned it that way). A press
-- looks for the tool's window ON THE CURRENT SPACE, which during a
-- workspace press is the workspace's own desktop, because the engine
-- switches Spaces before it fires state urls. A window belonging to a
-- different desktop is never stolen: a new one is created here
-- instead, so the same tool can run on several desktops at once.
--
-- Unlike the accessibility API, AppleScript sees Terminal windows on
-- every Space, so a window parked on another desktop is still found
-- rather than silently duplicated.
--
-- PERMISSION: this needs the one-time macOS Automation approval
-- "Hammerspoon.app wants access to control Terminal.app" — Hammerspoon
-- is the process sending the Apple Events, so Hammerspoon is what
-- macOS asks about. Until it is answered, Hammerspoon BLOCKS. Deny it
-- and no terminal button can work: the accessibility API cannot read a
-- tab's running processes or set a window's title.
--
-- CONFIG: config/terminal/*.json, any number of files, each holding
-- any number of entries. A first file of monitoring tools is written
-- for you if the folder does not exist yet.
--
--   {
--     "terminals": [
--       { "name": "Htop", "title": "htop", "command": "htop",
--         "description": "Processes, CPU and memory. Install: brew install htop" }
--     ]
--   }
--
--   name        -> the method name: launchTerminalHtop()
--   title       -> the window's custom title, and the workspace handle
--                  (defaults to name)
--   command     -> what runs in the tab
--   process     -> what to look for in the tab's process list
--                  (defaults to the command's first word; "docker stats"
--                  needs "docker")
--   cwd         -> optional directory to cd into first
--   description -> shown in the catalog; end it with the install command
--
-- Loaded from init.lua as: dofile(obj.spoonPath .. "terminal.lua")(obj)

return function(obj)

    local appName = "Terminal"

    local function configDir()
        return obj.spoonPath .. "config/terminal/"
    end

    local function generatedFile()
        return obj.spoonPath .. "availableTerminalComms.lua"
    end

    local function trace(message)
        if obj._runLog then
            obj._runLog("terminal: " .. message)
        end

        print("AppLaunchScripts/terminal: " .. message)
    end

    local function notify(message)
        hs.alert.show(message, 8)
        print("AppLaunchScripts/terminal: " .. message)

        if obj._runLog then
            obj._runLog("terminal ALERT: " .. message)
        end
    end

    -- Same rules as the other modules: Lua identifiers are ASCII-only.
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

    -- A Lua string as an AppleScript string literal.
    local function asString(value)
        return '"' .. tostring(value)
            :gsub("\\", "\\\\")
            :gsub('"', '\\"') .. '"'
    end

    local function runAppleScript(script)
        local ok, result, raw = hs.osascript.applescript(script)

        if not ok then
            trace("AppleScript failed: " .. tostring(raw))
            return nil
        end

        return result
    end

    -- The defaults written on first run, so the folder is never empty
    -- and every button below is real the moment the Spoon loads.
    local defaultTools = [[{
  "terminals": [
    {
      "name": "Htop",
      "title": "htop",
      "command": "htop",
      "description": "Processes, CPU and memory — the everyday monitor. Install: brew install htop"
    },
    {
      "name": "Btop",
      "title": "btop",
      "command": "btop",
      "description": "htop with graphs — CPU, memory, disks and network on one screen. Install: brew install btop"
    },
    {
      "name": "Glances",
      "title": "glances",
      "command": "glances",
      "description": "Everything at once: processes, sensors, containers, network. Install: brew install glances"
    },
    {
      "name": "Top",
      "title": "top",
      "command": "top -o cpu",
      "description": "Process monitor sorted by CPU. Install: built-in, none needed"
    },
    {
      "name": "MemoryPressure",
      "title": "vm-stat",
      "command": "vm_stat 2",
      "process": "vm_stat",
      "description": "Virtual memory pages and paging activity every 2s. Install: built-in, none needed"
    },
    {
      "name": "DiskIo",
      "title": "iostat",
      "command": "iostat -w 2",
      "process": "iostat",
      "description": "Disk throughput and CPU load every 2s. Install: built-in, none needed"
    },
    {
      "name": "DiskUsage",
      "title": "ncdu",
      "command": "ncdu /",
      "description": "Browse what is eating the disk, and delete from inside it. Install: brew install ncdu"
    },
    {
      "name": "NetTop",
      "title": "nettop",
      "command": "nettop -P",
      "description": "Network throughput per process. Install: built-in, none needed"
    },
    {
      "name": "DockerStats",
      "title": "docker-stats",
      "command": "docker stats",
      "process": "docker",
      "description": "Live CPU, memory, network and disk per container. Install: Docker Desktop"
    },
    {
      "name": "LazyDocker",
      "title": "lazydocker",
      "command": "lazydocker",
      "description": "Full container TUI — logs, stats, shells, restarts. Install: brew install lazydocker"
    }
  ]
}
]]

    --- AppLaunchScripts:terminalTools()
    --- Method
    --- Read every terminal entry from config/terminal/*.json. Creates
    --- the folder with a monitoring-tools file on first run.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A list of `{ name, title, command, process, cwd, description, source }` entries
    function obj:terminalTools()
        local dir = configDir()

        if not hs.fs.attributes(dir) then
            hs.fs.mkdir(dir)

            local seed = io.open(dir .. "monitoringTools.json", "w")

            if seed then
                seed:write(defaultTools)
                seed:close()
                trace("created config/terminal/monitoringTools.json with the default monitoring tools")
            end
        end

        local tools = {}
        local ok, iterator, dirObj = pcall(hs.fs.dir, dir)

        if not ok then
            return tools
        end

        local files = {}

        for entry in iterator, dirObj do
            if entry:match("%.json$") then
                table.insert(files, entry)
            end
        end

        table.sort(files)

        for _, entry in ipairs(files) do
            local file = io.open(dir .. entry, "r")
            local config = file and hs.json.decode(file:read("*a"))

            if file then
                file:close()
            end

            for _, tool in ipairs(config and config.terminals or {}) do
                if tool.name and tool.command then
                    table.insert(tools, {
                        name = tool.name,
                        title = tool.title or tool.name,
                        command = tool.command,
                        -- "docker stats" runs as "docker": the first
                        -- word is the right default, not always right.
                        process = tool.process or tool.command:match("^(%S+)"),
                        cwd = tool.cwd,
                        description = tool.description,
                        source = entry,
                    })
                end
            end
        end

        return tools
    end

    -- The id of the Terminal window whose FIRST TAB carries this custom
    -- title, or nil. AppleScript sees windows on every Space, so this
    -- finds the window even when it lives on another desktop.
    local function findWindowIds(title)
        local result = runAppleScript(string.format([[
tell application "Terminal"
  set found to {}
  repeat with w in windows
    try
      if (custom title of tab 1 of w) is %s then set end of found to (id of w)
    end try
  end repeat
  set oldD to AppleScript's text item delimiters
  set AppleScript's text item delimiters to ","
  set r to found as text
  set AppleScript's text item delimiters to oldD
  return r
end tell]], asString(title)))

        local ids = {}

        for id in (result or ""):gmatch("%d+") do
            table.insert(ids, tonumber(id))
        end

        return ids
    end

    -- Is this window usable from where we are standing? A window
    -- assigned to all Spaces reports many; one on another desktop
    -- reports only that one.
    -- "here", "elsewhere" or "unknown".
    --
    -- Unknown is not a rounding error: a MINIMIZED or hidden window
    -- reports no spaces at all (measured 2026-08-02), and treating that
    -- as "elsewhere" made a press ignore the window actually running
    -- the tool and act on an idle one instead. Unknown windows stay
    -- candidates; they just rank below a window we can see is here.
    local function whereIsWindow(windowId)
        local spaces = hs.spaces.windowSpaces(windowId)

        if spaces == nil or #spaces == 0 then
            return "unknown"
        end

        if hs.fnutils.contains(spaces, hs.spaces.focusedSpace()) then
            return "here"
        end

        return "elsewhere"
    end

    -- Bring the window forward with tab 1 selected and displayed.
    local function showWindow(windowId)
        runAppleScript(string.format([[
tell application "Terminal"
  activate
  set w to (first window whose id is %d)
  if miniaturized of w then set miniaturized of w to false
  set selected of tab 1 of w to true
  set index of w to 1
  set frontmost of w to true
end tell]], windowId))

        local window = hs.window.get(windowId)

        if window then
            if window:isMinimized() then
                window:unminimize()
            end

            window:focus()
        end
    end

    -- A tab sitting at a prompt still lists its shell. Anything BEYOND
    -- these is a program someone is running.
    local shellProcesses = {
        ["login"] = true, ["su"] = true, ["sudo"] = true,
        ["zsh"] = true, ["-zsh"] = true, ["bash"] = true, ["-bash"] = true,
        ["sh"] = true, ["-sh"] = true, ["fish"] = true, ["-fish"] = true,
        ["csh"] = true, ["-csh"] = true, ["tcsh"] = true, ["-tcsh"] = true,
    }

    -- What tab 1 is doing: busy true/false, plus the process list.
    local function inspectTab(windowId)
        local result = runAppleScript(string.format([[
tell application "Terminal"
  set t to tab 1 of (first window whose id is %d)
  set oldDelims to AppleScript's text item delimiters
  set AppleScript's text item delimiters to ","
  set p to (processes of t) as text
  set AppleScript's text item delimiters to oldDelims
  return ((busy of t) as text) & "|" & p
end tell]], windowId))

        if not result then
            return nil
        end

        local busy, processes = result:match("^([^|]*)|(.*)$")

        -- Split the list and work out what is actually running there.
        -- `busy` is NOT trustworthy: Terminal reports busy=false while
        -- htop is running full-screen (measured 2026-08-02), so a tab
        -- holding vim would look idle and we would type a command into
        -- it. The process list is the only reliable signal; busy is
        -- kept only as a second opinion.
        local running = {}

        for entry in (processes or ""):gmatch("[^,]+") do
            entry = entry:match("^%s*(.-)%s*$")

            if entry ~= "" and not shellProcesses[entry] then
                table.insert(running, entry)
            end
        end

        return {
            busy = busy == "true",
            processes = processes or "",
            running = running,
        }
    end

    -- Which of the candidate windows is OUR window?
    --
    -- Terminal COPIES the custom title into new tabs and windows opened
    -- from one that has it (measured 2026-08-02: Cmd+T in the htop
    -- window produced a second window also called "htop"), so the title
    -- alone is not unique. Prefer, in order: a window on this desktop
    -- that is actually running the tool, then any window on this
    -- desktop. A window that only exists on another desktop is not ours
    -- to take — we return nil and the caller creates one here.
    local function pickWindow(ids, process)
        local best, bestScore = nil, 0

        for _, id in ipairs(ids) do
            local place = whereIsWindow(id)

            if place ~= "elsewhere" then
                local tab = inspectTab(id)
                local runsIt = tab
                    and hs.fnutils.contains(tab.running, process)

                -- here + running it  > here  > unknown + running it > unknown
                local score = (place == "here" and 2 or 0)
                    + (runsIt and 1 or 0) + 1

                if score > bestScore then
                    best, bestScore = id, score
                end
            end
        end

        if best and #ids > 1 then
            trace(string.format(
                '%d windows carry this title — picked %d (%s, %s running "%s")',
                #ids, best, whereIsWindow(best),
                bestScore % 2 == 0 and "is" or "is not", process))
        end

        return best
    end

    local function fullCommand(command, cwd)
        if cwd and cwd ~= "" then
            return string.format("cd %s && %s", cwd, command)
        end

        return command
    end

    -- Run the command in tab 1 of an existing window.
    local function runInTab(windowId, command, cwd)
        runAppleScript(string.format([[
tell application "Terminal"
  do script %s in tab 1 of (first window whose id is %d)
end tell]], asString(fullCommand(command, cwd)), windowId))
    end

    -- Create the window here, on the Space we are standing on, and
    -- give its tab the custom title that identifies it from now on.
    local function createWindow(title, command, process, cwd)
        runAppleScript(string.format([[
tell application "Terminal"
  activate
  set t to do script %s
  set custom title of t to %s
end tell]], asString(fullCommand(command, cwd)), asString(title)))

        -- Re-find rather than trusting "front window": the tab now
        -- carries the title, so the normal lookup is authoritative.
        for _ = 1, 20 do
            local ids = findWindowIds(title)

            if #ids > 0 then
                return pickWindow(ids, process) or ids[#ids]
            end

            hs.timer.usleep(100000)
        end

        return nil
    end

    --- AppLaunchScripts:launchTerminalComm(title, command, process, cwd)
    --- Method
    --- Show the dedicated Terminal window for one tool and keep its
    --- command in sync: create the window if this desktop has none,
    --- re-run the command if the tool has exited, and leave the window
    --- strictly alone when it is busy with something else.
    ---
    --- Parameters:
    ---  * title - the window's custom title, identifying it
    ---  * command - the command to run in tab 1
    ---  * process - the process name to look for (optional, defaults to the command's first word)
    ---  * cwd - directory to cd into first (optional)
    ---
    --- Returns:
    ---  * `true` when the window is up, `false` when Terminal is unavailable
    function obj:launchTerminalComm(title, command, process, cwd)
        process = process or command:match("^(%S+)")

        local started = hs.timer.secondsSinceEpoch()

        local function since()
            return hs.timer.secondsSinceEpoch() - started
        end

        local candidates = findWindowIds(title)
        local windowId = pickWindow(candidates, process)

        if not windowId and #candidates > 0 then
            trace(string.format(
                '"%s" exists on another desktop — creating one here instead of stealing it',
                title))
        end

        -- 1. Window up, creating it if this desktop has none.
        if not windowId then
            windowId = createWindow(title, command, process, cwd)

            if not windowId then
                notify(string.format(
                    'Could not open a Terminal window for "%s"', title))
                return false
            end

            trace(string.format('created "%s" window (id %d) in %.2fs — running: %s',
                title, windowId, since(), fullCommand(command, cwd)))

            showWindow(windowId)

            return true
        end

        -- 2. Show it, tab 1 selected, BEFORE looking at what it runs —
        -- so a command that fails instantly fails where you can see it.
        showWindow(windowId)

        -- 3. Now decide whether anything needs doing.
        local tab = inspectTab(windowId)

        if not tab then
            trace(string.format('showed "%s" but could not read tab 1', title))
            return true
        end

        if hs.fnutils.contains(tab.running, process) then
            trace(string.format('"%s" already running (%s) — shown, nothing to do',
                title, tab.processes))
            return true
        end

        if #tab.running > 0 or tab.busy then
            -- Something else is in there — vim, a build, an ssh
            -- session. Never interrupt it: an interrupted program is
            -- not recoverable, a wrongly focused window is.
            trace(string.format(
                '"%s" is busy with something else (%s) — focused, left alone',
                title, table.concat(tab.running, ", ")))
            return true
        end

        trace(string.format('"%s" was idle (%s) — restarting: %s',
            title, tab.processes, fullCommand(command, cwd)))

        runInTab(windowId, command, cwd)

        return true
    end

    -- ================= shell scripts (config/terminal/shells/) =========
    -- Every script in that folder becomes a button. They all share ONE
    -- Terminal window on Desktop 1: a script runs only when that window
    -- is idle, and a press while something is still running is refused
    -- rather than typed into it.
    local shellWindowTitle = "shells"

    local function shellsDir()
        return configDir() .. "shells/"
    end

    -- The script's own first comment line, used as its catalog
    -- description — so a script documents its own button.
    local function scriptDescription(path)
        local file = io.open(path, "r")

        if not file then
            return nil
        end

        local description

        for _ = 1, 10 do
            local line = file:read("*l")

            if not line then
                break
            end

            if not line:match("^#!") then
                local text = line:match("^#%s*(.+)$")

                if text then
                    description = text
                    break
                end

                if line:match("%S") then
                    break
                end
            end
        end

        file:close()

        return description
    end

    --- AppLaunchScripts:shellScripts()
    --- Method
    --- Scan config/terminal/shells/ for runnable scripts. Creates the
    --- folder if it does not exist. README.md and dotfiles are skipped.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * A list of `{ name, path, description }` entries, sorted by name
    function obj:shellScripts()
        local dir = shellsDir()

        if not hs.fs.attributes(dir) then
            hs.fs.mkdir(dir)
        end

        local scripts = {}
        local ok, iterator, dirObj = pcall(hs.fs.dir, dir)

        if not ok then
            return scripts
        end

        for entry in iterator, dirObj do
            if entry:sub(1, 1) ~= "." and entry ~= "README.md" then
                local path = dir .. entry
                local attributes = hs.fs.attributes(path)
                local permissions = attributes and attributes.permissions or ""

                -- Anything executable, plus anything named *.sh so a
                -- script that lost its +x bit still shows up.
                if attributes and attributes.mode == "file"
                    and (entry:match("%.sh$") or permissions:sub(3, 3) == "x") then
                    table.insert(scripts, {
                        name = entry:gsub("%.%w+$", ""),
                        path = path,
                        description = scriptDescription(path),
                    })
                end
            end
        end

        table.sort(scripts, function(a, b)
            return a.name < b.name
        end)

        return scripts
    end

    --- AppLaunchScripts:launchShellComm(label, path)
    --- Method
    --- Run one shell script in the shared shell window on Desktop 1:
    --- switch there, bring the window up (creating it if needed), and
    --- run the script only when the window is idle. A window still busy
    --- with an earlier script is reported and the launch is cancelled.
    ---
    --- Parameters:
    ---  * label - the script's name, for messages
    ---  * path - absolute path to the script
    ---
    --- Returns:
    ---  * `true` when the script was started, `false` when the window was busy or unavailable
    function obj:launchShellComm(label, path)
        -- Desktop 1 means the FIRST Space of the screen you are on.
        local screen = hs.screen.mainScreen()
        local spaces = screen and hs.spaces.spacesForScreen(screen)
        local desktopOne = spaces and spaces[1]

        if desktopOne and hs.spaces.focusedSpace() ~= desktopOne then
            trace(string.format('switching to Desktop 1 (space %d) to run "%s"',
                desktopOne, label))
            hs.spaces.gotoSpace(desktopOne)
            hs.timer.usleep(700000)
        end

        -- Single-quoted so paths with spaces survive the shell.
        local command = "'" .. path .. "'"
        local windowId = pickWindow(findWindowIds(shellWindowTitle), label)

        if not windowId then
            windowId = createWindow(shellWindowTitle, command, label, nil)

            if not windowId then
                notify(string.format('Could not open the shell window for "%s"',
                    label))
                return false
            end

            trace(string.format('created the shared shell window (id %d) — running "%s"',
                windowId, label))
            showWindow(windowId)

            return true
        end

        -- Always focused, as asked: you see the window before anything
        -- else happens, whether it runs or is refused.
        showWindow(windowId)

        local tab = inspectTab(windowId)

        if tab and (#tab.running > 0 or tab.busy) then
            notify(string.format(
                'Shell window is busy running %s — "%s" was not started, try again later',
                table.concat(tab.running, ", "), label))
            return false
        end

        trace(string.format('running "%s" in the shared shell window', label))
        runInTab(windowId, command, nil)

        return true
    end

    --- AppLaunchScripts:generateTerminalMethods()
    --- Method
    --- Regenerate availableTerminalComms.lua from config/terminal/*.json
    --- and load it: one launchTerminal<Name>() per entry, each also
    --- bound as a hammerspoon:// URL. Runs when the Spoon loads and on
    --- every help() call.
    ---
    --- Parameters:
    ---  * None
    ---
    --- Returns:
    ---  * The AppLaunchScripts object
    function obj:generateTerminalMethods()
        for _, method in ipairs(obj._terminalGenerated or {}) do
            obj[method] = nil
        end

        local tools = self:terminalTools()
        local launchers = {}
        local generated = {}
        local lines = {
            "-- Generated by terminal.lua from config/terminal/*.json",
            "-- — DO NOT EDIT.",
            "--",
            "-- One dedicated Terminal window per tool, identified by the",
            "-- custom title of its first tab. A press shows that window,",
            "-- selects tab 1, and then restarts the tool if it had exited.",
            "-- A window busy with something else is focused and left alone.",
            "--",
            "-- The title is also the window title, so a workspace can place",
            "-- it with:  { \"name\": \"Terminal\", \"window\": \"<title>\" }",
            "--",
            "-- COPY-PASTE CATALOG: every function below is documented with",
            "-- its shell command and its hammerspoon:// address — paste the",
            "-- address into a Stream Deck \"Website\" action (Open with:",
            "-- Hammerspoon) to make a button.",
            "return function(obj)",
        }

        local usedMethods = {}
        local usedTitles = {}

        for _, tool in ipairs(tools) do
            local requested = "launchTerminal" .. camelize(tool.name)
            local method = requested
            local bump = 0

            while usedMethods[method] do
                bump = bump + 1
                method = requested .. bump
            end

            local what = string.format('Terminal tool "%s" — %s',
                tool.title, tool.description or tool.command)

            table.insert(launchers, method)
            table.insert(generated, method)
            table.insert(lines, "")
            table.insert(lines, "    -- " .. what)
            table.insert(lines, string.format("    -- runs:   %s",
                fullCommand(tool.command, tool.cwd)))
            table.insert(lines, string.format("    -- window: %s   (from %s)",
                tool.title, tool.source))

            if bump > 0 then
                table.insert(lines, string.format(
                    '    -- NOTE: "%s" was not available — already taken by: %s.',
                    requested, usedMethods[requested]))
            end

            -- Two tools fighting over one window would each restart the
            -- other's command forever; say so rather than let it happen.
            if usedTitles[tool.title] then
                table.insert(lines, string.format(
                    '    -- WARNING: window title "%s" is also used by %s — give one of them a different "title".',
                    tool.title, usedTitles[tool.title]))
                notify(string.format(
                    'Terminal config: two tools share the window title "%s" (%s and %s) — rename one',
                    tool.title, usedTitles[tool.title], tool.name))
            end

            usedMethods[method] = what
            usedTitles[tool.title] = tool.name

            table.insert(lines, string.format(
                "    -- shell:  hs -c 'spoon.AppLaunchScripts:%s()'", method))
            table.insert(lines, string.format(
                "    -- button: hammerspoon://%s", method:lower()))
            table.insert(lines, string.format([[
    function obj:%s()
        return self:launchTerminalComm(%q, %q, %q, %s)
    end]], method, tool.title, tool.command, tool.process,
                tool.cwd and string.format("%q", tool.cwd) or "nil"))
        end

        -- Shell scripts: one button each, all sharing one window.
        local shellLaunchers = {}
        local scripts = self:shellScripts()

        if #scripts > 0 then
            table.insert(lines, "")
            table.insert(lines, "    -- ---- Shell scripts (config/terminal/shells/) ----")
            table.insert(lines, "    -- All of these share ONE Terminal window on Desktop 1.")
            table.insert(lines, "    -- A script runs only when that window is idle; a press")
            table.insert(lines, "    -- while something is still running is refused, not queued.")
        end

        for _, script in ipairs(scripts) do
            local requested = "launchShell" .. camelize(script.name)
            local method = requested
            local bump = 0

            while usedMethods[method] do
                bump = bump + 1
                method = requested .. bump
            end

            local what = string.format('Shell script "%s"%s', script.name,
                script.description and (" — " .. script.description) or "")

            table.insert(launchers, method)
            table.insert(generated, method)
            table.insert(shellLaunchers, method)
            table.insert(lines, "")
            table.insert(lines, "    -- " .. what)

            if bump > 0 then
                table.insert(lines, string.format(
                    '    -- NOTE: "%s" was not available — already taken by: %s.',
                    requested, usedMethods[requested]))
            end

            usedMethods[method] = what

            table.insert(lines, string.format(
                "    -- shell:  hs -c 'spoon.AppLaunchScripts:%s()'", method))
            table.insert(lines, string.format(
                "    -- button: hammerspoon://%s", method:lower()))
            table.insert(lines, string.format([[
    function obj:%s()
        return self:launchShellComm(%q, %q)
    end]], method, script.name, script.path))
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

        obj._terminalLaunchers = launchers
        obj._terminalGenerated = generated
        obj._shellLaunchers = shellLaunchers

        for _, method in ipairs(launchers) do
            local handler = function()
                if obj[method] then
                    obj[method](obj)
                else
                    notify(string.format(
                        'Launcher "%s" no longer exists — reassign the button from availableTerminalComms.lua',
                        method))
                end
            end

            hs.urlevent.bind(method, handler)
            hs.urlevent.bind(method:lower(), handler)
        end

        return self
    end

    obj:generateTerminalMethods()
end
