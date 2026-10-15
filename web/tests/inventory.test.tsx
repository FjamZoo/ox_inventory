import './setup';
import { expect, test } from 'bun:test';
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { Provider } from 'react-redux';
import { DndProvider } from 'react-dnd';
import { store } from '../src/store';
import { Items } from '../src/store/items';
import { setupInventory, moveSlots, swapSlots } from '../src/store/inventory';
import InventoryGrid from '../src/components/inventory/InventoryGrid';
import type { Inventory, SlotWithItem } from '../src/typings';

const rifle: SlotWithItem = {
  slot: 1,
  name: 'rifle',
  size: { width: 4, height: 2 },
  weight: 100,
  count: 1,
  metadata: {},
};
Items.rifle = { name: 'rifle', label: 'Rifle', stack: false, close: false, usable: false, count: 1, size: rifle.size };
Items.phone = { name: 'phone', label: 'Phone', stack: true, close: false, usable: false, count: 1 };
const inventory: Inventory = {
  id: 'player',
  label: 'Player',
  slots: 20,
  type: 'player',
  maxWeight: 1000,
  items: [rifle],
};
const backend = () => ({
  setup() {},
  teardown() {},
  connectDragSource: () => () => {},
  connectDragPreview: () => () => {},
  connectDropTarget: () => () => {},
});

test('setup retains recovery anchors rather than truncating to configured slots', () => {
  store.dispatch(setupInventory({ leftInventory: { ...inventory, items: [rifle, { ...rifle, slot: 21 }] } }));
  expect(store.getState().inventory.leftInventory.items.length).toBe(21);
  expect(store.getState().inventory.leftInventory.items[20].name).toBe('rifle');
});

test('in-place rotation updates the item without removing it', () => {
  store.dispatch(setupInventory({ leftInventory: inventory }));
  store.dispatch(
    moveSlots({ fromSlot: rifle, toSlot: rifle, fromType: 'player', toType: 'player', count: 1, rotated: true })
  );
  expect(store.getState().inventory.leftInventory.items[0]).toMatchObject({ name: 'rifle', rotated: true, count: 1 });
});

test('split transfers orientation to only the new stack', () => {
  const stack = { ...rifle, count: 4, weight: 400 };
  store.dispatch(setupInventory({ leftInventory: { ...inventory, items: [stack] } }));
  store.dispatch(
    moveSlots({ fromSlot: stack, toSlot: { slot: 3 }, fromType: 'player', toType: 'player', count: 2, rotated: true })
  );
  const items = store.getState().inventory.leftInventory.items;
  expect(items[0]).toMatchObject({ count: 2, weight: 200 });
  expect(items[0].rotated).toBeUndefined();
  expect(items[2]).toMatchObject({ count: 2, weight: 200, rotated: true });
});

test('swap transfers the selected rotation, preserving the other item', () => {
  const phone: SlotWithItem = { slot: 11, name: 'phone', count: 1, weight: 1, metadata: {} };
  store.dispatch(setupInventory({ leftInventory: { ...inventory, items: [rifle, phone] } }));
  store.dispatch(swapSlots({ fromSlot: rifle, toSlot: phone, fromType: 'player', toType: 'player', rotated: true }));
  const items = store.getState().inventory.leftInventory.items;
  expect(items[0].name).toBe('phone');
  expect(items[10]).toMatchObject({ name: 'rifle', rotated: true });
});

test('render spans the rifle rectangle and shows recovery separately', () => {
  store.dispatch(setupInventory({ leftInventory: { ...inventory, items: [rifle, { ...rifle, slot: 21 }] } }));
  const html = renderToStaticMarkup(
    <Provider store={store}>
      <DndProvider backend={backend}>
        <InventoryGrid inventory={store.getState().inventory.leftInventory} />
      </DndProvider>
    </Provider>
  );
  expect(html).toContain('grid-column:1 / span 4;grid-row:1 / span 2');
  expect(html).toContain('data-grid-cell="20"');
  expect(html).not.toContain('data-grid-cell="21"');
  expect(html).toContain('Recovery');
  expect(html).toContain('R: rotate while dragging');
});
