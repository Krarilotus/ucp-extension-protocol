"""Actual Protocol/common/framework binding path against a private PE; no game."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import pefile
from lupa.lua54 import LuaRuntime


def check(path,variant,framework):
    root=Path(__file__).resolve().parents[1]
    raw=path.read_bytes(); pe=pefile.PE(data=raw)
    base=pe.OPTIONAL_HEADER.ImageBase; image=bytearray(pe.get_memory_mapped_image())
    lua=LuaRuntime(unpack_returned_tuples=True)
    scans=[]; matches={}; exposures=[]
    def scan(pattern,start=None,stop=None):
        scans.append((pattern,start))
        regex=b''.join(b'.' if t=='?' else re.escape(bytes([int(t,16)])) for t in pattern.split())
        offset=max(0,(start or base)-base)
        found=re.search(regex,image[offset:(stop-base) if stop else None],re.DOTALL)
        address=base+offset+found.start() if found else 0
        if start is None: matches[pattern]=address
        return address
    def read(a,n):
        assert base<=a and a+n<=base+len(image),hex(a)
        return bytes(image[a-base:a-base+n])
    g=lua.globals(); g.root=root.as_posix(); g.scan=scan
    g.read_int=lambda a:struct.unpack('<i',read(a,4))[0]
    g.read_bytes=lambda a,n:lua.table_from(read(a,n))
    g.expose=lambda a,n,c:exposures.append((a,n,c))
    lua.execute("""
package.path=root..'/?.lua;'..package.path
log=function() end
core={AOBScan=scan,scanForAOB=scan,readInteger=read_int,readBytes=read_bytes,
 exposeCode=function(a,n,c) expose(a,n,c);return function(...) lastCall={a,...}; return 91 end end}
package.loaded.core=core
""")
    g.utils=lua.execute((framework/'utils.lua').read_text(encoding='utf-8'))
    common=lua.eval("(require('protocols.common'))")
    before=len(scans)
    owner=lua.eval("(require('game.interface'))")
    api=owner.getNativeCommandInterface()
    expected=(0x191d768,0x480210,0x489100,0x1a275dc,0x1fe7da8,0x109ee0) if variant=='SHC' else (
        0x23547d8,0x4803e0,0x489210,0x24baadc,0x2a7b2a8,0x166370)
    handler,schedule,queue,player,tick,write_offset=expected
    assert exposures==[(queue,2,1),(schedule,5,1)]
    assert (api.queueEntry,api.scheduleEntry)==(queue,schedule)
    assert lua.eval("function(api) return api.queueBytes:byte(1,#api.queueBytes) end")(api)==tuple(read(queue,69))
    assert lua.eval("function(api) return api.scheduleBytes:byte(1,#api.scheduleBytes) end")(api)==tuple(read(schedule,79))
    assert (api.version,api.handler,api.ring,api.stride,api.capacity)==(1,handler,handler+0x3c67c,1272,200)
    assert (api.writeIndex,api.currentCommand,api.localPlayer,api.tick,api.receivedParameters)==(
        handler+write_offset,handler+0x2d824,player,tick,handler+0xcdc)
    assert len(scans)-before==2
    for _ in range(100): owner.getNativeCommandInterface()
    assert len(scans)-before==2
    interface_patterns=[p for p,start in scans[before:] if start is None]
    negative=0
    def rejected():
        count=len(exposures)
        lua.execute("package.loaded['game.interface']=nil; assert(not pcall(require,'game.interface'))")
        assert len(exposures)==count
    for pattern in interface_patterns:
        address=matches[pattern]
        saved=image[address-base]; image[address-base]=0xcc
        rejected(); negative+=1
        g.core.AOBScan=lambda p:address if p==pattern else scan(p)
        rejected(); negative+=1
        g.core.AOBScan=scan; image[address-base]=saved
        assert scan(pattern,address+1)==0, 'non-unique fixture context'
        g.core.AOBScan=lua.eval('function() error("framework discovery failed") end')
        rejected(); negative+=1
        g.core.AOBScan=scan
    for address in (queue,queue+12,schedule+37):
        saved=image[address-base]; image[address-base]=0xcc
        rejected(); negative+=1
        image[address-base]=saved
    for key in ('COMMAND_ARRAY_ADDRESS','COMMAND_CURRENT_ID_ADDRESS','TOTAL_GAME_COMMAND_SIZE','MAP_TIME_ADDRESS'):
        saved=common[key]; common[key]=123
        rejected(); negative+=1; common[key]=saved
    return dict(variant=variant,referenceSha256=hashlib.sha256(raw).hexdigest(),
                numericFields=12,ownerDiscoveryCalls=2,negativeCases=negative,
                scope='Private image/framework extraction; exposed native calls are stand-ins; no game.')


if __name__=='__main__':
    p=argparse.ArgumentParser()
    p.add_argument('--reference',type=Path,required=True)
    p.add_argument('--variant',choices=['SHC','Extreme'],required=True)
    p.add_argument('--framework-code',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args(); result=check(a.reference,a.variant,a.framework_code)
    a.output.write_text(json.dumps(result,indent=2)+'\n'); print(json.dumps(result,indent=2))
