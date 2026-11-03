---@class AirWall_Variable_C:AActor
    ---@field AirWall_Collision UBoxComponent
    ---@field AirWall_Fog UStaticMeshComponent
    ---@field AirWallVisible boolean
    ---@field FadeDuration number
    ---@field FogOpacity number
    local AirWall_Variable = {}
    local function valid(o)
        return o ~= nil and KismetSystemLibrary.IsValid(o)
    end
    local function setOpacity(self, opacity)
        self.CurrentFogOpacity = opacity
        if valid(self.AirWallFogMaterial) then
            self.AirWallFogMaterial:SetScalarParameterValue('Opacity', opacity)
        end
    end
    -- Public interface for external logic. Collision is never changed here.
    function AirWall_Variable:SetAirWallVisible(visible)
        self.AirWallVisible = visible == true
    end
    function AirWall_Variable:ReceiveBeginPlay()
        AirWall_Variable.SuperClass.ReceiveBeginPlay(self)
        self.CurrentFogOpacity = 0.0
        if valid(self.AirWall_Collision) then
            self.AirWall_Collision:SetCollisionProfileName('BlockAll')
        end
        if valid(self.AirWall_Fog) then
            self.AirWall_Fog:SetCollisionEnabled(0)
            self.AirWall_Fog:SetVisibility(false, false)
            self.AirWallFogMaterial = self.AirWall_Fog:CreateDynamicMaterialInstance(0)
            setOpacity(self, 0.0)
        end
    end
    function AirWall_Variable:ReceiveTick(deltaTime)
        if not valid(self.AirWall_Fog) then return end
        local target = self.AirWallVisible and (self.FogOpacity or 0.55) or 0.0
        local duration = math.max(0.001, self.FadeDuration or 1.5)
        local current = self.CurrentFogOpacity or 0.0
        local alpha = math.min(1.0, deltaTime / duration)
        local nextOpacity = current + (target - current) * alpha
        if target > 0.0 and current <= 0.001 then
            self.AirWall_Fog:SetVisibility(true, false)
        end
        setOpacity(self, nextOpacity)
        if target <= 0.0 and nextOpacity <= 0.001 then
            self.AirWall_Fog:SetVisibility(false, false)
        end
    end
    return AirWall_Variable
    