-- Server-only bounded nearby search; no occupied-position fallback.
local M = {}
function M.Find(context, origin, cfg, bindings, class)
    local members={}
    for _, actor in ipairs(UGCActorComponentUtility.GetAllActorsOfClass(context,class)) do members[actor]=true end
    local candidates = {{X=origin.X,Y=origin.Y,Z=origin.Z}}
    for ring=1,cfg.Rings do
        local radius=cfg.SearchRadius*ring/cfg.Rings
        for i=0,cfg.SamplesPerRing-1 do
            local angle=2*math.pi*i/cfg.SamplesPerRing
            candidates[#candidates+1]={X=origin.X+radius*math.cos(angle),
                Y=origin.Y+radius*math.sin(angle),Z=origin.Z}
        end
    end
    for _, candidate in ipairs(candidates) do
        local ok, ground=UGCNavigationSystem.ProjectPointToNavigation(context,candidate,cfg.QueryExtent)
        if ok then
            local dx,dy=ground.X-origin.X,ground.Y-origin.Y
            if dx*dx+dy*dy <= cfg.SearchRadius*cfg.SearchRadius
                and math.abs(ground.Z-origin.Z) <= cfg.QueryExtent.Z then
                local center={X=ground.X,Y=ground.Y,Z=ground.Z+cfg.HalfHeight+cfg.GroundClearance}
                local actors={}
                local blocked=KismetSystemLibrary.CapsuleOverlapActors(context,center,
                    cfg.Radius+cfg.Spacing,cfg.HalfHeight,cfg.ObjectTypes,nil,{},actors)
                if not blocked then
                    -- Immediate actor transforms also reserve space before physics overlap registration.
                    for actor, binding in pairs(bindings) do
                        if (binding.Context == context or members[actor]) and KismetSystemLibrary.IsValid(actor) and binding.Placement then
                            local p=actor:K2_GetActorLocation()
                            local x,y=center.X-p.X,center.Y-p.Y
                            local other=binding.Placement
                            local gap=cfg.Radius+other.Radius+math.max(cfg.Spacing,other.Spacing)
                            if math.abs(center.Z-p.Z)<cfg.HalfHeight+other.HalfHeight
                                and x*x+y*y<gap*gap then blocked=true;break end
                        end
                    end
                end
                if not blocked then return center end
            end
        end
    end
    return nil,'SPAWN_SPACE_OCCUPIED'
end
return M
