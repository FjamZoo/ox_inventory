# Review record

The review scope includes the full change from `488aa6d7`, the native harness, the client transport and the NUI. Reviewers inspect the real implementation independently. Findings below are triaged by the coordinating agent.

| Finding | Decision | Evidence |
| --- | --- | --- |
| Confiscation return can duplicate records after a failed durable save and retry | Fix with a database transaction before publishing restored ownership | `tests/server/grid-recovery.lua` |
| ESX serializes active items without rotation or recovery | Store an authoritative player row in the existing inventory table and mirror ESX atomically | `modules/mysql/server.lua` |
| An empty authoritative ESX row must not become SQL NULL | Persist an explicit empty JSON array so stale framework data cannot be reimported | Native ESX persistence regression |
| Disconnect during a storage transaction skips removal | Defer removal until the storage operation releases ownership | Native recovery lifecycle regression |
| Death drop can copy items when clearing the busy source fails | Guard the ownership transfer and reject the busy source | Panel A reproduction |
| Normal reload passes false as the slot sentinel | Preserve the sentinel and grant ped ammunition only after server acceptance | Panel A reproduction |
| Item status effects can happen before rejected consumption | Apply effects after server acceptance and revalidate the exact used record | Panel A reproduction |
| Default Give passes a zero count | Preserve the existing one-item default while rejecting malformed counts | Panel A reproduction |
| Unknown recovery blocked a withdrawal into a compatible stack | Mark the source as acquiring only for an actual exchange | Native recovery withdrawal regression |
| Framework synchronization can throw after disconnect and leave storage locked | Guard absent framework players and release storage regardless of notification outcome | Panel B reproduction with the real ND bridge |
| Equipped weapon is disarmed before its returned slot remap arrives | Publish the equipped anchor with authoritative owner updates before processing removals | Panel B client/server ordering reproduction |
| Repeated confiscation overwrites the earlier confiscated possessions | Preserve prior confiscated ownership and merge new possessions transactionally | Panel C native reproduction |
| Caller-supplied item tables can claim a canonical non-stack item is stackable | Resolve definitions by canonical name and keep invalid saved multiplicity out of active slots | Panel C native reproduction |
| Merging valid recovery arrays can collide on generated IDs | Assign a fresh ID while preserving the record, reason, weight and reclaimability | Confiscation, return and reclaim regression |
| Untouched migrated stashes do not save recovery tags | Mark reconciliation migrations for normal durable saving | Panel C load/unload/reload reproduction |
| Durability refresh replaces slot objects while lookup exports return the old objects | Read the authoritative slot after the update | Panel C real-item-module reproduction |
| Three comments narrate internal operations | Delete them; no code redesign was required | Fresh comment review |

Browser evidence uses explicit fixtures. Native evidence runs actual registered exports and callbacks with the runtime boundaries described in [tests/README.md](../../tests/README.md). Neither establishes live FiveM or SQL behavior.

The independent code panel used gpt-6-astra, gpt-6.1-sol and gpt-6-sol. All findings above had a concrete path or reproduction and were accepted. No style-only redesign was required. The existing absence of ordinary swap-distance revalidation was investigated and not attributed to this feature.

A separate gpt-6-astra trail audit corrected a historical test count and browser chronology, added omitted decision checkpoints, and kept new LuaLS warnings explicit. The historical baseline is ten compatibility tests, not the later expanded thirteen-test suite.

After the fixes, a fresh gpt-6-astra verifier found no remaining issue in the targeted paths. It independently passed all 191 native checks and five additional read-only failure/lookup scenarios. The coordinating agent also reran the native suite, all 61 Lua parse checks, NUI tests, TypeScript, production build and LuaLS. The limitations in the verification record still apply.
