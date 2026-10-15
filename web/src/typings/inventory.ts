import { Slot } from './slot';

export enum InventoryType {
  PLAYER = 'player',
  SHOP = 'shop',
  CONTAINER = 'container',
  CRAFTING = 'crafting',
}

export type Inventory = {
  id: string | number;
  type: string;
  slots: number;
  items: Slot[];
  grid?: { columns: number; cells: number };
  recovery?: Array<{ id: string; reason: string; record: unknown }>;
  weight?: number;
  maxWeight?: number;
  label?: string;
  groups?: Record<string, number>;
};
