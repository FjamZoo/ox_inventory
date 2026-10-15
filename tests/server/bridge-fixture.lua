local Bridge = {}

function Bridge.new(root, Fixture, framework)
    local fixture = Fixture.new(root, { framework = framework, loadServer = true })
    local env = fixture.env

    fixture.frameworkPlayers, fixture.frameworkUpdates, fixture.errors = {}, {}, {}
    env.lib.checkDependency = function() return true end
    env.lib.print.error = function(message) fixture.errors[#fixture.errors + 1] = message end
    env.AddStateBagChangeHandler = function() end

    local export = env.exports

    env.exports = setmetatable({
        qbx_core = { GetPlayer = function(_, id) return fixture.frameworkPlayers[id] end },
        es_extended = { getSharedObject = function()
            return {
                GetConfig = function() return { CustomInventory = 'ox' } end,
                GetPlayerFromId = function(id) return fixture.frameworkPlayers[id] end,
                Players = {},
            }
        end },
    }, { __call = function(_, ...) return export(...) end })
    env.MySQL.ready = function() end

    local load = env.lib.load

    env.lib.load = function(name)
        if name == '@ND_Core.init' then
            env.NDCore.getPlayer = function(id) return fixture.frameworkPlayers[id] end
            env.NDCore.getPlayers = function() return {} end
        elseif name:match('^modules.bridge.') then
            return assert(loadfile(root .. '/' .. name:gsub('%.', '/') .. '.lua', 't', env))()
        else
            return load(name)
        end
    end

    assert(loadfile(root .. '/modules/bridge/server.lua', 't', env))()

    if framework == 'esx' then
        fixture:flushTimeouts()
    end

    function fixture:frameworkPlayer(id)
        local updates = self.frameworkUpdates
        local player = {
            setData = function(name, value) updates[#updates + 1] = { name, value } end,
            Functions = {
                SetPlayerData = function(name, value) updates[#updates + 1] = { name, value } end,
                GetMoney = function() return 0 end,
                SetMoney = function(name, value) updates[#updates + 1] = { name, value } end,
            },
        }
        self.frameworkPlayers[id] = player

        return self:player(id)
    end

    return fixture
end

return Bridge
