import { Inventory } from './inventory';
import { Slot } from './slot';

export type State = {
  leftInventory: Inventory;
  rightInventory: Inventory;
  itemAmount: number;
  shiftPressed: boolean;
  isBusy: boolean;
  dragRotated?: boolean;
  additionalMetadata: Array<{ metadata: string; value: string }>;
};
