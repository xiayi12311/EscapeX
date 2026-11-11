local Config = {
    Version = 'prototype-0.2-player-survival',
    TargetDurationSeconds = {Min = 180, Max = 300},
    PreparationSeconds = 10,
    Waves = {
        {Count = 8, BatchSize = 2, IntervalSeconds = 4, RestSeconds = 10},
        {Count = 12, BatchSize = 3, IntervalSeconds = 3, RestSeconds = 10},
        {Count = 16, BatchSize = 4, IntervalSeconds = 3, RestSeconds = 0},
    },
    Difficulties = {
        [1] = {CountMultiplier = 1, IntervalMultiplier = 1, AliveLimit = 6},
        [2] = {CountMultiplier = 1.5, IntervalMultiplier = 1, AliveLimit = 10},
        [3] = {CountMultiplier = 2, IntervalMultiplier = 1, AliveLimit = 14},
        [4] = {CountMultiplier = 2.5, IntervalMultiplier = 1, AliveLimit = 18},
    },
}

return Config
