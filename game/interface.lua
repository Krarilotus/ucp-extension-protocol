local common=require('protocols.common')
local queueCaller='E8 ? ? ? ? 8B ? ? ? ? ? 8B 4C 24 10 01 ? ? ? ? ? 03 C8 3B ? ? ? ? ? 89 4C 24 10 0F ? ? ? ? ? 83 ? ? ? ? 83 C5 01 83 FD 40'
local queuePattern='53 56 8B F1 8B 86 ? ? ? ? 89 86 24 D8 02 00 69 C0 F8 04 00 00 57 8D 84 30 86 C6 03 00 50 33 FF 57 68 EC 04 00 00 B9 ? ? ? ? E8 ? ? ? ? 8B 8E 24 D8 02 00 69 C9 F8 04 00 00 C6 84 31 85 C6 03 00 01'
local schedulePattern='56 8B F1 81 BE ? ? ? ? C8 00 00 00 0F 8D 15 02 00 00 80 7C 24 08 4D 75 35 8B 44 24 0C 83 05 ? ? ? ? 28 50 E8 ? ? ? ? 3B 05 ? ? ? ? 75 1C 8B 0D ? ? ? ? 8B 96 24 D8 02 00 83 C1 01 69 D2 F8 04 00 00 89 8C 32 7C C6 03 00'

local function find(pattern,name)
  local ok,address=pcall(core.AOBScan,pattern)
  assert(ok and type(address)=='number' and address>0 and address%1==0,
    'Protocol cannot resolve '..name)
  return address
end
local function verify(address,pattern,name)
  local tokens={}
  for token in pattern:gmatch('%S+') do tokens[#tokens+1]=token end
  local bytes=core.readBytes(address,#tokens)
  for i,token in ipairs(tokens) do
    assert(token=='?' or bytes[i]==tonumber(token,16),'Protocol has a modified or occupied '..name)
  end
  return string.char((table.unpack or unpack)(bytes))
end

local caller=find(queueCaller,'command queue caller')
verify(caller,queueCaller,'command queue caller')
local queue=caller+5+core.readInteger(caller+1)
local queueContext=verify(queue,queuePattern,'command queue')
local schedule=find(schedulePattern,'received command scheduler')
local scheduleContext=verify(schedule,schedulePattern,'received command scheduler')
local handler=common.MULTIPLAYER_HANDLER_ADDRESS
assert(type(handler)=='number' and handler>=0x10000 and handler<0x7fe00000,
  'Protocol has an invalid command handler pointer')
local writeOffset=core.readInteger(schedule+5)
assert(writeOffset>0 and writeOffset<0x200000 and core.readInteger(queue+6)==writeOffset,
  'Protocol command write-index operands disagree')
assert(common.COMMAND_ARRAY_ADDRESS==handler+core.readInteger(schedule+75)
  and common.COMMAND_ARRAY_ADDRESS+10==handler+core.readInteger(queue+26)
  and common.COMMAND_CURRENT_ID_ADDRESS==handler+core.readInteger(schedule+59)
  and common.TOTAL_GAME_COMMAND_SIZE==core.readInteger(schedule+68)
  and common.TOTAL_GAME_COMMAND_SIZE==core.readInteger(queue+18)
  and common.MAP_TIME_ADDRESS==core.readInteger(schedule+53),
  'Protocol command metadata does not match its native scheduler')
local localPlayer=core.readInteger(schedule+45)
assert(type(localPlayer)=='number' and localPlayer>0 and localPlayer<0x80000000,
  'Protocol has an invalid native local-player pointer')

-- Retain the original owner bridges; consumers do not expose them again.
local queueCommand=core.exposeCode(queue,2,1)
local scheduleCommand=core.exposeCode(schedule,5,1)
local capacity=core.readInteger(schedule+9)
local function getNativeCommandInterface()
  return {version=1,handler=handler,ring=common.COMMAND_ARRAY_ADDRESS,
    stride=common.TOTAL_GAME_COMMAND_SIZE,capacity=capacity,
    writeIndex=handler+writeOffset,currentCommand=common.COMMAND_CURRENT_ID_ADDRESS,
    localPlayer=localPlayer,tick=common.MAP_TIME_ADDRESS,
    receivedParameters=common.COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS,
    scheduleCommand=scheduleCommand,queueEntry=queue,scheduleEntry=schedule,
    queueBytes=queueContext,scheduleBytes=scheduleContext}
end
return {_queueCommand=queueCommand,_scheduleCommand=scheduleCommand,
  getNativeCommandInterface=getNativeCommandInterface}
