-- Lobby-only agreement. The native Start owner remains responsible for readiness,
-- host authority, map selection, RNG seeding and dispatching the actual start.
local M = {}
local function hash(value)
  return type(value)=='string' and #value==64 and value:match('^[0-9a-f]+$')~=nil
end
local function sameRoster(a,b)
  if type(a)~='table' or type(b)~='table' or #a~=8 or #b~=8 then return false end
  for slot=1,8 do if a[slot]~=b[slot] then return false end end
  return true
end
local function copyRoster(roster)
  local result={}
  for slot=1,8 do
    local value=roster[slot]
    assert(type(value)=='number' and value==math.floor(value)
      and value>=-2147483648 and value<=2147483647,'Invalid lobby transport handle')
    result[slot]=value
  end
  return result
end

function M.new(adapter)
  local state={serial=0}
  local function snapshot()
    local localPlayer,roster=adapter.roster()
    assert(localPlayer>=1 and localPlayer<=8 and localPlayer==math.floor(localPlayer),
      'Invalid local lobby slot')
    roster=copyRoster(roster)
    assert(roster[localPlayer]~=-1,'Local lobby transport is unavailable')
    local digest=adapter.identity()
    assert(hash(digest),'Invalid multiplayer content fingerprint')
    return localPlayer,roster,digest
  end
  local function request(round)
    return {kind=0,serial=round.serial,host=round.host,roster=round.roster,digest=round.digest}
  end
  local function allowed(round)
    local waiting=false
    for slot=1,8 do
      if round.roster[slot]~=-1 then
        if round.responses[slot]==nil then waiting=true
        elseif round.responses[slot]~=round.digest then return false,'mismatch' end
      end
    end
    if waiting then return false,'waiting' end
    return true,'matched'
  end
  return {
    start=function()
      if not adapter.isHost() then return false,'host-only' end
      local player,roster,digest=snapshot()
      local round=state.round
      if not round or round.host~=player or round.digest~=digest or not sameRoster(roster,round.roster) then
        assert(state.serial<2147483647,'Restart the game before another admission round')
        state.serial=state.serial+1
        round={serial=state.serial,host=player,roster=roster,digest=digest,responses={[player]=digest}}
        state.round=round
      end
      local ok,reason=allowed(round)
      if not ok then adapter.send(request(round)) end -- retry only on a Start action
      return ok,reason
    end,
    receive=function(sender,message)
      if type(message)~='table' or (message.kind~=0 and message.kind~=1)
          or type(message.serial)~='number' or message.serial<1 or message.serial>2147483647
          or message.serial~=math.floor(message.serial) or not hash(message.digest)
          or type(sender)~='number' or sender<1 or sender>8 or sender~=math.floor(sender)
          or type(message.host)~='number' or message.host<1 or message.host>8
          or message.host~=math.floor(message.host) then return false end
      -- Ignore non-lobby traffic without freezing a provider or hashing content.
      if not adapter.inLobby() then return false end
      local localPlayer,current=adapter.roster()
      if not sameRoster(current,message.roster) or current[sender]==-1 then return false end
      if message.kind==0 then
        if adapter.isHost() or message.host~=sender then return false end
        local player,roster,digest=snapshot()
        if player==sender then return false end
        adapter.send({kind=1,serial=message.serial,host=sender,roster=roster,digest=digest})
        return true
      end
      local round=state.round
      if not adapter.isHost() or not round or message.host~=localPlayer
          or round.host~=message.host or round.serial~=message.serial
          or not sameRoster(round.roster,message.roster) or sender==localPlayer then return false end
      round.responses[sender]=message.digest
      return true
    end,
    reset=function() state.round=nil end,
  }
end
return M
