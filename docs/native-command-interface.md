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
extraction path, ten numeric fields and thirteen negative cases. Native calls
are stand-ins in this binding check. Original-instruction replay scheduling and
live multiplayer/replay composition remain consumer acceptance work.
