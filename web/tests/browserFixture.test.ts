import { expect, test } from 'bun:test';
import { createBrowserFixture, fixtureInventories } from '../src/utils/browserFixture';
import type { Inventory } from '../src/typings';

const request = { fromType: 'player', toType: 'stash', fromSlot: 1, toSlot: 1, count: 4, rotated: true };

test('accept fixture publishes the authoritative rotated destination and released source', async () => {
  const target = new EventTarget();
  const snapshots: Inventory[] = [];
  Object.assign(globalThis, { window: target });
  target.addEventListener('message', (event) => snapshots.push((event as MessageEvent).data.data.inventory));
  const fixture = createBrowserFixture(fixtureInventories, true);
  expect(fixture('swapItems', request)).toBe(true);
  await Promise.resolve();
  expect(
    snapshots.map((inventory) => ({
      id: inventory.id,
      items: inventory.items.map((item) => [item.slot, item.name, item.count, !!item.rotated]),
    }))
  ).toEqual([
    {
      id: 'fixture-player',
      items: [
        [5, 'phone', 1, false],
        [11, 'pistol', 1, false],
      ],
    },
    { id: 'fixture-stash', items: [[1, 'rifle', 4, true]] },
  ]);
});

test('reject fixture returns false while accepted operations return true', () => {
  expect(createBrowserFixture(fixtureInventories, false)('swapItems', request)).toBe(false);
  expect(createBrowserFixture(fixtureInventories, true)('buyItem', request)).toBe(false);
  expect(createBrowserFixture(fixtureInventories, false)('uiLoaded', {})).toBe(true);
});

test('reclaim fixture removes only the reclaimed recovery record and publishes its first fit', async () => {
  const target = new EventTarget();
  const snapshots: Inventory[] = [];
  Object.assign(globalThis, { window: target });
  target.addEventListener('message', (event) => snapshots.push((event as MessageEvent).data.data.inventory));
  expect(
    createBrowserFixture(fixtureInventories, true)('recoverItem', {
      fromType: 'player',
      recoveryId: 'fixture-recovery',
    })
  ).toBe(true);
  await Promise.resolve();
  expect({ item: snapshots[0].items.find((item) => item.slot === 10), recovery: snapshots[0].recovery }).toEqual({
    item: { slot: 10, name: 'phone', count: 1, weight: 100, metadata: {} },
    recovery: [],
  });
});
