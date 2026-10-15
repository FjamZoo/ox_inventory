import { isEqual } from 'lodash-es';
import type { Inventory, ItemData, Slot, SlotWithItem } from '../typings';

type Grid = { columns: number; cells: number };
type Size = { width: number; height: number };
type Definitions = Record<string, ItemData | undefined>;

export const getGrid = (inventory: Inventory): Grid => inventory.grid ?? { columns: 5, cells: inventory.slots };

export const getFootprint = (size: Size = { width: 1, height: 1 }, rotated = false): Size =>
  rotated ? { width: size.height, height: size.width } : size;

export const getOccupiedCells = (grid: Grid, slot: number, size?: Size, rotated = false): number[] | null => {
  const { width, height } = getFootprint(size, rotated);
  const column = (slot - 1) % grid.columns;
  if (!Number.isInteger(slot) || slot < 1 || column + width > grid.columns) return null;
  const cells: number[] = [];
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const cell = slot + y * grid.columns + x;
      if (cell > grid.cells) return null;
      cells.push(cell);
    }
  }
  return cells;
};

export const getCellOwner = (inventory: Inventory, cell: number, definitions: Definitions): Slot | undefined =>
  inventory.items.find(
    (item) =>
      item.name &&
      getOccupiedCells(getGrid(inventory), item.slot, definitions[item.name]?.size, item.rotated)?.includes(cell)
  );

export const canPlace = (
  grid: Grid,
  items: Slot[],
  item: Slot,
  toSlot: number,
  rotated: boolean,
  definitions: Definitions,
  ignoredAnchors: number[] = []
): boolean => {
  const cells = getOccupiedCells(grid, toSlot, item.name ? definitions[item.name]?.size : undefined, rotated);
  if (!cells) return false;
  const occupied = new Set(
    items.flatMap((other) =>
      other.name && !ignoredAnchors.includes(other.slot)
        ? (getOccupiedCells(grid, other.slot, definitions[other.name]?.size, other.rotated) ?? [])
        : []
    )
  );
  return cells.every((cell) => !occupied.has(cell));
};

export type Placement = {
  valid: boolean;
  anchor: number;
  cells: number[];
  kind: 'move' | 'stack' | 'swap' | 'rotate';
  pending?: boolean;
};

const catalogueDestination = (
  inventory: Inventory,
  source: Slot & Pick<SlotWithItem, 'ingredients' | 'price' | 'currency'>,
  sourceType: string,
  count: number
): Inventory => {
  const debits =
    sourceType === 'crafting'
      ? Object.entries(source.ingredients ?? {}).filter(([, amount]) => amount >= 1)
      : [[source.currency ?? 'money', (source.price ?? 0) * count] satisfies [string, number]];
  const items = inventory.items.map((item) => ({ ...item }));
  for (const [name, required] of debits) {
    let remaining = required;
    for (const item of items) {
      if (item.name !== name || !item.count || remaining <= 0) continue;
      const debit = Math.min(item.count, remaining);
      item.count -= debit;
      remaining -= debit;
      if (item.count === 0) item.name = undefined;
    }
  }
  return { ...inventory, items };
};

