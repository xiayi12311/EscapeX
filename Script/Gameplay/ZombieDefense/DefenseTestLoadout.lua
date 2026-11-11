-- Temporary test-map equipment only; classic UGCBackPackSystem, no retry fallback.
local M = {}
M.Config = {
    Enabled = true,
    MapName = 'ZombieTestMap',
    DelaySeconds = 2,
    Items = {{ItemId = 101004, Count = 1}, {ItemId = 303001, Count = 180}},
}
local pending = setmetatable({}, {__mode = 'k'})
local attempted = setmetatable({}, {__mode = 'k'})
local function eligible(pawn)
    return UE.IsValid(pawn) and pawn:HasAuthority() and M.Config.Enabled
        and UGCGameSystem.GetCurrentLevel(pawn, true) == M.Config.MapName
end
function M.Schedule(pawn)
    if not eligible(pawn) or pending[pawn] or attempted[pawn] then return false end
    pending[pawn] = UGCTimerUtility.CreateLuaTimer(M.Config.DelaySeconds, function()
        pending[pawn] = nil
        if not eligible(pawn) then return end
        attempted[pawn] = true
        for _, item in ipairs(M.Config.Items) do
            local ok = UGCBackPackSystem.AddItem(pawn, item.ItemId, item.Count)
            ugcprint('[ZombieTestLoadout] item=' .. item.ItemId .. ' count=' .. item.Count
                .. ' success=' .. tostring(ok))
            if not ok then
                ugcprint('[ZombieTestLoadout] grant failed; no retry; verify backpack configuration/readiness')
                return
            end
        end
    end, false)
    return true
end
function M.Cancel(pawn)
    if pending[pawn] then UGCTimerUtility.RemoveLuaTimer(pending[pawn]); pending[pawn] = nil end
end
return M
