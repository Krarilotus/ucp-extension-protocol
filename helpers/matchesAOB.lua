-- Framework 3.0.8 provides core.matchesAOB; 3.0.7 does not, so compare the bytes here.
local function matchesAOB(pattern, address)
  if core.matchesAOB then return core.matchesAOB(pattern, address) end
  local offset = 0
  for token in pattern:gmatch('%S+') do
    if token ~= '?' and core.readByte(address + offset) ~= tonumber(token, 16) then return false end
    offset = offset + 1
  end
  return true
end

return matchesAOB
