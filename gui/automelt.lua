-- config ui for autochop

local gui = require('gui')
local widgets = require('gui.widgets')
local plugin = require('plugins.automelt')

local PROPERTIES_HEADER = 'Monitor  Melt  Items Marked  '
local REFRESH_MS = 10000

--
-- StockpileSettings
--

StockpileSettings = defclass(StockpileSettings, widgets.Window)
StockpileSettings.ATTRS{
    lockable=false,
    frame={l=0, t=5, w=56, h=13},
}

function StockpileSettings:init()
    self:addviews{
        widgets.Label{
            frame={t=0, l=0},
            text='Stockpile: ',
        },
        widgets.Label{
            view_id='name',
            frame={t=0, l=12},
            text_pen=COLOR_GREEN,
        },
        widgets.ToggleHotkeyLabel{
            view_id='monitored',
            frame={t=2, l=0},
            key='CUSTOM_M',
            label='Monitor stockpile',
        },
        widgets.ToggleHotkeyLabel{
            view_id='melt',
            frame={t=3, l=0},
            key='CUSTOM_SHIFT_M',
            label='Melt all items',
        },

        widgets.HotkeyLabel{
            frame={t=8, l=0},
            key='SELECT',
            label='Apply',
            on_activate=self:callback('commit'),
        },
    }
end

function StockpileSettings:show(choice, on_commit)
    self.data = choice.data
    self.on_commit = on_commit
    local data = self.data
    self.subviews.name:setText(data.name)
    self.subviews.monitored:setOption(data.monitored)
    self.subviews.melt:setOption(data.melt)
    self.visible = true
    self:setFocus(true)
    self:updateLayout()
end

function StockpileSettings:hide()
    self:setFocus(false)
    self.visible = false
end

function StockpileSettings:commit()
    local data = {
        id=self.data.id,
        monitored=self.subviews.monitored:getOptionValue(),
        melt=self.subviews.melt:getOptionValue(),

    }
    plugin.setStockpileConfig(data)
    self:hide()
    self.on_commit()
end

function StockpileSettings:onInput(keys)
    if keys.LEAVESCREEN or keys._MOUSE_R_DOWN then
        self:hide()
        return true
    end
    StockpileSettings.super.onInput(self, keys)
    return true -- we're a modal dialog
end

--
-- Automelt
--

Automelt = defclass(Automelt, widgets.Window)
Automelt.ATTRS {
    frame_title='Automelt',
    frame={w=60, h=27},
    resizable=true,
    resize_min={h=25},
}

function Automelt:init()
    local minimal = false
    local saved_frame = {w=45, h=8, r=2, t=18}
    local saved_resize_min = {w=saved_frame.w, h=saved_frame.h}
    local function toggle_minimal()
        minimal = not minimal
        local swap = self.frame
        self.frame = saved_frame
        saved_frame = swap
        swap = self.resize_min
        self.resize_min = saved_resize_min
        saved_resize_min = swap
        self:updateLayout()
        self:refresh_data()
    end
    local function is_minimal()
        return minimal
    end
    local function is_not_minimal()
        return not minimal
    end

    self:addviews{
        widgets.ToggleHotkeyLabel{
            view_id='enable_toggle',
            frame={t=0, l=0, w=31},
            label='Automelt is',
            key='CUSTOM_CTRL_E',
            options={{value=true, label='Enabled', pen=COLOR_GREEN},
                     {value=false, label='Disabled', pen=COLOR_RED}},
            on_change=function(val) plugin.setEnabled(val) end,
        },
        widgets.HotkeyLabel{
            frame={r=0, t=0, w=10},
            key='CUSTOM_ALT_M',
            label=string.char(31)..string.char(30),
            on_activate=toggle_minimal},
        widgets.Label{
            view_id='minimal_summary',
            frame={t=1, l=0, h=4},
            auto_height=false,
            visible=is_minimal,
        },
        widgets.Label{
            frame={t=3, l=0},
            text='Stockpile',
            auto_width=true,
            visible=is_not_minimal,
        },
        widgets.Label{
            frame={t=3, r=0},
            text=PROPERTIES_HEADER,
            auto_width=true,
            visible=is_not_minimal,
        },
        widgets.List{
            view_id='list',
            frame={t=5, l=0, r=0, b=14},
            on_submit=self:callback('configure_stockpile'),
            visible=is_not_minimal,
        },
        widgets.ToggleHotkeyLabel{
            view_id='hide',
            frame={b=10, l=0},
            label='Hide stockpiles with no items: ',
            key='CUSTOM_CTRL_H',
            initial_option=false,
            on_change=function() self:update_choices() end,
            visible=is_not_minimal,
        },
        widgets.HotkeyLabel{
            frame={b=9, l=0},
            label='Designate items for melting now',
            key='CUSTOM_CTRL_D',
            on_activate=function()
                plugin.automelt_designate()
                self:refresh_data()
                self:update_choices()
            end,
            visible=is_not_minimal,
        },
        widgets.Label{
            view_id='summary',
            frame={b=0, l=0},
            visible=is_not_minimal,
        },
        StockpileSettings{
            view_id='stockpile_settings',
            visible=false,
        },
    }

    self:refresh_data()
