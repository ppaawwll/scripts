-- unsuspend construction jobs; buildingplan-safe
--@module = true

local guidm = require('gui.dwarfmode')
local utils = require('utils')

local overlay = require('plugins.overlay')

local ok, buildingplan = pcall(require, 'plugins.buildingplan')
if not ok then
    buildingplan = nil
end

local function foreach_construction_job(fn)
    for _,job in utils.listpairs(df.global.world.jobs.list) do
        if job.job_type == df.job_type.ConstructBuilding then
            fn(job)
        end
    end
end

SuspendOverlay = defclass(SuspendOverlay, overlay.OverlayWidget)
SuspendOverlay.ATTRS{
    viewscreens='dwarfmode',
    default_enabled=true,
    overlay_only=true,
    overlay_onupdate_max_freq_seconds=30,
}

function SuspendOverlay:init()
    self:reset()
    -- there can only be one of these widgets allocated at a time, so this is
    -- safe
    dfhack.onStateChange.unsuspend = function(code)
        if code ~= SC_MAP_LOADED then return end
        self:reset()
    end
end

function SuspendOverlay:reset()
    -- value of df.global.building_next_id on last scan
    self.prev_building_next_id = 0

    -- increments on every refresh so we can clear old data from the map
    self.data_version = 0

    -- map of building id -> {suspended=bool, suspend_count=int, version=int}
    -- suspended is the job suspension state as of the last refresh
    -- if suspend_count > 1 then this is a repeat offender (red 'X')
    -- only buildings whose construction is in progress should be in this map.
    self.in_progress_buildings = {}

    -- viewport for cached screen_buildings
    self.viewport = {}

    -- map of building ids to current visible screen position
    self.screen_buildings = {}
end

function SuspendOverlay:overlay_onupdate()
    local added = false
    self.data_version = self.data_version + 1
    foreach_construction_job(function(job)
        self:update_building(dfhack.job.getHolder(job).id, job)
        added = true
    end)
    self.prev_building_next_id = df.global.building_next_id
    if added then
        -- invalidate screen_buildings cache
        self.viewport = {}
    end
    -- clear out old data
    for bld_id,data in pairs(self.in_progress_buildings) do
        if data.version ~= self.data_version then
            self.in_progress_buildings[bld_id] = nil
        end
    end
end

function SuspendOverlay:update_building(bld_id, job)
    local suspended = job.flags.suspend
    local data = self.in_progress_buildings[bld_id]
    if not data then
        self.in_progress_buildings[bld_id] = {suspended=suspended,
                suspend_count=suspended and 1 or 0, version=self.data_version}
    else
        if suspended and suspended ~= data.suspended then
            data.suspend_count = data.suspend_count + 1
        end
        data.suspended = suspended
        data.version = self.data_version
    end
end

function SuspendOverlay:process_new_buildings()
    local added = false
    for bld_id=self.prev_building_next_id,df.global.building_next_id-1 do
        local bld = df.building.find(bld_id)
        if not bld or #bld.jobs ~= 1 then
            goto continue
        end
        local job = bld.jobs[0]
        if job.job_type ~= df.job_type.ConstructBuilding then
            goto continue
        end
        self:update_building(bld_id, job)
        added = true
        ::continue::
    end
    self.prev_building_next_id = df.global.building_next_id
    if added then
        -- invalidate screen_buildings cache
        self.viewport = {}
    end
end

-- returns true if viewport has changed
function SuspendOverlay:update_viewport(viewport)
    local pviewport = self.viewport
    if viewport.z == pviewport.z
            and viewport.x1 == pviewport.x1 and viewport.x2 == pviewport.x2
            and viewport.y1 == pviewport.y1 and viewport.y2 == pviewport.y2 then
        return false
    end
    self.viewport = viewport
    return true
end

function SuspendOverlay:refresh_screen_buildings()
    local viewport = guidm.Viewport.get()
    if not self:update_viewport(viewport) then return end
    local screen_buildings, z = {}, viewport.z
    for bld_id,data in pairs(self.in_progress_buildings) do
        local bld = df.building.find(bld_id)
        if bld then
            local pos = {x=bld.centerx, y=bld.centery, z=bld.z}
            if viewport:isVisible(pos) then
                screen_buildings[bld_id] = viewport:tileToScreen(pos)
            end
        end
    end
    self.screen_buildings = screen_buildings
end

function SuspendOverlay:render_marker(dc, bld, screen_pos)
    if not bld or #bld.jobs ~= 1 then return end
    local data = self.in_progress_buildings[bld.id]
    if not data then return end
    local job = bld.jobs[0]
    if job.job_type ~= df.job_type.ConstructBuilding
            or not job.flags.suspend then
        return
    end
    local color = COLOR_YELLOW
    local ch = 'x'
    if data.suspend_count > 1 then
        color = COLOR_RED
        ch = 'X'
    elseif buildingplan and buildingplan.isPlannedBuilding(bld) then
        color = COLOR_GREEN
        ch = 'P'
    end
    dc:seek(screen_pos.x, screen_pos.y):tile(ch, nil, color)
end

function SuspendOverlay:onRenderFrame(dc)
    if not df.global.pause_state and not dfhack.screen.inGraphicsMode() then
        return
    end

    self:process_new_buildings()
    self:refresh_screen_buildings()

    dc:map(true)
    for bld_id,screen_pos in pairs(self.screen_buildings) do
        self:render_marker(dc, df.building.find(bld_id), screen_pos)
    end
    dc:map(false)
end

OVERLAY_WIDGETS = {overlay=SuspendOverlay}

if dfhack_flags.module then
    return
end

local unsuspended_count, flow_count, buildingplan_count = 0, 0, 0

foreach_construction_job(function(job)
    if not job.flags.suspend then return end
    if dfhack.maps.getTileFlags(job.pos).flow_size > 1 then
        flow_count = flow_count + 1
        return
    end
    local bld = dfhack.buildings.findAtTile(job.pos)
    if bld and buildingplan and buildingplan.isPlannedBuilding(bld) then
        buildingplan_count = buildingplan_count + 1
        return
    end
    job.flags.suspend = false
    unsuspended_count = unsuspended_count + 1
end)

local opts = utils.invert{...}
local quiet = opts['-q'] or opts['--quiet']

if flow_count > 0 then
    print(string.format('Not unsuspending %d underwater job(s)', flow_count))
end
if buildingplan_count > 0 then
    print(string.format('Not unsuspending %d buildingplan job(s)', buildingplan_count))
end
if unsuspended_count > 0 or not quiet then
    print(string.format('Unsuspended %d job(s).', unsuspended_count))
end
