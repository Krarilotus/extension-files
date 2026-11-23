# Files

UCP3 module that redirects the game's file operations; see `locale/description-en.md` for its
functions.

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

- `"format": 1` is optional; other formats are not read. The file must be valid JSON of at most 32 KB.
- Map names are the file names, with or without `.map`, compared without ASCII letter case. The game reads file names in the Windows code page; a name with letters such as `ü` is also matched in its Latin-1 form, which fits Western European Windows. Names with letters outside Latin-1 can't be matched, so those maps are listed from the start. ASCII file names are safest.
- A missing or broken file, or an entry without a real `YYYY-MM-DD` date, never hides a map: the module writes a warning to the log (for a broken file or entry) and lists the map. A name given twice keeps the earlier date. Only folders inside the game folder can have an `availability.json`.
- The game checks the dates whenever it builds its map list. A map whose day starts while the game is running appears the next time the list is built.
- Until its date, a dated map also doesn't replace a map with the same name, for example one in the game's own `maps` folder. From its date on it does, like any other extra map. When several folders have a map of that name, which one opens depends on the order in which they are registered and become available, so give dated maps names of their own.
- Saved games are not affected.
- Other modules can ask whether a map can be played today with `modules.files:getMapAvailability(name, "crusader")`. It returns `false` and the date (`"2026-12-05"`) while a dated map's date hasn't come, and `true` (plus the date, for a dated map) otherwise. A map whose date has come also gets its file redirect then, so a module can open it without the map list having been shown. Custom Skirmish Trails uses this for its scenario missions.
- Map authors can preview a schedule without changing the system clock: set `map-availability-date` to a date such as `2026-12-05` in `ucp-config.yml`, in the files or the maploader configuration (the maploader's value wins when both are set). That date then counts as today. The option has no launcher control.
