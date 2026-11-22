local DISABLE_GAME_DIR_MAPS = false
local DISABLE_USER_DIR_MAPS = false
local DISABLE_USER_DIR_SAVS = false
local DISABLE_GAME_DIR_MAPS_EXTREME = false
local DISABLE_USER_DIR_MAPS_EXTREME = false
local DISABLE_USER_DIR_SAVS_EXTREME = false

local EXTRA_DIRS = {}

--[[
Dated map availability.

An extra map directory may contain a file named availability.json:

  {
    "format": 1,
    "maps": {
      "Door01": "2026-12-01",
      "Door02": "2026-12-02"
    }
  }

A map named in "maps" (with or without ".map") is listed by the game only from that date on,
in the player's local time. Maps that are not named are listed as before. A missing or invalid
file, or an invalid entry, never hides a map: a warning is logged and the map is listed.

The option "map-availability-date" ("YYYY-MM-DD") makes that date count as today, so map
authors and testers can preview a schedule without changing the system clock.

The date is checked each time the game builds its map list, so a map whose date arrives while
the game runs appears the next time the list is built.
--]]
local AVAILABILITY_FILE_NAME = "availability.json"

---Per FindFirstFile pattern of an extra directory (lower case): lower-case map name -> yyyymmdd
---@type table<string, table<string, number>>
local AVAILABLE_FROM = {}

---yyyymmdd that counts as today instead of the system date, or nil
---@type number|nil
local TODAY_OVERRIDE = nil

---Parses "YYYY-MM-DD" into yyyymmdd, or returns nil
local function parseDate(value)
    if type(value) ~= "string" then return nil end
    local y, m, d = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y == nil then return nil end
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
    return y * 10000 + m * 100 + d
end

local function today()
    if TODAY_OVERRIDE ~= nil then return TODAY_OVERRIDE end
    local now = os.date("*t")
    return now.year * 10000 + now.month * 100 + now.day
end

local function mapKey(name)
    local key = name:lower()
    if key:sub(-4) == ".map" then key = key:sub(1, -5) end
    return key
end

---Reads the availability.json of an extra map directory.
---@param dir string the directory as registered
---@return table<string, number>|nil lower-case map name -> yyyymmdd, nil without a usable file
local function readAvailability(dir)
    local path = dir
    if path:sub(-1) ~= "/" and path:sub(-1) ~= "\\" then path = path .. "/" end
    path = path .. AVAILABILITY_FILE_NAME

    local handle = io.open(path, "rb")
    if handle == nil then return nil end
    local text = handle:read("*all")
    handle:close()

    local ok, data = pcall(function() return json:decode(text) end)
    if not ok or type(data) ~= "table" or type(data.maps) ~= "table" then
        log(WARNING, string.format("%s is not a valid availability file; every map in this folder is listed", path))
        return nil
    end
    if data.format ~= nil and data.format ~= 1 then
        log(WARNING, string.format("%s: unknown format %s; every map in this folder is listed", path, tostring(data.format)))
        return nil
    end

    local result = {}
    local count = 0
    for name, date in pairs(data.maps) do
        local from = parseDate(date)
        if type(name) ~= "string" or name == "" or from == nil then
            log(WARNING, string.format("%s: entry %s = %s ignored (expected a map name and \"YYYY-MM-DD\"); the map is listed",
                path, tostring(name), tostring(date)))
        else
            result[mapKey(name)] = from
            count = count + 1
        end
    end
    log(INFO, string.format("%s: %d maps with a date", path, count))
    return result
end

---Remembers the dated maps of an extra directory under its FindFirstFile pattern
local function registerAvailability(fnfDir, dir)
    local dated = readAvailability(dir)
    if dated ~= nil then
        AVAILABLE_FROM[fnfDir:lower()] = dated
    end
end

local function setTodayOverride(value)
    if value == nil or value == "" then
        TODAY_OVERRIDE = nil
        return
    end
    local parsed = parseDate(value)
    if parsed == nil then
        log(WARNING, string.format("map-availability-date: %s ignored (expected \"YYYY-MM-DD\")", tostring(value)))
        TODAY_OVERRIDE = nil
        return
    end
    log(INFO, string.format("map-availability-date: dated maps are listed as on %s", value))
    TODAY_OVERRIDE = parsed
