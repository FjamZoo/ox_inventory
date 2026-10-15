# Item sizes and inventory grids

Item definitions in `data/items.lua` and `data/weapons.lua` accept an optional size:

```lua
-- Add these fields to your existing definitions; no changes are required by default.
size = { width = 4, height = 2 } -- rifle
size = { width = 2, height = 1 } -- pistol
size = { width = 1, height = 1 } -- phone, and the default for every existing item
```

`size = { 4, 2 }` is also accepted. Dimensions must be positive, finite integers.
Missing dimensions default to 1; invalid dimension pairs fall back to 1×1. This change does not assign larger
sizes to any stock item automatically. `metadata.size` remains the existing
container capacity setting; it does **not** control an item's footprint.

## Capacity and positions

- Player inventories, stashes, trunks, gloveboxes, containers, evidence lockers,
  dumpsters, and drops use five columns, or fewer when their capacity is below five.
- Existing `slots` settings remain the **exact number of usable cells**. For
  example, 50 slots means 5×10; 12 slots means two full rows and two cells in the
  third row. There is no free capacity from rounding up a partial row.
- Slot IDs remain one-based, row-major numbers. An item's slot is its **top-left
  anchor**. Covered cells are not extra item records. Existing exports, metadata,
  item references and hotkeys continue to use the anchor. Hotkeys 1–5 therefore
  select items anchored in the first five cells, not items merely covering them.
- Rotation is a separate boolean `rotated` on the inventory entry, persisted with
  the anchor. It is not metadata and does not prevent otherwise identical stacks
  from combining. A stack uses one rectangle regardless of count, and retains the
  destination stack's orientation. Non-stackable copies require separate rectangles.
- Shops and crafting benches remain catalogs: their slot IDs identify products or
  recipes. The UI packs their sized cards into five-column rows without changing
  those IDs or multiplying the footprint by stock quantity. Cards wider than five
  cells are visually constrained to five columns and still display their actual
  dimensions. Purchases and crafting outputs must fit in the receiving inventory.
- Dragging uses the cell under the pointer as the top-left destination. Hovering
  another item's rectangle targets its anchor for a stack or swap. Green/red
  previews indicate geometric validity; the server also checks weight and all
  existing access, item, container, stock, currency and hook rules. Press **R** while
  dragging to rotate, including a rotation in place. Shift splits still apply.

## Existing saves and recovery

No SQL schema migration is required. The optional `rotated` field is stored in the
existing JSON item records; missing values mean unrotated. Item sizes always come
from current server definitions, not saved/client-provided size fields.

On load (including returned confiscated inventories), the server:

1. Processes saved entries in ascending slot order and keeps positions that fit.
2. Repositions conflicting or out-of-bounds entries using the first available
   rectangle in their saved orientation, then tries the opposite orientation.
3. Places anything still unable to fit in **recovery**, using anchor IDs greater
   than the configured slot count. This also covers items too wide/tall for the grid.

Recovery is a separate, visible section rather than additional usable grid cells.
Names, counts and metadata are retained; nothing is discarded to make the layout
fit. Recovery items still contribute their full weight. Players can use/remove,
give, drop, or move them to a valid normal-grid destination. They cannot place,
rotate, swap incoming items, or add to a stack in recovery. Free normal-grid space
or transfer items elsewhere to recover them. If an item cannot fit *any* configured
inventory, an administrator must adjust its definition or a destination's capacity.

Recovery entries are saved normally and reconsidered on the next load. The packing
algorithm is deterministic first-fit, preserving valid anchors; it is not a global
packing optimizer. Manual rearrangement can free space that first-fit cannot find.
Ordinary decay and removal behavior still applies. Changing sizes can move anchors,
so external resources must not treat a saved slot number as a permanent item ID.

Fresh explicit `CustomDrop`/`CreateTemporaryStash` contents that exceed cell or weight
capacity fail as a whole with `nil, 'inventory_full'`. Existing saves and built-in
random loot use recovery to preserve their contents. `CreateDropFromPlayer` preserves
the player's full layout, capacity and recovery entries.

