import { describe, expect, test } from 'bun:test';
import { assessPlacement, canPlace, findPlacement, getOccupiedCells, packCatalogue } from '../src/helpers/grid';
import vectors from '../../tests/fixtures/grid.json';
import type { Inventory, ItemData, Slot } from '../src/typings';

const definition = (name: string, size = { width: 1, height: 1 }, stack = false): ItemData => ({
  name,
  label: name,
  size,
  stack,
  usable: false,
  close: false,
  count: 0,
});

const definitions = {
  rifle: definition('rifle', { width: 4, height: 2 }, true),
  pistol: definition('pistol', { width: 2, height: 1 }),
  phone: definition('phone'),
};

const inventory = (id: string, items: Slot[], slots = 30): Inventory => ({
  id,
  type: id === 'left' ? 'player' : 'stash',
  slots,
  grid: { columns: 5, cells: slots },
  items,
});

const rifle = { slot: 1, name: 'rifle', count: 4, weight: 100, metadata: {} };

const place = (items: Slot[], toSlot: number, rotated = false, count = 4) => {
  const inv = inventory('left', items);

  return assessPlacement({
    sourceInventory: inv,
    targetInventory: inv,
    source: rifle,
    toSlot,
    rotated,
    count,
    definitions,
  });
};

describe('shared server and NUI geometry', () => {
  for (const vector of vectors.occupancy) {
    test(vector.name, () => {
      expect(getOccupiedCells(vector.grid, vector.slot, vector.size, vector.rotated)).toEqual(vector.cells);
    });
  }

  for (const vector of vectors.placement) {
    test(vector.name, () => {
      expect(
        canPlace(
          vector.grid,
          vector.items,
          { slot: 1, name: vector.item },
          vector.toSlot,
          vector.rotated ?? false,
          definitions,
          vector.ignoreAnchors
        )
      ).toBe(vector.fits);
    });
  }
});

test('same anchor rotation is a full move', () => {
  expect(place([rifle], 1, true)).toEqual({
    valid: true,
    anchor: 1,
    kind: 'rotate',
    cells: [1, 2, 6, 7, 11, 12, 16, 17],
  });
  expect(place([rifle], 1, true, 2)).toEqual({
    valid: false,
    anchor: 1,
    kind: 'rotate',
    cells: [1, 2, 6, 7, 11, 12, 16, 17],
  });
});

test('released source cells fit a full move but remain occupied for a split', () => {
  expect(place([rifle], 2)).toEqual({ valid: true, anchor: 2, kind: 'move', cells: [2, 3, 4, 5, 7, 8, 9, 10] });
  expect(place([rifle], 2, false, 2)).toEqual({
    valid: false,
    anchor: 2,
    kind: 'move',
    cells: [2, 3, 4, 5, 7, 8, 9, 10],
  });
});

test('covered stack targets resolve anchor and preserve target orientation', () => {
  expect(place([rifle, { ...rifle, slot: 14, rotated: true }], 19)).toEqual({
    valid: true,
    anchor: 14,
    kind: 'stack',
    cells: [14, 15, 19, 20, 24, 25, 29, 30],
  });
});

test('swap checks both rectangles and rejects partial incompatible swaps', () => {
  const pistol = { slot: 11, name: 'pistol', count: 1, weight: 100 };

  expect(place([rifle, pistol], 12)).toEqual({
    valid: true,
    anchor: 11,
    kind: 'swap',
    cells: [11, 12, 13, 14, 16, 17, 18, 19],
  });
  expect(place([rifle, pistol], 12, false, 2)).toEqual({
    valid: false,
    anchor: 11,
    kind: 'swap',
    cells: [11, 12, 13, 14, 16, 17, 18, 19],
  });
  expect(place([rifle, { slot: 5, name: 'phone', count: 1 }], 5)).toEqual({
    valid: false,
    anchor: 5,
    kind: 'swap',
    cells: [5, 10],
  });
});

test('cross inventory swap rejects a target that cannot fit source inventory', () => {
  const source = { slot: 5, name: 'phone', count: 1, weight: 1 };

  expect(
    assessPlacement({
      sourceInventory: inventory('left', [source], 5),
      targetInventory: inventory('right', [rifle]),
      source,
      toSlot: 2,
      count: 1,
      rotated: false,
      definitions,
    })
  ).toEqual({ valid: false, anchor: 1, kind: 'swap', cells: [1] });
});

test('automatic placement skips covered cells and partial final row', () => {
  expect(findPlacement(inventory('left', [rifle], 13), { slot: 1, name: 'phone' }, definitions)).toBe(5);
  expect(findPlacement(inventory('left', [rifle], 13), { slot: 1, name: 'pistol' }, definitions)).toBe(11);
});

test('catalogue packing preserves recipe indices and includes entries after cell thirty', () => {
  const inv = inventory(
    'right',
    Array.from({ length: 8 }, (_, i) => ({ ...rifle, slot: (i + 1) * 2 }))
  );
  inv.type = 'crafting';

  const result = packCatalogue(inv, definitions);

  expect(result.entries.map(({ item, anchor }) => [item.slot, anchor])).toEqual([
    [2, 1],
    [4, 11],
    [6, 21],
    [8, 31],
    [10, 41],
    [12, 51],
    [14, 61],
    [16, 71],
  ]);
  expect(result.cells).toBe(80);
});

test('craft preview releases ingredients consumed by the first craft', () => {
  const targetInventory = inventory('left', [{ slot: 1, name: 'phone', count: 2, weight: 100 }]);
  const source = { ...rifle, ingredients: { phone: 2 } };

  expect(
    assessPlacement({
      sourceInventory: { ...inventory('right', [source]), type: 'crafting' },
      targetInventory,
      source,
      toSlot: 1,
      count: 1,
      rotated: false,
      definitions,
    })
  ).toEqual({
    valid: true,
    anchor: 1,
    kind: 'move',
    cells: [1, 2, 3, 4, 6, 7, 8, 9],
  });
});

test('purchase preview releases the complete payment footprint', () => {
  const targetInventory = inventory('left', [{ slot: 1, name: 'phone', count: 2, weight: 100 }]);
  const source = { ...rifle, currency: 'phone', price: 2 };

  expect(
    assessPlacement({
      sourceInventory: { ...inventory('right', [source]), type: 'shop' },
      targetInventory,
      source,
      toSlot: 1,
      count: 1,
      rotated: false,
      definitions,
    })
  ).toEqual({
    valid: true,
    anchor: 1,
    kind: 'move',
    cells: [1, 2, 3, 4, 6, 7, 8, 9],
  });
});

test('uncertain catalogue footprint is sent for server assessment with amber preview', () => {
  const targetInventory = inventory('left', [{ slot: 1, name: 'phone', count: 2, weight: 100 }]);
  const source = { ...rifle, ingredients: { phone: 0.5 } };

  expect(
    assessPlacement({
      sourceInventory: { ...inventory('right', [source]), type: 'crafting' },
      targetInventory,
      source,
      toSlot: 1,
      count: 1,
      rotated: false,
      definitions,
    })
  ).toEqual({
    valid: true,
    pending: true,
    anchor: 1,
    kind: 'move',
    cells: [1, 2, 3, 4, 6, 7, 8, 9],
  });
});
