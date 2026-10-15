import { CaseReducer, PayloadAction } from '@reduxjs/toolkit';
import { getItemData, itemDurability } from '../helpers';
import { Items } from '../store/items';
import { Inventory, State } from '../typings';

export const setupInventoryReducer: CaseReducer<
  State,
  PayloadAction<{
    leftInventory?: Inventory;
    rightInventory?: Inventory;
  }>
> = (state, action) => {
  const { leftInventory, rightInventory } = action.payload;
  const curTime = Math.floor(Date.now() / 1000);

  if (leftInventory)
    state.leftInventory = {
      ...leftInventory,
      items: Array.from(
        Array(Math.max(leftInventory.slots, ...Object.values(leftInventory.items).map((item) => item?.slot || 0))),
        (_, index) => {
          const item = Object.values(leftInventory.items).find((item) => item?.slot === index + 1) || {
            slot: index + 1,
          };

          if (!item.name) return item;

          if (typeof Items[item.name] === 'undefined') {
            getItemData(item.name);
          }

          return { ...item, durability: itemDurability(item.metadata, curTime) };
        }
      ),
    };

  if (rightInventory)
    state.rightInventory = {
      ...rightInventory,
      items: Array.from(
        Array(Math.max(rightInventory.slots, ...Object.values(rightInventory.items).map((item) => item?.slot || 0))),
        (_, index) => {
          const item = Object.values(rightInventory.items).find((item) => item?.slot === index + 1) || {
            slot: index + 1,
          };

          if (!item.name) return item;

          if (typeof Items[item.name] === 'undefined') {
            getItemData(item.name);
          }

          return { ...item, durability: itemDurability(item.metadata, curTime) };
        }
      ),
    };

  state.shiftPressed = false;
  state.isBusy = false;
};
