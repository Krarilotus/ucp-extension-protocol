"""Owner API and verified bindings at relocated addresses on both Lua runtimes."""
import os
from pathlib import Path
import re
import struct
import pytest
from lupa.lua54 import LuaRuntime as Lua54
from lupa.luajit21 import LuaRuntime as LuaJIT

ROOT=Path(__file__).resolve().parents[1]


@pytest.fixture(params=[Lua54,LuaJIT],ids=['lua54','luajit'])
def fixture(request):
    lua=request.param(unpack_returned_tuples=True)
    g=lua.globals(); g.root=ROOT.as_posix()
    patterns=dict(re.findall(r"local (queueCaller|queuePattern|schedulePattern)='([^']+)'",(ROOT/'game/interface.lua').read_text()))
    addresses={'queueCaller':0x10000000,'queuePattern':0x11000000,'schedulePattern':0x12000000}
    memory={}
    for name,pattern in patterns.items():
        for i,token in enumerate(pattern.split()): memory[addresses[name]+i]=0x19 if token=='?' else int(token,16)
    def word(a,v):
        for i,b in enumerate(struct.pack('<I',v&0xffffffff)): memory[a+i]=b
    word(addresses['queueCaller']+1,addresses['queuePattern']-addresses['queueCaller']-5)
    word(addresses['queuePattern']+6,0x109ee0)
    word(addresses['schedulePattern']+5,0x109ee0)
    word(addresses['schedulePattern']+45,0x20109e74)
    word(addresses['schedulePattern']+53,0x30000000)
    scans=[]
    def scan(pattern,start=None):
        scans.append((pattern,start))
        name=next(k for k,v in patterns.items() if v==pattern)
        assert name!='queuePattern','Queue target must be decoded, not rescanned'
        return 0 if start else addresses[name]
    g.scan=scan
    g.read_bytes=lambda a,n:lua.table_from(memory[a+i] for i in range(n))
    g.read_int=lambda a:struct.unpack('<i',bytes(memory[a+i] for i in range(4)))[0]
    g.write_word=word
    lua.execute('''
package.path=root..'/?.lua;'..package.path
common={MULTIPLAYER_HANDLER_ADDRESS=0x20000000,COMMAND_ARRAY_ADDRESS=0x2003c67c,
 COMMAND_CURRENT_ID_ADDRESS=0x2002d824,TOTAL_GAME_COMMAND_SIZE=1272,
 MAP_TIME_ADDRESS=0x30000000,COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS=0x20000cdc}
package.loaded['protocols.common']=common
calls={}; exposed=0
core={AOBScan=scan,scanForAOB=scan,readBytes=read_bytes,readInteger=read_int,
 exposeCode=function(address,count,abi)
  assert(abi==1 and (address==0x11000000 and count==2 or address==0x12000000 and count==5))
  exposed=exposed+1
  return function(...) calls[#calls+1]={address,...}; return 91 end
 end}
''')
    return lua,memory,scans


def test_native_metadata_reuses_existing_callable_without_repeat_scans(fixture):
    lua,_,scans=fixture
    lua.execute('''
owner=require('game.interface')
local api=owner.getNativeCommandInterface()
assert(api.version==1 and api.handler==common.MULTIPLAYER_HANDLER_ADDRESS)
assert(api.ring==common.COMMAND_ARRAY_ADDRESS and api.stride==1272 and api.capacity==200)
assert(api.writeIndex==0x20109ee0 and api.currentCommand==common.COMMAND_CURRENT_ID_ADDRESS)
assert(api.localPlayer==0x20109e74 and api.tick==common.MAP_TIME_ADDRESS)
assert(api.receivedParameters==common.COMMAND_FIXED_RECEIVED_PARAMETER_LOCATION_ADDRESS)
assert(api.scheduleCommand==owner._scheduleCommand and exposed==2)
assert(api.scheduleCommand(api.handler,33,4,1000,0x31000000)==91)
assert(#calls[1]==6 and calls[1][1]==0x12000000 and calls[1][2]==api.handler)
assert(calls[1][3]==33 and calls[1][4]==4 and calls[1][5]==1000 and calls[1][6]==0x31000000)
api.handler=1; assert(owner.getNativeCommandInterface().handler==0x20000000)
for i=1,100 do assert(owner.getNativeCommandInterface().scheduleCommand==owner._scheduleCommand) end
''')
    assert len(scans)==4


@pytest.mark.parametrize('failure',['missing','ambiguous','queue','schedule','target','writeIndex','ring','tick','localPlayer'])
def test_failed_binding_exposes_neither_native_call(fixture,failure):
    lua,memory,_=fixture
    if failure=='missing': lua.execute('core.AOBScan=function() return 0 end')
    elif failure=='ambiguous': lua.execute('core.scanForAOB=function() return 123 end')
    elif failure=='queue': memory[0x11000000+12]=0xcc
    elif failure=='schedule': memory[0x12000000+37]=0xcc
    elif failure=='target': lua.execute('write_word(0x10000001,123)')
    elif failure=='writeIndex': lua.execute('write_word(0x11000006,123)')
    elif failure=='ring': lua.execute('common.COMMAND_ARRAY_ADDRESS=123')
    elif failure=='tick': lua.execute('common.MAP_TIME_ADDRESS=123')
    elif failure=='localPlayer': lua.execute('write_word(0x1200002d,0)')
    lua.execute("assert(not pcall(require,'game.interface')); assert(exposed==0)")


def test_public_owner_lifecycle_and_callback_through_actual_framework_proxy(fixture):
    lua,_,scans=fixture
    proxy=os.environ.get('UCP_FRAMEWORK_PROXIES')
    assert proxy,'Set UCP_FRAMEWORK_PROXIES to the actual framework proxy source'
    lua.globals().proxies=lua.execute(Path(proxy).read_text(encoding='utf-8'))
    lua.execute('''
package.loaded['game.version']={setMultiplayerGameVersion=function() end}
local hookCalls=0
package.loaded['game.hooks']={setHooks=function() hookCalls=hookCalls+1 end}
hooks={registerHookCallback=function(name,callback) assert(name=='afterInit') end}
local namespace=dofile(root..'/init.lua')
local public=proxies.ExtensionProxy(namespace)
assert(not pcall(public.getNativeCommandInterface,public))
namespace:enable({})
local api=public:getNativeCommandInterface()
assert(api.version==1 and api.capacity==200 and api.handler==common.MULTIPLAYER_HANDLER_ADDRESS)
assert(api.scheduleCommand(api.handler,33,4,1000,0x31000000)==91)
assert(calls[1][1]==0x12000000 and calls[1][2]==api.handler and #calls[1]==6)
assert(not pcall(function() api.handler=1 end))
assert(hookCalls==1 and exposed==2)
''')
    assert len(scans)==4