end

local function RawFindFileInterface()
    local addressOfFindFirstFileARef = core.readInteger(core.AOBScan("8D 4C 24 60 51 57") + 8)
    local addressOfFindFirstFileA = core.readInteger(addressOfFindFirstFileARef)
    local callingConventionFindFirstFileA = 2
    local argCountFindFirstFileA = 2

    local FindFirstFileA = core.exposeCode(addressOfFindFirstFileA, argCountFindFirstFileA,
        callingConventionFindFirstFileA) -- actually stdcall, so 2 args

    local addressOfFindNextFileARef = core.readInteger(core.AOBScan("8D 4C 24 60 51 52") + 8)
    local addressOfFindNextFileA = core.readInteger(addressOfFindNextFileARef)
    local callingConventionFindNextFileA = 2
    local argCountFindNextFileA = 2

    local FindNextFileA = core.exposeCode(addressOfFindNextFileA, argCountFindNextFileA, callingConventionFindNextFileA) -- actually stdcall

    local addressOfFindCloseRef = core.readInteger(core.AOBScan("FF ? ? ? ? ? 8B ? ? ? ? ? ? 64 ? ? ? ? ? ? 59") + 2)
    local addressOfFindClose = core.readInteger(addressOfFindCloseRef)
    local callingConventionFindClose = 2
    local argCountFindClose = 1

    local FindClose = core.exposeCode(addressOfFindClose, argCountFindClose, callingConventionFindClose)

    local addressOfGetTimeZoneInformationRef = core.readInteger(core.AOBScan("FF ? ? ? ? ? 83 F8 01 75 09") + 2)
    local addressOfGetTimeZoneInformation = core.readInteger(addressOfGetTimeZoneInformationRef)
    local callingConventionGetTimeZoneInformation = 2
    local argCountGetTimeZoneInformation = 1

    local GetTimeZoneInformation = core.exposeCode(addressOfGetTimeZoneInformation, argCountGetTimeZoneInformation,
        callingConventionGetTimeZoneInformation)

    local allmul = core.exposeCode(core.AOBScan("8B 44 24 08 8B 4C 24 10 0B C8"), 4, 2)

    local addressOfFileTimeToDosDateTimeRef = core.readInteger(core.AOBScan(
        "83 F8 FF 89 44 24 24 0F ? ? ? ? ? 81 3E F4 01 00 00") + 25 + 2)
    local addressOfFileTimeToDosDateTime = core.readInteger(addressOfFileTimeToDosDateTimeRef)
    local callingConventionFileTimeToDosDateTime = 2
    local argCountFileTimeToDosDateTime = 3

    local FileTimeToDosDateTime = core.exposeCode(addressOfFileTimeToDosDateTime, argCountFileTimeToDosDateTime,
        callingConventionFileTimeToDosDateTime)

    local ptr_ResourceManager = core.readInteger(core.AOBScan("A1 ? ? ? ? 89 46 74 33 C0 39 ? ? ? ? ? 7E 15") + 1)
    local ptr_LoadedMapNames = ptr_ResourceManager + 0xbc8
    local ptr_MapFileTimeArray = ptr_ResourceManager + 0x7fd14


    return {
        FindFirstFileA = FindFirstFileA,
        FindNextFileA = FindNextFileA,
        FindClose = FindClose,
        GetTimeZoneInformation = GetTimeZoneInformation,
        allmul = allmul,
        FileTimeToDosDateTime = FileTimeToDosDateTime,
        ptr_LoadedMapNames = ptr_LoadedMapNames,
        ptr_MapFileTimeArray = ptr_MapFileTimeArray,
        ptr_ResourceManager = ptr_ResourceManager,
        ptr_MapFileCounter = ptr_ResourceManager, -- integer value
    }
end

local rawInterface = RawFindFileInterface()

local ptr_timeZoneInformation = core.allocate(172)
local timeZoneOffset = 0 -- 64 bit
local timeZoneOffsetLow = 0
local timeZoneOffsetHigh = 0

