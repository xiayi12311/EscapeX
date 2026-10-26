-- Placeholder content/text: replace resources before production acceptance.
local Config = {
    FixedSearchOutcomes = {[5]='NoteEvent_05', [10]='NoteEvent_10'},
    Pools = {Default={{Id='Ordinary',Weight=80},{Id='Strange',Weight=20}}},
    Outcomes = {
        Ordinary={Label='普通物件',ContentScale={X=0.1,Y=0.1,Z=0.1},Effects={}},
        Strange={Label='异常物件',ContentScale={X=0.2,Y=0.05,Z=0.08},Effects={{Type='UI',Audience='Searcher',Text='抽屉里似乎有什么动静……'}}},
        NoteEvent_05={Label='纸条',IsNote=true,ContentScale={X=0.16,Y=0.12,Z=0.005},Effects={{Type='Broadcast',Audience='All',Text='你们发现了第一张纸条。'}}},
        NoteEvent_10={Label='纸条',IsNote=true,ContentScale={X=0.16,Y=0.12,Z=0.005},Effects={{Type='Broadcast',Audience='All',Text='你们发现了第二张纸条。'}}},
    },
}

function Config.Roll(poolId,random)
    local pool=Config.Pools[poolId or 'Default']
    if not pool then return nil end
    local total=0
    for _,entry in ipairs(pool) do
        if entry.Weight>0 and Config.Outcomes[entry.Id] then total=total+entry.Weight end
    end
    if total<=0 then return nil end
    local value=(random or math.random)()*total
    for _,entry in ipairs(pool) do
        if entry.Weight>0 and Config.Outcomes[entry.Id] then
            value=value-entry.Weight
            if value<0 then return entry.Id end
        end
    end
    return pool[#pool].Id
end

return Config
