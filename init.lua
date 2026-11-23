local overrides = require('overrides')
-- local iteration = require('iteration')
local discovery = require('discovery')

---@module "files"
local files = {
  enable = function(self, config)
    overrides.enable(config)
    discovery.enable(config)
  end,
  disable = function(self, config)
  end,
}



function files:overrideFileWith(file, newFile)
  return overrides.overrideFileWith(file, newFile)
end
function files:registerOverrideFunction(func)
  return overrides.registerOverrideFunction(func)
end
function files:setIterationOption(key, value)
  return discovery.setOption(key, value)
end

---Register an extra file source for game files
---Does not support map files, use registerExtraMapDirectory
---@param relativePath string The path to register relative to the game directory
---@return void
function files:registerFileSource(path)
  return overrides.registerFileSource(path)
end


---Register an extra map directory for Crusader, Crusader Extreme, or both (default)
---@param self table the files module itself
---@param path string The folder containing the maps
---@param which string Either "both", "crusader" or "extreme" indicating which game should load these maps
---@return void
function files:registerExtraMapDirectory(path, which)
  return discovery.registerExtraMapDirectory(path, which)
end

---Whether a map named in the availability.json of an extra map directory can be played today,
---and the date it opens. A map whose date has come gets its file redirect at this call, so it
---can be opened even if the game hasn't built its map list since that date.
---@param self table the files module itself
---@param name string the map name, with or without ".map"
---@param which string|nil "crusader" (default) or "extreme"
---@return boolean available false only while a dated map's date hasn't come
---@return string|nil from the date ("YYYY-MM-DD") of a dated map, nil for other maps
function files:getMapAvailability(name, which)
  return discovery.getMapAvailability(name, which)
end

return files, {
    public = {
        "overrideFileWith",
        "registerOverrideFunction",
        "setIterationOption",
        'registerFileSource',
        'registerExtraMapDirectory',
        'getMapAvailability',
    }
}
