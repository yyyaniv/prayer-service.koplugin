-- Developer tool: walks through the app's screens and saves a screenshot of each one.
-- Started when the file "molytva-tour" exists in KOReader's data directory
-- (e.g. touch .adds/koreader/molytva-tour on Kobo, then open «Молитва»).
-- Screenshots go to <data dir>/molytva-screenshots/; tour.log records what happened.
local DataStorage = require("datastorage")
local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Date = require("molytva_lib.civil_date")
local Session = require("molytva_lib.session")

local M = { FLAG = "molytva-tour" }

local function dir() return DataStorage:getDataDir() .. "/molytva-screenshots" end

local function log(text)
    logger.info("Molytva tour:", text)
    local f = io.open(dir() .. "/tour.log", "ab")
    if f then f:write(os.date("%H:%M:%S "), text, "\n"); f:close() end
end

local function shot(name)
    UIManager:forceRePaint()
    local path = dir() .. "/" .. name .. ".png"
    local ok, err = pcall(Device.screen.shot, Device.screen, path)
    -- shot() returns nothing on success, so check the file instead.
    local f = io.open(path, "rb")
    if f then f:close() end
    log(name .. ((ok and f) and " saved" or (" FAILED " .. tostring(err))))
end

local function close_last_dialog()
    if Session.last_dialog then UIManager:close(Session.last_dialog); Session.last_dialog = nil end
end

local function top_widget()
    return Session.widgets[#Session.widgets]
end

-- Closes app screens above the first `n` ones.
local function pop_to(plugin, n)
    while #Session.widgets > n do plugin:pop(Session.widgets[#Session.widgets]) end
end

local function find_button(viewer, text)
    for _, row in ipairs(viewer and viewer.buttons_table or {}) do
        for _, b in ipairs(row) do if b.text == text then return b end end
    end
end

-- Runs steps one by one: action, pause for e-ink, screenshot, next.
local function run(steps, i)
    local step = steps[i]
    if not step then return end
    UIManager:scheduleIn(step.wait or 1.5, function()
        if step.fn then
            local ok, err = pcall(step.fn)
            if not ok then log((step.shot or "step") .. " ERROR " .. tostring(err)) end
        end
        UIManager:scheduleIn(step.settle or 2.5, function()
            if step.shot then shot(step.shot) end
            run(steps, i + 1)
        end)
    end)
end

-- Consumes the flag; returns true when a tour was started.
function M.maybe_start(plugin)
    local flag = DataStorage:getDataDir() .. "/" .. M.FLAG
    local f = io.open(flag, "rb")
    if not f then return false end
    f:close(); os.remove(flag)
    os.execute("mkdir -p '" .. dir() .. "'")
    Session.tour = { stage = "app" }
    log("start, screen " .. Device.screen:getWidth() .. "x" .. Device.screen:getHeight())
    M.app_part(plugin)
    return true
end

function M.app_part(plugin)
    local now = os.date("*t")
    local today = Date.new(now.year, now.month, now.day)
    local pack
    run({
        { wait = 1, fn = function() plugin:showApp(today, true) end, shot = "01-day" },
        { fn = function()
            local more = find_button(top_widget(), "Устав, читання, святі…")
            if more then more.callback() else log("02-day-more skipped: no button") end
          end, settle = 3, shot = "02-day-more" },
        { fn = function() close_last_dialog(); plugin:showAppMenu(today) end, shot = "03-menu" },
        { fn = function() close_last_dialog(); plugin:showSettingsDialog() end, shot = "04-settings" },
        { fn = function() close_last_dialog(); plugin:showServices() end, shot = "05-liturgies" },
        { fn = function() pop_to(plugin, 2) end, shot = "06-back-to-day" },
        { fn = function() pop_to(plugin, 1) end, shot = "07-month" },
        { fn = function() top_widget():onNextPage() end, shot = "08-month-page2" },
        { fn = function() plugin:showDatePicker(today) end, shot = "09-date-picker" },
        { fn = function() close_last_dialog(); plugin:showDay(Date.new(now.year + 1, 2, 10)) end,
          shot = "10-day-without-texts" },
        { fn = function() plugin:showPackInfo() end, shot = "11-pack-info" },
        { fn = function()
            close_last_dialog()
            plugin:pop(top_widget())
            pack = plugin:loadPack()
            local path = pack and pack:day_view_service(today, "liturgy")
            log("opening " .. tostring(path))
            Session.tour.stage = "reader"
            plugin:openDocument(path, today)
        end },
    }, 1)
end

-- Called from the reader instance once the service is open.
function M.reader_part(plugin)
    run({
        { wait = 3, shot = "12-liturgy" },
        { fn = function() plugin:showServiceMenu() end, shot = "13-service-menu" },
        { fn = function() close_last_dialog(); plugin.ui:handleEvent(Event:new("GotoViewRel", 1)) end,
          shot = "14-liturgy-next-page" },
        { fn = function() Session.tour.stage = "back"; plugin.ui:onHome() end },
    }, 1)
end

-- Called from the file manager instance after the app came back from the service.
function M.back_part()
    run({
        { wait = 3, shot = "15-back-to-day" },
        { fn = function() log("done"); Session.tour = nil end },
    }, 1)
end

return M
