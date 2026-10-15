import { describe, expect, test } from 'bun:test';
import { cells, fits, canPlace, occupant } from '../src/helpers/grid';
import type { Inventory, Slot } from '../src/typings';

const item = (slot: number, width = 1, height = 1, count = 1): Slot => ({
  slot,
  name: 'test',
  size: { width, height },
  count,
  weight: count,
});
const inventory = (slots: number, items: Slot[] = [], id = 'test'): Inventory => ({
  id,
  type: 'player',
  slots,
  items: Array.from(
    { length: slots },
    (_, index) => items.find((item) => item.slot === index + 1) || { slot: index + 1 }
  ),
});

describe('grid geometry used by drag previews', () => {
  test('legacy items use one cell', () => {
    expect(cells(inventory(10), { slot: 1 }, 1)).toEqual([1]);
  });
  test('rectangles and rotation use the same cells as the server', () => {
    expect(cells(inventory(20), item(1, 4, 2), 1)).toEqual([1, 2, 3, 4, 6, 7, 8, 9]);
    expect(cells(inventory(20), item(1, 4, 2), 1, true)).toEqual([1, 2, 6, 7, 11, 12, 16, 17]);
  });
  test('right edge, bottom edge and partial last row are blocked', () => {
    expect(cells(inventory(12), item(5, 2), 5)).toBeNull();
    expect(cells(inventory(12), item(7, 2, 2), 7)).toBeNull();
    expect(cells(inventory(12), item(11, 2), 11)).toEqual([11, 12]);
    expect(cells(inventory(1), item(1, 2), 1)).toBeNull();
  });
  test('occupied non-anchor cells resolve to the owning item', () => {
    const rifle = item(1, 4, 2);
    const inv = inventory(20, [rifle]);
    expect(occupant(inv, 9)).toEqual(rifle);
    expect(fits(inv, item(7), 7)).toBe(false);
    expect(fits(inv, item(10), 10)).toBe(true);
  });
  test('full moves can overlap the source but splits cannot', () => {
    const box = item(1, 2, 2, 4),
      inv = inventory(20, [box]);
    expect(canPlace(inv, inv, box, 2, 4, false, false)).toBe(true);
    expect(canPlace(inv, inv, box, 2, 2, false, false)).toBe(false);
    expect(canPlace(inv, inv, box, 11, 2, false, false)).toBe(true);
  });
  test('in-place rotation checks new cells', () => {
    const pistol = item(1, 2);
    const empty = inventory(10, [pistol]);
    const blocked = inventory(10, [pistol, item(6)]);
    expect(canPlace(empty, empty, pistol, 1, 1, true, false)).toBe(true);
    expect(canPlace(blocked, blocked, pistol, 1, 1, true, false)).toBe(false);
  });
  test('both sides of a swap must fit without intersecting', () => {
    const phone = item(1),
      pistol = item(2, 2),
      inv = inventory(10, [phone, pistol]);
    expect(canPlace(inv, inv, phone, 2, 1, false, false)).toBe(false);
    const a = inventory(20, [item(1, 4, 2)], 'a'),
      b = inventory(20, [pistol, item(8)], 'b');
    expect(canPlace(a, b, a.items[0], 2, 1, false, false)).toBe(false);
  });
  test('recovery cannot receive items or stacks', () => {
    const inv = inventory(10);
    inv.items[10] = item(11, 4, 2);
    expect(fits(inv, item(11), 11)).toBe(false);
    expect(canPlace(inv, inv, item(1), 11, 1, false, true)).toBe(false);
    expect(canPlace(inv, inv, inv.items[10], 1, 1, false, false)).toBe(true);
  });
  test('catalog purchases cannot swap with an existing item', () => {
    const source = inventory(1, [item(1)], 'shop');
    source.type = 'shop';
    const destination = inventory(10, [item(1)], 'player');
    expect(canPlace(source, destination, source.items[0], 1, 1, false, false)).toBe(false);
    expect(canPlace(source, destination, source.items[0], 1, 1, false, true)).toBe(true);
  });
});
