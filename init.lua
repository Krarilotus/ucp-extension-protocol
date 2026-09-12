
local globals = require("globals")
local FIRST_AVAILABLE_NUMBER = globals.FIRST_AVAILABLE_NUMBER
local CUSTOM_PROTOCOL_NUMBER1 = globals.CUSTOM_PROTOCOL_NUMBER1

local common = require("protocols.common")
local interface = require("game.interface")

local gameVersion = require("game.version")

local PROTOCOL_REGISTRY = globals.PROTOCOL_REGISTRY

---@class protocol
local namespace = {
  enable = function(self, config)

    require("game.hooks").setHooks()

    hooks.registerHookCallback("afterInit", function()
      gameVersion.setMultiplayerGameVersion()
    end)

    -- require("tests")
  end,
  disable = function(self, config)
  end,
  
}


---Helper function to process a protocol value that is either a number or a key
---@param p string|number the protocol
---@return number protocol the protocol number
local function argToProtocolNumber(p)
  if type(p) ~= "number" then
    local protocolNumber = namespace:getProtocolNumberByKey(p)
    if protocolNumber == nil then
      error(string.format("Cannot find a protocol associated with identifier: %s", tostring(p)))
    end
    return protocolNumber
  end
  return p
end

local knownProtocolTypes = require("game.knownProtocolTypes")

---Register a lobby fingerprint provider. Capture must freeze its configuration
---and return a lowercase SHA256. It is never called from simulation ticks.
function namespace:registerMultiplayerAdmission(name, capture, notify)
  return require('admission.init').register(self, name, capture, notify)
end

function namespace:multiplayerAdmissionVersion() return 1 end

---Register a custom protocol. Note that an IMMEDIATE protocol (used to communicate information and events outside
---of the simulation) can only invoke another IMMEDIATE protocol, but never a LOCKSTEP protocol.
---@param extension string name of the extension
---@param name string name of the protocol
---@param type string "IMMEDIATE" or "LOCKSTEP"
---@param parameterSize number total size of the parameters in serialized form
---@param handler Handler handler of this protocol, table with function schedule, scheduleAfterReceive, and execute.
---@see Handler
---@return integer number
---@return string key
function namespace:registerCustomProtocol(extension, name, type, parameterSize, handler)
  -- TODO: insert check for known registerProtocol numbers
  -- TODO: insert check for too large parameter size?

    
  local KNOWN_REGISTRY_ENTRIES = globals.KNOWN_REGISTRY_ENTRIES
  local nextAvailableRegistrySlot = globals.nextAvailableRegistrySlot

  local key = tostring(extension) .. ".protocols." .. tostring(name)

  local number

  for reservedNumber, protocolName in pairs(KNOWN_REGISTRY_ENTRIES) do
    if protocolName == key then
      number = reservedNumber

      if PROTOCOL_REGISTRY[number] ~= nil then
        error(string.format("protocol already registered: %s", key))
      end
    end
  end

  if number == nil then number = nextAvailableRegistrySlot() end

  KNOWN_REGISTRY_ENTRIES[number] = key

  ---@type Protocol
  local protocol = {
    extension = extension,
    type = type,
    name = name,
    parameterSize = parameterSize,
    handler = handler,
  }
  PROTOCOL_REGISTRY[number] = protocol

  knownProtocolTypes[number] = type

  return number, name
end

---Get the protocol number
---@param key string key of the protocol
---@return number|nil number
function namespace:getProtocolNumberByKey(key)
  
  local KNOWN_REGISTRY_ENTRIES = globals.KNOWN_REGISTRY_ENTRIES

  for number, k in pairs(KNOWN_REGISTRY_ENTRIES) do
    if k == key then return number end
  end

  return nil
end

---Get the protocol number
---@param extension string name of the extension
---@param name string name of the protocol
---@return nil|number number
function namespace:getProtocolNumber(extension, name)
  
  local KNOWN_REGISTRY_ENTRIES = globals.KNOWN_REGISTRY_ENTRIES

  local key = tostring(extension) .. ".protocols." .. tostring(name)

  for number, k in pairs(KNOWN_REGISTRY_ENTRIES) do
    if k == key then return number end
  end

  return nil
end


local CUSTOM_PROTOCOL_NUMBER2 = globals.CUSTOM_PROTOCOL_NUMBER2
local COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS = common.COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS
local MULTIPLAYER_HANDLER_ADDRESS = common.MULTIPLAYER_HANDLER_ADDRESS
local _scheduleCommand = interface._scheduleCommand

