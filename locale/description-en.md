# Files
This extension is named files because it hijacks the file operations that are performed by the game.

A key feature is to provide a method for hijacking specific `open` file operations to direct them to files of choice.

This extension provides the engine of many extensions that rely on hijacking the `open` operation.

## Usage
This extension provides four functions:
```lua
--[[
Override/hijack the open operation for a specific file.
Note that the game uses Windows OS style paths, such as "maps\\Close Encounters.map"

file  string  the original path as used by the game
newfile  string  the path to the file that should override the original
--]]
modules.files:overrideFileWith(file, newFile)

--[[
Register an override function that is called each time an open operation is called.
This is useful for files that are not loaded once, but are rather loaded more often during the game.
--]]
modules.files:registerOverrideFunction(func)

--[[
This function is used by the maploader extension to set parameters for the game's .amp and .sav file loading
--]]
modules.files:setIterationOption(key, value)

--[[
With this function you can set up an alternative location for the game to look for game files (only gm, gfx, fx, binks)
Maps should be registered with the maploader
--]]
modules.files:registerFileSource(path)

--[[
Add a folder of .map files to the game's map lists. `which` is "both" (default), "crusader" or "extreme".
Several folders can be registered, for example one per plugin.
--]]
modules.files:registerExtraMapDirectory(path, which)

```

## Maps that appear from a date on
An extra map folder (from `registerExtraMapDirectory` or the maploader's extra map directory) can hold a file named `availability.json`. Every map named in it is listed in the game only from its date on, in the player's local time. Maps that are not named are listed as usual. This is meant for map packs that open one map per day, such as an advent calendar.

```json
{
  "format": 1,
  "maps": {
    "Door01": "2026-12-01",
    "Door02": "2026-12-02"
  }
}
```

- Map names are the file names, with or without `.map`, in any letter case.
- A missing or broken file, or an entry without a valid `YYYY-MM-DD` date, never hides a map. The module writes a warning to the log and lists the map.
- The game checks the dates whenever it builds its map list. A map whose day starts while the game is running appears the next time the list is built.
- Saved games are not affected.
- Map authors can preview a schedule without changing the system clock: set the option `map-availability-date` to a date such as `2026-12-05`, in the files or maploader configuration. That date then counts as today.
