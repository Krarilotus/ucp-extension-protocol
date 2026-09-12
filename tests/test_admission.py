from pathlib import Path
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def runtime():
    lua = LuaRuntime()
    lua.globals().root = ROOT.as_posix()
    lua.execute('''
      package.path=root..'/?.lua;'..package.path
      factory=require('admission.consensus')
      peers,queue,hashCalls={}, {},0
      for slot=1,8 do
        local p={slot=slot,roster={10,20,30,40,50,60,70,80},host=slot==1,lobby=true,
          digest=string.rep('a',64)}
        peers[slot]=p
        p.owner=factory.new({roster=function()return p.slot,p.roster end,
          isHost=function()return p.host end,inLobby=function()return p.lobby end,
          identity=function()hashCalls=hashCalls+1;p.frozen=true;return p.digest end,
          send=function(message)queue[#queue+1]={sender=p.slot,message=message} end})
      end
      function deliver()
        local count=0
        while #queue>0 do
          count=count+1;assert(count<=100)
          local item=table.remove(queue,1)
          for _,p in ipairs(peers) do p.owner.receive(item.sender,item.message) end
        end
      end
    ''')
    return lua


def test_all_eight_peers_must_match_before_start():
    runtime().execute('''
      assert(not peers[1].owner.start() and #queue==1)
      assert(not peers[2].owner.start())
      deliver()
      assert(peers[1].owner.start() and #queue==0)
      for _,p in ipairs(peers) do assert(p.frozen) end
    ''')


def test_missing_mismatched_and_newly_joined_peers_block():
    runtime().execute('''
      peers[8].lobby=false
      peers[1].owner.start();deliver()
      local ok,why=peers[1].owner.start();assert(not ok and why=='waiting')
      peers[8].lobby=true;peers[8].digest=string.rep('b',64);deliver()
      ok,why=peers[1].owner.start();assert(not ok and why=='mismatch');queue={}
      peers[8].digest=string.rep('a',64)
      peers[1].owner.start();deliver();assert(peers[1].owner.start())
      for _,p in ipairs(peers) do p.roster[8]=81 end
      assert(not peers[1].owner.start());deliver();assert(peers[1].owner.start())
    ''')


def test_old_responses_and_departed_slots_cannot_admit_new_round():
    runtime().execute('''
      peers[1].owner.start();local old=queue[1].message;deliver()
      for _,p in ipairs(peers) do p.roster[2]=21 end
      assert(not peers[1].owner.start())
      old.kind=1
      assert(not peers[1].owner.receive(2,old))
      deliver();assert(peers[1].owner.start())
      for _,p in ipairs(peers) do p.roster[8]=-1 end
      peers[8].lobby=false
      assert(not peers[1].owner.start());deliver();assert(peers[1].owner.start())
    ''')


def test_host_migration_requires_new_host_agreement():
    runtime().execute('''
      peers[1].owner.start();deliver();assert(peers[1].owner.start())
      peers[1].host=false;peers[2].host=true
      assert(not peers[1].owner.start())
      assert(not peers[2].owner.start());deliver();assert(peers[2].owner.start())
    ''')


def test_malformed_and_non_lobby_messages_do_not_hash_or_freeze():
    runtime().execute('''
      assert(not peers[2].owner.receive(0,{}))
      assert(not peers[2].owner.receive(1,{kind=0,serial=1,host=1,digest='bad',roster=peers[2].roster}))
      peers[2].lobby=false
      assert(not peers[2].owner.receive(1,{kind=0,serial=1,host=1,
        digest=string.rep('a',64),roster=peers[2].roster}))
      assert(hashCalls==0 and not peers[2].frozen)
    ''')


def test_canonical_settings_have_type_and_length_framing():
    runtime().execute('''
      local c=require('admission.content').canonical
      assert(c({b=2,a=1})==c({a=1,b=2}))
      assert(c({ab='c'})~=c({a='bc'}))
      assert(c({[1]='x'})~=c({['1']='x'}))
      assert(c({x=false})~=c({x='false'}))
      local cycle={};cycle.x=cycle;assert(not pcall(c,cycle))
      assert(not pcall(c,{x=function()end}))
      assert(not pcall(c,{x=0/0}))
    ''')


def test_registered_wire_message_serializes_76_bytes_and_freezes_provider():
    lua=runtime()
    import hashlib
    lua.globals().hash_text=lambda value: hashlib.sha256(value.encode()).hexdigest()
    lua.execute('''
      local native={roster=function()return 1,{10,20,-1,-1,-1,-1,-1,-1} end,
        isHost=function()return true end,inLobby=function()return true end,
        install=function(check)start=check end}
      package.loaded['admission.native']=native
      sha={sha256=function(value)return hash_text(value) end}
      configFinal={ai={file='wolf.json'}}
      hooks={registerHookCallback=function()end};log=function()end
      local registered,handler
      local protocol={registerCustomProtocol=function(_,extension,name,kind,size,callbacks)
        assert(extension=='protocol' and name=='content-admission-v1' and kind=='IMMEDIATE' and size==76)
        handler=callbacks;return 131
      end,invokeCustomProtocol=function(_,number,message)
        assert(number==131)
        local values,bytes={},0
        local p={serializeInteger=function(_,v)values[#values+1]=v;bytes=bytes+4 end,
          serializeBytes=function(_,v)values[#values+1]=v;bytes=bytes+#v end}
        handler:schedule({parameters=p},message)
        assert(bytes==76 and #values==12 and #values[4]==32)
        local cursor=0
        local function nextValue()cursor=cursor+1;return values[cursor]end
        p.deserializeInteger=nextValue;p.deserializeBytes=nextValue
        handler:execute({player=1,parameters=p})
        assert(cursor==12)
      end}
      local admission=require('admission.init')
      admission.register(protocol,'aic',function()frozen=true;return string.rep('a',64) end,
        function(reason)assert(reason=='waiting');notified=true end)
      admission.contentHash=string.rep('b',64)
      assert(not start() and frozen and notified)
      assert(not pcall(admission.register,protocol,'late',function()end))
    ''')
