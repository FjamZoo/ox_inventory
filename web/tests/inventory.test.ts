import { expect, test } from 'bun:test';
import type { Inventory } from '../src/typings';

Object.assign(globalThis, { window: { fetch: globalThis.fetch, invokeNative: true } });
await import('../src/store');
const { default: reducer, setupInventory, refreshSlots } = await import('../src/store/inventory');
const { validateMove } = await import('../src/thunks/validateItems');
const { Items } = await import('../src/store/items');
Items.phone = { name: 'phone', label: 'Phone', stack: false, count: 0, close: false, usable: true };
const left: Inventory = {
  id: 12,
  type: 'player',
  slots: 8,
  items: [{ slot: 1, name: 'phone', count: 1, weight: 100 }],
  grid: { columns: 5, cells: 8 },
  recovery: [{ id: 'recover-a', reason: 'no_space', record: { name: 'phone' } }],
};
const right: Inventory = { id: 'stash', type: 'stash', slots: 10, items: [] };
const request = { fromType: 'player', toType: 'stash', fromSlot: 1, toSlot: 1, count: 1, rotated: false };

test('rejection preserves authoritative refresh received while move is pending', () => {
  let state = reducer(undefined, setupInventory({ leftInventory: left, rightInventory: right }));
  state = reducer(state, validateMove.pending('move-1', request));
  expect({ busy: state.isBusy, anchor: state.leftInventory.items[0].name }).toEqual({ busy: true, anchor: 'phone' });
  state = reducer(
    state,
    refreshSlots({
      inventory: {
        ...left,
        items: [{ slot: 6, name: 'phone', count: 2, weight: 200 }],
        recovery: [{ id: 'recover-b', reason: 'unknown_item', record: { name: 'removed-definition' } }],
      },
    })
  );
  state = reducer(state, validateMove.rejected(new Error('rejected'), 'move-1', request));
  expect({
    busy: state.isBusy,
    slots: state.leftInventory.items.filter((item) => item.name).map((item) => [item.slot, item.count]),
    recovery: state.leftInventory.recovery?.map((item) => item.id),
    right: state.rightInventory.id,
  }).toEqual({
    busy: false,
    slots: [[6, 2]],
    recovery: ['recover-b'],
    right: 'stash',
  });
});

test('ordinary partial refresh preserves geometry and recovery', () => {
  let state = reducer(undefined, setupInventory({ leftInventory: left, rightInventory: right }));
  state = reducer(
    state,
    refreshSlots({
      items: [
        { item: { slot: 1 }, inventory: 12 },
        { item: { slot: 6, name: 'phone', count: 1, weight: 100, rotated: true }, inventory: 12 },
      ],
    })
  );
  expect({
    anchors: state.leftInventory.items.filter((item) => item.name).map((item) => [item.slot, item.rotated]),
    grid: state.leftInventory.grid,
    recovery: state.leftInventory.recovery?.map((item) => item.id),
  }).toEqual({
    anchors: [[6, true]],
    grid: { columns: 5, cells: 8 },
    recovery: ['recover-a'],
  });
});

test('incoming capacity snapshot replaces anchors and keeps pending state until reply', () => {
  let state = reducer(undefined, setupInventory({ leftInventory: left, rightInventory: right }));
  state = reducer(state, validateMove.pending('move-2', request));
  state = reducer(
    state,
    refreshSlots({ inventory: { ...left, slots: 3, grid: { columns: 5, cells: 3 }, items: [], recovery: [] } })
  );
  expect({
    busy: state.isBusy,
    cells: state.leftInventory.items.map((item) => item.slot),
    recovery: state.leftInventory.recovery,
  }).toEqual({
    busy: true,
    cells: [1, 2, 3],
    recovery: [],
  });
  state = reducer(state, validateMove.fulfilled(undefined, 'move-2', request));
  expect({ busy: state.isBusy, cells: state.leftInventory.grid }).toEqual({
    busy: false,
    cells: { columns: 5, cells: 3 },
  });
});

test('catalogues preserve sparse recipe indices beyond reported slot capacity', () => {
  const state = reducer(
    undefined,
    setupInventory({
      rightInventory: {
        ...right,
        type: 'crafting',
        slots: 2,
        items: [{ slot: 41, name: 'phone', weight: 100, count: 1 }],
      },
    })
  );
  expect(state.rightInventory.items.filter((item) => item.name).map((item) => item.slot)).toEqual([41]);
});
