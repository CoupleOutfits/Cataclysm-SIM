gdebug.log_info("Life Sim: Preload")

---@class ModLifeSim
---@field on_every_5_minutes fun()
---@field on_every_hour fun()
---@field relieve_action fun()
---@field status_action fun()
---@field examine_toilet fun(params: { user: Character, pos: TripointBubMs })
---@field finish_relief fun(params: { user: Character, data: LifeSimReliefActivityData? })
---@type ModLifeSim
local mod = game.mod_runtime[game.current_mod]

gapi.add_on_every_x_hook(TimeDuration.from_minutes(5), function() mod.on_every_5_minutes() end)
gapi.add_on_every_x_hook(TimeDuration.from_hours(1), function() mod.on_every_hour() end)

game.examine_functions["LIFE_SIM_TOILET_EXAMINE"] = function(...) return mod.examine_toilet(...) end
game.activity_functions["LIFE_SIM_FINISH_RELIEF"] = function(...) return mod.finish_relief(...) end

gapi.register_action_menu_entry({
  id = "life_sim_relieve",
  name = locale.gettext("Relieve yourself"),
  category = "misc",
  fn = function() mod.relieve_action() end,
})
gapi.register_action_menu_entry({
  id = "life_sim_status",
  name = locale.gettext("Check personal needs"),
  category = "info",
  fn = function() mod.status_action() end,
})
