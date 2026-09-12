local M={}
local START,RETURN,REJECT=0x44280D,0x442813,0x442693
local MODE,HOST,PLAYER,HANDLES,VIEW=0x191DD80,0x191DEF8,0x1A275DC,0x191DE10,0x1FE7D1C

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
  -- This site precedes all native Start checks and the recorder's later seed
  -- observer at 0x442877. No command handler or simulation tick is replaced.
  local expected={0x39,0x3D,0xF8,0xDE,0x91,0x01,0x0F,0x84,0x7A,0xFE,0xFF,0xFF}
  for i,value in ipairs(expected) do
    assert(core.readByte(START+i-1)==value,'Protocol: unsupported or modified SHC 1.41 Start owner')
  end
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
end
return M
