import InventoryComponent from './components/inventory';
import useNuiEvent from './hooks/useNuiEvent';
import { Items } from './store/items';
import { Locale } from './store/locale';
import { setImagePath } from './store/imagepath';
import { setupInventory } from './store/inventory';
import { Inventory } from './typings';
import { useAppDispatch } from './store';
import { debugData } from './utils/debugData';
import DragPreview from './components/utils/DragPreview';
import { fetchNui, setNuiFixture } from './utils/fetchNui';
import { isEnvBrowser } from './utils/misc';
import { createBrowserFixture, fixtureInventories, fixtureItems } from './utils/browserFixture';
import { useDragDropManager } from 'react-dnd';
import KeyPress from './components/utils/KeyPress';

if (import.meta.env.DEV && isEnvBrowser()) {
  Object.assign(Items, fixtureItems);
  setNuiFixture(
    createBrowserFixture(fixtureInventories, new URLSearchParams(window.location.search).get('fixture') === 'accept')
  );
  debugData([{ action: 'setupInventory', data: fixtureInventories }]);
}

const App: React.FC = () => {
  const dispatch = useAppDispatch();
  const manager = useDragDropManager();

  useNuiEvent<{
    locale: { [key: string]: string };
    items: typeof Items;
    leftInventory: Inventory;
    imagepath: string;
  }>('init', ({ locale, items, leftInventory, imagepath }) => {
    for (const name in locale) Locale[name] = locale[name];
    for (const name in items) Items[name] = items[name];

    setImagePath(imagepath);
    dispatch(setupInventory({ leftInventory }));
  });

  fetchNui('uiLoaded', {});

  useNuiEvent('closeInventory', () => {
    manager.dispatch({ type: 'dnd-core/END_DRAG' });
  });

  return (
    <div className="app-wrapper">
      <InventoryComponent />
      <DragPreview />
      <KeyPress />
    </div>
  );
};

addEventListener('dragstart', function (event) {
  event.preventDefault();
});

export default App;
