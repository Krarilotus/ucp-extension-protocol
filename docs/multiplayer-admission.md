# Multiplayer content admission

`registerMultiplayerAdmission(name, capture, notify)` adds a provider;
`multiplayerAdmissionVersion()` returns 1. A provider's `capture` freezes its
settings and returns their lowercase SHA256. Register before `afterInit`; no
provider can be added after the first admission exchange. `registerMultiplayerAdmission`
returns false when admission is off on this game (see below). Without a provider,
Protocol and the native Start action behave as without admission.

## What is compared

On the first admission check of a session, Protocol hashes the files of every
active extension (through the Files module's traversal), their load order, files
and folders named in option values, and `ucp/ucp-version.yml`. The result is kept
for the session. The full resolved configuration and the sorted provider names
and digests are added at every check. Strings sort byte by byte and numbers are
encoded in binary, so PCs with different system locales agree. This is content
agreement, not protection against deliberately modified clients; unrelated local
configuration differences can also block Start.

The first check hashes everything once with the framework's Lua SHA256, so the
host's first Start in a session can wait as long as that takes (about 80 seconds
for some 300 MB of active extensions). Later checks reuse the result.

## Start

On a multiplayer host's Start action, admission runs before the native
readiness and map checks, the random seed and start command 11. One 76-byte
IMMEDIATE message carries kind, request serial, host slot, the SHA256 and the
eight native player handles. Every connected human slot must reply with that
identity and roster. Missing, stale or mismatched replies block Start; pressing
Start again retries. Roster changes and host migration need a fresh agreement.
Protocol never starts a match from a network callback and adds no simulation
command, polling, file read or hash to game ticks.

The host logs waiting and mismatch, and calls each provider's `notify(reason)`
with `waiting`, `mismatch` or `error`. Providers own the player-facing text.

## Game sites

Protocol resolves four instruction contexts once, when the first provider
registers: the host comparison before the readiness loop (Start, return and
rejection branch), the lobby command-52 call (game mode), the local player slot
and the current menu view. Both lobby calls must use the transport's command
handler from `protocols/common.lua`. The Start site is checked again just before
the patch; the bridge keeps registers, stack and flags, runs the original host
comparison once and keeps its branch. If a site is missing or differs, admission
logs a warning and stays off; the command transport keeps working.

Limits: 32 providers, 256 extensions, 50,000 files, 1 GiB per file, 4 GiB in
total; 100,000 configuration values, nested at most 32 deep.
