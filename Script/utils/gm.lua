-- EscapeX commands registered in the built-in UGC debug panel.
local GM = {}

function GM:Register(_)
    local ui = require('client.ingame.ugc.ugc_gmui')
    local button = ui.ItemTypeEnum.Button
    return {
        EscapeX = {
            ['玩法调试'] = {
                {ui.ItemTypeEnum.TextInput, {{'设置搜桌次数', '非负整数'}, {'下一次成功搜索从这个次数加一'}}, 'S_SetDeskCount'},
                {button, {{'重置守点'}, {'移除守点敌人并恢复为可开战'}}, 'S_ResetDefense'},
                {button, {{'物品、子弹不消耗'}, {'保留使用掉的道具及枪械弹药'}}, 'S_ToggleFreeSupplies'},
                {button, {{'背包高容量'}, {'仅当前角色有效，关闭后恢复'}}, 'S_ToggleBackpack'},
                {button, {{'无限商店钱'}, {'购买和刷新免费，且不限购、不限刷新次数'}}, 'S_ToggleShop'},
            },
            ['角色调试'] = {
                {button, {{'切换隐身'}, {'让怪物忽略当前角色'}}, 'S_ToggleInvisibility'},
                {button, {{'切换无敌'}, {'开关当前角色的伤害免疫'}}, 'S_ToggleInvincibility'},
                {button, {{'切换飞行'}, {'穿过墙和地形，朝上或朝下前进可升降'}}, 'S_ToggleFlight'},
            },
        },
    }
end

local function authorized(controller)
    return UGCGameSystem.IsServer() and controller ~= nil
        and KismetSystemLibrary.IsValid(controller) and controller:HasAuthority()
        and UGCGameSystem.IsEnableGM(controller)
end

local function activePawn(controller)
    if not authorized(controller) then return end

    local pawn = UGCGameSystem.GetPlayerPawnByPlayerController(controller)
    local key = UGCGameSystem.GetPlayerKeyByPlayerController(controller)
    if pawn == nil or not KismetSystemLibrary.IsValid(pawn)
        or type(key) ~= 'number' or key < 0 or not UGCPlayerStateSystem.IsAlive(key) then
        UGCWidgetManagerSystem.ShowTipsUIByServer('当前没有存活角色', controller)
        return
    end
    return pawn, UGCGameSystem.UGCRequire('Script.Gameplay.Debug.GMPlayerState')
end

local function report(controller, name, enabled, success)
    local message = name .. (success and (enabled and '已开启' or '已关闭') or '切换失败，请查看服务端日志')
    ugcprint('[EscapeX GM] '..message)
    UGCWidgetManagerSystem.ShowTipsUIByServer(message, controller)
end

function GM:S_ToggleInvisibility(_, controller)
    local pawn, state = activePawn(controller)
    if not pawn then return end
    local enabled = not state.IsInvisible(pawn)
    report(controller, '隐身', enabled, state.SetInvisible(pawn, enabled))
end

function GM:S_ToggleInvincibility(_, controller)
    local pawn, state = activePawn(controller)
    if not pawn then return end
    local enabled = not state.IsGMInvincible(pawn)
    report(controller, '无敌', enabled, state.SetGMInvincible(pawn, enabled))
end

function GM:S_ToggleFlight(_, controller)
    local pawn = activePawn(controller)
    if not pawn then return end
    local flight = UGCGameSystem.UGCRequire('Script.Gameplay.Debug.GMFlight')
    local enabled = not pawn.EscapeXGMFlight
    report(controller, '飞行', enabled, flight.Set(pawn, enabled))
end

local function worldCommand(controller, action)
    if not authorized(controller) then return end
    local mode = UGCGameSystem.GetGameMode()
    local message = mode and KismetSystemLibrary.IsValid(mode) and action(mode) or '服务器服务尚未就绪'
    UGCWidgetManagerSystem.ShowTipsUIByServer(message, controller)
end

function GM:S_SetDeskCount(param, controller)
    worldCommand(controller, function(mode)
        local count = tonumber(param)
        local manager = mode.DeskSearchManager
        if not manager then return '课桌服务尚未就绪' end
        if not manager:SetOpenedCount(count) then return '请输入非负整数' end
        return '搜桌次数已设为 '..count
    end)
end

function GM:S_ResetDefense(_, controller)
    worldCommand(controller, function(mode)
        local ok, reason = mode:ResetZombieDefenseForGM()
        return ok and '守点已重置，可以重新开战' or '守点重置失败：'..tostring(reason)
    end)
end

function GM:S_ToggleFreeSupplies(_, controller)
    local pawn = activePawn(controller)
    if not pawn then return end
    local inventory = UGCGameSystem.UGCRequire('Script.Gameplay.Debug.GMInventory')
    local enabled = not pawn.EscapeXGMFreeSupplies
    report(controller, '物品、子弹不消耗', enabled, inventory.SetFreeSupplies(pawn, enabled))
end

function GM:S_ToggleBackpack(_, controller)
    local pawn = activePawn(controller)
    if not pawn then return end
    local inventory = UGCGameSystem.UGCRequire('Script.Gameplay.Debug.GMInventory')
    local enabled = pawn.EscapeXGMCapacityBonus == nil
    report(controller, '背包高容量', enabled, inventory.SetCapacityBonus(pawn, enabled))
end

function GM:S_ToggleShop(_, controller)
    local pawn = activePawn(controller)
    if not pawn then return end
    local enabled = not pawn.EscapeXGMUnlimitedShop
    pawn.EscapeXGMUnlimitedShop = enabled
    if controller.HospitalShopPlayerRecord then
        UGCGameSystem.UGCRequire('Script.utils.HospitalShopService').SendState(controller)
    end
    report(controller, '无限商店钱', enabled, true)
end

return GM
