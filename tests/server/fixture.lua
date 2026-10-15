local Fixture = {}

local function clone(value)
    if type(value) ~= 'table' then return value end

    local copy = {}
    for key, item in pairs(value) do copy[key] = clone(item) end
    return copy
end

local function matches(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= 'table' then return left == right end

    for key, value in pairs(left) do
        if not matches(value, right[key]) then return false end
    end

    for key in pairs(right) do
        if left[key] == nil then return false end
    end

    return true
end

local function contains(left, right)
    for key, value in pairs(right) do
        if type(value) == 'table' then
            if type(left[key]) ~= 'table' or not contains(left[key], value) then return false end
        elseif left[key] ~= value then
            return false
        end
    end

    return true
end

local function tableType(value)
    if type(value) ~= 'table' then return nil end
    if not next(value) then return 'empty' end

    local count = 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then return 'hash' end
        count += 1
    end

    return count == #value and 'array' or 'hash'
end

function Fixture.new(root, options)
    options = options or {}

    local fixture = {
        exports = {},
        callbacks = {},
        events = {},
        clientEvents = {},
        timeouts = {},
        cron = {},
        writes = {},
        persisted = { player = {}, stash = {}, trunk = {}, glovebox = {} },
        payloads = {},
        exploits = {},
        commands = {},
        libHooks = {},
        await = { ['ox_inventory:startCrafting'] = function() return true end },
        definitions = clone(options.items or {
            phone = { name = 'phone', label = 'Phone', weight = 100, stack = false, close = true },
            water = { name = 'water', label = 'Water', weight = 250, stack = true, close = true },
            money = { name = 'money', label = 'Money', weight = 0, stack = true, close = true },
            scrap = { name = 'scrap', label = 'Scrap', weight = 50, stack = true, close = true },
            rifle = { name = 'rifle', label = 'Rifle', weight = 4000, stack = false, close = true, size = { width = 4, height = 2 } },
        }),
        data = clone(options.data or {}),
    }

    local env = setmetatable({}, { __index = _G })
    fixture.env = env
    env._G = env
    env.table = clone(table)
    env.table.clone = function(value)
        local copy = {}
        for key, item in pairs(value) do copy[key] = item end
        return copy
    end
    env.table.deepclone = clone
    env.table.matches = matches
    env.table.contains = contains
    env.table.create = function() return {} end
    env.table.wipe = function(value)
        for key in pairs(value) do value[key] = nil end
    end
    env.table.type = tableType
    env.math = clone(math)
    env.math.groupdigits = tostring
    env.os = clone(os)
    env.os.microtime = function() return os.clock() * 1000000 end
    env.shared = {
        resource = 'ox_inventory', framework = 'standalone', ready = true,
        playerslots = 30, playerweight = 30000, dropslots = 30, dropweight = 30000,
        police = {}, info = function() end,
    }
    env.server = {
        loglevel = 0, accounts = { money = 0 }, hasGroup = function() return true, 0 end,
        setPlayerData = clone,
    }
    env.cache = { resource = 'ox_inventory', game = 'gta5' }
    env.locale = function(key, ...) return key end
    env.GetConvarInt = function(_, fallback) return fallback end
    env.GetConvar = function(name, fallback)
        return name == 'inventory:versioncheck' and 'false' or fallback
    end
    env.GetInvokingResource = function() return 'fixture' end
    env.GetPlayerPed = function(id) return id end
    env.GetEntityCoords = function() return vector3(0, 0, 0) end
    env.Player = function() return { state = {} } end
    env.GetPlayerEndpoint = function() return nil end
    env.TriggerClientEvent = function(name, target, ...)
        fixture.clientEvents[#fixture.clientEvents + 1] = { name = name, target = target, args = clone({ ... }) }
    end
    env.TriggerEvent = function(name, ...)
        local handlers = fixture.events[name]
        if handlers then
            for i = 1, #handlers do handlers[i](...) end
        end
    end
    env.AddEventHandler = function(name, callback)
        fixture.events[name] = fixture.events[name] or {}
        fixture.events[name][#fixture.events[name] + 1] = callback
    end
    env.RegisterServerEvent = env.AddEventHandler
    env.RegisterNetEvent = env.AddEventHandler
    env.RegisterCommand = function(name, callback) fixture.commands[name] = callback end
    env.CreateThread = function(callback) callback() end
    env.SetTimeout = function(delay, callback)
        fixture.timeouts[#fixture.timeouts + 1] = { delay = delay, callback = callback }
    end
    env.Wait = function() error('the fixture cannot simulate a yielding Wait', 2) end
    env.exports = function(name, callback) fixture.exports[name] = callback end
    env.lib = {
        load = function(name) return clone(fixture.data[name] or {}) end,
        callback = {
            register = function(name, callback) fixture.callbacks[name] = callback end,
            await = function(name, ...)
                local callback = assert(fixture.await[name], 'unconfigured client callback ' .. name)
                return callback(...)
            end,
        },
        cron = { new = function(expression, callback) fixture.cron[expression] = callback end },
        logger = function() end,
        print = { error = function(message) error(message, 2) end },
        addCommand = function(name, properties, callback)
            fixture.commands[type(name) == 'table' and name[1] or name] = callback
        end,
        registerHook = function(name, callback, properties)
            fixture.libHooks[#fixture.libHooks + 1] = { name = name, callback = callback, properties = properties }
        end,
    }

    env.json = {
        encode = function(value)
            local token = 'fixture-json-' .. (#fixture.payloads + 1)
            fixture.payloads[#fixture.payloads + 1] = clone(value)
            fixture.payloads[token] = clone(value)
            return token
        end,
        decode = function(token)
            return clone(assert(fixture.payloads[token], 'unknown fixture JSON token ' .. tostring(token)))
        end,
    }

    local function stashKey(owner, id)
        return tostring(owner or '') .. ':' .. tostring(id)
    end

    local function save(kind, id, payload)
        fixture.persisted[kind][id] = payload
        fixture.writes[#fixture.writes + 1] = { kind = kind, id = id, payload = payload }
        return true
    end

    env.db = {
        savePlayer = function(owner, payload) return save('player', owner, payload) end,
        loadPlayer = function(owner)
            local payload = fixture.persisted.player[owner]
            return payload and env.json.decode(payload)
        end,
        saveStash = function(owner, id, payload) return save('stash', stashKey(owner, id), payload) end,
        loadStash = function(owner, id) return fixture.persisted.stash[stashKey(owner, id)] end,
        saveTrunk = function(id, payload) return save('trunk', id, payload) end,
        loadTrunk = function(id) return { trunk = fixture.persisted.trunk[id] } end,
        saveGlovebox = function(id, payload) return save('glovebox', id, payload) end,
        loadGlovebox = function(id) return { glovebox = fixture.persisted.glovebox[id] } end,
    }
    env.db.saveInventories = function(players, trunks, gloveboxes, stashes)
        for _, row in ipairs(players) do env.db.savePlayer(row[2], row[1]) end
        for _, row in ipairs(trunks) do env.db.saveTrunk(row[2], row[1]) end
        for _, row in ipairs(gloveboxes) do env.db.saveGlovebox(row[2], row[1]) end
        for _, row in ipairs(stashes) do env.db.saveStash(row[2], row[3], row[1]) end
    end
    env.MySQL = {
        scalar = { await = function(query, parameters)
            assert(query == 'SELECT data FROM ox_inventory WHERE name = ?', 'unexpected scalar query')
            return fixture.persisted.stash[stashKey(parameters[1], parameters[1])]
        end },
        update = { await = function(query, parameters)
            assert(query == 'DELETE FROM ox_inventory WHERE name = ?', 'unexpected update query')
            fixture.persisted.stash[stashKey(parameters[1], parameters[1])] = nil
            return 1
        end },
    }

    local items = setmetatable({ containers = {} }, {
        __call = function(_, name) return name and fixture.definitions[name] or fixture.definitions end,
    })
    items.Metadata = function(_, item, metadata, count)
        if type(metadata) ~= 'table' then metadata = metadata and { type = metadata } or {} end
        return clone(metadata), item.stack and count or 1
    end
    items.CheckMetadata = function(metadata) return clone(metadata) end
    items.UpdateDurability = function(_, slot, _, durability)
        if durability then slot.metadata.durability = durability end
        return false
    end

    local modules = {
        ['modules.items.server'] = items,
        ['modules.mysql.server'] = env.db,
        ['modules.bridge.server'] = true,
        ['modules.pefcl.server'] = true,
        ['modules.utils.server'] = { LogExploit = function(...)
            fixture.exploits[#fixture.exploits + 1] = { ... }
        end },
    }
    env.require = function(name)
        if modules[name] ~= nil then return modules[name] end

        local chunk = assert(loadfile(root .. '/' .. name:gsub('%.', '/') .. '.lua', 't', env))
        local value = chunk()
        modules[name] = value == nil and true or value
        return modules[name]
    end

    fixture.Inventory = env.require('modules.inventory.server')
    fixture.Items = items
    env.require('modules.shops.server')
    env.require('modules.crafting.server')
    if options.loadServer then env.require('server') end

    function fixture:inventory(id, invType, slots, maxWeight)
        return self.Inventory.Create(id, tostring(id), invType or 'stash', slots or 30, 0, maxWeight or 30000, false, {})
    end

    function fixture:player(id, slots, maxWeight)
        local inventory = self.Inventory.Create(id, 'Player ' .. id, 'player', slots or 30, 0, maxWeight or 30000, 'player-' .. id, {})
        inventory.player = { source = id, ped = id, name = inventory.label }
        inventory:openInventory()
        return inventory
    end

    function fixture:call(name, ...)
        return assert(self.callbacks[name], 'unregistered callback ' .. name)(...)
    end

    function fixture:decode(payload) return self.env.json.decode(payload) end

    function fixture:addHook(name, callback, properties)
        local hook = setmetatable({}, { __call = function(_, payload) return callback(payload) end })
        return self.exports.registerHook(name, hook, properties)
    end

    function fixture:flushTimeouts()
        local pending = self.timeouts
        self.timeouts = {}
        for i = 1, #pending do pending[i].callback() end
    end

    return fixture
end

return Fixture
