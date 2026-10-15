return function(context)
    local Fixture, test, equal, slot = context.Fixture, context.test, context.equal, context.slot
    local Mysql = assert(loadfile(context.root .. '/tests/server/mysql-fixture.lua'))()
    local upsert = 'INSERT INTO ox_inventory (data, owner, name) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE data = VALUES(data)'
    local playerUpdate = 'UPDATE `users` SET inventory = ? WHERE `identifier` = ?'
    local gridSelect = 'SELECT data FROM ox_inventory WHERE owner = ? AND name = ?'

    test('ESX root reconstruction prefers durable grid over supplied framework data', function()
        local fixture = Fixture.new(context.root, { framework = 'esx', loadServer = true })
        local recovery = { id = 'unknown-owned', reason = 'unknown_item', record = { name = 'missing', count = 1, slot = 20, custom = 'keep' } }
        fixture.persisted.playerGrid['esx-player'] = fixture.env.json.encode({
            { name = 'rifle', count = 1, slot = 1, rotated = true }, { _gridRecovery = recovery },
        })
        fixture.exports.setPlayerInventory({ source = 1, identifier = 'esx-player', name = 'ESX player' }, { { name = 'water', count = 9, slot = 1 } })
        local inventory = fixture.exports.GetInventory(1)
        equal({ slot(inventory.items[1]), inventory.items[1].rotated, inventory.weight, inventory.recovery, fixture.exports.GetItemCount(1, 'water') }, {
            { name = 'rifle', slot = 1, count = 1, weight = 4000, metadata = {} }, true, 4000, { recovery }, 0,
        })
        equal(fixture:decode(fixture.persisted.playerGrid['esx-player']), {
            { name = 'rifle', count = 1, slot = 1, rotated = true }, { _gridRecovery = recovery },
        })
    end)

    test('ESX root persists the initial canonical inventory before publishing it', function()
        local fixture = Fixture.new(context.root, { framework = 'esx', loadServer = true })
        local published
        fixture.env.TriggerClientEvent = function(name)
            if name == 'ox_inventory:setPlayerInventory' then published = fixture.persisted.playerGrid['new-esx'] end
        end
        fixture.exports.setPlayerInventory({ source = 1, identifier = 'new-esx', name = 'ESX player' }, { { name = 'water', count = 2, slot = 7 } })
        equal(fixture:decode(published), { { name = 'water', count = 2, slot = 7 } })
        equal(slot(fixture.exports.GetInventory(1).items[7]), { name = 'water', slot = 7, count = 2, weight = 500, metadata = {} })
    end)

    test('ESX failed initial canonical save does not expose a player inventory', function()
        local fixture = Fixture.new(context.root, { framework = 'esx', loadServer = true })
        fixture.env.db.savePlayer = function() return false end
        local success = pcall(fixture.exports.setPlayerInventory, { source = 1, identifier = 'failed-esx', name = 'ESX player' }, { { name = 'water', count = 2, slot = 7 } })
        equal(success, false)
        equal(#fixture.exports.GetInventories('player'), 0)
        equal(#fixture.clientEvents, 0)
    end)

    test('ESX save cadence retains rotation and tagged recovery through framework mirror changes', function()
        local fixture = Fixture.new(context.root, { framework = 'esx', loadServer = true })
        fixture.exports.setPlayerInventory({ source = 1, identifier = 'esx-save', name = 'ESX player' }, { { name = 'rifle', count = 1, slot = 1, rotated = true } })
        equal(fixture.exports.SetSlotCount(1, 0), true)
        fixture.Inventory.SaveInventories(false, false)
        local saved = fixture:decode(fixture.persisted.playerGrid['esx-save'])
        equal({ #saved, saved[1]._gridRecovery.reason, saved[1]._gridRecovery.record.rotated }, { 1, 'no_space', true })
        fixture.Inventory.Remove(1)
        fixture.persisted.player['esx-save'] = fixture.env.json.encode({ { name = 'water', count = 99, slot = 1 } })
        fixture.exports.setPlayerInventory({ source = 1, identifier = 'esx-save', name = 'ESX player' }, { { name = 'water', count = 99, slot = 1 } })
        local loaded = fixture.exports.GetInventory(1)
        equal({ loaded.weight, #loaded.recovery, loaded.recovery[1].record.rotated, fixture.exports.GetItemCount(1, 'water') }, { 4000, 1, true, 0 })
    end)

    test('ESX saved empty ownership remains authoritative over stale framework items', function()
        local fixture = Fixture.new(context.root, { framework = 'esx', loadServer = true })
        fixture.exports.setPlayerInventory({ source = 1, identifier = 'empty-esx', name = 'ESX player' }, { { name = 'water', count = 1, slot = 1 } })
        equal(fixture.exports.RemoveItem(1, 'water', 1), true)
        fixture.Inventory.SaveInventories(false, false)
        fixture.Inventory.Remove(1)
        fixture.exports.setPlayerInventory({ source = 1, identifier = 'empty-esx', name = 'ESX player' }, { { name = 'water', count = 9, slot = 1 } })
        local loaded = fixture.exports.GetInventory(1)
        equal({ fixture.exports.GetItemCount(1, 'water'), loaded.weight, #loaded.recovery }, { 0, 0, 0 })
    end)

    test('real ESX mysql save writes framework mirror and canonical grid in one transaction', function()
        local fixture = Mysql.new(context.root)
        equal(fixture.db.savePlayer('identifier-1', 'grid-payload'), true)
        equal(fixture.transactions, { {
            { query = playerUpdate, values = { 'grid-payload', 'identifier-1' } },
            { query = upsert, values = { 'grid-payload', 'identifier-1', '__ox_inventory_player_grid' } },
        } })
    end)

    test('real ESX mysql restore removes only the owner-scoped confiscation source transactionally', function()
        local fixture = Mysql.new(context.root)
        equal(fixture.db.restorePlayer('identifier-1', 'restored-grid'), true)
        equal(fixture.transactions, { {
            { query = playerUpdate, values = { 'restored-grid', 'identifier-1' } },
            { query = upsert, values = { 'restored-grid', 'identifier-1', '__ox_inventory_player_grid' } },
            { query = 'DELETE FROM ox_inventory WHERE name = ? AND owner = ?', values = { 'identifier-1', 'identifier-1' } },
        } })
    end)

    test('real ESX mysql confiscation atomically empties both player stores and preserves original records', function()
        local fixture = Mysql.new(context.root)
        equal(fixture.db.confiscatePlayer('identifier-1', 'confiscated-grid'), true)
        equal(fixture.transactions, { {
            { query = playerUpdate, values = { '[]', 'identifier-1' } },
            { query = upsert, values = { '[]', 'identifier-1', '__ox_inventory_player_grid' } },
            { query = upsert, values = { 'confiscated-grid', 'identifier-1', 'identifier-1' } },
        } })
    end)

    test('real ESX mysql loading reads the canonical grid before a stale framework mirror', function()
        local fixture = Mysql.new(context.root)
        fixture.responses[gridSelect] = 'authoritative-grid'
        equal(fixture.db.loadPlayer('identifier-1'), 'authoritative-grid')
        equal(fixture.prepared, { { query = gridSelect, values = { 'identifier-1', '__ox_inventory_player_grid' } } })
    end)

    test('real ESX mysql bulk player save uses transactional canonical writes', function()
        local fixture = Mysql.new(context.root)
        fixture.db.saveInventories({ { 'bulk-grid', 'identifier-1' } }, {}, {}, {}, { 1, 0, 0, 0, 1 })
        equal(fixture.transactions, { {
            { query = playerUpdate, values = { 'bulk-grid', 'identifier-1' } },
            { query = upsert, values = { 'bulk-grid', 'identifier-1', '__ox_inventory_player_grid' } },
        } })
    end)

    test('real mysql stale-stash cleanup excludes reserved canonical player grids', function()
        local fixture = Mysql.new(context.root)
        equal(fixture.queries[#fixture.queries], {
            query = 'DELETE FROM ox_inventory WHERE name <> ? AND lastupdated < (NOW() - INTERVAL 6 MONTH)',
            values = { '__ox_inventory_player_grid' },
        })
    end)

    test('real ESX mysql transaction failure is returned to the inventory caller', function()
        local fixture = Mysql.new(context.root)
        fixture.transactionResult = false
        equal(fixture.db.savePlayer('identifier-1', 'failed-grid'), false)
        equal(fixture.transactions[1], {
            { query = playerUpdate, values = { 'failed-grid', 'identifier-1' } },
            { query = upsert, values = { 'failed-grid', 'identifier-1', '__ox_inventory_player_grid' } },
        })
    end)

    test('real ESX mysql saves explicit empty canonical ownership when inventory is nil', function()
        local fixture = Mysql.new(context.root)
        equal(fixture.db.savePlayer('identifier-1', nil), true)
        equal(fixture.transactions[1], {
            { query = playerUpdate, values = { '[]', 'identifier-1' } },
            { query = upsert, values = { '[]', 'identifier-1', '__ox_inventory_player_grid' } },
        })
    end)
end
