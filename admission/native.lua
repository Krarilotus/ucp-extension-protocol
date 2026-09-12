local M={}
local resolver=require('admission.sites')
local sites=resolver.resolve()
local START,RETURN,REJECT=sites.start,sites.resume,sites.reject
local MODE,HOST,PLAYER,HANDLES,VIEW=sites.mode,sites.host,sites.player,sites.handles,sites.view
local installed=false

function M.roster()
  local result={}
  for slot=1,8 do result[slot]=core.readInteger(HANDLES+slot*4) end
  return core.readInteger(PLAYER),result
end
function M.isHost() return core.readInteger(HOST)~=0 end
function M.inLobby()
  local mode=core.readInteger(MODE)
  return (mode==1 or mode==2) and core.readInteger(VIEW)==20
end

function M.install(check)
  assert(not installed,'Protocol: multiplayer admission is already installed')
  -- Preserve the host comparison and its original conditional branch. This
  -- boundary precedes the native seed call observed by Recorder.
  resolver.verify(sites)
  local result=core.allocate(4,true)
  local callback=core.allocateCode({0x90,0x90,0x90,0x90,0x90,0xC3})
  core.detourCode(function(registers)
    core.writeInteger(result,0) -- errors must keep Start blocked
    local ok,allowed=pcall(check)
    if ok and allowed==true then core.writeInteger(result,1)
    elseif not ok then log(ERROR,'Multiplayer admission: '..tostring(allowed)) end
    return registers
  end,callback,5)
  local bridge=core.allocateCode(192)
  core.writeCode(bridge,core.assemble([[
    use32
    pushfd
    cmp dword [MODE], 1
    je check
    cmp dword [MODE], 2
    jne original
  check:
    cmp dword [HOST], 0
    je original
    pushad
    call CALLBACK
    popad
    cmp dword [RESULT], 1
    jne blocked
  original:
    popfd
    cmp dword [HOST], edi
    jmp RETURN
  blocked:
    popfd
    jmp REJECT
  ]],{MODE=MODE,HOST=HOST,CALLBACK=callback,RESULT=result,RETURN=RETURN,REJECT=REJECT},bridge))
  core.writeCode(START,{0xE9,bridge-START-5,0x90})
  installed=true
end
return M
