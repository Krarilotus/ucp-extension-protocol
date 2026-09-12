# Native command interface

Related: gynt/ucp-extension-protocol#4 and Corax34/ucp_recorder#47.

Reuse inspection at Protocol587e38b/framework02a7a6b: `protocols/common.lua`
already resolves the command handler, current slot, ring, parameter buffers and
tick. `game/interface.lua` already exposes queue/schedule through the framework's
thiscall bridge; `init.lua:injectProtocol` uses that scheduler but accepts only
registered custom protocols and writes the shared receive buffer. Recorder
replays original categories with recorded player/time/private payload and needs
that existing native boundary. No alternate dispatcher or consumer scan is needed.

`protocol:getNativeCommandInterface()` is available after Protocol is enabled.
It returns version1 metadata for the existing handler, ring, stride/capacity,
write/current indices, local player, tick and receive buffer, plus the existing
`scheduleCommand(handler, category, player, tick, payloadAddress)` callable.
The owner verifies queue/scheduler contexts and cross-checks decoded operands
against its shared command metadata. No new command hook is installed.

Protocol 1.1.4 adds `queueEntry` and `scheduleEntry` to version1 metadata. They
are the already-resolved native entries backing the owner callables, not new
lookups. Recorder's queue suppression and payload-copy guards need to validate
their existing hook spans within these functions. Exposing the owner entries
avoids another queue/scheduler resolver in that consumer. Hooking remains a
separate responsibility: verify the full relevant context and occupied sites,
retain Protocol's dispatch hooks, and preserve the original-call contract.
Ordinary command submission should continue to use the existing callable.
`queueBytes` / `scheduleBytes` are immutable binary strings containing the
full instruction contexts verified by Protocol. Consumers recheck these at
the corresponding entries before hooking instead of copying the owner's
signature or accepting changed code. Strings retain their length through the
framework's table proxy, which does not implement a table-length metamethod.

Callers own authority, payload/category validation, command-boundary admission
and error handling. This low-level API does not make immediate categories safe
to replay or permit scheduling from an unsynchronized multiplayer context.
Resolve once at consumer initialization; do not call it per simulation tick.
The callback reuses the native scheduler, including Protocol's existing handlers;
it does not bypass them or change the wire format.

Validation: 42 portable tests pass, including relocated Lua 5.4/LuaJIT bindings,
actual framework proxy behavior, enabled lifecycle, unchanged scheduler
arguments and zero repeat scans. Each private original SHC/Extreme image and
each official Firefly EFIGS/Polish 1.41 pair passes the actual common/framework
extraction path, twelve numeric fields and thirteen negative cases. Native calls
are stand-ins in this binding check. Original-instruction replay scheduling and
live multiplayer/replay composition remain consumer acceptance work.
