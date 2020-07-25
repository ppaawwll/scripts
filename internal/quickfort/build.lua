-- build-related logic for the quickfort script
--@ module = true

if not dfhack_flags.module then
    qerror('this script cannot be called directly')
end

local quickfort_common = reqscript('internal/quickfort/common')
local log = quickfort_common.log

function do_run(zlevel, grid)
    local stats = nil
    print('"quickfort run" not yet implemented for mode: build')
    return stats
end

function do_orders(zlevel, grid)
    local stats = nil
    print('"quickfort orders" not yet implemented for mode: build')
    return stats
end

function do_undo(zlevel, grid)
    local stats = nil
    print('"quickfort undo" not yet implemented for mode: build')
    return stats
end
