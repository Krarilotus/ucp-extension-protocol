-- Resolve before installing admission. Protocol owns both command transport and
-- this lobby boundary; no simulation hook or alternative patch manager is used.
local function unique(pattern)
  local address = core.AOBScan(pattern)
  assert(type(address) == 'number' and address > 0,
    'Protocol: multiplayer admission binding is unavailable')
  local second = core.scanForAOB(pattern, address + 1)
  assert(second == nil or second == 0,
    'Protocol: multiplayer admission binding is ambiguous')
  return address
end

local startPattern = '39 3D ? ? ? ? 0F 84 ? ? ? ? B8 ? ? ? ? 83 C9 FF 39 88 ? ? ? ? 74 08 39 38 0F 84 ? ? ? ? 83 C0 04 3D ? ? ? ? 7C E6 B9 ? ? ? ? E8 ? ? ? ? 83 F8 02'
local modePattern = '6A 34 B9 ? ? ? ? E8 ? ? ? ? 83 3D ? ? ? ? 63 75 1E 57 89 3D'
local playerPattern = 'A1 ? ? ? ? 69 C0 F4 39 00 00 8B 88 ? ? ? ? 85 C9 74 39 83 B8 ? ? ? ? 00 74 16'
local viewPattern = 'A1 ? ? ? ? 83 F8 37 C7 05 ? ? ? ? 0A 00 00 00 C6 05 ? ? ? ? 00 74 0C 83 F8 38 74 07'

local M = {}
function M.resolve()
  local start = unique(startPattern)
  local mode = unique(modePattern)
  local player = unique(playerPattern)
  local view = unique(viewPattern)
  local handler = require('protocols.common').MULTIPLAYER_HANDLER_ADDRESS
  -- Both lobby calls must use the transport owner's resolved singleton.
  assert(core.readInteger(start + 47) == handler and core.readInteger(mode + 3) == handler,
    'Protocol: multiplayer admission does not match the command transport owner')
  local ready = core.readInteger(start + 13)
  assert(core.readInteger(start + 40) == ready + 8 * 4,
    'Protocol: unsupported multiplayer readiness roster layout')
  local handles = ready + core.readInteger(start + 22) - 4
  local reject = start + 12 + core.readInteger(start + 8)
  assert(start + 36 + core.readInteger(start + 32) == reject,
    'Protocol: multiplayer Start checks disagree on the rejection boundary')
  return {start=start, resume=start + 6, reject=reject,
    host=core.readInteger(start + 2), mode=core.readInteger(mode + 14),
    player=core.readInteger(player + 1), handles=handles,
    view=core.readInteger(view + 1), pattern=startPattern}
end

-- The site may have been occupied after resolution by a later module.
function M.verify(sites)
  local index = 0
  for token in sites.pattern:gmatch('%S+') do
    if token ~= '?' then
      assert(core.readByte(sites.start + index) == tonumber(token, 16),
        'Protocol: multiplayer Start owner was modified before admission installation')
    end
    index = index + 1
  end
  assert(core.readInteger(sites.start + 2) == sites.host
      and sites.start + 12 + core.readInteger(sites.start + 8) == sites.reject,
    'Protocol: multiplayer Start operands changed before admission installation')
end
return M