---Pretend a protocol invocation is received over multiplayer. Note the protocol must be a number.
---@param protocol number|string protocol number or key
---@param player number the player that sent the invocation
---@param time number use 0 for immediate execution instead of lockstep (game time)
---@param parameterBytes table table of bytes that represent the parameters to the protocol invocation
---@return nil
function namespace:injectProtocol(protocol, player, time, parameterBytes)
  local protocolNumber = argToProtocolNumber(protocol)
  
  if PROTOCOL_REGISTRY[protocolNumber] == nil then 
    error("Unknown custom protocol: " .. tostring(protocolNumber)) 
  end

  if #parameterBytes > globals.MAX_PARAMETER_LENGTH then 
    error("parameter bytes is too long")
  else
    core.writeBytes(COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS, parameterBytes)
  end

  
  if protocolNumber < 0 or protocolNumber > CUSTOM_PROTOCOL_NUMBER2 then
    error("Illegal command category: " .. tostring(protocol))
  end
  _scheduleCommand(MULTIPLAYER_HANDLER_ADDRESS, protocolNumber, player, time, COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS)
end

local setupInvocationParameters = require("helpers.setupInvocationParameters").setupInvocationParameters

local checkIllegalInvocationNesting = require("helpers.checkIllegalInvocationNesting").checkIllegalInvocationNesting
local _queueCommand = interface._queueCommand

---Invoke original protocol. Note that the protocol must be a number.
---@param protocol number|string protocol number or key
---@param ... number|table a number or table with numbers acting as the parameters to the invocation
---@return nil
function namespace:invokeOriginalProtocol(protocol, ...) 
  local protocolNumber = argToProtocolNumber(protocol)

  if protocolNumber >= FIRST_AVAILABLE_NUMBER then
    error(string.format("Illegal original protocol number: %s", protocolNumber))
  end

  if protocolNumber < 0 or protocolNumber > CUSTOM_PROTOCOL_NUMBER2 then
    error("Illegal protocol number: " .. tostring(protocol))
  end

  checkIllegalInvocationNesting(protocolNumber)

  setupInvocationParameters(...)
  _queueCommand(MULTIPLAYER_HANDLER_ADDRESS, protocolNumber)
end


---Invoke custom protocol by key (or number).
---Arguments for the protocol are to be set up during the call to 'schedule'
---@param protocol number|string key or number of the protocol
---@param context table a table representing the invocation context, passed unto schedule()
---@return nil
function namespace:invokeCustomProtocol(protocol, context)
  local protocolNumber = argToProtocolNumber(protocol)

  if protocolNumber < FIRST_AVAILABLE_NUMBER then
    error(string.format("Illegal custom protocol number: %s", protocolNumber))
  end

  if PROTOCOL_REGISTRY[protocolNumber] == nil then 
    error("Unknown custom protocol: " .. tostring(protocolNumber)) 
  end

  checkIllegalInvocationNesting(protocolNumber)

  -- This is legal since context is only used during scheduling
  -- in case of context overriding occurring with multiple invocations
  -- look here for solutions.
  if globals.CONTEXT.current ~= nil then
    log(WARNING, string.format("Context for custom protocol (#) invocation was non nil"))
  end
  globals.CONTEXT.current = context

  if PROTOCOL_REGISTRY[protocolNumber].type == "IMMEDIATE" then
    core.writeInteger(common.COMMAND_PARAM_0_ADDRESS, protocolNumber)
    self:invokeOriginalProtocol(CUSTOM_PROTOCOL_NUMBER1) -- todo, add arg protocolNumber
  elseif PROTOCOL_REGISTRY[protocolNumber].type == "LOCKSTEP" then
    core.writeInteger(common.COMMAND_PARAM_0_ADDRESS, protocolNumber)
    self:invokeOriginalProtocol(CUSTOM_PROTOCOL_NUMBER2) -- todo, add arg protocolNumber
  else
    error(string.format("unknown protocol type: %s", tostring(PROTOCOL_REGISTRY[protocolNumber].type)))
  end

  -- Just to be sure
  globals.CONTEXT.current = nil
end

local LAST_ORIGINAL_NUMBER = globals.LAST_ORIGINAL_NUMBER

---Invoke protocol by key. Note it is possible to invoke by number but this
---is only for advanced use or when invoking an original protocol from the game.
---@param protocol number|string key or number of the protocol
---@param ... number|table a number or table with numbers acting as the parameters to the invocation
---in case of an original protocol. For custom protocols, a table representing the invocation context
---passed unto schedule call
---@return nil
function namespace:invokeProtocol(protocol, ...)
  local protocolNumber = argToProtocolNumber(protocol)

  if protocolNumber < 1 then
    error(string.format("invalid protocol number: %s", protocolNumber))    
  end

  log(DEBUG, string.format("invokeProtocol(%s)", protocolNumber))

  if protocolNumber <= LAST_ORIGINAL_NUMBER then
    return self:invokeOriginalProtocol(protocolNumber, ...)
  end

  if protocolNumber >= FIRST_AVAILABLE_NUMBER then
    return self:invokeCustomProtocol(protocolNumber, ...)
  end

  error(string.format("illegal protocol number: %s", protocolNumber))
end

return namespace
