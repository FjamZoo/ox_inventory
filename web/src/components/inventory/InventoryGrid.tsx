import React, { useMemo, useRef } from 'react';
import { useDragLayer, useDrop, XYCoord } from 'react-dnd';
import { DragSource, Inventory } from '../../typings';
import WeightBar from '../utils/WeightBar';
import InventorySlot from './InventorySlot';
import { getTargetInventory, getTotalWeight } from '../../helpers';
import { assessPlacement, getFootprint, getGrid, packCatalogue } from '../../helpers/grid';
import { useAppDispatch, useAppSelector } from '../../store';
import { Items } from '../../store/items';
import { getMoveCount, onDrop } from '../../dnd/onDrop';
import { onBuy } from '../../dnd/onBuy';
import { onCraft } from '../../dnd/onCraft';
import { recoverItem } from '../../thunks/recoverItem';
import { Locale } from '../../store/locale';

const gridStyle = (anchor: number, columns: number, width = 1, height = 1): React.CSSProperties => ({
  gridColumn: `${((anchor - 1) % columns) + 1} / span ${width}`,
  gridRow: `${Math.floor((anchor - 1) / columns) + 1} / span ${height}`,
});

const recoveryName = (record: unknown) => {
  if (record && typeof record === 'object' && 'name' in record && typeof record.name === 'string') {
    return Items[record.name]?.label ?? record.name;
  }

  return Locale.ui_unknown_item || 'Unknown item';
};

const InventoryGrid: React.FC<{ inventory: Inventory }> = ({ inventory }) => {
  const state = useAppSelector((state) => state.inventory);
  const dispatch = useAppDispatch();
  const contentRef = useRef<HTMLDivElement | null>(null);
  const catalogue = inventory.type === 'shop' || inventory.type === 'crafting';
  const layout = useMemo(
    () =>
      catalogue
        ? packCatalogue(inventory, Items)
        : {
            ...getGrid(inventory),
            entries: inventory.items
              .filter((item) => item.name)
              .map((item) => ({
                item,
                anchor: item.slot,
                ...getFootprint(item.name ? Items[item.name]?.size : undefined, item.rotated),
              })),
          },
    [inventory, catalogue]
  );
  const weight = inventory.weight ?? getTotalWeight(inventory.items);
  const { source, point, dragging } = useDragLayer((monitor) => ({
    source: monitor.getItem<DragSource>() ?? null,
    point: monitor.getClientOffset(),
    dragging: monitor.isDragging(),
  }));

  const placementAt = (source: DragSource, point: XYCoord | null) => {
    const element = contentRef.current;

    if (!element || !point || catalogue || state.isBusy) return;

    const rect = element.getBoundingClientRect();
    const viewport = element.parentElement?.getBoundingClientRect();

    if (viewport && (point.x < viewport.left || point.x >= viewport.right)) return;

    if (viewport && (point.y < viewport.top || point.y >= viewport.bottom)) return;

    const css = getComputedStyle(element);
    const gap = parseFloat(css.columnGap) || 0;
    const rowHeight = parseFloat(css.gridAutoRows) + (parseFloat(css.rowGap) || 0);
    const column = Math.floor((point.x - rect.left) / ((rect.width + gap) / layout.columns));
    const row = Math.floor((point.y - rect.top) / rowHeight);
    const cell = row * layout.columns + column + 1;

    if (column < 0 || column >= layout.columns || row < 0 || cell > layout.cells) return;

    const { sourceInventory } = getTargetInventory(state, source.inventory);
    const sourceItem = sourceInventory.items[source.item.slot - 1];

    if (!sourceItem?.name) return;

    const isCatalogue = source.inventory === 'shop' || source.inventory === 'crafting';
    const requested = state.itemAmount || 1;
    const count = isCatalogue
      ? source.inventory === 'shop' && sourceItem.count
        ? Math.min(requested, sourceItem.count)
        : requested
      : getMoveCount(sourceItem.count ?? 1, state.itemAmount, state.shiftPressed);

    return assessPlacement({
      sourceInventory,
      targetInventory: inventory,
      source: sourceItem,
      toSlot: cell,
      count,
      rotated: source.rotated ?? !!sourceItem.rotated,
      definitions: Items,
    });
  };

  const [, drop] = useDrop<DragSource>(
    () => ({
      accept: 'SLOT',
      canDrop: (source, monitor) => placementAt(source, monitor.getClientOffset())?.valid === true,
      drop: (source, monitor) => {
        const placement = placementAt(source, monitor.getClientOffset());

        if (!placement?.valid) return;

        const target = { inventory: inventory.type, item: { slot: placement.anchor } };

        if (source.inventory === 'shop') onBuy(source, target);
        else if (source.inventory === 'crafting') onCraft(source, target);
        else onDrop(source, target);
      },
    }),
    [inventory, state, layout]
  );
  const preview = dragging && source ? placementAt(source, point) : undefined;

  return (
    <div className="inventory-grid-wrapper" aria-busy={state.isBusy}>
      <div>
        <div className="inventory-grid-header-wrapper">
          <p>{inventory.label}</p>
          {!!inventory.maxWeight && (
            <p>
              {Math.floor(weight) / 1000}/{inventory.maxWeight / 1000}kg
            </p>
          )}
        </div>
        <WeightBar percent={inventory.maxWeight ? (weight / inventory.maxWeight) * 100 : 0} />
      </div>
      <div className="inventory-grid-container">
        <div
          className="inventory-grid-content"
          ref={(element) => {
            contentRef.current = element;
            drop(element);
          }}
          style={{ gridTemplateColumns: `repeat(${layout.columns}, 10.2vh)` }}
        >
          {Array.from({ length: layout.cells }, (_, index) => (
            <div
              className="inventory-cell"
              key={`cell-${index}`}
              style={gridStyle(index + 1, layout.columns)}
              data-cell={index + 1}
            />
          ))}
          {layout.entries.map(({ item, anchor, width, height }) => (
            <InventorySlot
              key={`${inventory.id}-${item.slot}`}
              item={item}
              inventoryType={inventory.type}
              inventoryGroups={inventory.groups}
              inventoryId={inventory.id}
              style={{
                ...gridStyle(anchor, layout.columns, width, height),
                backgroundSize: width > 1 || height > 1 ? 'contain' : undefined,
              }}
            />
          ))}
          {preview &&
            preview.cells
              .filter((cell) => cell >= 1 && cell <= layout.cells)
              .map((cell) => (
                <div
                  key={`preview-${cell}`}
                  className={`inventory-placement ${preview.pending ? 'pending' : preview.valid ? 'valid' : 'invalid'}`}
                  style={gridStyle(cell, layout.columns)}
                >
                  {cell === preview.anchor && (
                    <span>
                      {preview.anchor}
                      {preview.pending ? ' ?' : ''}
                    </span>
                  )}
                </div>
              ))}
        </div>
      </div>
      {!!inventory.recovery?.length && (
        <div className="inventory-recovery">
          <p>
            {Locale.ui_recovery || 'Recovery'} ({inventory.recovery.length})
          </p>
          {inventory.recovery.map((entry) => (
            <div className="inventory-recovery-entry" key={entry.id}>
              <div>
                <span>{recoveryName(entry.record)}</span>
                <small>{entry.reason.replaceAll('_', ' ')}</small>
              </div>
              <button
                disabled={state.isBusy || inventory.type === 'inspect'}
                onClick={() => dispatch(recoverItem({ fromType: inventory.type, recoveryId: entry.id }))}
              >
                {Locale.ui_reclaim || 'Reclaim'}
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
};

export default InventoryGrid;
