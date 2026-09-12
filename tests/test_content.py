"""Admission fingerprints retain their format when enumeration uses Files."""
import hashlib
import os
from pathlib import Path

import pytest
from lupa.lua54 import LuaRuntime as Lua54
from lupa.luajit21 import LuaRuntime as LuaJIT

ROOT = Path(__file__).resolve().parents[1]
FILES = Path(os.environ.get('UCP_FILES_TEST_ROOT', ROOT.parent / 'aic-tactics-files-inventory'))


@pytest.fixture(params=[Lua54, LuaJIT], ids=['lua54', 'luajit'])
def lua(request):
    runtime = request.param()
    runtime.globals().root = ROOT.as_posix()
    runtime.globals().files_root = FILES.as_posix()
    runtime.globals().hash_string = lambda value: hashlib.sha256(value.encode()).hexdigest()
    runtime.execute('''
package.path=root..'/?.lua;'..package.path
local walk=dofile(files_root..'/walk.lua')
modules={files={createFileWalker=function(self,...) return walk.create(...) end}}
sha={sha256=function(value)
 if value~=nil then return hash_string(value) end
 local chunks={};return function(chunk)
  if chunk then chunks[#chunks+1]=chunk else return hash_string(table.concat(chunks)) end
 end
end}
packed='ucp/modules/packed-1.0.0'; unpacked='ucp/plugins/unpacked-1.0.0'
contents={[packed..'.zip']='archive',[unpacked..'/init.lua']='script',
 [unpacked..'/data.zip']='nested archive',[unpacked..'/code/x.lua']='nested script',
 ['maps/test.map']='map',['ucp/ucp-version.yml']='version'}
listing={[packed..'/']={},[unpacked..'/']={unpacked..'/init.lua',unpacked..'/data.zip'},
 [unpacked..'/code/']={unpacked..'/code/x.lua'}}
children={[packed..'/']={},[unpacked..'/']={unpacked..'/code/',unpacked..'/data/',unpacked..'/.git/'},
 [unpacked..'/code/']={}}
ucp={internal={resolveAliasedPath=function(path)
 return (path:gsub('^alias/',unpacked..'/'))
end,io={files=function(path) return assert(listing[path],'Cannot list '..path) end,
 directories=function(path) return assert(children[path],'Cannot list '..path) end}}}
opened,closed=0,0
io.open=function(path)
 if not contents[path] then return nil end
 opened=opened+1;local read=false
 return {read=function()
  if read then return nil end
  read=true;return contents[path]
 end,close=function() closed=closed+1;return true end}
end
content=require('admission.content')
extensions={{name='packed',version='1.0.0',type=function() return 'ModuleLoader' end},
 {name='unpacked',version='1.0.0',type=function() return 'PluginLoader' end}}
function expected(extra)
 local files={}
 for _,path in ipairs({packed..'.zip',unpacked..'/init.lua',unpacked..'/data.zip',
  unpacked..'/code/x.lua','ucp/ucp-version.yml'}) do files[path]=hash_string(contents[path]) end
 for key,value in pairs(extra or {}) do files[key]=hash_string(value) end
 return hash_string(content.canonical({order={packed,unpacked},files=files}))
end
''')
    return runtime


def test_existing_fingerprint_and_stream_closure(lua):
    lua.execute('''
local actual=content.capture(extensions,{map='maps/test.map',text='https://example.invalid'})
assert(actual==expected({['option/maps/test.map']='map'}))
assert(opened==closed)
''')


def test_physical_shadowing_folder_changes_fingerprint(lua):
    lua.execute('''
local before=content.capture(extensions,{})
assert(before==expected())
local path=unpacked..'/data/'
listing[path]={path..'shadow.lua'};children[path]={};contents[path..'shadow.lua']='shadow'
local after=content.capture(extensions,{})
assert(after~=before and after==expected({[path..'shadow.lua']='shadow'}))
''')


def test_alias_directory_keys_and_resolved_file_identity(lua):
    lua.execute('''
local actual=content.capture({extensions[1]},{folder='alias/code/',file='alias/init.lua'})
local files={[packed..'.zip']=hash_string('archive'),['ucp/ucp-version.yml']=hash_string('version'),
 ['option/alias/code/x.lua']=hash_string('nested script'),['option/alias/init.lua']=hash_string('script')}
assert(actual==hash_string(content.canonical({order={packed},files=files})))
''')


def test_invalid_listing_and_missing_asset_fail(lua):
    lua.execute('''
listing[unpacked..'/code/']={'elsewhere.lua'}
assert(not pcall(content.capture,extensions,{}))
listing[unpacked..'/code/']={unpacked..'/code/x.lua'}
contents[unpacked..'/code/x.lua']=nil
assert(not pcall(content.capture,extensions,{}))
assert(opened==closed)
''')


def test_cycles_fail_and_unreferenced_files_do_not_change_digest(lua):
    lua.execute('''
local before=content.capture(extensions,{})
contents['unused.lua']='unreferenced'
assert(content.capture(extensions,{})==before)
local cycle={};cycle.self=cycle
assert(not pcall(content.capture,extensions,cycle))
''')
