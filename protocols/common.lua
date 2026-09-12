-- ECX value for most multiplayer functionality (command functionality)
local MULTIPLAYER_HANDLER_ADDRESS = core.readInteger(core.AOBScan("B9 ? ? ? ? E8 ? ? ? ? 39 ? ? ? ? ? 75 17") + 1)

-- ECX value for most multiplayer functionality (command functionality)

local niceCommandInfo = core.AOBScan("89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 0F ? ? ? ? ? ? 8B ? ? ? ? ? ?")
local COMMAND_PARAM_5_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(niceCommandInfo + 2 + 6)
local COMMAND_PARAM_4_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(niceCommandInfo + 2 + 6 + 6)
local COMMAND_PARAM_3_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(niceCommandInfo + 2 + 6 + 6 + 6)
local COMMAND_PARAM_2_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(niceCommandInfo + 2 + 6 + 6 + 6 + 6)
local COMMAND_PARAM_1_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(niceCommandInfo + 2 + 6 + 6 + 6 + 6 + 6)
local COMMAND_PARAM_0_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(niceCommandInfo + 2 + 6 + 6 + 6 + 6 + 6 + 6)


local COMMAND_CURRENT_ID_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(core.AOBScan("8B ? ? ? ? ? 69 ? ? ? ? ? 8B ? ? ? ? ? ? 8D 3C 31") + 2)

local niceCommandInfo = core.AOBScan("89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 89 ? ? ? ? ? 0F ? ? ? ? ? ? 8B ? ? ? ? ? ?")

-- 0 means execute, 1 means schedule, 2 means received
local COMMAND_ACTION_PLAN_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(niceCommandInfo + 2 + 6 + 6 + 6 + 6 + 6 + 6 + 6)

local COMMAND_ARRAY_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(core.AOBScan("89 ? ? ? ? ? ? 8B ? ? ? ? ? 69 ? ? ? ? ? 89 ? ? ? ? ? C7 ? ? ? ? ? ? ? ? ?") + 3)

-- Offset into the parameter array (where currently is being read or written from)
local COMMAND_PARAMETER_OFFSET_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(niceCommandInfo + 2 + 6 + 6 + 6 + 6 + 6 + 6 + 6 + 6)


-- Both supported game families use this native ring-row stride.
local TOTAL_GAME_COMMAND_SIZE = 1272

local getCommandOffset = function(commandID)
  return COMMAND_ARRAY_ADDRESS + (commandID * TOTAL_GAME_COMMAND_SIZE)
end

local _, pGameCore = utils.AOBExtract("A3 I( ? ? ? ? ) 89 5C 24 1C")
local _, pMapTime = utils.AOBExtract("8B ? I(? ? ? ?) 66 8B 54 24 1C")
local MAP_TIME_ADDRESS = pMapTime



---Get data for the invocation
---@param commandID number invocation number
---@return CommandMetaInformation
local function getCommandMetaInformation(commandID)
  local base = getCommandOffset(commandID)
  return {
    base = base,
    time = core.readInteger(base),
    timeAddress = base,
    player = core.readInteger(base + 4),
    category = core.readByte(base + 4 + 4),
    state = core.readByte(base + 4 + 4 + 1),
    parametersAddress = base + 4 + 4 + 1 + 1,
    parameters = {},
  }
end

local COMMAND_PARAMETER_SIZE_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(core.AOBScan("8B ? ? ? ? ? 8D ? ? ? ? ? 51 52 50") + 2)
local setCommandParameterSize = function(size) core.writeInteger(COMMAND_PARAMETER_SIZE_ADDRESS, size) end

-- Immediate specific
local COMMAND_FIXED_PARAMETER_LOCATION_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(core.AOBScan("8B ? ? ? ? ? 8D ? ? ? ? ? 51 52 50") + 6 + 2)

local COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS + core.readInteger(core.AOBScan("8D ? ? ? ? ? 52 8B 13") + 2)


return {
  MULTIPLAYER_HANDLER_ADDRESS = MULTIPLAYER_HANDLER_ADDRESS,
  COMMAND_ACTION_PLAN_ADDRESS = COMMAND_ACTION_PLAN_ADDRESS,
  COMMAND_CURRENT_ID_ADDRESS = COMMAND_CURRENT_ID_ADDRESS,
  COMMAND_PARAM_0_ADDRESS = COMMAND_PARAM_0_ADDRESS,
  COMMAND_PARAM_1_ADDRESS = COMMAND_PARAM_1_ADDRESS,
  COMMAND_PARAM_2_ADDRESS = COMMAND_PARAM_2_ADDRESS,
  COMMAND_PARAM_3_ADDRESS = COMMAND_PARAM_3_ADDRESS,
  COMMAND_PARAM_4_ADDRESS = COMMAND_PARAM_4_ADDRESS,
  COMMAND_PARAM_5_ADDRESS = COMMAND_PARAM_5_ADDRESS,
  COMMAND_PARAMETER_OFFSET_ADDRESS = COMMAND_PARAMETER_OFFSET_ADDRESS,
  getCommandMetaInformation = getCommandMetaInformation,
  setCommandParameterSize = setCommandParameterSize,
  COMMAND_FIXED_PARAMETER_LOCATION_ADDRESS = COMMAND_FIXED_PARAMETER_LOCATION_ADDRESS,
  COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS = COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS,
  MAP_TIME_ADDRESS = MAP_TIME_ADDRESS,
  COMMAND_ARRAY_ADDRESS = COMMAND_ARRAY_ADDRESS,
  TOTAL_GAME_COMMAND_SIZE = TOTAL_GAME_COMMAND_SIZE,
}
