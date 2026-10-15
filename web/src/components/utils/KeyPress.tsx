import { useEffect } from 'react';
import { setDragRotated, setShiftPressed } from '../../store/inventory';
import useKeyPress from '../../hooks/useKeyPress';
import { useAppDispatch } from '../../store';
import { useDragDropManager } from 'react-dnd';
import { DragSource } from '../../typings';

const KeyPress: React.FC = () => {
  const dispatch = useAppDispatch();
  const manager = useDragDropManager();
  const shiftPressed = useKeyPress('Shift');

  useEffect(() => {
    dispatch(setShiftPressed(shiftPressed));
  }, [shiftPressed, dispatch]);

  useEffect(() => {
    const rotate = (event: KeyboardEvent) => {
      if (event.code !== 'KeyR' || event.repeat || !manager.getMonitor().isDragging()) return;
      const source: DragSource | null = manager.getMonitor().getItem();
      if (!source) return;
      event.preventDefault();
      source.rotated = !source.rotated;
      dispatch(setDragRotated(source.rotated));
    };
    window.addEventListener('keydown', rotate);
    return () => window.removeEventListener('keydown', rotate);
  }, [manager, dispatch]);

  return <></>;
};

export default KeyPress;
