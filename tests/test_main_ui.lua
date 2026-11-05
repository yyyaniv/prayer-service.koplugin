-- Runs main.lua's app screens with stubbed KOReader modules.
-- The JSON stub mimics KOReader's luajson: decode is a callable table and null is a sentinel.
local test_dir = os.getenv("MOLYTVA_TEST_DIR")
local plugin = test_dir .. "/../molytva.koplugin"
dofile(test_dir .. "/stubs/json_decoder.lua")
local tmp = os.tmpname(); os.remove(tmp)
local data_dir = tmp .. "-data"
os.execute("mkdir -p '" .. data_dir .. "'")

local shown = {}
local events = {}
local opened = {}
local function widget()
    local W = {}
    function W:new(o) o = o or {}; return setmetatable(o, { __index = self }) end
    function W:extend(o) o = o or {}; return setmetatable(o, { __index = self }) end
    function W:switchItemTable(_, items, n) self.item_table = items; self.focus = n end
    function W:onNextPage() self.page = (self.page or 1) + 1 end
    return W
end
local function remove(w)
    for i = #shown, 1, -1 do if shown[i] == w then table.remove(shown, i) end end
end
package.preload["datastorage"] = function()
    return { getDataDir = function() return data_dir end, getSettingsDir = function() return data_dir end }
end
for _, m in ipairs({ "ui/widget/datetimewidget", "ui/widget/infomessage", "ui/widget/menu",
    "ui/widget/textviewer", "ui/widget/spinwidget", "ui/widget/container/widgetcontainer",
    "ui/widget/buttondialog", "ui/widget/titlebar" }) do
    package.preload[m] = function() return widget() end
