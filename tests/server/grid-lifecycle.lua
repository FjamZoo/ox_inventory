return function(context)
    local Fixture, test, equal = context.Fixture, context.test, context.equal
    local Bridge = assert(loadfile(context.root .. '/tests/server/bridge-fixture.lua'))()

    for _, framework in ipairs({ 'nd', 'qbx' }) do
        for _, operation in ipairs({ 'confiscatePlayer', 'restorePlayer' }) do
            test(framework .. ' disconnect during ' .. operation .. ' releases committed ownership', function()
                local fixture = Bridge.new(context.root, Fixture, framework)
                local inventory = fixture:frameworkPlayer(1)
                equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
                if operation == 'restorePlayer' then equal(fixture.exports.ConfiscateInventory(1), true) end
                local transaction = fixture.env.db[operation]
                fixture.env.db[operation] = function(owner, payload)
                    fixture.frameworkPlayers[1] = nil
                    fixture.env.server.playerDropped(1)
                    return transaction(owner, payload)
                end
                local result
                if operation == 'restorePlayer' then result = fixture.exports.ReturnInventory(1)
                else result = fixture.exports.ConfiscateInventory(1) end
                equal(result, true)
                equal({ inventory.storageBusy or false, inventory.removeAfterStorage or false, #fixture.exports.GetInventories('player'), #fixture.errors }, { false, false, 0, 0 })
                local records = operation == 'restorePlayer' and fixture.persisted.player['player-1'] or fixture.persisted.stash['player-1:player-1']
                equal(fixture:decode(records), { { name = 'rifle', count = 1, slot = 1 } })
                equal(fixture:frameworkPlayer(1).owner, 'player-1')
            end)
        end
    end

    test('ESX disconnect during initial import retires the unpublished inventory', function()
        local fixture = Bridge.new(context.root, Fixture, 'esx')
        local save = fixture.env.db.savePlayer
        local pending
        fixture.env.db.savePlayer = function(owner, payload)
            pending = fixture.Inventory(1)
            fixture.env.server.playerDropped(1)
            return save(owner, payload)
        end
        fixture.exports.setPlayerInventory({ source = 1, identifier = 'initial-esx', name = 'Player', job = { name = 'civilian', grade = 0 }, variables = {} }, {
            { name = 'rifle', count = 1, slot = 1, rotated = true },
        })
        equal({ pending.storageBusy or false, pending.removeAfterStorage or false, #fixture.exports.GetInventories('player') }, { false, false, 0 })
        equal(fixture:decode(fixture.persisted.playerGrid['initial-esx']), { { name = 'rifle', count = 1, slot = 1, rotated = true } })
        equal(#fixture.clientEvents, 0)
    end)

    test('ESX disconnected initial recovery remains in player storage', function()
        local fixture = Bridge.new(context.root, Fixture, 'esx')
        local save = fixture.env.db.savePlayer
        fixture.env.db.savePlayer = function(owner, payload)
            fixture.env.db.savePlayer = save
            fixture.env.server.playerDropped(1)
            return save(owner, payload)
        end
        fixture.exports.setPlayerInventory({ source = 1, identifier = 'recovery-esx', name = 'Player' }, { { name = 'missing', count = 2, slot = 1 } })
        equal({ #fixture.exports.GetInventories('player'), #fixture.clientEvents, next(fixture.persisted.stash) or false }, { 0, 0, false })
        equal(fixture:decode(fixture.persisted.playerGrid['recovery-esx']), {
            { _gridRecovery = { id = 'recovery-1', reason = 'unknown_item', record = { name = 'missing', count = 2, slot = 1 } } },
        })
    end)

    test('framework synchronization failure reports a committed confiscation as successful', function()
        local fixture = Bridge.new(context.root, Fixture, 'nd')
        local inventory = fixture:frameworkPlayer(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        fixture.frameworkPlayers[1].setData = function() error('framework unavailable') end
        equal(fixture.exports.ConfiscateInventory(1), true)
        equal({ inventory.storageBusy or false, inventory.weight, #fixture.errors }, { false, 0, 1 })
        equal(fixture.errors[1]:find('framework unavailable', 1, true) ~= nil, true)
        equal(fixture:decode(fixture.persisted.stash['player-1:player-1']), { { name = 'rifle', count = 1, slot = 1 } })
    end)

    test('unexpected publication error still releases the storage guard', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'rifle', 1, nil, 1), true)
        fixture.env.TriggerClientEvent = function() error('engine boundary failed') end
        equal(pcall(fixture.exports.ConfiscateInventory, 1), false)
        equal({ inventory.storageBusy or false, inventory.weight }, { false, 0 })
        equal(fixture:decode(fixture.persisted.stash['player-1:player-1']), { { name = 'rifle', count = 1, slot = 1 } })
    end)

    for _, grant in ipairs({ false, true }) do
        test('repeated confiscation preserves earlier ownership with new grant ' .. tostring(grant), function()
            local fixture = Fixture.new(context.root)
            fixture:player(1)
            equal(fixture.exports.AddItem(1, 'phone', 1, nil, 1), true)
            equal(fixture.exports.ConfiscateInventory(1), true)
            if grant then equal(fixture.exports.AddItem(1, 'water', 2, nil, 1), true) end
            equal(fixture.exports.ConfiscateInventory(1), true)
            equal(fixture.exports.ReturnInventory(1), true)
            equal({ fixture.exports.GetItemCount(1, 'phone'), fixture.exports.GetItemCount(1, 'water'), fixture.Inventory(1).weight }, { 1, grant and 2 or 0, grant and 600 or 100 })
            equal(fixture.persisted.stash['player-1:player-1'], nil)
        end)
    end

    test('confiscation refuses malformed stored ownership without overwriting either side', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        equal(fixture.exports.AddItem(1, 'phone', 1, nil, 1), true)
        fixture.persisted.stash['player-1:player-1'] = 'invalid JSON'
        equal(fixture.exports.ConfiscateInventory(1), false)
        equal({ fixture.exports.GetItemCount(1, 'phone'), inventory.storageBusy or false, fixture.persisted.stash['player-1:player-1'], #fixture.writes }, { 1, false, 'invalid JSON', 0 })
    end)

    test('repeated confiscation merges colliding recovery IDs without losing weight or reclaimability', function()
        local fixture = Fixture.new(context.root)
        local inventory = fixture:player(1)
        for _, serial in ipairs({ 'first', 'second' }) do
            equal(fixture.exports.SetSlotCount(1, 30), true)
            equal(fixture.exports.AddItem(1, 'rifle', 1, { serial = serial }, 1), true)
            equal(fixture.exports.SetSlotCount(1, 0), true)
            equal(inventory.recovery[1].id, 'recovery-1')
            equal(fixture.exports.ConfiscateInventory(1), true)
        end
        equal(fixture.exports.SetSlotCount(1, 30), true)
        equal(fixture.exports.ReturnInventory(1), true)
        equal({ inventory.weight, inventory.unknownWeight, #inventory.recovery, inventory.recovery[1].reason, inventory.recovery[2].reason }, { 8000, false, 2, 'no_space', 'no_space' })
        local first, second = inventory.recovery[1].id, inventory.recovery[2].id
        equal(first ~= second, true)
        equal(fixture:call('ox_inventory:recoverItem', 1, { fromType = 'player', recoveryId = first }), true)
        equal(fixture:call('ox_inventory:recoverItem', 1, { fromType = 'player', recoveryId = second }), true)
        equal({ inventory.weight, #inventory.recovery, fixture.exports.GetItemCount(1, 'rifle'), inventory.items[1].metadata.serial, inventory.items[11].metadata.serial }, { 8000, 0, 2, 'second', 'first' })
    end)
end
