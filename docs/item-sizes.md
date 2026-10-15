# Item sizes and grids

Items without a `size` still occupy one cell. Existing slot counts and weight limits need no configuration changes. This update does not assign larger sizes to existing item definitions automatically.

Add a size to an item in `data/items.lua`, or to a weapon entry under `Weapons` in `data/weapons.lua`.

```lua
size = { width = 4, height = 2 },
```

A rifle can use 4x2, a pistol 2x1, and a phone 1x1. Width and height must be positive integers. Size belongs to the definition. Container `metadata.size` continues to describe the container's capacity.

Each physical inventory has five columns and exactly its configured number of cells. A 30-slot inventory is 5x6. A 12-slot inventory has two complete rows and two usable cells in the third row. Player inventories, stashes, trunks, gloveboxes, drops and item containers use this rule. Shops and crafting benches display catalogues that grow to show every offer while preserving their offer indices.

Drag an item to a cell to see its landing footprint. Press **R** during the drag to rotate it 90 degrees. The server validates the requested position. An item cannot cross the right edge, enter the unused part of the final row, overlap another item or exceed the destination's weight limit. A stack occupies one rectangle regardless of its count. Separate non-stack items each need their own rectangle.

Green previews fit the visible layout. Red previews fail geometry checks. Amber purchase or crafting previews need the server to resolve the final layout after payment, ingredient consumption and generated metadata. Weight and permissions are always checked by the server. Items stay in their current location until an authoritative update arrives.

Numeric slots still identify the top-left cell of an item. Hotkeys address anchors 1 through 5. Covered cells do not contain extra item records or hotbar entries. Rotation is stored on the slot record and survives saving. It is separate from stack metadata.

## Resource exports

Existing export names and argument order remain. Automatic additions first look for a compatible stack, then use the first fitting unrotated position. They do not rearrange existing items. A supplied destination slot is exact. An invalid requested position fails instead of being redirected.

`AddItem` checks both space and weight. A non-stack batch either fits completely or adds nothing. Callers must handle its failure result. `CanCarryItem` is an advisory check against the current inventory and supplied metadata. It does not reserve space or run item-creation hooks. A later `AddItem` can fail if inventory state or generated metadata changes.

`GetEmptySlot` returns a free 1x1 cell. Use `GetSlotForItem` or `CanCarryItem` when asking about a larger item. Moves, swaps, gives, drops, purchases, crafting outputs and durability splits also require a valid final placement. Purchases and crafting must not consume money, stock or ingredients when their final inventory cannot be committed.

The `craftItem` veto hook now runs after progress completes, immediately before the final validated exchange. Recipes, access and ingredients are checked again after progress. A hook that independently changes an inventory keeps its change, while the stale outer operation fails. Hooks must not rely on a failed outer operation undoing their own writes.

Tables returned by trusted server exports remain live for compatibility. Resources must use supported mutation exports. Arbitrary writes to those tables bypass inventory ownership and cannot be protected from another server resource's Lua code.

## Existing saves and recovery

No SQL schema change is needed. The saved JSON array keeps its existing item records and adds optional rotation. With all definitions left at 1x1, valid existing placements stay in their old slots.

When sizes or capacities change, loading first preserves valid saved anchors. It then places displaced records in the first available position, trying their saved orientation before rotation. Items that still cannot fit are retained in a visible recovery tray. Unknown item definitions and malformed item records are also retained with their original decoded data. Duplicate saved slots cannot overwrite another record.

Recovery is for possessions already present in saved data or displaced by a capacity change. A failed new grant does not create recovery storage. Recovery records cannot be used, given, sold, stacked or consumed in crafting. Reclaim places a known valid record back into the same inventory when it fits. Existing recovery records stay in the tray across reloads until explicitly reclaimed.

Automatic reclaim tries the saved orientation and then rotation. Saved records containing multiple copies of a non-stack item are retained as invalid records in recovery instead of treating several items as one rectangle. Their known weight still counts. Correct those records before reclaiming them.

Known recovery records still count toward weight. Records whose weight cannot be determined block incoming additions until their definitions or data are resolved. Existing active items can still be withdrawn. Restoring a missing definition allows its valid recovery record to be reclaimed. Invalid JSON prevents loading and saving that inventory, so its stored payload is not replaced with an empty inventory.

Recovery persists through ordinary saves and confiscation/return. Its tagged records extend the save format. **Back up inventory data before enabling larger sizes.** Older resource versions cannot read the recovery tags. Downgrading after recovery has been saved requires restoring the backup or explicitly migrating those records back.

ESX's ordinary item serializer does not retain the new fields. For ESX, the existing `ox_inventory` table holds an authoritative player row with name `__ox_inventory_player_grid` and the player's identifier as owner. The resource prefers that row on load and writes it together with the `users.inventory` mirror in a transaction. Empty inventories are saved explicitly. The first import is persisted before the inventory is exposed. Later saves use the normal inventory save and disconnect cadence. The reserved row is excluded from automatic old-stash cleanup. No new table, column or configuration is required. Administrators restoring or migrating ESX players must include this row.

Confiscation and return update durable player ownership and confiscated storage together. Disconnect removal waits for that operation to finish. This protects retries and interrupted ownership transfers; it does not make every ordinary move durable immediately before an unexpected server process crash.

Repeated confiscation keeps earlier confiscated possessions and adds any newly confiscated items. Repeating it with an empty player inventory does not erase the saved source.

## Verification

The native test harness executes the resource's real Lua exports and registered callbacks under CfxLua with explicit FiveM, item-policy and database stubs. See [the test instructions](../tests/README.md) and [verification record](item-grid/verification.md) for commands, evidence and limits. These tests do not establish live FiveM networking, framework database behavior or in-game pointer interaction.
