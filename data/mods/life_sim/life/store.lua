-- Numeric/string state persisted on a Character via character values (saved with the character).

local store = {}

local PREFIX = "life_sim_"

---@param who Character
---@param key string
---@param default number
---@return number
store.get_num = function(who, key, default)
  local raw = who:get_value(PREFIX .. key)
  if raw == "" then return default end
  return tonumber(raw) or default
end

---@param who Character
---@param key string
---@param value number
store.set_num = function(who, key, value) who:set_value(PREFIX .. key, tostring(value)) end

---@param who Character
---@param key string
---@return string
store.get_str = function(who, key) return who:get_value(PREFIX .. key) end

---@param who Character
---@param key string
---@param value string
store.set_str = function(who, key, value) who:set_value(PREFIX .. key, value) end

---@return integer
store.now = function() return gapi.current_turn():to_turn() end

return store
