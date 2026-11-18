local Config = {}
local tableRoot = 'Data/Table/Customized/ZombieDefense/'

local function readRows(name)
    local ok, rows = pcall(UGCGameSystem.GetTableData, tableRoot .. name)
    local kind = type(rows)
    if ok and (kind == 'table' or kind == 'userdata') then
        -- The engine exposes its table container through pairs, not Lua's next.
        for _ in pairs(rows) do return rows end
    end
    return nil, 'WAVE_TABLE_UNAVAILABLE: ' .. name
end

local function indexed(rows, field, minimum, maximum, name)
    local values, last = {}, minimum - 1
    for label, row in pairs(rows) do
        local kind = type(row)
        local index = (kind == 'table' or kind == 'userdata') and row[field]
        if type(index) ~= 'number' or not (index >= minimum and index <= maximum
            and index < math.huge and index == math.floor(index)) then
            return nil, 'WAVE_TABLE_INVALID_INDEX: ' .. name .. ' ' .. tostring(label) .. ' ' .. field
        end
        if values[index] then
            return nil, 'WAVE_TABLE_DUPLICATE_INDEX: ' .. name .. ' ' .. field .. '=' .. index
        end
        values[index], last = row, math.max(last, index)
    end
    return values, last
end

function Config.Load()
    local waveTable, difficultyTable = 'DT_ZS_Waves', 'DT_ZS_Difficulty'
    local rows, err = readRows(waveTable)
    if not rows then return nil, err end
    local phases, last = indexed(rows, 'Phase', 0, math.huge, waveTable)
    if not phases then return nil, last end
    local opening = phases[0]
    if not opening then return nil, 'WAVE_TABLE_MISSING_INDEX: ' .. waveTable .. ' Phase=0' end
    if opening.Count ~= 0 or opening.BatchSize ~= 0 or opening.IntervalSeconds ~= 0 then
        return nil, 'WAVE_TABLE_INVALID_PREPARATION: ' .. waveTable .. ' Phase=0'
    end
    if last == 0 then return nil, 'WAVE_TABLE_MISSING_INDEX: ' .. waveTable .. ' Phase=1' end
    local waves = {}
    for phase = 1, last do
        local row = phases[phase]
        if not row then return nil, 'WAVE_TABLE_MISSING_INDEX: ' .. waveTable .. ' Phase=' .. phase end
        waves[phase] = {Count = row.Count, BatchSize = row.BatchSize,
            IntervalSeconds = row.IntervalSeconds, RestSeconds = row.WaitSeconds}
    end

    rows, err = readRows(difficultyTable)
    if not rows then return nil, err end
    local tiers
    tiers, err = indexed(rows, 'PlayerCount', 1, 4, difficultyTable)
    if not tiers then return nil, err end
    local difficulties = {}
    for count = 1, 4 do
        local row = tiers[count]
        if not row then
            return nil, 'WAVE_TABLE_MISSING_INDEX: ' .. difficultyTable .. ' PlayerCount=' .. count
        end
        difficulties[count] = {CountMultiplier = row.CountMultiplier,
            IntervalMultiplier = row.IntervalMultiplier, AliveLimit = row.AliveLimit}
    end
    return {
        Version = 'prototype-0.2-player-survival',
        TargetDurationSeconds = {Min = 180, Max = 300},
        PreparationSeconds = opening.WaitSeconds,
        Waves = waves,
        Difficulties = difficulties,
    }
end

return Config
