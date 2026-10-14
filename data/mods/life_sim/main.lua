gdebug.log_info("Life Sim: Main")

local bladder = require("life.bladder")
local hair = require("life.hair")

---@type ModLifeSim
local mod = game.mod_runtime[game.current_mod]

mod.on_every_5_minutes = function() bladder.update(gapi.get_avatar()) end

mod.on_every_hour = function()
  hair.update(gapi.get_avatar())
  for _, npc in ipairs(gapi.get_all_npcs()) do
    hair.update(npc)
  end
end

mod.relieve_action = bladder.relieve_action
mod.examine_toilet = bladder.examine_toilet
mod.finish_relief = bladder.finish_relief

mod.status_action = function()
  local who = gapi.get_avatar()
  bladder.update(who)
  hair.update(who)
  local lines = { bladder.describe(who) }
  for _, line in ipairs(hair.describe(who)) do
    table.insert(lines, line)
  end
  local menu = UiList.new()
  menu:title(locale.gettext("Personal needs"))
  for i, line in ipairs(lines) do
    menu:add(i, line)
  end
  menu:query()
end