export const assessPlacement = ({
  sourceInventory,
  targetInventory,
  source,
  toSlot,
  count,
  rotated,
  definitions,
}: {
  sourceInventory: Inventory;
  targetInventory: Inventory;
  source: Slot & Pick<SlotWithItem, 'ingredients' | 'price' | 'currency'>;
  toSlot: number;
  count: number;
  rotated: boolean;
  definitions: Definitions;
}): Placement => {
  const sameInventory =
    sourceInventory === targetInventory ||
    (sourceInventory.id === targetInventory.id && sourceInventory.type === targetInventory.type);
  const catalogue = sourceInventory.type === 'shop' || sourceInventory.type === 'crafting';
  const destination = catalogue
    ? catalogueDestination(targetInventory, source, sourceInventory.type, count)
    : targetInventory;
  const owner = getCellOwner(destination, toSlot, definitions);
  const ownCell = sameInventory && owner?.slot === source.slot;
  const anchor = owner && !ownCell ? owner.slot : toSlot;
  const target = owner && !ownCell ? owner : undefined;
  const grid = getGrid(targetInventory);
  const size = getFootprint(source.name ? definitions[source.name]?.size : undefined, rotated);
  const cells = getOccupiedCells(grid, anchor, source.name ? definitions[source.name]?.size : undefined, rotated) ?? [];
  const clippedCells = Array.from({ length: size.height }, (_, y) =>
    Array.from(
      { length: Math.min(size.width, grid.columns - ((anchor - 1) % grid.columns)) },
      (_, x) => anchor + y * grid.columns + x
    )
  )
    .flat()
    .filter((cell) => cell <= grid.cells);
  const result: Placement = { valid: false, anchor, cells: cells.length ? cells : clippedCells, kind: 'move' };
  if (
    !source.name ||
    count < 1 ||
    (!catalogue && count > (source.count ?? 0)) ||
    ['shop', 'crafting', 'inspect'].includes(targetInventory.type)
  )
    return result;
  const fullMove = !catalogue && count === source.count;
  const ignored = sameInventory && fullMove ? [source.slot] : [];

  if (sameInventory && anchor === source.slot) {
    return {
      ...result,
      kind: 'rotate',
      valid:
        fullMove &&
        rotated !== !!source.rotated &&
        canPlace(grid, targetInventory.items, source, anchor, rotated, definitions, ignored),
    };
  }
  if (
    target &&
    definitions[source.name]?.stack &&
    source.name === target.name &&
    isEqual(source.metadata, target.metadata)
  ) {
    return {
      ...result,
      kind: 'stack',
      valid: true,
      cells: getOccupiedCells(grid, target.slot, definitions[source.name]?.size, target.rotated) ?? [target.slot],
    };
  }
  if (!target) {
    const fits = canPlace(grid, destination.items, source, anchor, rotated, definitions, ignored);
    return catalogue && !fits && cells.length ? { ...result, valid: true, pending: true } : { ...result, valid: fits };
  }
  if (catalogue)
    return {
      ...result,
      anchor: toSlot,
      cells:
        getOccupiedCells(grid, toSlot, source.name ? definitions[source.name]?.size : undefined, rotated) ??
        clippedCells,
      valid: getOccupiedCells(grid, toSlot, source.name ? definitions[source.name]?.size : undefined, rotated) !== null,
      pending: true,
    };
  result.kind = 'swap';
  if (!fullMove || catalogue) return result;
  const targetIgnored = sameInventory ? [source.slot, target.slot] : [target.slot];
  const sourceIgnored = sameInventory ? targetIgnored : [source.slot];
  const targetCells = getOccupiedCells(
    getGrid(sourceInventory),
    source.slot,
    target.name ? definitions[target.name]?.size : undefined,
    target.rotated
  );
  result.valid =
    canPlace(grid, targetInventory.items, source, anchor, rotated, definitions, targetIgnored) &&
    canPlace(
      getGrid(sourceInventory),
      sourceInventory.items,
      target,
      source.slot,
      !!target.rotated,
      definitions,
      sourceIgnored
    ) &&
    (!sameInventory || (!!targetCells && cells.every((cell) => !targetCells.includes(cell))));
  return result;
};

export const findPlacement = (
  inventory: Inventory,
  item: Slot,
  definitions: Definitions,
  rotated = false
): number | undefined => {
  if (item.name && definitions[item.name]?.stack) {
    const stack = inventory.items.find((other) => other.name === item.name && isEqual(other.metadata, item.metadata));
    if (stack) return stack.slot;
  }
  const grid = getGrid(inventory);
  for (let slot = 1; slot <= grid.cells; slot++) {
    if (canPlace(grid, inventory.items, item, slot, rotated, definitions)) return slot;
  }
};

export const packCatalogue = (inventory: Inventory, definitions: Definitions) => {
  const columns = 5;
  const occupied = new Set<number>();
  const entries: Array<{ item: Slot; anchor: number; width: number; height: number }> = [];
  let lastCell = 0;
  for (const item of inventory.items) {
    if (!item.name) continue;
    const original = getFootprint(definitions[item.name]?.size, item.rotated);
    const rotated = original.width > columns && original.height <= columns ? !item.rotated : !!item.rotated;
    const size = getFootprint(definitions[item.name]?.size, rotated);
    const displaySize = { width: Math.min(size.width, columns), height: size.height };
    let anchor = 1;
    while (true) {
      const cells = getOccupiedCells({ columns, cells: Number.MAX_SAFE_INTEGER }, anchor, displaySize);
      if (cells && cells.every((cell) => !occupied.has(cell))) {
        cells.forEach((cell) => occupied.add(cell));
        lastCell = Math.max(lastCell, ...cells);
        entries.push({ item, anchor, ...displaySize });
        break;
      }
      anchor++;
    }
  }
  return { entries, cells: Math.ceil(lastCell / columns) * columns, columns };
};
