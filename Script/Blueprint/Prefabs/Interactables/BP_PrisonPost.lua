local Service = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CaptureService')
local Presentation = UGCGameSystem.UGCRequire('Script.Gameplay.Capture.CapturePresentation')

-- Synced fields and defaults live in the Lua table itself, the pattern the official
-- variable-sync doc uses (gp-docs/wiki/298.md). Blueprint variables of the same name
-- can override them later without touching this file.
local Post = {
    PrisonState = {PlayerKey = -1, State = 'Free', PostId = '', Revision = 0},
    PostId = 0,
    RescueRadius = 220,
    RescueDuration = 3,
    StrugglePresses = 8,
    BindHeightOffset = 90,
}

function Post:GetReplicatedProperties()
    return 'PrisonState'
end

local LOG = '[HTCapture]'
local function log(text) ugcprint(LOG .. ' post ' .. tostring(text)) end
local function valid(o) return o ~= nil and KismetSystemLibrary.IsValid(o) end

-- The GameMode's service is created in its own BeginPlay, which can be later than an
-- actor placed in the level, so registration retries. A refused registration is a
-- configuration error that retrying cannot fix, so it stops after a bounded number of
-- attempts and says so loudly instead of leaving the post silently unusable.
local REGISTER_RETRY_LIMIT = 50

local function registerOnce(self)
    local gm = UGCGameSystem.GetGameMode()
    if not (gm and gm.CaptureManager) then return 'waiting' end
    local ok, detail = Service.RegisterPost(gm, self)
    if ok then return 'done' end
    return 'failed', detail
end

function Post:ReceiveBeginPlay()
    Post.SuperClass.ReceiveBeginPlay(self)
    if valid(self.RescueArea) then
        self.RescueArea:SetSphereRadius(self.RescueRadius or 220, true)
    end
    if self:HasAuthority() then
        self.PostRegisterTries = 0
        self.PostRegisterTimer = UGCTimerUtility.CreateLuaTimer(0.1, function()
            if not KismetSystemLibrary.IsValid(self) then
                if self.PostRegisterTimer then
                    UGCTimerUtility.RemoveLuaTimer(self.PostRegisterTimer)
                    self.PostRegisterTimer = nil
                end
                return
            end
            local state, detail = registerOnce(self)
            if state == 'done' then
                UGCTimerUtility.RemoveLuaTimer(self.PostRegisterTimer)
                self.PostRegisterTimer = nil
            elseif state == 'failed' then
                self.PostRegisterTries = (self.PostRegisterTries or 0) + 1
                if self.PostRegisterTries >= REGISTER_RETRY_LIMIT then
                    UGCTimerUtility.RemoveLuaTimer(self.PostRegisterTimer)
                    self.PostRegisterTimer = nil
                    log('registration refused for ' .. tostring(self.name or self)
                        .. ': ' .. tostring(detail) .. '; post is unusable')
                end
            end
        end, true)
    else
        Presentation.Bind(self, self.PrisonState)
    end
end

-- Click components call these with one FClick_Param (the parameter struct the engine
-- generates for Check/Execute), not with (PC, ExtraMessage): the desk's native AssignNew
-- signature is recorded in Docs/SearchableDesk_PIE验证记录.md. The controller comes out
-- of that struct, and the function names must match what the click component references
-- in the blueprint, so rename them together if the graph generates different names.
local function controllerOf(Click_Param)
    return Click_Param and Click_Param.PlayerController
end

-- Teammate action: starts the rescue timer. The manager re-validates proximity every
-- tick, so walking away cancels the progress.
function Post:CheckRescuePrisoner(Click_Param)
    if self:HasAuthority() then
        local ok = Service.CanRescue(UGCGameSystem.GetGameMode(), self, controllerOf(Click_Param))
        return ok == true
    end
    local state = self.PrisonState
    local key = Service.KeyOf(controllerOf(Click_Param))
    return state ~= nil and state.State == 'Imprisoned' and key >= 0
        and key ~= state.PlayerKey and state.RescuerKey == nil
end

function Post:OnClickRescuePrisoner(Click_Param)
    if not self:HasAuthority() then return end
    local ok, detail = Service.Rescue(UGCGameSystem.GetGameMode(), self, controllerOf(Click_Param))
    if not ok then log('rescue refused ' .. tostring(detail)) end
end

-- Prisoner action: available only once the imprisonment grace has passed (the manager
-- reports that as StruggleReady), then one call per press.
function Post:CheckBreakFree(Click_Param)
    local prisoner
    if self:HasAuthority() then
        prisoner = Service.PrisonerOf(UGCGameSystem.GetGameMode(), self)
    else
        prisoner = self.PrisonState
    end
    if not prisoner then return false end
    if prisoner.State ~= 'Imprisoned' then return false end
    local key = Service.KeyOf(controllerOf(Click_Param))
    if key < 0 or key ~= prisoner.PlayerKey then return false end
    return prisoner.StruggleReady == true
end

function Post:OnClickBreakFree(Click_Param)
    if not self:HasAuthority() then return end
    local ok, detail = Service.Struggle(UGCGameSystem.GetGameMode(), self, controllerOf(Click_Param))
    if not ok then log('struggle refused ' .. tostring(detail)) end
end

function Post:OnRep_PrisonState()
    if self:HasAuthority() then return end
    Presentation.Bind(self, self.PrisonState)
end

function Post:ReceiveEndPlay(Reason)
    if self.PostRegisterTimer then
        UGCTimerUtility.RemoveLuaTimer(self.PostRegisterTimer)
        self.PostRegisterTimer = nil
    end
    if self:HasAuthority() then
        Service.UnregisterPost(UGCGameSystem.GetGameMode(), self)
    else
        Presentation.End(self)
    end
    Post.SuperClass.ReceiveEndPlay(self, Reason)
end

return Post
