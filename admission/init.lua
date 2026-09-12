local M={providers={},installed=false}
local function identity()
  local content=require('admission.content')
  assert(M.contentHash,'Multiplayer content fingerprint is unavailable; restart the game')
  local names={}
  for name in pairs(M.providers) do names[#names+1]=name end
  table.sort(names)
  local values={'protocol-admission-v1\n',M.contentHash,'\n',
    content.canonical(assert(configFinal,'Resolved multiplayer settings are unavailable')),'\n'}
  for _,name in ipairs(names) do
    local digest=M.providers[name].capture()
    assert(type(digest)=='string' and #digest==64 and digest:match('^[0-9a-f]+$'),
      'Invalid admission fingerprint for '..name)
    values[#values+1]=name..'='..digest..'\n'
  end
  return sha.sha256(table.concat(values))
end
local function write(meta,message)
  local p=meta.parameters
  p:serializeInteger(message.kind); p:serializeInteger(message.serial); p:serializeInteger(message.host)
  local bytes={}
  for pair in message.digest:gmatch('%x%x') do bytes[#bytes+1]=tonumber(pair,16) end
  p:serializeBytes(bytes)
  for slot=1,8 do p:serializeInteger(message.roster[slot]) end
end
local function read(meta)
  local p=meta.parameters
  local value={kind=p:deserializeInteger(),serial=p:deserializeInteger(),host=p:deserializeInteger(),roster={}}
  local hex={}
  for _,byte in ipairs(p:deserializeBytes(32)) do hex[#hex+1]=string.format('%02x',byte) end
  value.digest=table.concat(hex)
  for slot=1,8 do value.roster[slot]=p:deserializeInteger() end
  return value
end
function M.register(protocol,name,capture,notify)
  assert(type(name)=='string' and #name<=128 and name:match('^[%w_-]+$')
    and type(capture)=='function' and (notify==nil or type(notify)=='function')
    and not M.providers[name],'Invalid multiplayer admission provider')
  local count=0
  for _ in pairs(M.providers) do count=count+1 end
  assert(count<32,'Too many multiplayer admission providers')
  assert(not M.frozen,'Multiplayer admission providers are frozen')
  if not M.installed then
    local native=require('admission.native')
    local consensus,number
    consensus=require('admission.consensus').new({
      identity=function() M.frozen=true; return identity() end,
      roster=native.roster,isHost=native.isHost,inLobby=native.inLobby,
      send=function(message) protocol:invokeCustomProtocol(number,message) end,
    })
    native.install(function()
      if not native.inLobby() then return false end
      local ok,allowed,reason=pcall(consensus.start)
      if not ok then
        log(ERROR,'Multiplayer admission: '..tostring(allowed))
        allowed,reason=false,'error'
      end
      if not allowed then
        log(WARNING,reason=='mismatch' and 'Multiplayer settings differ; use the same extension files and AIC settings.'
          or 'Checking multiplayer settings. Press Start again after all players have responded.')
        local names={}
        for key in pairs(M.providers) do names[#names+1]=key end
        table.sort(names)
        for _,key in ipairs(names) do
          local callback=M.providers[key].notify
          if callback then callback(reason) end
        end
      end
      return allowed
    end)
    number=protocol:registerCustomProtocol('protocol','content-admission-v1','IMMEDIATE',76,{
      schedule=function(self,meta,message) write(meta,message) end,
      execute=function(self,meta) consensus.receive(meta.player,read(meta)) end,
    })
    M.installed=true
    hooks.registerHookCallback('afterInit',function()
      M.contentHash=require('admission.content').capture(allActiveExtensions,configFinal)
    end)
  end
  M.providers[name]={capture=capture,notify=notify}
end
return M