## Exports and transactions

Existing call signatures continue to work with 1×1 items. Grid-related behavior:

| API | Behavior |
| --- | --- |
| `AddItem(inv, item, count, metadata, slot, cb, rotated)` | Plans the entire addition before changing items. An explicit anchor must fit; it does not silently redirect to another slot. Without an explicit orientation it tries unrotated, then rotated. Optional seventh argument fixes orientation. Failure returns `false, 'inventory_full'` or `false, 'cannot_carry'`; multi-copy additions are not partial. |
| `CanCarryItem` | Checks weight and the actual rectangles needed for the requested count/metadata, including separate non-stackable copies. |
| `CanCarryAmount` | Limits non-stackable quantities by available rectangles as well as weight. For weightless stackable items with a destination, returns the finite sentinel `2147483647`. |
| `CanCarryWeight` | Remains a weight-only query; it cannot determine geometry without an item. |
| `CanSwapItem` | Simulates removing the requested quantity, then checks the incoming quantity's weight and layout. |
| `GetEmptySlot(inv, item?)` | Returns a free 1×1 cell by default. An optional item definition/name searches for that item's rectangle. Returns `slot, rotated`. |
| `GetSlotForItem` | Finds a compatible normal-grid stack or a fitting rectangle; returns `slot, rotated`. Pass the orientation through when an exact one is required. |
| `GetItemSlots` | Its third return value counts unoccupied grid cells, not empty anchor records. |
| `SetSlot` / `SwapSlots` | Validate rectangles and weights before mutation. `SwapSlots` checks both destinations and updates both inventory weights. |
| `SetSlotCount` / `SetInventory(..., 'slots', ...)` | Reject a live capacity/column change that would strand an item or turn an existing recovery anchor into a grid cell. Remove/recover items first. Config changes on restart instead use migration. |

Capacity queries do not invoke `createItem` hooks or generate random/unique metadata.
They estimate using the supplied metadata and current definitions; `AddItem` performs
the final authoritative check after generating metadata. It can fail after an earlier
successful query if metadata or inventory state changes. Callers must check its result.

Moves, swaps, splits, stacking, giving, drops and purchases validate on the server.
Grid operations lock shared inventories and recheck after hooks. Crafting simulates
ingredient removal, retained tools, durability splits and output placement before
committing; a failed output placement consumes neither ingredients nor durability.
Weight checks remain independent of geometry. Existing overweight saves can be
rearranged or emptied, but additional weight cannot be inserted.

`AddItem` now enforces weight itself, and explicit invalid slots fail rather than
falling back. Resources that previously used these behaviors to bypass capacity
must handle failure. Resources should use exports instead of directly modifying
the mutable `inventory.items` table; direct table writes bypass validation.

## Verification

From the repository root:

```sh
python tests/run.py           # Python 3.8+, Lua 5.4 and luac on PATH
cd web
bun install --frozen-lockfile
bun test
bun run build
```

The server harness runs the actual inventory, shop and crafting modules with mocked
FiveM/ox_lib/database/metadata services. A narrow adapter translates Cfx-only syntax
for stock Lua 5.4 and syntax-checks the touched server/client entry points. Tests
cover placement, malformed requests, swaps, splits, rotation, recovery, persistence
records, capacity exports, giving, generated drops, purchase failure/stock/currency,
craft transactions, hooks changing state, and 1,000 seeded random operations.
UI tests cover geometry, reducer behavior, recovery retention and rendered markup.

The production UI builds locally; generated `web/build` remains ignored as in this
repository. Build it when deploying source.

**Still unverified:** actual FiveM/Cfx execution, mouse/touch drag behavior and R-key
handling in NUI, visual layout at game resolutions, real database round trips,
framework bridges, and simultaneous real-player/network interactions. No browser
connection or running game server was available for this implementation run. Before
deployment, check these in a staging server with existing saves, occupied containers,
weapons, concurrent stash users, shop stock/currency, and canceled/completed crafts.
