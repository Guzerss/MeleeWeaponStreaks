local ffi  = require('ffi')
local hook = require('monethook')
local mem  = require('SAMemory')
local cfg  = require('jsoncfg')

mem.require('CPed')
mem.require('CWeapon')

local cast = ffi.cast
local gta  = ffi.load('GTASA')

ffi.cdef[[
    void* _Z13RwFrameGetLTMP7RwFrame(void* frame);
    void  _Z20RpClumpForAllAtomicsP7RpClumpPFP8RpAtomicS2_PvES3_(RpClump* clump, void*(*cb)(void*, void*), void* data);
    void* _ZNK16CPedIntelligence15GetTaskFightingEv(void* intelligence);
    void  _ZN4CPed6RenderEv(CPed* ped);

    typedef struct {
        uint32_t id;
        uint8_t  r;
        uint8_t  g;
        uint8_t  b;
        uint8_t  a;
        float    startX;
        float    startY;
        float    startZ;
        uint8_t  pad1[0x18];
        float    endX;
        float    endY;
        float    endZ;
        uint8_t  pad2[0x18];
        uint8_t  active;
        uint8_t  pad3[0x3];
    } MotionBlurStreak;
]]

local MAX_STREAKS = 4
local aStreaks    = cast('MotionBlurStreak*', MONET_GTASA_BASE + 0xA56600)

local defaultConfig = {
    weapons = {
        ["2"] = { r=100, g=100, b=100, a=255, xs=0.02, ys=0.05, zs=0.07, xe=0.096, ye=-0.0175, ze=0.95  },
        ["5"] = { r=100, g=100, b=100, a=255, xs=0.02, ys=0.05, zs=0.07, xe=0.096, ye=-0.0175, ze=0.8   },
        ["8"] = { r=100, g=100, b=100, a=255, xs=0.02, ys=0.05, zs=0.07, xe=0.096, ye=-0.0175, ze=1.096 },
    }
}

local config     = cfg.load(defaultConfig, 'meleestreaks')
cfg.save(config, 'meleestreaks')

local foundFrame = ffi.new('void*[1]')

local cbGetFrame = ffi.cast('void*(*)(void*, void*)', function(atomic_ptr, _)
    local atomic = cast('RpAtomic*', atomic_ptr)
    if foundFrame[0] == nil then
        foundFrame[0] = cast('void*', atomic.object.object.parent)
    end
    return atomic_ptr
end)

local function findOrAllocSlot(id)
    for i = 0, MAX_STREAKS - 1 do
        if aStreaks[i].id == id then return i end
    end
    for i = 0, MAX_STREAKS - 1 do
        if aStreaks[i].active == 0 then return i end
    end
    return 0
end

local function writeStreak(id, r, g, b, a, sx, sy, sz, ex, ey, ez)
    local slot = findOrAllocSlot(id)
    local s    = aStreaks[slot]
    s.id     = id
    s.r      = r; s.g = g; s.b = b; s.a = a
    s.startX = sx; s.startY = sy; s.startZ = sz
    s.endX   = ex; s.endY   = ey; s.endZ   = ez
    s.active = 1
end

local function addWeaponStreak(ped, weapType)
    local wcfg = config.weapons[tostring(weapType)]
    if wcfg == nil then return end

    local weapClump = ped.pWeaponObject
    if weapClump == nil then return end

    foundFrame[0] = nil
    gta._Z20RpClumpForAllAtomicsP7RpClumpPFP8RpAtomicS2_PvES3_(weapClump, cbGetFrame, nil)
    if foundFrame[0] == nil then return end

    local ltm = cast('float*', gta._Z13RwFrameGetLTMP7RwFrame(foundFrame[0]))
    if ltm == nil then return end

    local function transform(px, py, pz)
        return ltm[0]*px + ltm[4]*py + ltm[8]*pz  + ltm[12],
               ltm[1]*px + ltm[5]*py + ltm[9]*pz  + ltm[13],
               ltm[2]*px + ltm[6]*py + ltm[10]*pz + ltm[14]
    end

    local sx, sy, sz = transform(wcfg.xs, wcfg.ys, wcfg.zs)
    local ex, ey, ez = transform(wcfg.xe, wcfg.ye, wcfg.ze)
    local id = tonumber(cast('uintptr_t', weapClump))

    writeStreak(id, wcfg.r, wcfg.g, wcfg.b, wcfg.a, sx, sy, sz, ex, ey, ez)
end

local pedRenderHook
pedRenderHook = hook.new(
    'void(*)(CPed*)',
    function(ped)
        if ped ~= nil and ped.pWeaponObject ~= nil and ped.nActiveWeaponSlot > 0 then
            local intel = ped.pIntelligence
            if intel ~= nil then
                local ok, fighting = pcall(gta._ZNK16CPedIntelligence15GetTaskFightingEv, intel)
                if ok and fighting ~= nil then
                    local weapType = tonumber(ped.aWeapons[ped.nActiveWeaponSlot].nType)
                    addWeaponStreak(ped, weapType)
                end
            end
        end
        pedRenderHook(ped)
    end,
    cast('uintptr_t', cast('void*', gta._ZN4CPed6RenderEv))
)

function main()
    while true do wait(0) end
end