end
package.preload["device"] = function()
    return { screen = { getWidth = function() return 600 end, getHeight = function() return 800 end,
        scaleBySize = function(_, v) return v * 2 end,
        shot = function(_, path) _G.__shots[#_G.__shots + 1] = path:match("([^/]+)%.png$"); return true end } }
end
package.preload["ffi/blitbuffer"] = function()
    return { COLOR_BLACK = "black" }
end
package.preload["logger"] = function()
    local noop = function() end
    return { info = noop, warn = noop, dbg = noop }
end
package.preload["dispatcher"] = function() return { registerAction = function() end } end
package.preload["apps/reader/readerui"] = function()
    return { showReader = function(_, path) opened[#opened + 1] = path end }
end
package.preload["ui/uimanager"] = function()
    return { show = function(_, w) shown[#shown + 1] = w end, close = function(_, w) remove(w) end,
        nextTick = function(_, f) f() end, tickAfterNext = function(_, f) f() end, forceRePaint = function() end, scheduleIn = function(_, _, f) f() end,
        broadcastEvent = function(_, e) events[#events + 1] = e.name end }
end
package.preload["ui/event"] = function()
    return { new = function(_, name, ...) return { name = name, args = { ... } } end }
end
package.preload["ui/network/manager"] = function() return {} end
package.preload["ui/trapper"] = function() return {} end
package.preload["luasettings"] = function()
    local S = {}
    function S:open() return setmetatable({ d = {} }, { __index = S }) end
    function S:readSetting(k, d) if self.d[k] == nil then self.d[k] = d end; return self.d[k] end
    function S:saveSetting(k, v) self.d[k] = v; return self end
    function S:flush() end
    return S
end
package.preload["json"] = function()
    return { decode = setmetatable({}, { __call = function(_, s) return _G.__jsondecode(s) end }) }
end

_G.__shots = {}
package.preload["ui/uimanager_force"] = nil
local Molytva = dofile(plugin .. "/main.lua")
local Session = require("molytva_lib.session")
local function instance(document)
    local inst = Molytva:new{ path = plugin,
        ui = { menu = { registerToMainMenu = function() end }, document = document } }
    inst:init()
    return inst
end
local function find_button(view, text)
    for _, row in ipairs(view.buttons_table) do
        for _, b in ipairs(row) do if b.text == text then return b end end
    end
end
local function open_from_menu()
    shown = {}
    Session.widgets = {}
    local inst = instance()
    local items = {}
    inst:addToMainMenu(items)
    assert(items.molytva.sorting_hint == "main", "menu entry should be in the main tab")
    items.molytva.callback()
    return inst
end

-- Sample pack (format 1): month calendar under today's day, with an update hint.
open_from_menu()
local month, day = shown[1], shown[2]
assert(month and month.title:find("^Молитва · "), "month calendar not shown")
assert(month.width == 600 and month.height == 800, "month calendar is not full-screen")
assert(month.linesize == 6 and month.line_color == "black", "calendar separators should be thick and black")
assert(month.item_table[month.focus].bold, "today is not focused/bold in the calendar")
assert(month.item_table[month.focus].mandatory:find("^сьогодні"), "today is not marked in the calendar")
local MonthView = require("molytva_lib.month")
assert(MonthView.join_titles({ "Неділя 22-га.", "Св. Павла, ісп.", "Прп. Іова" })
    == "Неділя 22-га. Св. Павла, ісп. Прп. Іова", "title joining")
assert(MonthView.join_titles({ "А", "Б" }) == "А; Б", "title joining with ;")
for _, item in ipairs(month.item_table) do
    assert(not item.text:find(".;", 1, true), "double punctuation in the calendar: " .. item.text)
end
assert(day and day.text:find("Оновити тексти", 1, true), "update hint missing")
assert(find_button(day, "Оновити тексти"), "update button missing on a day without texts")
assert(month.custom_title_bar.left_icon == "exit", "exit must be the top-left icon of the calendar")
assert(month.custom_title_bar.right_icon == "appbar.menu", "menu must be the top-right icon")
assert(day.width == 600, "day view is not full-screen")
print("ok - app opens: month calendar + today with sample pack")

-- Next day / calendar buttons.
local title = day.title
find_button(day, "Наступний ›").callback()
assert(shown[#shown] ~= day and shown[#shown].title ~= title, "next day not shown")
local next_day = shown[#shown]
assert(not find_button(next_day, "Календар") and not find_button(next_day, "Сьогодні"),
    "calendar/today should not clutter the day screen")
assert(next_day.show_menu == false, "day screen title bar should only have ✕")
remove(next_day); next_day.close_callback() -- ✕ in the title bar
assert(shown[#shown] == month, "✕ did not return to the month")
-- Month navigation: last item goes to next month and replaces the screen.
month:onMenuSelect(month.item_table[#month.item_table])
assert(#shown == 1 and shown[1] ~= month and shown[1].title:find("^Молитва · "), "next month not shown")
print("ok - day and month navigation")

-- Synthetic format 2 pack: services open as documents and the app comes back after closing.
os.execute("cp -R '" .. test_dir .. "/fixtures/format2' '" .. data_dir .. "/molytva'")
open_from_menu()
local function show_date(y, m, d)
    local inst = instance()
    shown = {}; Session.widgets = {}
    inst:showApp({ year = y, month = m, day = d }, true)
    return shown[#shown]
end
day = show_date(2026, 11, 4)
assert(day.buttons_table[1][2].text == "Меню", "menu button should be in the top row")
local more = find_button(day, "Устав, читання, святі…")
assert(more, "button for ustav/readings/saints missing")
more.callback()
local more_dialog = shown[#shown]
assert(more_dialog.buttons[1][1].text:find("^Устав"), "ustav missing in the extra texts")
remove(more_dialog)
local vespers = find_button(day, "Вечірня (ввечері)")
assert(vespers, "vespers button missing (file of the next day)")
vespers.callback()
assert(#shown == 0, "app screens not closed when opening a service")
assert(opened[#opened]:find("2026%-11%-05/vespers.html$"), "wrong vespers file")
local reader = instance({ file = opened[#opened] })
reader:onCloseDocument()
assert(Session.pending_return, "closing the service did not request a return")
shown = {}
instance() -- file manager after the reader closes
assert(shown[#shown] and shown[#shown].title:find("4 листопада 2026", 1, true), "did not return to the day")
assert(not Session.pending_return, "return request not consumed")
print("ok - service opens and the app returns to its day")

-- Reading a service: wider margins, Kobo-like tap zones, and a middle-tap menu with "back".
local reader_events, zones, went_home = {}, nil, false
local reader_ui = { menu = { registerToMainMenu = function() end }, document = { file = opened[#opened] },
    handleEvent = function(_, e) reader_events[#reader_events + 1] = e end,
    registerTouchZones = function(_, z) if #z > 0 then zones = z end end,
    onHome = function() went_home = true end }
local service_reader = Molytva:new{ path = plugin, ui = reader_ui }
service_reader:init()
service_reader:onReaderReady()
assert(reader_events[1].name == "SetPageHorizMargins", "service margins not set")
assert(zones and #zones == 3, "tap zones not registered")
assert(zones[1].screen_zone.ratio_x == 0 and zones[3].screen_zone.ratio_x > 0.6, "tap zone layout")
reader_events = {}
zones[1].handler(); zones[3].handler()
assert(reader_events[1].name == "GotoViewRel" and reader_events[1].args[1] == -1, "left tap should go back")
assert(reader_events[2].name == "GotoViewRel" and reader_events[2].args[1] == 1, "right tap should go forward")
shown = {}
zones[2].handler()
local service_menu = shown[#shown]
assert(service_menu.buttons[1][1].text == "‹ Назад до дня", "back button missing in the service menu")
service_menu.buttons[1][1].callback()
assert(went_home, "back did not close the service")
-- Own books keep KOReader's usual taps.
zones = nil
local book = Molytva:new{ path = plugin, ui = { menu = reader_ui.menu, document = { file = "/books/a.epub" },
    handleEvent = reader_ui.handleEvent, registerTouchZones = reader_ui.registerTouchZones } }
book:init(); book:onReaderReady()
assert(zones == nil, "tap zones changed for a normal book")
print("ok - service reading: margins, taps, back")

-- A different book in the reader clears the way back.
Session.return_file = opened[#opened]
instance({ file = "/books/other.epub" }):onCloseDocument()
assert(not Session.pending_return and Session.return_file == nil, "stale return kept for another book")
print("ok - other books do not reopen the app")

-- Readable update progress.
local text = Molytva.update_progress_text("Завантаження assets/2026/12/files.zip", 6, 7)
assert(text:find("Крок 6 з 7", 1, true) and text:find("грудень 2026", 1, true), "progress text unclear")
print("ok - update progress text")

-- Launcher flag: opens the app on start, removes the flag, and closing quits back to Kobo.
local flag = data_dir .. "/molytva-open-today"
io.open(flag, "w"):close()
shown = {}; Session.widgets = {}
instance()
assert(io.open(flag, "r") == nil, "launcher flag not removed")
assert(Session.launched, "launch not remembered")
month, day = shown[1], shown[#shown]
assert(month.title:find("^Молитва · ") and day.buttons_table, "app not opened by launcher flag")
find_button(day, "Меню").callback()
local dialog = shown[#shown]
for _, row in ipairs(dialog.buttons) do
    assert(not row[1].text:find("Вийти", 1, true), "exit should only be the top-left icon")
end
assert(dialog.title:find("Тексти: 2026", 1, true), "menu should show the downloaded range")
shown[#shown] = nil
month.custom_title_bar.left_icon_tap_callback()
assert(events[#events] == "Exit", "top-left exit did not quit back to Kobo")
assert(#Session.widgets == 0, "app screens left open after quitting")
print("ok - launcher flag opens the app and quits back")
-- Screenshot tour (developer tool): walks every screen, including the service and the way back.
Session.launched = false
io.open(data_dir .. "/molytva-tour", "w"):close()
shown = {}; Session.widgets = {}
instance()
assert(Session.tour and Session.tour.stage == "reader", "tour did not reach the service")
local tour_reader = Molytva:new{ path = plugin, ui = { menu = { registerToMainMenu = function() end },
    document = { file = opened[#opened] }, handleEvent = function() end, registerTouchZones = function() end,
    onHome = function() end } }
tour_reader:init(); tour_reader:onReaderReady()
assert(Session.tour.stage == "back", "tour did not go back from the service")
tour_reader:onCloseDocument()
instance()
assert(Session.tour == nil, "tour did not finish")
local names = table.concat(_G.__shots, ",")
for _, want in ipairs({ "01-day", "02-day-more", "03-menu", "07-month", "10-day-without-texts", "12-liturgy", "15-back-to-day" }) do
    assert(names:find(want, 1, true), "tour screenshot missing: " .. want .. " in " .. names)
end
local log = io.open(data_dir .. "/molytva-screenshots/tour.log"):read("*a")
assert(not log:find("ERROR", 1, true), "tour step failed:\n" .. log)
print("ok - screenshot tour covers all screens")
os.execute("rm -rf '" .. data_dir .. "'")
