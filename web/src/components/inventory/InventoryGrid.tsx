import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useDrop, useDragLayer } from 'react-dnd';
import { DragSource, Inventory, Slot } from '../../typings';
import WeightBar from '../utils/WeightBar';
import InventorySlot from './InventorySlot';
import { canStack, getTotalWeight } from '../../helpers';
import { canPlace, columns, dimensions, fits, occupant } from '../../helpers/grid';
import { useAppSelector } from '../../store';
import { Items } from '../../store/items';
import { onDrop } from '../../dnd/onDrop';
import { onBuy } from '../../dnd/onBuy';
import { onCraft } from '../../dnd/onCraft';

const InventoryGrid: React.FC<{ inventory: Inventory }> = ({ inventory }) => {
  const state = useAppSelector((state) => state.inventory);
  const weight = useMemo(() => getTotalWeight(inventory.items), [inventory.items]);
  const catalog = inventory.type === 'shop' || inventory.type === 'crafting';
  const cols = catalog ? 5 : columns(inventory) || 5;
  // Catalog slot IDs remain product/recipe IDs; display positions are independent.
  const catalogItems = useMemo(() => {
    if (!catalog) return [];
    const products = inventory.items.filter((item) => item?.name);
    const layout: Inventory = {
      ...inventory,
      slots: Math.max(
        5,
        products.reduce(
          (sum, item) => sum + dimensions({ ...item, size: item.size || Items[item.name!]?.size }).height * 5,
          0
        )
      ),
      items: [],
    };
    return products.map((item) => {
      const size = dimensions({ ...item, size: item.size || Items[item.name!]?.size });
      const visual = { ...item, size: { width: Math.min(5, size.width), height: size.height }, rotated: false };
      let slot = 1;
      while (!fits(layout, visual, slot)) slot++;
      layout.items.push({ ...visual, slot });
      return { item, visual, slot };
    });
  }, [catalog, inventory]);
  const containerRef = useRef<HTMLDivElement>(null);
  const [hoverCell, setHoverCell] = useState<number>();
  const [, rerender] = useState(0);
  const { source } = useDragLayer((monitor) => ({ source: monitor.getItem() as DragSource | null }));
  useEffect(() => {
    const rotate = () => rerender((value) => value + 1);
    window.addEventListener('inventory:rotate', rotate);
    return () => window.removeEventListener('inventory:rotate', rotate);
  }, []);
  const from = source?.inventory === 'player' ? state.leftInventory : state.rightInventory;
  const original = source && from.items[source.item.slot - 1];
  const dragged = original
    ? { ...original, size: source?.size || original.size || Items[original.name!]?.size }
    : undefined;
  const rotated = source?.rotated === true;
  const count = original
    ? from.type === 'shop' || from.type === 'crafting'
      ? state.itemAmount || 1
      : state.shiftPressed && (original.count || 0) > 1
        ? Math.floor(original.count! / 2)
        : !state.itemAmount || state.itemAmount > original.count!
          ? original.count!
          : state.itemAmount
    : 0;
  const landing = (cell: number) => {
    const other = occupant(inventory, cell);
    return other && !(from.id === inventory.id && other.slot === original?.slot) ? other.slot : cell;
  };
  const anchor = hoverCell === undefined ? undefined : landing(hoverCell);
  const target = anchor ? inventory.items[anchor - 1] : undefined;
  const valid =
    !!dragged &&
    anchor !== undefined &&
    canPlace(
      from,
      inventory,
      dragged,
      anchor,
      count,
      rotated,
      !!target?.name && !!Items[dragged.name!]?.stack && canStack(dragged, target)
    );
  const cellAt = (point: { x: number; y: number } | null) => {
    const element = containerRef.current;
    if (!element || !point) return undefined;
    const bounds = element.getBoundingClientRect();
    const cell = element.querySelector<HTMLElement>('[data-grid-cell]');
    if (!cell) return undefined;
    const cellBounds = cell.getBoundingClientRect();
    const x = Math.floor((point.x - bounds.left) / (cellBounds.width + 2));
    const y = Math.floor((point.y - bounds.top + element.scrollTop) / (cellBounds.height + 2));
    if (x < 0 || x >= cols || y < 0 || point.y > bounds.bottom) return undefined;
    const slot = y * cols + x + 1;
    return slot <= inventory.slots ? slot : undefined;
  };
  const [{ isOver }, drop] = useDrop<DragSource, void, { isOver: boolean }>(
    () => ({
      accept: 'SLOT',
      collect: (monitor) => ({ isOver: monitor.isOver() }),
      hover: (_, monitor) => setHoverCell(cellAt(monitor.getClientOffset())),
      canDrop: () => !catalog && inventory.type !== 'inspect',
      drop: (source, monitor) => {
        const cell = cellAt(monitor.getClientOffset());
        if (cell === undefined) return;
        const slot = landing(cell);
        const destination = { inventory: inventory.type, item: { slot } };
        if (source.inventory === 'shop') onBuy(source, destination);
        else if (source.inventory === 'crafting') onCraft(source, destination);
        else onDrop(source, destination);
      },
    }),
    [inventory, from, original, catalog, cols]
  );
  const position = (slot: number, item?: Slot): React.CSSProperties => {
    const { width, height } = item ? dimensions(item) : { width: 1, height: 1 };
    return {
      gridColumn: `${((slot - 1) % cols) + 1} / span ${width}`,
      gridRow: `${Math.floor((slot - 1) / cols) + 1} / span ${height}`,
    };
  };
  const recovery = inventory.items.filter((item) => item?.name && item.slot > inventory.slots);
  const renderItem = (item: Slot, style?: React.CSSProperties) => (
    <InventorySlot
      key={`${inventory.id}-${item.slot}`}
      item={item}
      gridManaged
      style={style}
      inventoryType={inventory.type}
      inventoryGroups={inventory.groups}
      inventoryId={inventory.id}
    />
  );
  const preview = dragged && anchor && isOver && !catalog && inventory.type !== 'inspect';
  return (
    <div className="inventory-grid-wrapper" style={{ pointerEvents: state.isBusy ? 'none' : 'auto' }}>
      <div>
        <div className="inventory-grid-header-wrapper">
          <p>{inventory.label}</p>
          {inventory.maxWeight !== undefined && (
            <p>
              {weight / 1000}/{inventory.maxWeight / 1000}kg
            </p>
          )}
        </div>
        <WeightBar percent={inventory.maxWeight ? (weight / inventory.maxWeight) * 100 : 0} />
        <p className="grid-hint">{catalog ? 'Drag to your inventory' : 'R: rotate while dragging'}</p>
      </div>
      <div
        className="inventory-grid-container"
        ref={(node) => {
          containerRef.current = node;
          drop(node);
        }}
        style={{ gridTemplateColumns: `repeat(${cols}, 10.2vh)` }}
      >
        {catalog ? (
          catalogItems.map(({ item, visual, slot }) => renderItem(item, position(slot, visual)))
        ) : (
          <>
            {Array.from({ length: inventory.slots }, (_, index) => (
              <div
                key={`cell-${index}`}
                data-grid-cell={index + 1}
                className="inventory-grid-cell"
                style={position(index + 1)}
              />
            ))}
            {inventory.items
              .filter((item) => item?.name && item.slot <= inventory.slots)
              .map((item) => renderItem(item, position(item.slot, item)))}
            {preview && (
              <div
                className={`grid-placement ${valid ? 'valid' : 'invalid'}`}
                aria-label={valid ? 'Fits' : 'Does not fit'}
                style={{
                  position: 'absolute',
                  left: `calc(${(anchor - 1) % cols} * (10.2vh + 2px))`,
                  top: `calc(${Math.floor((anchor - 1) / cols)} * (10.42vh + 2px))`,
                  width: `calc(${dimensions(dragged, rotated).width} * 10.2vh + ${dimensions(dragged, rotated).width - 1} * 2px)`,
                  height: `calc(${dimensions(dragged, rotated).height} * 10.42vh + ${dimensions(dragged, rotated).height - 1} * 2px)`,
                }}
              />
            )}
          </>
        )}
      </div>
      {recovery.length > 0 && (
        <div className="inventory-recovery">
          <p>Recovery — move these items into free space or another inventory.</p>
          <div className="recovery-items">{recovery.map((item) => renderItem(item))}</div>
        </div>
      )}
    </div>
  );
};
export default InventoryGrid;
