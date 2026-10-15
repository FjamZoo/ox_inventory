local Client = {}

function Client.new(root, fixture, id, weaponSlot)
    local file = assert(io.open(root .. '/client.lua', 'r'))
    local source = file:read('*a')

    file:close()

    local updates = assert(source:match('(local function updateInventory.-)RegisterNetEvent%(\'ox_inventory:inventoryReturned\''))
    local swap = assert(source:match('(local swapActive = false.-)RegisterNUICallback%(\'recoverItem\''))
    local inventory = fixture.Inventory(id)
    local client = { handlers = {}, callbacks = {}, disarms = 0, events = {} }
    local definitions = fixture.env.table.deepclone(fixture.definitions)

    for _, item in pairs(definitions) do
        item.count = 0
    end

    local env = setmetatable({
        currentWeapon = weaponSlot and fixture.env.table.deepclone(inventory.items[weaponSlot]),
        PlayerData = { inventory = fixture.env.table.deepclone(inventory.items), weight = inventory.weight },
        cache = { serverId = id }, invOpen = true, invBusy = false, source = 0, currentInventory = {},
        Items = function(name) return definitions[name] end,
        shared = { framework = 'standalone' },
        Weapon = { Disarm = function() client.disarms += 1 end },
        SendNUIMessage = function() end,
        TriggerEvent = function(name, value) client.events[#client.events + 1] = { name, value } end,
        RegisterNetEvent = function(name, callback) client.handlers[name] = callback end,
        RegisterNUICallback = function(name, callback) client.callbacks[name] = callback end,
        inventoryView = function() end,
        client = {},
        lib = { callback = {} },
    }, { __index = _G })
    env.client.setPlayerData = function(name, value) env.PlayerData[name] = value end
    env.lib.notify = function() end
    env.locale = function(key) return key end
    env.lib.callback.await = function(name, _, data) return fixture:call(name, id, data) end
    assert(load(updates .. '\n' .. swap, '@client.lua:inventory-updates', 't', env))()
    client.env = env

    local send = fixture.env.TriggerClientEvent

    fixture.env.TriggerClientEvent = function(name, target, ...)
        send(name, target, ...)

        if target == id and client.handlers[name] then
            client.handlers[name](fixture.env.table.deepclone(...), select(2, ...))
        end
    end

    return client
end

return Client