local function computeTimeZoneOffset()
    local v = rawInterface.GetTimeZoneInformation(ptr_timeZoneInformation)
    local lowOrder = 0
    local highOrder = 0
    if v == 1 then
        lowOrder = -1 * core.readInteger(ptr_timeZoneInformation + 0x54)
        highOrder = (lowOrder & 0xFFFFFFFF) >> 0x1F
    elseif v == 2 then
        lowOrder = -1 * core.readInteger(ptr_timeZoneInformation + 0xa8)
        highOrder = (lowOrder & 0xFFFFFFFF) >> 0x1F
    end

    timeZoneOffset = rawInterface.allmul(lowOrder, highOrder, 600000000, 0)
    timeZoneOffsetLow = timeZoneOffset & 0xFFFFFFFF
    timeZoneOffsetHigh = (timeZoneOffset >> 0x20) & 0xFFFFFFFF
    return timeZoneOffset
end

local ptr_filetime = core.allocate(8)
local ptr_dosDateTime = core.allocate(4)

local ptr_win32FindData = core.allocate(320)

local function dosTime()
    core.writeInteger(ptr_dosDateTime, 0)

    local low = core.readInteger(ptr_win32FindData + 0x14 + 0) + timeZoneOffsetLow
    local high = core.readInteger(ptr_win32FindData + 0x14 + 4) + timeZoneOffsetHigh
    core.writeInteger(ptr_filetime + 0, low)
    local carry = 0
    if (low >> 0x20) > 0 then carry = 1 end
    core.writeInteger(ptr_filetime + 4, high + carry)

    rawInterface.FileTimeToDosDateTime(ptr_filetime, ptr_dosDateTime + 2, ptr_dosDateTime)

    return core.readInteger(ptr_dosDateTime)
end

local function filename()
    return core.readString(ptr_win32FindData + 0x2c)
end

local ptr_stringBufferThing = core.allocate(28)

local documentsMapPattern

local function getDocumentsMapPattern()
    local _f = core.exposeCode(
        core.AOBScan(
            "6A FF 68 ? ? ? ? 64 A1 00 00 00 00 50 83 EC 40 A1 ? ? ? ? 33 C4 89 44 24 3C 53 55 56 57 A1 ? ? ? ? 33 C4 50 8D 44 24 54 64 A3 00 00 00 00 8B 7C 24 64 33 DB 53 8D 44 24 38 50 89 5C 24 1C E8 ? ? ? ? 6A 05"),
        3, 1)
    _f(rawInterface.ptr_ResourceManager, ptr_stringBufferThing, 1)
    local _g = core.exposeCode(core.AOBScan("53 56 8B F1 8B 56 18"), 3, 1)
    _g(ptr_stringBufferThing, ucp.internal.registerString("*.map"), 5)

    if core.readInteger(ptr_stringBufferThing + 0x18) < 0x10 then
        documentsMapPattern = core.readString(ptr_stringBufferThing + 0x4)
    else
        documentsMapPattern = core.readString(core.readInteger(ptr_stringBufferThing + 0x4))
    end
end

local documentsFolder

local function getDocumentsFolder()
    local _f = core.exposeCode(
        core.AOBScan(
            "6A FF 68 ? ? ? ? 64 A1 00 00 00 00 50 83 EC 40 A1 ? ? ? ? 33 C4 89 44 24 3C 53 55 56 57 A1 ? ? ? ? 33 C4 50 8D 44 24 54 64 A3 00 00 00 00 8B 7C 24 64 33 DB 6A 15"),
        3, 1)
    _f(rawInterface.ptr_ResourceManager, ptr_stringBufferThing, 1)

    if core.readInteger(ptr_stringBufferThing + 0x18) < 0x10 then
        documentsFolder = core.readString(ptr_stringBufferThing + 0x4)
    else
        documentsFolder = core.readString(core.readInteger(ptr_stringBufferThing + 0x4))
    end

    log(VERBOSE, string.format("getDocumentsFolder: %s", documentsFolder))
end

local ptr_targetPattern = core.allocate(1001)

