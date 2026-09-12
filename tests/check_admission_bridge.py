"""Actual Lua/FASM host Start bridge against pinned SHC/Extreme instructions.

No game is launched. The Lua callback runs, but transport is a test double.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import struct
import subprocess

import pefile
from lupa import LuaRuntime, lua_type
from unicorn import Uc, UC_ARCH_X86, UC_MODE_32, UC_HOOK_CODE
from unicorn.x86_const import (UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX,
    UC_X86_REG_EDX, UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP,
    UC_X86_REG_ESP, UC_X86_REG_EFLAGS, UC_X86_REG_EIP)

p = argparse.ArgumentParser()
p.add_argument('--reference', type=Path, required=True)
p.add_argument('--fasm', type=Path, required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--variant', choices=('SHC', 'SHCE'), default='SHC')
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
raw = a.reference.read_bytes()
sha = hashlib.sha256(raw).hexdigest()
fixtures = {
    'SHC': ('3bb0a8c1e72331b3a30a5aa93ed94beca0081b476b04c1960e26d5b45387ac5a',
        dict(start=0x44280d, resume=0x442813, reject=0x442693, mode=0x191dd80,
             host=0x191def8, player=0x1a275dc, view=0x1fe7d1c, handles=0x191de10, rng=0x1a279c0)),
    'SHCE': ('55648e6b05d67d37a5773fe699bbb17a2d6ad4de1bb9dbded9a21caef82bd7fb',
        dict(start=0x4429cd, resume=0x4429d3, reject=0x442853, mode=0x2354df0,
             host=0x2354f68, player=0x24baadc, view=0x2a7b21c, handles=0x2354e80, rng=0x24baec0)),
}
expected_sha, expected = fixtures[a.variant]
assert sha == expected_sha
pe = pefile.PE(data=raw)
uc = Uc(UC_ARCH_X86, UC_MODE_32)
uc.mem_map(0x400000, (pe.OPTIONAL_HEADER.SizeOfImage + 4095) & ~4095)
for section in pe.sections:
    uc.mem_write(0x400000 + section.VirtualAddress, section.get_data())
uc.mem_map(0x3000000, 0x100000)
lua = LuaRuntime(unpack_returned_tuples=True)
allocation, detours = 0x3020000, {}


def get(address):
    return struct.unpack('<i', uc.mem_read(address, 4))[0]


def put(address, value):
    uc.mem_write(address, struct.pack('<I', int(value) & 0xffffffff))


image = pe.get_memory_mapped_image()
scan_calls = 0
patterns_seen = {}
def scan(pattern, start=0x400000):
    global scan_calls
    scan_calls += 1
    regex = b''.join(b'.' if token == '?' else re.escape(bytes([int(token, 16)]))
                     for token in pattern.split())
    found = re.search(regex, image[max(0, start-0x400000):], re.DOTALL)
    address = start + found.start() if found else None
    if start == 0x400000 and address:
        patterns_seen[pattern] = address
    return address


def compile_code(code):
    data = bytearray()
    for value in code.values():
        if lua_type(value) == 'table':
            data.extend(compile_code(value))
        elif 0 <= value <= 255:
            data.append(int(value))
        else:
            data.extend(struct.pack('<I', int(value) & 0xffffffff))
    return bytes(data)


def allocate(value, zero=None):
    global allocation
    data = compile_code(value) if lua_type(value) == 'table' else bytes(value)
    address = allocation
    allocation += (len(data) + 15) & ~15
    uc.mem_write(address, data)
    return address


def assemble(source, symbols, origin):
    asm = a.output / 'start.asm'
    binary = asm.with_suffix('.bin')
    asm.write_text(f'use32\norg {origin}\n' + ''.join(
        f'{key} equ {int(value)}\n' for key, value in symbols.items()) + source)
    subprocess.run([str(a.fasm.resolve()), str(asm.resolve()), str(binary.resolve())], check=True)
    data = binary.read_bytes()
    assert len(data) <= 192
    return lua.table_from(data)


g = lua.globals()
g.root = Path(__file__).resolve().parents[1].as_posix()
g.core = lua.table_from({'readByte': lambda address: uc.mem_read(address, 1)[0],
    'AOBScan': scan, 'scanForAOB': scan,
    'readInteger': get, 'writeInteger': put, 'allocate': allocate, 'allocateCode': allocate,
    'writeCode': lambda address, code: uc.mem_write(address, compile_code(code)),
    'assemble': assemble, 'detourCode': lambda callback, address, size: detours.update({address: callback})})
original = bytes(uc.mem_read(expected['start'], 6))
lua.execute('''
  package.path=root..'/?.lua;'..package.path
  -- Resolve the existing transport owner's singleton using its production AoB.
  package.loaded['protocols.common']={MULTIPLAYER_HANDLER_ADDRESS=core.readInteger(
    core.AOBScan('B9 ? ? ? ? E8 ? ? ? ? 39 ? ? ? ? ? 75 17')+1)}
  resolved=require('admission.sites').resolve()
  log=function()end;ERROR=1;calls=0;decision=1
  require('admission.native').install(function()
    calls=calls+1
    if decision==2 then error('capture failed') end
    return decision==1
  end)
''')
for key, value in expected.items():
    if key != 'rng':
        assert g.resolved[key] == value, (key, g.resolved[key], value)
wrapped = bytes(uc.mem_read(expected['start'], 6))
g.adapter = lua.eval("require('admission.native')")
for slot in range(1, 9):
    put(expected['handles'] + slot*4, slot*13)
startup_scans = scan_calls
registers = [UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX,
    UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP, UC_X86_REG_ESP, UC_X86_REG_EFLAGS]


def hook(machine, address, size, context):
    if address in (expected['resume'], expected['reject']):
        machine.emu_stop()
    elif address in detours:
        detours[address](lua.table())
        sp = machine.reg_read(UC_X86_REG_ESP)
        for reg in registers[:7]:
            machine.reg_write(reg, 0xdeadbeef)
        machine.reg_write(UC_X86_REG_EFLAGS, 0x202)
        machine.reg_write(UC_X86_REG_EIP, get(sp) & 0xffffffff)
        machine.reg_write(UC_X86_REG_ESP, sp + 4)


uc.hook_add(UC_HOOK_CODE, hook)
cases = 0
for mode in (0, 1, 2, 99):
    for host in (0, 1):
        for player in range(1, 9):
            for edi in (0, 1):
                for decision in (0, 1, 2):
                    for flags in (0x202, 0x247, 0xa92):
                        put(expected['mode'], mode)
                        put(expected['host'], host)
                        put(expected['player'], player)
                        put(expected['view'], 20)
                        local_player, roster = g.adapter.roster()
                        assert local_player == player and list(roster.values()) == [slot*13 for slot in range(1, 9)]
                        assert g.adapter.isHost() == bool(host)
                        assert g.adapter.inLobby() == (mode in (1, 2))
                        g.decision = decision
                        baseline = None
                        initial = [0x12345678, 0x98765432, 0xcc001101, 0x76543210,
                            0x1234, edi, 0x9876, 0x308f000, flags]
                        rng = bytes(uc.mem_read(expected['rng'], 0x9c50))
                        for code in (original, wrapped):
                            uc.mem_write(expected['start'], code)
                            uc.ctl_remove_cache(expected['start'], expected['resume'])
                            uc.mem_write(initial[7], b'unchanged caller frame')
                            for reg, value in zip(registers, initial):
                                uc.reg_write(reg, value)
                            g.calls = 0
                            uc.emu_start(expected['start'], 0, count=1000)
                            actual = [uc.reg_read(reg) for reg in registers]
                            called = code == wrapped and mode in (1, 2) and host != 0
                            assert g.calls == int(called)
                            blocked = called and decision != 1
                            assert uc.reg_read(UC_X86_REG_EIP) == expected['reject' if blocked else 'resume']
                            if code == original:
                                baseline = actual
                            elif blocked:
                                assert actual == initial
                            else:
                                assert actual == baseline
                            assert bytes(uc.mem_read(initial[7], 22)) == b'unchanged caller frame'
                            assert bytes(uc.mem_read(expected['rng'], 0x9c50)) == rng
                        cases += 1
assert scan_calls == startup_scans, 'Admission must never scan during callbacks'
uc.mem_write(expected['start'], original)
resolver = lua.eval("require('admission.sites')")
negative_cases = 0
original_image = image
for pattern, address in list(patterns_seen.items()):
    if pattern.startswith('B9 '):  # pre-existing transport binding, not admission's resolver
        continue
    offset = address - 0x400000
    image = original_image[:offset] + b'\xcc' + original_image[offset+1:]
    ok, _ = lua.eval('pcall')(resolver.resolve)
    assert not ok, ('missing binding accepted', pattern)
    negative_cases += 1
    length = len(pattern.split())
    image = original_image + original_image[offset:offset+length]
    ok, message = lua.eval('pcall')(resolver.resolve)
    assert not ok and 'ambiguous' in message, ('duplicate binding accepted', pattern)
    negative_cases += 1
image = original_image
for offset in (0, 2, 8):
    address = expected['start'] + offset
    saved = bytes(uc.mem_read(address, 1))
    uc.mem_write(address, bytes([saved[0] ^ 1]))
    ok, _ = lua.eval('pcall')(resolver.verify, g.resolved)
    assert not ok, ('occupied site or changed operand accepted', offset)
    uc.mem_write(address, saved)
    negative_cases += 1
handler = lua.eval("package.loaded['protocols.common']")
handler.MULTIPLAYER_HANDLER_ADDRESS += 4
ok, _ = lua.eval('pcall')(resolver.resolve)
assert not ok, 'Mismatched transport singleton accepted'
negative_cases += 1
result = {'cases': cases, 'variant': a.variant, 'referenceSHA256': sha,
    'negativeResolutionCases': negative_cases, 'callbackScans': 0,
    'resolved': {key: hex(g.resolved[key]) for key in expected if key != 'rng'},
    'sourceSHA256': hashlib.sha256((Path(g.root)/'admission/native.lua').read_bytes()).hexdigest(),
    'resolverSHA256': hashlib.sha256((Path(g.root)/'admission/sites.lua').read_bytes()).hexdigest(),
    'scope': 'Actual FASM bridge; original registers/flags/stack/RNG; host/SP/MP/error gates. No multiplayer game acceptance.'}
(a.output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result))
