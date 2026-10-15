import { Inventory, ItemData, Slot } from '../typings';
import { assessPlacement, findPlacement } from '../helpers/grid';

const definition = (name: string, label: string, width: number, height: number, stack: boolean): ItemData => ({
  name,
  label,
  size: { width, height },
  stack,
  count: 0,
  usable: true,
  close: false,
});

export const fixtureItems: Record<string, ItemData> = {
  rifle: { ...definition('rifle', 'Rifle', 4, 2, true), image: '/images/WEAPON_ASSAULTRIFLE.png' },
  pistol: { ...definition('pistol', 'Pistol', 2, 1, false), image: '/images/WEAPON_PISTOL.png' },
  phone: definition('phone', 'Phone', 1, 1, false),
};

export const fixtureInventories: { leftInventory: Inventory; rightInventory: Inventory } = {
  leftInventory: {
    id: 'fixture-player',
    type: 'player',
    label: 'Item grid fixture',
    slots: 33,
    grid: { columns: 5, cells: 33 },
    maxWeight: 50000,
    items: [
      { slot: 1, name: 'rifle', count: 4, weight: 4000, metadata: {} },
      { slot: 5, name: 'phone', count: 1, weight: 100, metadata: {} },
      { slot: 11, name: 'pistol', count: 1, weight: 700, metadata: {} },
    ],
    recovery: [
      {
        id: 'fixture-recovery',
        reason: 'no_space',
        record: { name: 'phone', slot: 99, count: 1, weight: 100, metadata: {} },
      },
    ],
  },
  rightInventory: {
    id: 'fixture-stash',
    type: 'stash',
    label: 'Storage',
    slots: 40,
    grid: { columns: 5, cells: 40 },
    maxWeight: 50000,
    items: [],
    recovery: [],
  },
};

export const createBrowserFixture = (initial: typeof fixtureInventories, accept: boolean) => {
  const inventories = structuredClone(initial);

  const emit = () => {
    for (const inventory of Object.values(inventories)) {
      window.dispatchEvent(
        new MessageEvent('message', {
          data: { action: 'refreshSlots', data: { inventory: structuredClone(inventory) } },
        })
      );
    }
  };

  const put = (inventory: Inventory, slot: number, item?: Slot) => {
    inventory.items = inventory.items.filter((entry) => entry.slot !== slot);

    if (item) inventory.items.push({ ...item, slot });
  };

  return (eventName: string, payload: unknown): unknown => {
    if (eventName === 'uiLoaded') {
      return true;
    }

    if (eventName === 'getItemData') {
      return typeof payload === 'string' ? (fixtureItems[payload] ?? false) : false;
    }

    if (eventName === 'exit') {
      window.dispatchEvent(new MessageEvent('message', { data: { action: 'closeInventory', data: false } }));

      return true;
    }

    if (!accept || !payload || typeof payload !== 'object') return false;

    if (eventName === 'recoverItem' && 'fromType' in payload && 'recoveryId' in payload) {
      const inventory = payload.fromType === 'player' ? inventories.leftInventory : inventories.rightInventory;
      const entry = inventory.recovery?.find((entry) => entry.id === payload.recoveryId);
      const record = entry?.record;

      if (!record || typeof record !== 'object') return false;

      if (!('name' in record) || typeof record.name !== 'string') return false;

      if (!('count' in record) || typeof record.count !== 'number') return false;

      if (!('weight' in record) || typeof record.weight !== 'number') return false;

      const slot = findPlacement(inventory, { slot: 1, name: record.name }, fixtureItems);

      if (!slot) return false;

      put(inventory, slot, { slot, name: record.name, count: record.count, weight: record.weight, metadata: {} });
      inventory.recovery = inventory.recovery?.filter((item) => item.id !== payload.recoveryId);
      queueMicrotask(emit);

      return true;
    }

    if (eventName !== 'swapItems' || !('fromType' in payload) || !('toType' in payload)) return false;

    if (!('fromSlot' in payload) || !('toSlot' in payload) || !('count' in payload)) return false;

    if (typeof payload.fromSlot !== 'number' || typeof payload.toSlot !== 'number') return false;

    if (typeof payload.count !== 'number') return false;

    const sourceInventory = payload.fromType === 'player' ? inventories.leftInventory : inventories.rightInventory;
    const targetInventory = payload.toType === 'player' ? inventories.leftInventory : inventories.rightInventory;
    const source = sourceInventory.items.find((item) => item.slot === payload.fromSlot);

    if (!source?.count || !source.weight) return false;

    const rotated = 'rotated' in payload && typeof payload.rotated === 'boolean' ? payload.rotated : !!source.rotated;
    const placement = assessPlacement({
      sourceInventory,
      targetInventory,
      source,
      toSlot: payload.toSlot,
      count: payload.count,
      rotated,
      definitions: fixtureItems,
    });

    if (!placement.valid) return false;

    const target = targetInventory.items.find((item) => item.slot === placement.anchor);
    const count = payload.count;
    const moved = { ...source, count, weight: (source.weight / source.count) * count, rotated };

    if (placement.kind === 'rotate') {
      put(sourceInventory, source.slot, { ...source, rotated });
    } else if (placement.kind === 'swap' && target) {
      put(sourceInventory, source.slot, target);
      put(targetInventory, placement.anchor, moved);
    } else {
      put(
        sourceInventory,
        source.slot,
        count < source.count
          ? { ...source, count: source.count - count, weight: source.weight - moved.weight }
          : undefined
      );
      put(
        targetInventory,
        placement.anchor,
        placement.kind === 'stack' && target
          ? { ...target, count: (target.count ?? 0) + count, weight: (target.weight ?? 0) + moved.weight }
          : moved
      );
    }

    queueMicrotask(emit);

    return true;
  };
};
