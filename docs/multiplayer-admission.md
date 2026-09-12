# Multiplayer content admission

Protocol 1.1.0 adds `registerMultiplayerAdmission(name, capture, notify)` and
`multiplayerAdmissionVersion() == 1`. An opted-in extension's capture callback
freezes its settings and returns their lowercase SHA256. Register before
`afterInit`; no provider may be added after the first admission exchange.
Without a provider, existing Protocol behavior and native Start remain unchanged.

At startup, the framework VFS and streaming SHA256 fingerprint active extension
files, their load order, referenced option files/directories and the framework
version file. Directory/archive shadowing follows Recorder's existing
`code/replay-assets.lua` rule (source aaa3e82). The full resolved configuration
and sorted provider names/digests enter a typed, length-framed SHA256 at admission.
This is content agreement, not protection against deliberately modified clients.
All peers must use the same extension content, order and configuration; unrelated
local configuration differences can conservatively reject admission.

On a multiplayer host's Start action, admission checks agreement before the
existing readiness/map checks, RNG seed or start command 11. Single-player and
spectator paths retain their original instructions. The original
host/readiness/launch owners still perform the start.

Version 1.1.1 replaces the fixed SHC binding from 1.1.0 with framework AoB
discovery. See [native binding verification](admission-native-bindings.md) for
resolution, ownership and exact SHC/Extreme component evidence. Real two-peer
acceptance remains outstanding.

One 76-byte IMMEDIATE message carries kind, request serial, host slot, complete
SHA256 and eight native transport handles. Every connected human slot must reply
with that identity and roster. Missing, stale or mismatched responses block
Start. Roster changes and host migration require fresh agreement. Clicking
Start again retries missing replies; it launches only once all replies match.
The module never auto-launches from a network callback or queues an AI/player
simulation command. No polling, file reads, hashes or RNG calls enter game ticks.

The host reports waiting/mismatch through the framework log and optional
`notify(reason)` callbacks. AIC Tactics uses the existing chat module's local
display API; no additional message is broadcast for presentation. Native chat
font/encoding support limits these messages to ASCII English in this integration.
The native Start layout and transport/roster assumptions require actual
two-physical-peer testing; component tests do not establish multiplayer acceptance.
Limits: 32 providers, 256 extensions, 50,000 file/directory entries, 1 GiB per
file, 4 GiB total; hashing is streaming and occurs once before the message loop.
Start-time configuration serialization allows 100,000 values and depth 32.
