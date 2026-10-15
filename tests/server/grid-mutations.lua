return function(context)
    local Fixture, test, equal, slot = context.Fixture, context.test, context.equal, context.slot

    for _, method in ipairs({ 'GetSlot', 'GetSlotWithItem', 'GetSlotsWithItem', 'Save', 'SaveInventories' }) do
        test(method .. ' observes committed durability after an expired nondecaying item updates', function()
            local fixture = Fixture.new(context.root, { realItems = true, items = {
                food = { name = 'food', label = 'Food', weight = 100, stack = true, degrade = 10, decay = false },
            } })
            local inventory = fixture:player(1)
            equal(fixture.exports.AddItem(1, 'food', 1, { durability = os.time() - 100, degrade = 10 }, 1), true)
            local observed
            if method == 'Save' or method == 'SaveInventories' then
                if method == 'Save' then fixture.Inventory.Save(inventory) else fixture.Inventory.SaveInventories(false, false) end
                observed = fixture:decode(fixture.persisted.player['player-1'])[1]
            elseif method == 'GetSlot' then observed = fixture.exports.GetSlot(1, 1)
            else
                observed = fixture.exports[method](1, 'food')
                if method == 'GetSlotsWithItem' then observed = observed[1] end
            end
            equal({ observed.metadata.durability, inventory.items[1].metadata.durability }, { 0, 0 })
        end)
    end

    test('metadata weight removal recalculates the entire slot weight', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('metadata')
        equal(fixture.exports.AddItem(inventory.id, 'water', 1, { weight = 100 }, 1), true)
        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 2), true)
        equal(fixture.exports.SetMetadata(inventory.id, 1, {}), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
            { name = 'water', slot = 1, count = 1, weight = 250, metadata = {} },
            { name = 'phone', slot = 2, count = 1, weight = 100, metadata = {} }, 350,
        })
    end)

    test('overweight metadata replacement leaves the original metadata intact', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('metadata-cap', 'stash', 30, 500)
        equal(fixture.exports.AddItem(inventory.id, 'water', 1, nil, 1), true)
        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 2), true)
        equal(fixture.exports.SetMetadata(inventory.id, 1, { weight = 300 }), false)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
            { name = 'water', slot = 1, count = 1, weight = 250, metadata = {} },
            { name = 'phone', slot = 2, count = 1, weight = 100, metadata = {} }, 350,
        })
    end)

    test('CanSwapItem uses both freed space and retained source occupancy', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('can-swap', 'stash', 10)
        equal(fixture.exports.AddItem(inventory.id, 'water', 2, nil, 1), true)
        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 5), true)
        equal(fixture.exports.CanSwapItem(inventory.id, 'water', 1, 'rifle', 1), false)
        equal(fixture.exports.CanSwapItem(inventory.id, 'water', 2, 'rifle', 1), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[5]), inventory.weight }, {
            { name = 'water', slot = 1, count = 2, weight = 500, metadata = {} },
            { name = 'phone', slot = 5, count = 1, weight = 100, metadata = {} }, 600,
        })
    end)

    test('SetItem growth cannot publish a partial non-stack batch', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:inventory('set-item', 'stash', 10)
        equal(fixture.exports.AddItem(inventory.id, 'phone', 1, nil, 5), true)
        equal(fixture.exports.SetItem(inventory.id, 'rifle', 2), false)
        equal({ slot(inventory.items[5]), fixture.exports.GetItemCount(inventory.id, 'rifle'), inventory.weight }, {
            { name = 'phone', slot = 5, count = 1, weight = 100, metadata = {} }, 0, 100,
        })
    end)

    test('updating a registered stash reconciles its existing occupants', function()
        local fixture = Fixture.new(context.root)
        fixture.exports.RegisterStash('registered', 'Registered', 30, 30000)
        local inventory = fixture.exports.GetInventory('registered')
        equal(fixture.exports.AddItem(inventory.id, 'rifle', 2), true)
        fixture.exports.RegisterStash('registered', 'Registered', 10, 30000)
        equal({ inventory.slots, inventory.grid, inventory.weight, #inventory.recovery, fixture.exports.GetItemCount(inventory.id, 'rifle') }, {
            10, { columns = 5, cells = 10 }, 8000, 1, 1,
        })
    end)

    test('custom drop construction preserves excess generated items in recovery', function()
        local fixture = Fixture.new(context.root)
        local id = fixture.exports.CustomDrop('Fixture', { { 'rifle', 1 }, { 'rifle', 1 } }, vector3(0, 0, 0), 10, 30000)
        local inventory = fixture.exports.GetInventory(id)
        equal({ slot(inventory.items[1]), inventory.weight, #inventory.recovery, inventory.recovery[1].record.name }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, 8000, 1, 'rifle',
        })
    end)

    test('temporary stash construction preserves excess generated items in recovery', function()
        local fixture = Fixture.new(context.root)
        local id = fixture.exports.CreateTemporaryStash({ label = 'Fixture', slots = 10, maxWeight = 30000, items = { { 'rifle', 1 }, { 'rifle', 1 } } })
        local inventory = fixture.exports.GetInventory(id)
        equal({ slot(inventory.items[1]), inventory.weight, #inventory.recovery, inventory.recovery[1].record.name }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, 8000, 1, 'rifle',
        })
    end)

    test('real createItem hook mutation rejects a stale outer AddItem', function()
        local fixture = Fixture.new(context.root, { realItems = true })
        local inventory = fixture:inventory('create-hook')
        fixture:addHook('createItem', function() equal(fixture.exports.AddItem(inventory.id, 'water', 1, nil, 5), true) end, { itemFilter = { rifle = true } })
        equal(fixture.exports.AddItem(inventory.id, 'rifle', 1, nil, 1), false)
        equal({ slot(inventory.items[1]), slot(inventory.items[5]), inventory.weight }, {
            false, { name = 'water', slot = 5, count = 1, weight = 250, metadata = {} }, 250,
        })
    end)

    test('real item metadata is generated once across craft preflight and completion', function()
        local fixture = Fixture.new(context.root, { realItems = true, data = { ['data.crafting'] = {
            workbench = { items = { { name = 'phone', count = 1, ingredients = { scrap = 2 } } } },
        } } })
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'scrap', 2, nil, 1), true)
        local generated = 0
        fixture:addHook('createItem', function()
            generated += 1
            return { generation = generated }
        end, { itemFilter = { phone = true } })
        equal(fixture:call('ox_inventory:craftItem', 1, 'workbench', 1, 1, 1), true)
        equal({ slot(inventory.items[1]), inventory.weight, generated }, {
            { name = 'phone', slot = 1, count = 1, weight = 100, metadata = { generation = 1 } }, 100, 1,
        })
    end)

    test('real durability mutation survives stale outer move rejection', function()
        local fixture = Fixture.new(context.root, { realItems = true })
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'water', 2, { durability = 100 }, 1), true)
        fixture:addHook('swapItems', function() fixture.exports.SetDurability(1, 1, 75) end)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'player', fromSlot = 1, toSlot = 2, count = 1 }), false)
        equal({ slot(inventory.items[1]), slot(inventory.items[2]), inventory.weight }, {
            { name = 'water', slot = 1, count = 2, weight = 500, metadata = { durability = 75 } }, false, 500,
        })
    end)

    test('root item use splits durability with item-aware rotated placement', function()
        local fixture = Fixture.new(context.root, { realItems = true, loadServer = true, items = {
            tool = { name = 'tool', label = 'Tool', weight = 100, stack = true, consume = 0.25, size = { width = 2, height = 1 } },
        } })
        local inventory = fixture:player(1, 10)
        equal(fixture.exports.AddItem(1, 'tool', 2, { durability = 100 }, 1, nil, true), true)
        equal(fixture.exports.AddItem(1, 'phone', 1, nil, 2), true)
        fixture.await['ox_inventory:usingItem'] = function() return true end
        equal(fixture:call('ox_inventory:useItem', 1, 'tool', 1), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[3]), inventory.items[3].rotated, inventory.weight }, {
            { name = 'tool', slot = 1, count = 1, weight = 100, metadata = { durability = 100 } },
            { name = 'tool', slot = 3, count = 1, weight = 100, metadata = { durability = 75 } }, true, 300,
        })
    end)

    test('root item use refuses a durability split when no rectangle fits', function()
        local fixture = Fixture.new(context.root, { realItems = true, loadServer = true, items = {
            tool = { name = 'tool', label = 'Tool', weight = 100, stack = true, consume = 0.25, size = { width = 2, height = 2 } },
        } })
        local inventory = fixture:player(1, 10)
        equal(fixture.exports.AddItem(1, 'tool', 2, { durability = 100 }, 1), true)
        for _, anchor in ipairs({ 3, 4, 5, 8, 9, 10 }) do equal(fixture.exports.AddItem(1, 'phone', 1, nil, anchor), true) end
        local progress = 0
        fixture.await['ox_inventory:usingItem'] = function() progress += 1 return true end
        fixture:call('ox_inventory:useItem', 1, 'tool', 1)
        equal({ slot(inventory.items[1]), fixture.exports.GetItemCount(1, 'phone'), progress, inventory.weight }, {
            { name = 'tool', slot = 1, count = 2, weight = 200, metadata = { durability = 100 } }, 6, 0, 800,
        })
    end)

    test('root item use accepts unrelated inventory changes during progress', function()
        local fixture = Fixture.new(context.root, { realItems = true, loadServer = true, items = {
            food = { name = 'food', label = 'Food', weight = 100, stack = true, consume = 1 },
        } })
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'food', 2, nil, 1), true)
        fixture.await['ox_inventory:usingItem'] = function()
            equal(fixture.exports.AddItem(1, 'water', 1, nil, 5), true)
            return true
        end
        equal(fixture:call('ox_inventory:useItem', 1, 'food', 1), true)
        equal({ slot(inventory.items[1]), slot(inventory.items[5]), inventory.weight }, {
            { name = 'food', slot = 1, count = 1, weight = 100, metadata = {} },
            { name = 'water', slot = 5, count = 1, weight = 250, metadata = {} }, 350,
        })
    end)

    test('root item use rejects changed source ownership during progress', function()
        local fixture = Fixture.new(context.root, { realItems = true, loadServer = true, items = {
            food = { name = 'food', label = 'Food', weight = 100, stack = true, consume = 1 },
        } })
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'food', 2, nil, 1), true)
        fixture.await['ox_inventory:usingItem'] = function()
            equal(fixture.exports.RemoveItem(1, 'food', 1, nil, 1), true)
            return true
        end
        equal(fixture:call('ox_inventory:useItem', 1, 'food', 1), false)
        equal({ slot(inventory.items[1]), inventory.weight }, {
            { name = 'food', slot = 1, count = 1, weight = 100, metadata = {} }, 100,
        })
    end)

    test('weapon loading accepts the existing false slot sentinel and conserves ammunition weight', function()
        local fixture = Fixture.new(context.root, { realItems = true, items = {
            WEAPON_TEST = { name = 'WEAPON_TEST', label = 'Weapon', weight = 1000, stack = false, weapon = true, ammoname = 'ammo-test', durability = 0.1, size = { width = 2, height = 1 } },
            ['ammo-test'] = { name = 'ammo-test', label = 'Ammo', weight = 10, stack = true, ammo = true },
        } })
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'WEAPON_TEST', 1, { ammo = 0, durability = 100, registered = false }, 1, nil, true), true)
        equal(fixture.exports.AddItem(1, 'ammo-test', 5, { type = 'ap' }, 3), true)
        inventory.weapon = 1
        equal(fixture:call('ox_inventory:updateWeapon', 1, 'load', 3, false, 'ap'), true)
        equal({ inventory.items[1].metadata.ammo, inventory.items[1].metadata.specialAmmo, inventory.items[1].rotated, slot(inventory.items[3]), inventory.weight }, {
            3, 'ap', true, { name = 'ammo-test', slot = 3, count = 2, weight = 20, metadata = { type = 'ap' } }, 1050,
        })
        equal(fixture:call('ox_inventory:updateWeapon', 1, 'load', 6, false, 'ap'), false)
        equal({ inventory.items[1].metadata.ammo, inventory.items[3].count, inventory.weight }, { 3, 2, 1050 })
        equal(fixture:call('ox_inventory:removeAmmoFromWeapon', 1, 1), true)
        equal({ inventory.items[1].metadata.ammo, inventory.items[1].rotated, slot(inventory.items[3]), inventory.weight }, {
            0, true, { name = 'ammo-test', slot = 3, count = 5, weight = 50, metadata = { type = 'ap' } }, 1050,
        })
    end)

    test('exported container mutations include carried owner weight', function()
        local fixture = Fixture.new(context.root, { items = { bag = { name = 'bag', label = 'Bag', weight = 100, stack = false } } })
        fixture.Items.containers.bag = {}
        local player = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'bag', 1, { container = 'exported-bag', size = { 10, 2000 } }, 1), true)
        local container = fixture:inventory('exported-bag', 'container', 10, 2000)
        equal(fixture.exports.AddItem(container.id, 'water', 1, nil, 1), true)
        equal({ container.weight, player.items[1].metadata.weight, player.items[1].weight, player.weight }, { 250, 250, 350, 350 })
        equal(fixture.exports.SetMetadata(container.id, 1, { weight = 100 }), true)
        equal({ container.weight, player.items[1].metadata.weight, player.items[1].weight, player.weight }, { 350, 350, 450, 450 })
        equal(fixture.exports.RemoveItem(container.id, 'water', 1, nil, 1), true)
        equal({ container.weight, player.items[1].metadata.weight, player.items[1].weight, player.weight }, { 0, 0, 100, 100 })
    end)

    test('exported container acquisition rejects its carried owner weight cap', function()
        local fixture = Fixture.new(context.root, { items = { bag = { name = 'bag', label = 'Bag', weight = 100, stack = false } } })
        fixture.Items.containers.bag = {}
        local player = fixture:player(1, 30, 600)
        equal(fixture.exports.AddItem(1, 'bag', 1, { container = 'capped-bag', size = { 10, 2000 } }, 1), true)
        local container = fixture:inventory('capped-bag', 'container', 10, 2000)
        equal(fixture.exports.AddItem(container.id, 'water', 3), false)
        equal({ fixture.exports.GetItemCount(container.id, 'water'), container.weight, player.items[1].weight, player.weight }, { 0, 0, 100, 100 })
    end)

    test('exported container mutation invalidates a stale proposal involving its owner', function()
        local fixture = Fixture.new(context.root, { items = { bag = { name = 'bag', label = 'Bag', weight = 100, stack = false } } })
        fixture.Items.containers.bag = {}
        local player = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'bag', 1, { container = 'revision-bag', size = { 10, 2000 } }, 1), true)
        equal(fixture.exports.AddItem(1, 'water', 1, nil, 2), true)
        local container = fixture:inventory('revision-bag', 'container', 10, 2000)
        local target = fixture:inventory('owner-hook-target')
        player:openInventory(target)
        fixture:addHook('swapItems', function() equal(fixture.exports.AddItem(container.id, 'water', 1, nil, 1), true) end)
        equal(fixture:call('ox_inventory:swapItems', 1, { fromType = 'player', toType = 'stash', fromSlot = 2, toSlot = 1, count = 1 }), false)
        equal({ slot(player.items[2]), slot(container.items[1]), slot(target.items[1]), player.items[1].weight, player.weight, container.weight }, {
            { name = 'water', slot = 2, count = 1, weight = 250, metadata = {} },
            { name = 'water', slot = 1, count = 1, weight = 250, metadata = {} }, false, 350, 600, 250,
        })
    end)
end
