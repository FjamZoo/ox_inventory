import React, { useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useDragLayer, useDragDropManager } from 'react-dnd';
import { dimensions } from '../../helpers/grid';
import { DragSource } from '../../typings';

const DragPreview: React.FC = () => {
  const manager = useDragDropManager();
  const [, rerender] = useState(0);
  const rootRef = useRef<HTMLDivElement>(null);

  // Only collect item/isDragging here, so we re-render on drag start/end rather than
  // on every pointer move.
  const { data, isDragging } = useDragLayer((monitor) => ({
    data: monitor.getItem() as DragSource | null,
    isDragging: monitor.isDragging(),
  }));

  useEffect(() => {
    document.body.classList.toggle('inv-dragging', isDragging);
    return () => document.body.classList.remove('inv-dragging');
  }, [isDragging]);

  useEffect(() => {
    if (!isDragging || !data) return;
    const rotate = (event: KeyboardEvent) => {
      if (event.code !== 'KeyR' || event.repeat) return;
      event.preventDefault();
      data.rotated = !data.rotated;
      rerender((value) => value + 1);
      window.dispatchEvent(new Event('inventory:rotate'));
    };
    window.addEventListener('keydown', rotate);
    return () => window.removeEventListener('keydown', rotate);
  }, [isDragging, data]);

  // Write the position straight to the node so the preview tracks the cursor 1:1
  // instead of lagging a render behind it.
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

  const { width, height } = dimensions({ slot: 1, size: data.size, rotated: data.rotated });
  return (
    <div
      className="item-drag-preview"
      ref={rootRef}
      style={{
        width: `calc(${width} * 10.2vh + ${width - 1} * 2px)`,
        height: `calc(${height} * 10.42vh + ${height - 1} * 2px)`,
      }}
    >
      <div
        style={{
          position: 'absolute',
          left: '50%',
          top: '50%',
          backgroundImage: data.image,
          backgroundSize: 'contain',
          backgroundPosition: 'center',
          backgroundRepeat: 'no-repeat',
          width: data.rotated ? `calc(${height} * 10.42vh + ${height - 1} * 2px)` : '100%',
          height: data.rotated ? `calc(${width} * 10.2vh + ${width - 1} * 2px)` : '100%',
          transform: `translate(-50%, -50%) rotate(${data.rotated ? 90 : 0}deg)`,
        }}
      />
    </div>
  );
};

export default DragPreview;
