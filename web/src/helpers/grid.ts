import type { Inventory, Slot } from '../typings';

export const dimensions = (item: Slot, rotated = item.rotated) => {
  const { width = 1, height = 1 } = item.size || {};
  return rotated ? { width: height, height: width } : { width, height };
};
export const columns = (inventory: Inventory) => Math.min(5, inventory.slots);

export const cells = (inventory: Inventory, item: Slot, anchor: number, rotated = item.rotated): number[] | null => {
  const cols = columns(inventory);
  const { width, height } = dimensions(item, rotated);
  if (
    !Number.isInteger(anchor) ||
    anchor < 1 ||
    anchor > inventory.slots ||
    ((anchor - 1) % cols) + width > cols ||
    anchor + (height - 1) * cols + width - 1 > inventory.slots
  )
    return null;
  return Array.from({ length: width * height }, (_, i) => anchor + Math.floor(i / width) * cols + (i % width));
};

export const fits = (
  inventory: Inventory,
  item: Slot,
  anchor: number,
  rotated = item.rotated,
  ignore: number[] = []
) => {
  const rectangle = cells(inventory, item, anchor, rotated);
  if (!rectangle) return false;
  const occupied = new Set(
    inventory.items
      .filter((other) => other?.name && !ignore.includes(other.slot))
      .flatMap((other) => cells(inventory, other, other.slot) || [])
  );
  return rectangle.every((cell) => !occupied.has(cell));
};

export const occupant = (inventory: Inventory, cell: number) =>
  inventory.items.find((item) => item?.name && cells(inventory, item, item.slot)?.includes(cell));

export const canPlace = (
  from: Inventory,
  to: Inventory,
  item: Slot,
  anchor: number,
  count: number,
  rotated: boolean,
  stack: boolean
) => {
  const target = to.items[anchor - 1];
  const same = from.id === to.id && from.type === to.type;
  if (same && item.slot === anchor) return count === item.count && fits(to, item, anchor, rotated, [item.slot]);
  if (stack && target?.name) return fits(to, target, anchor, target.rotated, [anchor]);
  const ignore = target?.name ? [anchor] : [];
  if (same && (count === item.count || target?.name)) ignore.push(item.slot);
  if (!fits(to, item, anchor, rotated, ignore)) return false;
  if (target?.name) {
    if (count !== item.count || from.type === 'shop' || from.type === 'crafting') return false;
    if (!fits(from, target, item.slot, target.rotated, same ? [item.slot, anchor] : [item.slot])) return false;
    if (same) {
      const destination = new Set(cells(to, item, anchor, rotated));
      if (cells(from, target, item.slot)?.some((cell) => destination.has(cell))) return false;
    }
  }
  return true;
};
