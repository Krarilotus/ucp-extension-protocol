from pathlib import Path

import pytest
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize('failure', ['nil', 'zero', 'ambiguous'])
def test_failed_resolution_never_allocates_or_patches(failure):
    lua = LuaRuntime()
    lua.globals().root = ROOT.as_posix()
    lua.globals().failure = failure
    lua.execute('''
      package.path=root..'/?.lua;'..package.path
      core={
        AOBScan=function()
          if failure=='nil' then return nil end
          return failure=='zero' and 0 or 0x12340000
        end,
        scanForAOB=function() return 0x12350000 end,
      }
      setmetatable(core,{__index=function(_,key)
        error('Unexpected native operation: '..key)
      end})
      local ok,why=pcall(require,'admission.native')
      assert(not ok)
      assert(why:find(failure=='ambiguous' and 'ambiguous' or 'unavailable',1,true),why)
    ''')
