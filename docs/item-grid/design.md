# Item grid implementation contract

## Usage and data

Item definitions accept `size = { width = 4, height = 2 }`. Omitted size is 1x1. Positive integral dimensions are validated at definition boundaries. Do not reject widths above five merely because they may require rotation. Container `metadata.size` retains its existing meaning.

`inv.items[slot]` stays the sole active item source. The numeric slot is the rectangle's top-left cell. Runtime and saved slot records gain optional `rotated = true`; false is the default. Item sizes never enter stack metadata. Occupied cells are derived and are never duplicate item records.

Physical inventories have `grid = { columns = 5, cells = inv.slots }`. The partial last row exposes only the configured cells. Keep normal player/stash/vehicle/drop/container capacities unchanged. Hotkeys still refer to anchors 1 through 5. Shops and crafting are catalogues. Preserve offer/recipe indices while displaying all offers in a read-only packed grid with enough rows.

Automatic allocation uses compatible stacks, then unrotated first fit. Existing scalar GetSlotForItem callers receive an anchor that fits without another orientation result. Explicit destination requests are strict. Invalid, occupied, out-of-bounds or covered destinations fail instead of silently redirecting. Full moves preserve orientation when omitted. Splits keep the source footprint. Stacking keeps target orientation. Same-anchor rotation is a real operation. Swaps validate both final rectangles after releasing both original footprints; partial incompatible swaps fail.

## Authoritative ownership

The inventory owner exposes two internal operations, `Assess(commands)` and `Apply(plan)`. These are not external exports. Assess builds private candidate state and derives geometry and final weight. Apply checks revisions and publishes all participants without yielding, then sends notifications and framework updates. Keeping the proposal between these calls lets hooks run before publication without rebuilding output metadata. No hooks, events, framework calls or notifications run inside the assignment phase.

Changes cover add, remove, transfer, exchange, durability, resize, recovery and replacement. Exchange represents expected ingredient/currency debits, prepared output credits, durability changes and optional stock. Validate the final state, including space freed by consumed currency or ingredients. All-or-nothing non-stack additions and economic exchanges are required. Keep existing permissions, distance, container restrictions, item policy and hooks. Raw exported SwapSlots must own fit and weight checks. Remove duplicate caller weight accounting.

Generate output metadata once. Hooks run outside publication. Capture inventory revisions and participant identity, then reject a stale outer proposal if hooks mutate a participant. Never overwrite an independent hook mutation with rollback. Supported writers must participate in revision tracking. Arbitrary writes through live tables returned to trusted server resources remain unsupported and cannot be intercepted.

Crafting preflights without consumption, awaits progress, then revalidates access, recipe and current ingredients and builds a new complete exchange. The final craft hook runs immediately before guarded commit. No long-held inventory locks or partial refunds. This changes the craft veto hook to completion time and must be documented.

Preserve existing export names and argument order. AddItem now enforces weight itself. CanCarryItem, CanCarryAmount, CanSwapItem, GetSlotForItem and GetEmptySlot must reflect geometry. GetEmptySlot remains a free 1x1-cell query, so internal large-item callers must use item-aware planning.

## Recovery and persistence

Inventories gain `recovery = { { id = '...', reason = '...', record = originalRecord }, ... }`. Reasons distinguish unknown_item, invalid_record and no_space. Recovery records are not active items and do not appear in ordinary Search, use, sell, give or crafting. Known recovery weight counts toward inventory weight. Unresolved unknown weight prevents acquisition but allows withdrawals and safe reorganization. Reclaim does not charge owned weight twice.

Keep the JSON array. Active entries retain name/count/slot/metadata plus optional rotated. Recovery serializes as `{ _gridRecovery = { id, reason, record } }`. Preserve complete decoded records, including unknown fields. Malformed JSON must fail closed without an empty save. No SQL schema change. Downgrading after tagged recovery records exist requires restoring backup or an explicit reverse migration.

Reconcile in two passes. First reserve valid saved anchors in slot/input order. Then first-fit displaced records in their saved orientation, trying rotation if needed. Residual, unknown and malformed records enter recovery with stable IDs. Existing recovery envelopes remain there until explicit reclaim. Every player/stash/vehicle/create/resize/return path uses this policy before exposing items. All serializers, confiscation, return and death drops preserve recovery. Never delete the durable confiscated source before restored ownership is durably recorded.

Wire contract for reclaim is the new NUI callback `recoverItem` forwarding to `ox_inventory:recoverItem`. Payload is `{ fromType, recoveryId, toSlot?, rotated? }`. The server resolves only the requesting player's own or currently open inventory using fromType, applies normal access restrictions, and reclaims within that same inventory. Omitted toSlot uses first fit. Return success and sync authoritative inventory data. Unknown or malformed entries remain visible until their definitions/data are resolved. Recovery UI may provide a reclaim button using first fit; it cannot accept ordinary dropped items.

## Client and NUI

The Lua bridge sends item size in both init and getItemData and grid/recovery in every setup route. Existing move/buy/craft payloads gain `rotated?: boolean`. Do not rename existing slot/count/type fields.

Render a continuous grid. Derive covered cells, item rectangles and placement previews from anchors. Remove 30-cell slicing that cuts rectangles. During dragging R toggles only the drag orientation. Preview target footprint is colored for valid/invalid placement and shows the resolved anchor. Handle own released cells, partial splits, stacks and swaps. Keep hotbar behavior.

Prefer authoritative state while an operation is pending over fragile optimism. If optimism is retained, keep it separate from the current authoritative state so rejection cannot restore stale history over a newer refresh. No stable item IDs or replay protocol is required. Browser fixtures must return explicit acceptance or rejection.

## Design decision

The architect arena compared anchor-keyed state (A), stable item IDs with numeric projections (B), and anchor-keyed full projections (C). The independent judge scored A 28/30, B 22/30 and C 22/30. A is the base. Graft explicit reclaim from C and malformed-JSON fail-closed behavior from B. Reject ID translation, usable overflow slots, weightless recovery, request replay machinery and permanent occupancy maps.

Model the Domain kept one anchor map and a geometry owner. Foundational Thinking put the contract and executable baseline before integration. Boundary Discipline puts malformed client input checks at callbacks and exact fit checks in the planner. Prove It Works and Test Behavior, Not Implementation require real exported functions and registered callbacks in native CfxLua tests. Build the Lever supplies the reproducible runtime and fixtures. Separate Before Serializing Shared State assigns all authoritative Lua paths to one writer. Never Block on the Human selects the defaults here under the user's full-autonomy grant.