end

function Automelt:configure_stockpile(idx, choice)
    self.subviews.stockpile_settings:show(choice, function()
                self:refresh_data()
                self:update_choices()
            end)
end

function Automelt:update_choices()
    local list = self.subviews.list
    local name_width = list.frame_body.width - #PROPERTIES_HEADER
    local fmt = '%-'..tostring(name_width)..'s [%s]   [%s]   %5d  %5d  '
    local hide_empty = self.subviews.hide:getOptionValue()
    local choices = {}
    for _,c in ipairs(self.data.stockpile_configs) do
        local num_items = self.data.item_counts[c.id] or 0
        if not hide_empty or num_items > 0 then
            local text = (fmt):format(
                    c.name:sub(1,name_width), c.monitored and 'x' or ' ',
                    c.melt and 'x' or ' ',
                    num_items or 0, self.data.premarked_item_counts[c.id] or 0)
            table.insert(choices, {text=text, data=c})
        end
    end
    self.subviews.list:setChoices(choices)
    self.subviews.list:updateLayout()

end

function Automelt:refresh_data()
    self.subviews.enable_toggle:setOption(plugin.isEnabled())

    self.data = plugin.getItemCountsAndStockpileConfigs()

    local summary = self.data.summary
    local summary_text = {
        ' Items in monitored stockpiles: ', tostring(summary.total_items),
        NEWLINE,
        'Total items marked for melting: ', tostring(summary.premarked_items), NEWLINE,
    }
    self.subviews.summary:setText(summary_text)

    local minimal_summary_text = {
        '         Items monitored: ', tostring(summary.total_items), NEWLINE,
        'Items marked for melting: ',tostring(summary.premarked_items),
    }
    self.subviews.minimal_summary:setText(minimal_summary_text)

    self.next_refresh_ms = dfhack.getTickCount() + REFRESH_MS
end

function Automelt:postUpdateLayout()
    self:update_choices()
end

-- refreshes data every 10 seconds or so
function Automelt:onRenderBody()
    if self.next_refresh_ms <= dfhack.getTickCount() then
        self:refresh_data()
        self:update_choices()
    end
end

--
-- AutomeltScreen
--

AutomeltScreen = defclass(AutomeltScreen, gui.ZScreen)
AutomeltScreen.ATTRS {
    focus_path='automelt',
}

function AutomeltScreen:init()
    self:addviews{Automelt{}}
end

function AutomeltScreen:onDismiss()
    view = nil
end

if not dfhack.isMapLoaded() then
    qerror('automelt requires a map to be loaded')
end

view = view and view:raise() or AutomeltScreen{}:show()
