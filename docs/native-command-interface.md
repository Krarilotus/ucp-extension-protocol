# Native command interface

`protocol:getNativeCommandInterface()` is available after Protocol is enabled.
It returns version 1 metadata from the command transport Protocol already
resolves (`protocols/common.lua`, `game/interface.lua`):

- `handler`, `ring`, `stride`, `capacity`, `writeIndex`, `currentCommand`,
  `localPlayer`, `tick` and `receivedParameters`;
- `scheduleCommand(handler, category, player, tick, payloadAddress)`, the native
  scheduler with Protocol's handlers;
- `queueEntry` and `scheduleEntry`, the native queue and scheduler functions, with
  `queueBytes` and `scheduleBytes`, the instruction bytes Protocol verified there.
  A consumer that hooks inside these functions compares these bytes first instead
  of copying Protocol's patterns.

Protocol verifies both functions and cross-checks their operands with its command
metadata. If they differ, the interface is off (a warning in the log) and the
call raises an error; the command transport keeps working.

Callers own authority, payload and category validation and error handling. The
interface does not make immediate categories safe to replay and does not permit
scheduling from an unsynchronized multiplayer context. Resolve it once at
initialization, not per tick.
