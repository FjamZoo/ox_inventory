local Fixture = {}

local function clone(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = clone(item) end
    return result
end

function Fixture.new(root, framework)
    local fixture = { prepared = {}, transactions = {}, queries = {}, responses = {}, transactionResult = true }
    local env = setmetatable({
        lib = {}, server = {}, shared = { framework = framework or 'esx', info = function() end },
        Citizen = { CreateThreadNow = function(callback) callback() end },
        Wait = function() end,
        GetConvar = function(_, fallback) return fallback end,
        os = { nanotime = function() return 0 end },
    }, { __index = _G })
    env.MySQL = {
        scalar = { await = function() return 1 end },
        query = { await = function(query, values)
            fixture.queries[#fixture.queries + 1] = { query = query, values = clone(values) }
            if query:find('SHOW COLUMNS', 1, true) then return { { Field = 'glovebox' }, { Field = 'trunk' } } end
            return {}
        end },
        prepare = { await = function(query, values)
            fixture.prepared[#fixture.prepared + 1] = { query = query, values = clone(values) }
            if fixture.responses[query] ~= nil then return fixture.responses[query] end
            if query:sub(1, 6) ~= 'SELECT' then return true end
        end },
        transaction = { await = function(queries)
            fixture.transactions[#fixture.transactions + 1] = clone(queries)
            return fixture.transactionResult
        end },
    }
    fixture.db = assert(loadfile(root .. '/modules/mysql/server.lua', 't', env))()
    return fixture
end

return Fixture
