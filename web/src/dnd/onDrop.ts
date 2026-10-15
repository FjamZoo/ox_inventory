import { getTargetInventory, isSlotWithItem } from '../helpers';
import { assessPlacement, findPlacement } from '../helpers/grid';
import { validateMove } from '../thunks/validateItems';
import { store } from '../store';
import { DragSource, DropTarget, InventoryType } from '../typings';
import { Items } from '../store/items';

export const getMoveCount = (sourceCount: number, amount: number, split: boolean) =>
  split && sourceCount > 1 ? Math.floor(sourceCount / 2) : amount === 0 || amount > sourceCount ? sourceCount : amount;

export const onDrop = (source: DragSource, target?: DropTarget) => {
  const { inventory: state } = store.getState();

  if (state.isBusy) return;

  const { sourceInventory, targetInventory } = getTargetInventory(state, source.inventory, target?.inventory);
  const sourceSlot = sourceInventory.items[source.item.slot - 1];

  if (!sourceSlot || !isSlotWithItem(sourceSlot) || !Items[sourceSlot.name]) return;

  if (sourceSlot.metadata?.container !== undefined) {
    if (targetInventory.type === InventoryType.CONTAINER) return;

    if (state.rightInventory.id === sourceSlot.metadata.container) return;
  }

  const rotated = source.rotated ?? !!sourceSlot.rotated;
  const toSlot = target?.item.slot ?? findPlacement(targetInventory, sourceSlot, Items, rotated);

  if (toSlot === undefined) return;

  const count = getMoveCount(sourceSlot.count, state.itemAmount, state.shiftPressed);
  const placement = assessPlacement({
    sourceInventory,
    targetInventory,
    source: sourceSlot,
    toSlot,
    count,
    rotated,
    definitions: Items,
  });

  if (!placement.valid) return;

  const targetSlot = targetInventory.items[placement.anchor - 1];

  if (targetSlot?.metadata?.container !== undefined) {
    if (state.rightInventory.id === targetSlot.metadata.container) return;
  }

  store.dispatch(
    validateMove({
      fromSlot: sourceSlot.slot,
      toSlot: placement.anchor,
      fromType: sourceInventory.type,
      toType: targetInventory.type,
      count,
      rotated,
    })
  );
};
