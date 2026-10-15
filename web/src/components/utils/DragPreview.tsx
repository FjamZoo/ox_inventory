import React, { useEffect, useLayoutEffect, useRef } from 'react';
import { useDragLayer, useDragDropManager } from 'react-dnd';
import { DragSource } from '../../typings';
import { useAppSelector } from '../../store';
import { getFootprint } from '../../helpers/grid';
import { Items } from '../../store/items';

const DragPreview: React.FC = () => {
  const manager = useDragDropManager();
  const rootRef = useRef<HTMLDivElement>(null);
  const rotated = useAppSelector((state) => state.inventory.dragRotated);

  const { data, isDragging } = useDragLayer((monitor) => ({
    data: monitor.getItem() as DragSource | null,
    isDragging: monitor.isDragging(),
  }));

  useEffect(() => {
    document.body.classList.toggle('inv-dragging', isDragging);
    return () => document.body.classList.remove('inv-dragging');
  }, [isDragging]);

  useLayoutEffect(() => {
    if (!isDragging) return;
    const monitor = manager.getMonitor();
    const el = rootRef.current;
    const apply = () => {
      const offset = monitor.getClientOffset();
      if (el && offset) {
        el.style.transform = `translate3d(${offset.x}px, ${offset.y}px, 0) translate(-50%, -50%)`;
      }
    };
    apply();
    return monitor.subscribeToOffsetChange(apply);
  }, [isDragging, manager]);

  if (!isDragging || !data?.item) return null;

  const size = getFootprint(Items[data.item.name]?.size, rotated ?? data.rotated);

  return (
    <div
      className="item-drag-preview"
      ref={rootRef}
      style={{
        backgroundImage: data.image,
        width: `calc(${size.width} * 10.2vh + ${size.width - 1} * 2px)`,
        height: `calc(${size.height} * 10.42vh + ${size.height - 1} * 2px)`,
        backgroundSize: 'contain',
      }}
    >
      <span className="item-drag-size">
        {size.width} × {size.height} · R
      </span>
    </div>
  );
};

export default DragPreview;