local DiscoveryHandler = {

    new = function(self)
        local o = setmetatable({
            filenames = {},
            filetimes = {},
            count = 0,
        }, self)

        self.__index = self

        return o
    end,

    discoverForPattern = function(self, pattern)
        log(VERBOSE, string.format("discoverForPattern: %s", pattern))

        if self.count >= 500 then return false end

        core.setMemory(ptr_targetPattern, 0, 1001)
        core.writeString(ptr_targetPattern, pattern)
        local handle = rawInterface.FindFirstFileA(ptr_targetPattern, ptr_win32FindData)

        local dated = AVAILABLE_FROM[pattern:lower()]
        local now = dated ~= nil and today() or nil
        local notYet = 0

        if handle ~= -1 then
            while self.count < 500 do
                local name = filename()
                local t = dosTime()

                local from = dated ~= nil and dated[mapKey(name)] or nil
                if from ~= nil and from > now then
                    log(VERBOSE, string.format("discoverForPattern: %s is listed from %d on", name, from))
                    notYet = notYet + 1
                else
                    if self.filetimes[name:lower()] == nil then
                        log(VERBOSE, string.format("discoverForPattern: discovered new map: %s", name))
                        table.insert(self.filenames, name)
                        self.count = self.count + 1
                    end

                    self.filetimes[name:lower()] = t
                end

                local hasNext = rawInterface.FindNextFileA(handle, ptr_win32FindData)
                if hasNext == 0 then
                    break
                end
            end
        end

        if dated ~= nil then
            log(INFO, string.format("discoverForPattern: %s: %d maps not listed yet (today counts as %d)",
                pattern, notYet, now))
        end

        rawInterface.FindClose(handle)
        return self.count < 500
    end,

    commit = function(self)
        table.sort(self.filenames)

        core.setMemory(rawInterface.ptr_LoadedMapNames, 0, 500 * 1000)

        for i = 1, #self.filenames do
            local name = self.filenames[i]
            local t = self.filetimes[name:lower()]

            local shortname = name

            if name:sub(-4):lower() == ".map" then
                shortname = name:sub(1, -4 - 1)
            elseif name:sub(-4):lower() == ".sav" then
                shortname = name:sub(1, -4 - 1)
            elseif name:sub(-4):lower() == ".msv" then
                shortname = name:sub(1, -4 - 1)
            end

            log(VERBOSE, string.format("commit: committing: %s", shortname))
            core.writeString(rawInterface.ptr_LoadedMapNames + ((i - 1) * 1001), shortname)
            core.writeInteger(rawInterface.ptr_MapFileTimeArray + ((i - 1) * 4), t)
        end

        core.writeInteger(rawInterface.ptr_MapFileCounter, #self.filenames)
    end,

}


local function discoverMapFiles_hook(this, ptr_pattern)
    log(VERBOSE, string.format("discoverMapFiles: %s", core.readString(ptr_pattern)))

    if documentsFolder == nil then getDocumentsFolder() end

    local dh = DiscoveryHandler:new()

    local pattern = core.readString(ptr_pattern)

    local missionMaps = false
    local originalMaps = false
    local originalExtremeMaps = false
    local originalSavs = false
    local originalExtremeSavs = false

    if pattern == "maps\\*.map" then
        missionMaps = true
        originalMaps = true
    elseif pattern == "mapsExtreme\\*.map" then
        missionMaps = true
        originalExtremeMaps = true
    elseif pattern:sub(-("saves\\*.sav"):len()):lower() == "saves\\*.sav" then
        originalSavs = true
    elseif pattern:sub(-("savesextreme\\*.sav"):len()):lower() == "savesextreme\\*.sav" then
        originalExtremeSavs = true
    end

    local patterns = {}

    if originalMaps then
        if not DISABLE_GAME_DIR_MAPS then
            table.insert(patterns, pattern)
        end

        if not DISABLE_USER_DIR_MAPS then
            table.insert(patterns, documentsFolder .. "Maps\\*.map")
        end

        if EXTRA_DIRS[pattern] and #EXTRA_DIRS[pattern] > 0 then
            for _, dir in ipairs(EXTRA_DIRS[pattern]) do
                table.insert(patterns, dir)
            end
        end
    elseif originalExtremeMaps then
        if not DISABLE_GAME_DIR_MAPS_EXTREME then
            table.insert(patterns, pattern)
        end

        if not DISABLE_USER_DIR_MAPS_EXTREME then
            table.insert(patterns, documentsFolder .. "MapsExtreme\\*.map")
        end

        if EXTRA_DIRS[pattern] and #EXTRA_DIRS[pattern] > 0 then
            for _, dir in ipairs(EXTRA_DIRS[pattern]) do
                table.insert(patterns, dir)
            end
        end
    elseif originalSavs then
        if not DISABLE_USER_DIR_SAVS then
            table.insert(patterns, documentsFolder .. "Saves\\*.sav")
        end
    elseif originalExtremeSavs then
        if not DISABLE_USER_DIR_SAVS_EXTREME then
            table.insert(patterns, documentsFolder .. "SavesExtreme\\*.sav")
        end
    else
        log(WARNING, string.format("Unmodified pattern: %s", pattern))
        -- Insert the default requested pattern
        table.insert(patterns, pattern)
    end

    log(VERBOSE, string.format("discoverMapFiles: handler: %s", tostring(dh)))
    log(VERBOSE, string.format("discoverMapFiles: handler: func: %s", tostring(dh.discoverForPattern)))

    for _, p in ipairs(patterns) do
        if dh:discoverForPattern(p) == false then
            log(WARNING, "Too many map files (>499) are being loaded! List of maps will be truncated.")
            break
        end
    end

    dh:commit()
end


local MAP_SUFFIX = ".map"

-- TODO: this can be moved to the discovery logic
local function registerOverridesForDirectory(dir, extreme)
    log(DEBUG, "registerOverridesForDirectory: Registering map files in: " .. tostring(dir))

    local status, results = pcall(function()
        return ucp.internal.io.files(dir)
    end)

    if status == nil or status == false then
        log(WARNING, string.format("Cannot register directory. Folder does not exist: %s", tostring(dir)))
        log(WARNING, string.format("Accompanying error message: %s", results))
        return
    end

    for k, path in ipairs(results) do
        if path:sub(-MAP_SUFFIX:len()) == MAP_SUFFIX then
            local mapName = path:match("([^/\\]+)[.]map$")

            local trigger = "maps\\" .. mapName .. ".map"
            if extreme then
                trigger = "mapsExtreme\\" .. mapName .. ".map"
            end
            log(DEBUG, "registerOverridesForDirectory: files(): Registering " .. tostring(trigger) .. " => " .. tostring(path))
            modules.files:overrideFileWith(trigger, path)
        end
    end
end

local function registerExtraDir(target, dir)
    log(VERBOSE, "Registering extra directory: " .. tostring(dir))

    -- local addr = core.allocate(dir:len() + 1)
    -- core.writeString(addr, dir)
    -- core.writeByte(addr + dir:len(), 0)
    if EXTRA_DIRS[target] == nil then
        EXTRA_DIRS[target] = { [1] = dir }
    else
        table.insert(EXTRA_DIRS[target], dir)
    end
end

local function prepareDir(dir, ext)
    -- FindNextFile Directory should end with *.map
    local fnfDir = dir

    if dir:sub(-1) == "\\" or dir:sub(-1) == "/" then
        fnfDir = dir .. string.format("*.%s", ext)
    end
    if fnfDir:sub(-6) ~= string.format("\\*.%s", ext) and fnfDir:sub(-6) ~= string.format("/*.%s", ext) then
        fnfDir = fnfDir .. string.format("\\*.%s", ext)
    end

    fnfDir = ucp.internal.resolveAliasedPath(fnfDir)

    return fnfDir
end

return {
    setOption = function(key, value)
        if key == "disable-game-maps" then
            if value == true then
                DISABLE_GAME_DIR_MAPS = true
            else
                DISABLE_GAME_DIR_MAPS = false
            end
        end

        if key == "disable-game-maps-extreme" then
            if value == true then
                DISABLE_GAME_DIR_MAPS_EXTREME = true
            else
                DISABLE_GAME_DIR_MAPS_EXTREME = false
            end
        end

        if key == "disable-user-maps" then
            if value == true then
                DISABLE_USER_DIR_MAPS = true
            else
                DISABLE_USER_DIR_MAPS = false
            end
        end

        if key == "disable-user-maps-extreme" then
            if value == true then
                DISABLE_USER_DIR_MAPS_EXTREME = true
            else
                DISABLE_USER_DIR_MAPS_EXTREME = false
            end
        end

        if key == "disable-user-savs" then
            if value == true then
                DISABLE_USER_DIR_SAVS = true
            else
                DISABLE_USER_DIR_SAVS = false
            end
        end

        if key == "disable-user-savs-extreme" then
            if value == true then
                DISABLE_USER_DIR_SAVS_EXTREME = true
            else
                DISABLE_USER_DIR_SAVS_EXTREME = false
            end
        end

        if key == "extra-map-directory" then
            if value:len() > 0 then
                local dir = value
                log(DEBUG, string.format('extra-map-directory: %s', dir))

                -- FindNextFile Directory should end with *.map
                local fnfDir = prepareDir(dir, "map")

                log(DEBUG, "Registering extra map dir: " .. tostring(fnfDir))

                registerAvailability(fnfDir, dir)
                registerExtraDir("maps\\*.map", fnfDir)
                -- registerExtraDir("mapsExtreme\\*.map", fnfDir)

                registerOverridesForDirectory(dir, false)
            else
                log(DEBUG, "No extra map directory found in the config")
            end
        end

        if key == "extra-map-extreme-directory" then
            if value:len() > 0 then
                local dir = value
                log(DEBUG, string.format('extra-map-extreme-directory: %s', dir))

                -- FindNextFile Directory should end with *.map
                local fnfDir = prepareDir(dir, "map")

                log(DEBUG, "Registering extra map extreme dir: " .. tostring(fnfDir))

                registerAvailability(fnfDir, dir)
                -- registerExtraDir("maps\\*.map", fnfDir)
                registerExtraDir("mapsExtreme\\*.map", fnfDir)

                registerOverridesForDirectory(dir, true)
            else
                log(DEBUG, "No extra map extreme directory found in the config")
            end
        end

        if key == "extra-sav-directory" then
            --TODO: how to know the target? We don't know the user username and the documents path?
            --registerExtraDir("maps\\*.map", config["extra-sav-directory"])
            print("WARNING: not implemented: 'extra-sav-directory'")
        end

        if key == "map-availability-date" then
            setTodayOverride(value)
        end
    end,

    enable = function(config)
        if type(config) == "table" and config["map-availability-date"] ~= nil then
            setTodayOverride(config["map-availability-date"])
        end

        local ptr_discoverMapFiles = core.AOBScan("6A FF 68 ? ? ? ? 64 A1 00 00 00 00 50 81 EC 3C 02 00 00")

        core.hookCode(discoverMapFiles_hook, ptr_discoverMapFiles, 2, 1, 7)
    end,

    ---Register an extra map directory for Crusader, Crusader Extreme, or both (default)
    ---@param path string The folder containing the maps
    ---@param which string Either "both", "crusader" or "extreme" indicating which game should load these maps
    ---@return void
    registerExtraMapDirectory = function(path, which)
      if which == nil or which == "both" then
        which = "both"
      elseif which == "extreme" then
        which = "extreme"
      else
        which = "crusader"
      end

      local dir = path

      -- FindNextFile Directory should end with *.map
      local fnfDir = prepareDir(dir, "map")

      registerAvailability(fnfDir, dir)

      if which == "both" or which == "crusader" then
        log(DEBUG, "Registering extra map crusader dir: " .. tostring(fnfDir))
        registerExtraDir("maps\\*.map", fnfDir)
        -- registerExtraDir("mapsExtreme\\*.map", fnfDir)

        registerOverridesForDirectory(dir, false)
      end

      if which == "both" or which == "extreme" then
        log(DEBUG, "Registering extra map crusader extreme dir: " .. tostring(fnfDir))
              -- registerExtraDir("maps\\*.map", fnfDir)
        registerExtraDir("mapsExtreme\\*.map", fnfDir)

        registerOverridesForDirectory(dir, true)
      end

    end,
}
