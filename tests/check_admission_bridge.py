"""Actual Lua/FASM host Start bridge against pinned SHC 1.41 instructions.

No game is launched. The Lua callback runs, but transport is a test double.
"""
import argparse
import hashlib
import json
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
a = p.parse_args()
a.output.mkdir(parents=True, exist_ok=True)
raw = a.reference.read_bytes()
sha = hashlib.sha256(raw).hexdigest()
assert sha == '3bb0a8c1e72331b3a30a5aa93ed94beca0081b476b04c1960e26d5b45387ac5a'
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
    'readInteger': get, 'writeInteger': put, 'allocate': allocate, 'allocateCode': allocate,
    'writeCode': lambda address, code: uc.mem_write(address, compile_code(code)),
    'assemble': assemble, 'detourCode': lambda callback, address, size: detours.update({address: callback})})
original = bytes(uc.mem_read(0x44280d, 6))
lua.execute('''
  package.path=root..'/?.lua;'..package.path
  log=function()end;ERROR=1;calls=0;decision=1
  require('admission.native').install(function()
    calls=calls+1
    if decision==2 then error('capture failed') end
    return decision==1
  end)
''')
wrapped = bytes(uc.mem_read(0x44280d, 6))
registers = [UC_X86_REG_EAX, UC_X86_REG_EBX, UC_X86_REG_ECX, UC_X86_REG_EDX,
    UC_X86_REG_ESI, UC_X86_REG_EDI, UC_X86_REG_EBP, UC_X86_REG_ESP, UC_X86_REG_EFLAGS]


def hook(machine, address, size, context):
    if address in (0x442813, 0x442693):
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
                        put(0x191dd80, mode)
                        put(0x191def8, host)
                        put(0x1a275dc, player)
                        put(0x1fe7d1c, 20)
                        g.decision = decision
                        baseline = None
                        initial = [0x12345678, 0x98765432, 0xcc001101, 0x76543210,
                            0x1234, edi, 0x9876, 0x308f000, flags]
                        rng = bytes(uc.mem_read(0x1a279c0, 0x9c50))
                        for code in (original, wrapped):
                            uc.mem_write(0x44280d, code)
                            uc.ctl_remove_cache(0x44280d, 0x442813)
                            uc.mem_write(initial[7], b'unchanged caller frame')
                            for reg, value in zip(registers, initial):
                                uc.reg_write(reg, value)
                            g.calls = 0
                            uc.emu_start(0x44280d, 0, count=1000)
                            actual = [uc.reg_read(reg) for reg in registers]
                            called = code == wrapped and mode in (1, 2) and host != 0
                            assert g.calls == int(called)
                            blocked = called and decision != 1
                            assert uc.reg_read(UC_X86_REG_EIP) == (0x442693 if blocked else 0x442813)
                            if code == original:
                                baseline = actual
                            elif blocked:
                                assert actual == initial
                            else:
                                assert actual == baseline
                            assert bytes(uc.mem_read(initial[7], 22)) == b'unchanged caller frame'
                            assert bytes(uc.mem_read(0x1a279c0, 0x9c50)) == rng
                        cases += 1
result = {'cases': cases, 'referenceSHA256': sha,
    'sourceSHA256': hashlib.sha256((Path(g.root)/'admission/native.lua').read_bytes()).hexdigest(),
    'scope': 'Actual FASM bridge; original registers/flags/stack/RNG; host/SP/MP/error gates. No multiplayer game acceptance.'}
(a.output/'result.json').write_text(json.dumps(result, indent=2)+'\n')
print(json.dumps(result))
