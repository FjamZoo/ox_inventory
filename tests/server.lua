local temp = assert(arg[1])
local callbacks, exported, events = {}, {}, {}
local function noop() end
function table.clone(value) local result = {}; for k, v in pairs(value) do result[k] = v end; return result end
function table.deepclone(value)
    if type(value) ~= 'table' then return value end
    local result = {}; for k, v in pairs(value) do result[k] = table.deepclone(v) end; return result
end
function table.matches(a, b)
    if type(a) ~= 'table' or type(b) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not table.matches(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
table.contains = table.matches
table.create = function() return {} end
table.wipe = function(t) for k in pairs(t) do t[k] = nil end end
table.type = function(t) return type(t) == 'table' and 'array' or type(t) end
math.groupdigits = tostring
local definitions = {
    rifle = { name = 'rifle', size = { width = 4, height = 2 }, stack = false, weight = 100 },
    pistol = { name = 'pistol', size = { width = 2, height = 1 }, stack = false, weight = 50 },
    box = { name = 'box', size = { width = 2, height = 2 }, stack = true, weight = 10 },
    phone = { name = 'phone', size = { width = 1, height = 1 }, stack = true, weight = 1 },
    money = { name = 'money', size = { width = 1, height = 1 }, stack = true, weight = 0 },
    giant = { name = 'giant', size = { width = 6, height = 6 }, stack = false, weight = 0 },
}
for _, item in pairs(definitions) do item.label = item.name end
local metadataHook, eventHook, craftingHook
local Items = setmetatable({ containers = {} }, { __call = function(_, name) return definitions[name] end })
Items.Metadata = function(_, _, meta, count) if metadataHook then metadataHook() end; return meta, count end
Items.UpdateDurability = function() return false end
Items.CheckMetadata = function(metadata) return metadata end
package.loaded['modules.items.server'] = Items
package.loaded['modules.utils.server'] = { LogExploit = noop }
package.loaded['modules.hooks.server'] = function(name, payload)
    local success = not eventHook or eventHook(name, payload) ~= false
    return setmetatable({ success = success }, { __close = noop })
end
local recipes = { items = { { name = 'rifle', count = 1, ingredients = { phone = 1 } } } }
lib = { load = function(name) return name == 'data.crafting' and { test = recipes } or {} end,
    callback = { register = function(name, cb) callbacks[name] = cb end,
        await = function() if craftingHook then craftingHook() end; return true end },
    cron = { new = noop }, logger = noop, print = { error = error } }
shared = { playerweight = 10000, playerslots = 50, dropslots = 10, dropweight = 10000, police = {}, resource = 'ox_inventory' }
server = { loglevel = 0, accounts = {}, hasGroup = function() return true, 99 end }
db = { saveStash = noop, loadStash = function() return {} end }
json = { encode = table.deepclone, decode = table.deepclone }
function exports(name, fn) exported[name] = fn end
function TriggerClientEvent(name, ...) events[#events + 1] = { name, ... } end
TriggerEvent, CreateThread, SetTimeout, AddEventHandler, RegisterServerEvent, RegisterNetEvent, RegisterCommand = noop, noop, noop, noop, noop, noop, noop
function GetConvarInt(_, default) return default end
function GetInvokingResource() return 'tests' end
function GetPlayerPed(id) return id end
function Player() return { state = {} } end
function joaat() return -123 end
function locale(key) return key end
function GetEntityCoords() return setmetatable({}, { __sub = function() return setmetatable({}, { __len = function() return 0 end }) end }) end
local Inventory = assert(loadfile(temp .. '/modules/inventory/server.lua'))()
package.loaded['modules.inventory.server'] = Inventory
assert(loadfile(temp .. '/modules/shops/server.lua'))()
assert(loadfile(temp .. '/modules/crafting/server.lua'))()
local Grid = Inventory.Grid
local passed = 0
local function check(name, fn)
    metadataHook, eventHook, craftingHook = nil, nil, nil
    local ok, reason = pcall(fn)
    if not ok then error(name .. ': ' .. tostring(reason), 0) end
    passed = passed + 1; print('PASS ' .. name)
end
local id = 100
local function inv(slots, weight)
    id = id + 1
    local result = Inventory.Create(id, 'test', 'stash', slots or 20, 0, weight or 10000, false, {})
    result.player, result.type, result.open = { ped = id }, 'player', id
    return result
end
local function add(target, name, slot, count, rotated)
    local ok, result = Inventory.AddItem(target, name, count or 1, {}, slot, nil, rotated)
    assert(ok, result); return result
end
local function move(source, destination, from, to, count, rotated)
    source.open = destination.id
    return callbacks['ox_inventory:swapItems'](source.id, { fromType = 'player', toType = source == destination and 'player' or 'stash', fromSlot = from, toSlot = to, count = count or 1, rotated = rotated })
end
local function valid(target)
    for slot, item in pairs(target.items) do
        if slot <= target.slots then assert(Grid.fits(target, item, slot, item.rotated, { [slot] = true })) end
    end
    assert(target.weight == Inventory.CalculateWeight(target.items))
end

check('defaults and invalid size definitions', function()
    local w, h = Grid.size({}); assert(w == 1 and h == 1)
    w, h = Grid.size({ size = { 4, 2 } }, true); assert(w == 2 and h == 4)
    w, h = Grid.size({ size = { width = -1, height = 2 } }); assert(w == 1 and h == 1)
end)
check('edges, partial rows, narrow inventories and malformed anchors', function()
    local target = inv(12)
    assert(not Grid.fits(target, definitions.pistol, 5))
    assert(not Grid.fits(target, definitions.box, 7))
    assert(Grid.fits(target, definitions.pistol, 11))
    for _, slot in ipairs({ 0, -1, 1.5, math.huge, 0/0, '1' }) do assert(not Grid.fits(target, definitions.phone, slot)) end
    assert(not Grid.fits(inv(1), definitions.pistol, 1))
end)
check('AddItem prevents covered anchors and partial additions', function()
    local target = inv(10); add(target, 'rifle', 1)
    assert(not Inventory.AddItem(target, 'phone', 2, {}, 2))
    assert(not Inventory.AddItem(target, 'pistol', 2))
    assert(Inventory.GetItemCount(target, 'pistol') == 0)
    assert(Inventory.GetEmptySlot(target) == 5)
    valid(target)
end)
check('non-stackable copies are individually packed', function()
    local target = inv(10); assert(Inventory.AddItem(target, 'pistol', 4))
    assert(Inventory.GetItemCount(target, 'pistol') == 4); valid(target)
end)
check('weight, metadata weight, zero-weight and capacity exports', function()
    local target = inv(10, 99)
    assert(not Inventory.AddItem(target, 'rifle', 1)); assert(not Inventory.CanCarryItem(target, 'rifle', 1))
    assert(Inventory.CanCarryAmount(target, 'pistol') == 1)
    assert(not Inventory.CanCarryItem(target, 'phone', 1, { weight = 100 }))
    assert(Inventory.CanCarryAmount(target, 'money') == 2147483647)
    assert(Inventory.AddItem(target, 'money', 100)); valid(target)
end)
check('stacking preserves orientation and consumes one rectangle', function()
    local target = inv(10); add(target, 'box', 1, 2, true); add(target, 'box', 1, 3)
    assert(target.items[1].count == 5 and target.items[1].rotated)
    assert(Inventory.CanCarryItem(target, 'box', 2)); valid(target)
end)
check('full moves may overlap their former footprint, splits may not', function()
    local target = inv(20); add(target, 'box', 1, 4)
    assert(not move(target, target, 1, 2, 2))
    assert(move(target, target, 1, 2, 4)); assert(not target.items[1]); valid(target)
    assert(move(target, target, 2, 11, 2)); valid(target)
end)
check('rotation in place and cross-inventory rotation', function()
    local a, b = inv(20), inv(20); add(a, 'rifle', 1)
    assert(move(a, a, 1, 1, 1, true)); assert(a.items[1].rotated); valid(a)
    assert(move(a, b, 1, 3, 1, true)); assert(b.items[3].rotated); valid(a); valid(b)
end)
check('rotations into occupied cells are rejected', function()
    local target = inv(20); add(target, 'pistol', 1); add(target, 'phone', 6)
    assert(not move(target, target, 1, 1, 1, true)); valid(target)
end)
check('swaps validate both destination rectangles and weight', function()
    local a, b = inv(20), inv(20); add(a, 'rifle', 1); add(b, 'pistol', 1); add(b, 'phone', 6)
    assert(not move(a, b, 1, 1)); valid(a); valid(b)
    Inventory.RemoveItem(b, 'phone', 1)
    assert(move(a, b, 1, 1)); valid(a); valid(b)
end)
check('swapped rectangles cannot intersect each other', function()
    local target = inv(10); add(target, 'pistol', 2); add(target, 'phone', 1)
    assert(not move(target, target, 1, 2)); valid(target)
end)
check('metadata hooks changing layout are included in the final plan', function()
    local target = inv(10)
    metadataHook = function() metadataHook = nil; add(target, 'phone', 2) end
    assert(not Inventory.AddItem(target, 'rifle', 1, {}, 1)); assert(target.items[2]); valid(target)
end)
check('swap hooks cannot insert a blocker after validation', function()
    local a, b = inv(20), inv(20); add(a, 'rifle', 1)
    eventHook = function(name) if name == 'swapItems' then eventHook = nil; add(b, 'phone', 2) end end
    assert(not move(a, b, 1, 1)); assert(a.items[1]); valid(a); valid(b)
end)
check('saved collisions repack and overflow remains recoverable', function()
    local target = inv(10)
    target.items = {
        [1] = { name = 'rifle', slot = 1, count = 1, weight = 100, metadata = { serial = 'keep' } },
        [2] = { name = 'rifle', slot = 2, count = 1, weight = 100, metadata = { serial = 'overflow' } },
        [3] = { name = 'phone', slot = 3, count = 9, weight = 9, metadata = {} },
    }
    target.weight = 209; Grid.migrate(target, Items)
    assert(target.items[1].name == 'rifle' and target.items[5].name == 'phone')
    assert(target.items[11].metadata.serial == 'overflow')
    assert(not Inventory.AddItem(target, 'phone', 1, {}, 11)); valid(target)
    local saved = target:minimal(); local restored = {}
    for _, item in ipairs(saved) do restored[item.slot] = item end
    target.items = restored; Grid.migrate(target, Items)
    assert(target.items[11].metadata.serial == 'overflow')
    local destination = inv(20); assert(move(target, destination, 11, 1)); assert(destination.items[1].metadata.serial == 'overflow')
end)
check('rotation persists through all save/load paths', function()
    local target = inv(20); add(target, 'rifle', 1, 1, true)
    assert(target:minimal()[1].rotated)
    local saved
    target.player = nil; db.saveStash = function(_, _, value) saved = value end
    Inventory.Save(target); assert(saved[1].rotated)
    db.loadStash = function() return saved end
    local items = Inventory.Load('test', 'stash'); assert(items[1].rotated)
end)
check('CanSwapItem simulates freed cells; shrinking cannot strand items', function()
    local target = inv(10); add(target, 'rifle', 1)
    assert(Inventory.CanSwapItem(target, 'rifle', 1, 'pistol', 4))
    assert(not Inventory.CanSwapItem(target, 'rifle', 1, 'rifle', 2))
    assert(Inventory.SetSlotCount(target, 5) == false and target.slots == 10)
end)
check('giving fails without space and succeeds with an automatic rotation', function()
    local a, b = inv(20), inv(20); add(a, 'rifle', 1)
    for _, slot in ipairs({ 3, 8, 13, 18 }) do add(b, 'phone', slot) end
    assert(callbacks['ox_inventory:giveItem'](a.id, 1, b.id, 1) == nil)
    assert(b.items[1].name == 'rifle' and b.items[1].rotated); valid(a); valid(b)
end)
check('new drops reject invalid destination rectangles', function()
    local a = inv(20); add(a, 'rifle', 1)
    local data = { fromType = 'player', toType = 'newdrop', fromSlot = 1, toSlot = 4, count = 1 }
    assert(not callbacks['ox_inventory:swapItems'](a.id, data)); assert(a.items[1]); valid(a)
    data.toSlot = 1; assert(callbacks['ox_inventory:swapItems'](a.id, data)); assert(not a.items[1]); valid(a)
end)
check('shop purchase validates cells before charging and decrementing stock', function()
    local target = inv(10); add(target, 'money', 5, 100); add(target, 'phone', 2)
    server.shops.test = { items = { { name = 'rifle', price = 10, count = 2 } } }
    target.currentShop = 'test'
    local request = { fromSlot = 1, toSlot = 1, toType = 'player', count = 1 }
    assert(not callbacks['ox_inventory:buyItem'](target.id, request))
    assert(target.items[5].count == 100 and server.shops.test.items[1].count == 2)
    Inventory.RemoveItem(target, 'phone', 1)
    assert(callbacks['ox_inventory:buyItem'](target.id, request)); assert(target.items[5].count == 90); valid(target)
end)
check('craft output uses freed ingredient cells atomically', function()
    local target = inv(10); add(target, 'phone', 1)
    assert(callbacks['ox_inventory:craftItem'](target.id, 'test', 1, 1, 1, false))
    assert(target.items[1].name == 'rifle' and Inventory.GetItemCount(target, 'phone') == 0); valid(target)
end)
check('failed crafting leaves ingredients and durability intact', function()
    local target = inv(10); add(target, 'phone', 1); add(target, 'pistol', 2)
    local before = table.deepclone(target.items)
    assert(not callbacks['ox_inventory:craftItem'](target.id, 'test', 1, 1, 1, false))
    assert(table.matches(before, target.items)); valid(target)
end)
check('craft progress race does not consume replacement ingredients', function()
    local target = inv(10); add(target, 'phone', 1)
    craftingHook = function() target.items[1].metadata.changed = true end
    assert(not callbacks['ox_inventory:craftItem'](target.id, 'test', 1, 1, 1, false))
    assert(target.items[1].name == 'phone'); valid(target)
end)
check('malicious move fields are rejected', function()
    local target = inv(20); add(target, 'rifle', 1)
    for _, field in ipairs({ 'fromSlot', 'toSlot', 'count', 'rotated' }) do
        local request = { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 11, count = 1 }
        request[field] = 'invalid'
        assert(not callbacks['ox_inventory:swapItems'](target.id, request))
    end
    valid(target)
end)
check('incoming stacks keep an unrotated destination unrotated', function()
    local target = inv(10); add(target, 'box', 1, 2, false)
    assert(Inventory.SetSlot(target, definitions.box, 1, {}, 1, true))
    assert(target.items[1].rotated == false); valid(target)
end)
check('an explicit anchor can automatically rotate when orientation is omitted', function()
    local target = inv(20)
    for _, slot in ipairs({ 3, 8, 13, 18 }) do add(target, 'phone', slot) end
    local slot = Inventory.GetSlotForItem(target, 'rifle', {})
    assert(Inventory.AddItem(target, 'rifle', 1, {}, slot)); assert(target.items[slot].rotated); valid(target)
end)
check('generated drops and temporary stashes reject oversized contents', function()
    local drop, reason = exported.CustomDrop('test', { { 'rifle', 1 } }, {}, 5, 10000)
    assert(not drop and reason == 'inventory_full')
    assert(not Inventory.CreateTemporaryStash({ label = 'test', slots = 5, maxWeight = 10000, items = { { 'rifle', 1 } } }))
    local good = exported.CustomDrop('test', { { 'rifle', 1 }, { 'phone', 2 } }, {}, 10, 10000)
    assert(good); valid(Inventory(good))
end)
check('hooks that change unrelated weight invalidate pending moves', function()
    local a, b = inv(20), inv(20, 100); add(a, 'rifle', 1)
    eventHook = function(name) if name == 'swapItems' then eventHook = nil; add(b, 'phone', 20) end end
    assert(not move(a, b, 1, 1)); assert(a.items[1]); valid(a); valid(b)
end)
check('failed purchases restore stock when hooks block the target', function()
    local target = inv(20); add(target, 'money', 20, 100)
    server.shops.test = { items = { { name = 'rifle', price = 10, count = 2 } } }; target.currentShop = 'test'
    eventHook = function(name) if name == 'buyItem' then eventHook = nil; add(target, 'phone', 2) end end
    assert(not callbacks['ox_inventory:buyItem'](target.id, { fromSlot = 1, toSlot = 1, toType = 'player', count = 1 }))
    assert(target.items[20].count == 100 and server.shops.test.items[1].count == 2); valid(target)
end)
check('craft metadata-hook changes do not consume ingredients', function()
    local target = inv(10); add(target, 'phone', 1)
    metadataHook = function() metadataHook = nil; add(target, 'pistol', 2) end
    assert(not callbacks['ox_inventory:craftItem'](target.id, 'test', 1, 1, 1, false))
    assert(target.items[1].name == 'phone'); valid(target)
end)
check('crafting retains required tools and rejects missing ones', function()
    recipes.items[2] = { name = 'phone', count = 1, ingredients = { box = 1, pistol = 0 } }
    local target = inv(20); add(target, 'box', 1)
    assert(not callbacks['ox_inventory:craftItem'](target.id, 'test', 1, 2, 1, false))
    add(target, 'pistol', 11)
    assert(callbacks['ox_inventory:craftItem'](target.id, 'test', 1, 2, 1, false))
    assert(target.items[11].name == 'pistol' and target.items[1].name == 'phone'); valid(target)
end)
check('crafting durability splits reserve a second full rectangle', function()
    recipes.items[3] = { name = 'phone', count = 1, ingredients = { box = .25 } }
    local target = inv(10); add(target, 'box', 1, 2); target.items[1].metadata.durability = 100
    assert(callbacks['ox_inventory:craftItem'](target.id, 'test', 1, 3, 5, false))
    assert(target.items[1].count == 1 and target.items[1].metadata.durability == 100)
    assert(target.items[3].count == 1 and target.items[3].metadata.durability == 75); valid(target)
    local full = inv(5); add(full, 'pistol', 1)
    definitions.pistol.stack = true
    full.items[1].count, full.items[1].weight, full.weight = 2, 100, 100
    full.items[1].metadata.durability = 100
    recipes.items[4] = { name = 'box', count = 1, ingredients = { pistol = .25 } }
    assert(not callbacks['ox_inventory:craftItem'](full.id, 'test', 1, 4, 3, false))
    assert(full.items[1].count == 2 and full.items[1].metadata.durability == 100)
    definitions.pistol.stack = false
end)
check('moving contents out of an owned container does not double-count weight', function()
    definitions.bag = { name = 'bag', label = 'bag', stack = false, weight = 0, size = { width = 1, height = 1 } }
    local player, container = inv(20, 100), inv(20)
    container.player, container.type = nil, 'container'
    add(container, 'rifle', 1)
    assert(Inventory.AddItem(player, 'bag', 1, { container = container.id, weight = 100 }, 5))
    player.open, player.containerSlot = container.id, 5
    assert(callbacks['ox_inventory:swapItems'](player.id, { fromType = 'container', toType = 'player', fromSlot = 1, toSlot = 1, count = 1 }))
    assert(player.weight == 100 and container.weight == 0); valid(player); valid(container)
end)
check('randomized moves, swaps, splits and rotations conserve all items', function()
    math.randomseed(48201)
    local a, b = inv(40), inv(40)
    add(a, 'rifle', 1); add(a, 'box', 11, 6); add(a, 'phone', 15, 20)
    add(b, 'pistol', 1); add(b, 'box', 11, 4); add(b, 'phone', 20, 10)
    local function totals()
        local result = {}
        for _, target in ipairs({ a, b }) do
            for _, item in pairs(target.items) do result[item.name] = (result[item.name] or 0) + item.count end
        end
        return result
    end
    local initial = totals()
    for _ = 1, 1000 do
        local from = math.random(2) == 1 and a or b
        local to = math.random(2) == 1 and a or b
        local keys = {}; for key in pairs(from.items) do keys[#keys + 1] = key end
        if #keys > 0 then
            local slot = keys[math.random(#keys)]
            move(from, to, slot, math.random(40), math.random(from.items[slot].count), math.random(2) == 1)
            valid(a); valid(b); assert(table.matches(initial, totals()))
        end
    end
end)
print(('%d server regression tests passed'):format(passed))
