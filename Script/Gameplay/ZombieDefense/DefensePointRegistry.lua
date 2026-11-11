local Registry = {}
Registry.__index = Registry

local Specs = {
    Spawn = {Fields = {SpawnGroupId = 'SpawnGroups', EnemyConfigId = 'Enemies'},
        Components = {'SpawnDirection'}},
    Window = {Fields = {EntranceGroupId = 'EntranceGroups', BarricadeConfigId = 'Barricades'},
        Components = {'OutsideApproach', 'InsideLanding', 'BoardRoot', 'InteractionPoint'}},
    Shop = {Fields = {ShopConfigId = 'Shops'}, Components = {'InteractionPoint'}},
    Start = {Fields = {ModeConfigId = 'Modes'}, Components = {'InteractionPoint'}},
}

local function id(value)
    return type(value) == 'string' and value:match('%S') ~= nil
        and not value:match('^%s') and not value:match('%s$')
end

local function problem(code, encounter, point, field)
    return {Code = code, EncounterId = encounter, PointId = point, Field = field}
end

-- Build is transactional: invalid input never produces a partially usable registry.
function Registry.Build(points, catalog, isValid)
    assert(type(points) == 'table' and type(catalog) == 'table', 'INVALID_REGISTRY_INPUT')
    assert(type(isValid) == 'function', 'MISSING_VALIDATOR')
    local groups, errors = {}, {}
    for _, entry in ipairs(points) do
        local actor, kind = entry.Actor, entry.Kind
        if not isValid(actor) then
            errors[#errors + 1] = problem('INVALID_ACTOR', nil, nil, kind)
        elseif type(actor.Enabled) ~= 'boolean' then
            errors[#errors + 1] = problem('INVALID_ENABLED', actor.EncounterId, actor.PointId, kind)
        elseif actor.Enabled then
            local encounter, point = actor.EncounterId, actor.PointId
            local spec = Specs[kind]
            if not spec then
                errors[#errors + 1] = problem('UNKNOWN_POINT_KIND', encounter, point, kind)
            elseif not id(encounter) or not id(point) then
                errors[#errors + 1] = problem('INVALID_POINT_ID', encounter, point, kind)
            else
                if not groups[encounter] then
                    groups[encounter] = {ById = {}, Spawn = {}, Window = {}, Shop = {}, Start = {}}
                end
                local group = groups[encounter]
                if group.ById[point] then
                    errors[#errors + 1] = problem('DUPLICATE_POINT_ID', encounter, point, kind)
                else
                    local record = {Kind = kind, Actor = actor, EncounterId = encounter,
                        PointId = point, ConfigIds = {}, Components = {}}
                    group.ById[point] = record
                    group[kind][#group[kind] + 1] = record
                    for field, section in pairs(spec.Fields) do
                        local key = actor[field]
                        if not id(key) then
                            errors[#errors + 1] = problem('MISSING_CONFIG_ID', encounter, point, field)
                        elseif type(catalog[section]) ~= 'table'
                            or type(catalog[section][key]) ~= 'table' then
                            errors[#errors + 1] = problem('UNKNOWN_CONFIG_ID', encounter, point, field)
                        else
                            record.ConfigIds[field] = key
                        end
                    end
                    for _, component in ipairs(spec.Components) do
                        if not isValid(actor[component]) then
                            errors[#errors + 1] = problem('MISSING_COMPONENT', encounter, point, component)
                        else
                            record.Components[component] = actor[component]
                        end
                    end
                end
            end
        end
    end
    if #errors > 0 then return nil, errors end
    for _, group in pairs(groups) do
        for kind in pairs(Specs) do
            table.sort(group[kind], function(a, b) return a.PointId < b.PointId end)
        end
    end
    return setmetatable({Groups = groups, IsValid = isValid}, Registry), {}
end

function Registry:ValidateForStart(encounterId)
    local group = self.Groups[encounterId]
    if not group then return false, 'UNKNOWN_ENCOUNTER' end
    if #group.Start ~= 1 then return false, 'EXPECTED_ONE_START_POINT' end
    if #group.Spawn == 0 then return false, 'NO_SPAWN_POINTS' end
    for _, record in pairs(group.ById) do
        local actor = record.Actor
        if not self.IsValid(actor) or actor.Enabled ~= true
            or actor.EncounterId ~= record.EncounterId or actor.PointId ~= record.PointId then
            return false, 'POINT_CHANGED_REBUILD_REQUIRED'
        end
        for field, value in pairs(record.ConfigIds) do
            if actor[field] ~= value then return false, 'POINT_CHANGED_REBUILD_REQUIRED' end
        end
        for name, component in pairs(record.Components) do
            if actor[name] ~= component or not self.IsValid(component) then
                return false, 'POINT_CHANGED_REBUILD_REQUIRED'
            end
        end
    end
    return true
end

function Registry:GetPoints(encounterId, kind)
    assert(Specs[kind], 'UNKNOWN_POINT_KIND')
    local group = self.Groups[encounterId]
    if not group then return nil, 'UNKNOWN_ENCOUNTER' end
    local result = {}
    for index, record in ipairs(group[kind]) do
        result[index] = record.Actor
    end
    return result
end

return Registry
