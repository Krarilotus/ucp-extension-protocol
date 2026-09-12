# Admission native bindings

Protocol 1.1.1 corrects the fixed SHC addresses introduced by admission 1.1.0.
The API and 76-byte wire format remain version 1. Existing Protocol behavior
without an admission provider is unchanged. The published 1.1.0 ZIP is not
silently replaced; downstream previews need a new package and dependency pin.

## Owners and lifecycle

Inspected framework `02a7a6bc8ab9`: `content/ucp/code/core.lua` supplies cached
`core.AOBScan`, bounded/unbounded `core.scanForAOB`, assembly and patch APIs.
`data/cache.lua` owns scan caching. Legacy `caa50aba9fc8`,
`port/ai_attacktarget.lua` and `port/ai_defense.lua`, demonstrate discovery,
operand decoding and preserving displaced native code.

Protocol `a6d940357432`, `protocols/common.lua` and its callers in `init.lua`,
already own command transport and its resolved singleton. They do not export
the host Start boundary or local lobby roster. `admission/sites.lua` supplies
that missing binding inside Protocol, verifies both decoded lobby call
singletons equal `common.MULTIPLAYER_HANDLER_ADDRESS`, and uses existing
transport for messages. AIC Tactics does not install this hook.

Resolution occurs once when the first provider loads `admission.native`, before
patch installation. Four identifying instruction contexts use framework cached
scans; a subsequent framework scan detects a second occurrence. Missing,
ambiguous or conflicting bindings fail before patching; no reference-address
fallback or executable hash whitelist exists in production. No scan occurs in
roster reads, admission callbacks or simulation ticks.

| Binding | Evidence and decoding |
|---|---|
| Start/host/return | Host comparison followed by readiness-array loop and transport call; host is the absolute comparison operand, return follows the six displaced bytes |
| Rejection | Decode the original `je rel32`; confirm the readiness check reaches the same rejection path |
| Human handles | Decode readiness-array start and the signed displacement in its parallel handle comparison; verify the loop ends after eight four-byte slots; subtract one slot for native indexing |
| Mode | Decode the comparison following the lobby command-52 call; verify its transport singleton matches the existing owner |
| Local slot | Decode the absolute local-player load in the native per-player state access context |
| Current view | Decode the absolute view load in the menu dispatcher context |

Immediately before installation, recheck instruction context and the displaced
host operand/branch destination. The bridge preserves registers, stack and flags
around the Lua callback, executes the original host comparison exactly once on
allowed/native paths, and retains its conditional branch. Rejection restores
the entry flags and goes directly to the original rejection boundary. Callback
errors block Start. Recorder's later seed observer and Protocol's command hooks
are separate sites; real combined-runtime testing is still required.

## Executable verification

Private licensed fixtures (not distributed):

| Fixture | SHA256 | Start / return / rejection |
|---|---|---|
| SHC 1.41 | `3bb0a8c1e72331b3a30a5aa93ed94beca0081b476b04c1960e26d5b45387ac5a` | `44280D` / `442813` / `442693` |
| Extreme 1.41 | `55648e6b05d67d37a5773fe699bbb17a2d6ad4de1bb9dbded9a21caef82bd7fb` | `4429CD` / `4429D3` / `442853` |

Reference addresses in this table and the private test describe evidence only.
Production derives them from instructions.

On each fixture, `tests/check_admission_bridge.py` executes the actual Lua/FASM
bridge under Unicorn in 1,152 register/flags/stack/RNG comparisons across host,
client, SP/MP and callback-error cases. It verifies all decoded globals and
roster reads, with zero scans in callbacks. Twelve negative checks per fixture
cover each missing/duplicate context, occupied entry, changed host/branch operands
and a mismatched transport singleton. Ten public tests cover consensus and
failure before native allocation/patching.

Reproduce with Python, pefile, lupa, Unicorn and FASM:

```text
python -m pytest tests/test_admission.py tests/test_admission_bindings.py -q
python tests/check_admission_bridge.py --reference <licensed-exe> --variant SHC --fasm <fasm> --output build/admission-shc
python tests/check_admission_bridge.py --reference <licensed-extreme-exe> --variant SHCE --fasm <fasm> --output build/admission-extreme
```

These are native-instruction component tests, not real network, save/load,
replay, game-speed or complete AIC/Extreme acceptance. The rest of AIC Tactics
still requires its own address and layout correction.
