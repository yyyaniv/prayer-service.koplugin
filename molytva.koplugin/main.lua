local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local DateTimeWidget = require("ui/widget/datetimewidget")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local JSON = require("json")
local LuaSettings = require("luasettings")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local ReaderUI = require("apps/reader/readerui")
local SpinWidget = require("ui/widget/spinwidget")
local TextViewer = require("ui/widget/textviewer")
local TitleBar = require("ui/widget/titlebar")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local logger = require("logger")
-- KOReader's json (luajson) exposes decode as a callable table, not a function; wrap it.
local function json_decode(text) return JSON.decode(text) end

local Date = require("molytva_lib.civil_date")
local Day = require("molytva_lib.liturgical_day")
local MonthView = require("molytva_lib.month")
local Pack = require("molytva_lib.pack")
local Session = require("molytva_lib.session")
local UkrainianDate = require("molytva_lib.uk_date")

-- Set by a launcher outside KOReader (the NickelMenu entry on Kobo): if this file exists at
-- startup, the plugin opens as a stand-alone app on today's day; closing it quits KOReader.
local OPEN_TODAY_FLAG = "molytva-open-today"

local Molytva = WidgetContainer:extend{
    name = "molytva",
    is_doc_only = false,
}

local function message(text)
    UIManager:show(InfoMessage:new{ text = text })
end

local function today()
    local now = os.date("*t")
    return Date.new(now.year, now.month, now.day)
end

local function screen_size()
    local screen = Device.screen
    return screen:getWidth(), screen:getHeight()
end

function Molytva:init()
    self.settings = LuaSettings:open(DataStorage:getSettingsDir() .. "/molytva.lua")
    self.settings:readSetting("calendar", "new-julian")
    self.settings:readSetting("months_ahead", 1)
    self.settings:readSetting("delay", 5)
    self.ui.menu:registerToMainMenu(self)
    self:onDispatcherRegisterActions()

    local document = self.ui.document
    if document then
        -- Reader instance: keep the way back only while one of the app's documents is open.
        if Molytva.isAppDocument(document.file) then
            if document.file ~= Session.return_file then
                -- Opened from history or the file browser: go back to the day in its path.
                Session.return_file = document.file
                Session.return_date = Molytva.dateFromPath(document.file)
            end
        else
            Session.return_file, Session.return_date = nil, nil
        end
        Session.pending_return = false
    end

    local flag = DataStorage:getDataDir() .. "/" .. OPEN_TODAY_FLAG
    local f = io.open(flag, "rb")
    local launched_now = false
    if f then
        f:close()
        os.remove(flag)
        Session.launched = true
        launched_now = true
    end
    if not document and require("molytva_lib.tour").maybe_start(self) then
        return -- developer screenshot tour
    end
    if launched_now then
        Session.pending_return = false
        UIManager:scheduleIn(0.5, function() self:showApp(today(), true) end)
    elseif Session.pending_return and not document then
        -- A service opened from the app was closed: go back to its day, not to the file browser.
        Session.pending_return = false
        local date = Session.return_date or today()
        UIManager:scheduleIn(0.2, function() self:showApp(date, true) end)
        if Session.tour and Session.tour.stage == "back" then require("molytva_lib.tour").back_part() end
    end
end

function Molytva:onDispatcherRegisterActions()
    Dispatcher:registerAction("molytva_open", {
        category = "none", event = "MolytvaOpen", title = "Молитва", general = true,
    })
end

function Molytva:onMolytvaOpen()
    self:showApp(today(), true)
    return true
end

function Molytva:onCloseDocument()
    local document = self.ui.document
    if document and Molytva.isAppDocument(document.file) then
        Session.pending_return = true
    end
end

-- Reading services ---------------------------------------------------------------------------

-- Services of the text pack (or the bundled sample), as opposed to the user's own books.
function Molytva.isAppDocument(file)
    if type(file) ~= "string" then return false end
    return file:find("/molytva/days/", 1, true) ~= nil
        or file:find("/molytva/services/", 1, true) ~= nil
        or file:find("molytva.koplugin/sample-pack/", 1, true) ~= nil
end

function Molytva.dateFromPath(file)
    local y, m, d = tostring(file):match("/days/(%d%d%d%d)%-(%d%d)%-(%d%d)/")
    if not y then return nil end
    local ok, date = pcall(Date.new, tonumber(y), tonumber(m), tonumber(d))
    return ok and date or nil
end

-- Page margins for services (unscaled px, like KOReader's own settings; its default is 15).
Molytva.SERVICE_MARGINS = { left = 40, top = 20, right = 40, bottom = 20 }

-- Kobo-like taps: left third back, right third forward, middle opens the service menu.
local TAP_OVERRIDES = {
    "tap_forward", "tap_backward", "readerfooter_tap",
    "readermenu_tap", "readermenu_ext_tap", "readerconfigmenu_tap", "readerconfigmenu_ext_tap",
    "tap_top_left_corner", "tap_top_right_corner", "tap_left_bottom_corner", "tap_right_bottom_corner",
}

function Molytva:onReaderReady()
    local document = self.ui.document
    if not (document and Molytva.isAppDocument(document.file)) then return end
    local margins = Molytva.SERVICE_MARGINS
    self.ui:handleEvent(Event:new("SetPageHorizMargins", { margins.left, margins.right }))
    self.ui:handleEvent(Event:new("SetPageTopMargin", margins.top))
    self.ui:handleEvent(Event:new("SetPageBottomMargin", margins.bottom))

    local function zone(id, x, w, handler)
        return { id = id, ges = "tap", overrides = TAP_OVERRIDES, handler = handler,
            screen_zone = { ratio_x = x, ratio_y = 0, ratio_w = w, ratio_h = 1 } }
    end
    local zones = {
        zone("molytva_tap_back", 0, 1/3, function()
            self.ui:handleEvent(Event:new("GotoViewRel", -1)); return true
        end),
        zone("molytva_tap_menu", 1/3, 1/3, function() self:showServiceMenu(); return true end),
        zone("molytva_tap_forward", 2/3, 1/3, function()
            self.ui:handleEvent(Event:new("GotoViewRel", 1)); return true
        end),
    }
    self.ui:registerTouchZones(zones)
    -- Links (e.g. to readings) keep priority over our zones.
    local graph = self.ui.touch_zone_dg
    if graph and self.ui._zones and self.ui._zones.tap_link then
        for _, z in ipairs(zones) do pcall(graph.addNodeDep, graph, z.id, "tap_link") end
        self.ui:registerTouchZones({}) -- re-sort zones
    end
    if Session.tour and Session.tour.stage == "reader" then require("molytva_lib.tour").reader_part(self) end
end

function Molytva:showServiceMenu()
    return self:showChoice("Молитва", {
        { "‹ Назад до дня", function() self.ui:onHome() end },
        { "Зміст служби", function() self.ui:handleEvent(Event:new("ShowToc")) end },
        { "Шрифт і поля", function() self.ui:handleEvent(Event:new("ShowConfigMenu")) end },
        { "Меню KOReader", function() self.ui:handleEvent(Event:new("ShowMenu")) end },
        { "Читати далі", function() end },
    })
end

-- App screens --------------------------------------------------------------------------------

function Molytva:push(widget)
    Session.widgets[#Session.widgets + 1] = widget
    UIManager:show(widget)
end

local function forget(widget)
    for i = #Session.widgets, 1, -1 do
        if Session.widgets[i] == widget then table.remove(Session.widgets, i) end
    end
end

function Molytva:pop(widget)
    forget(widget)
    UIManager:close(widget)
end

function Molytva:closeApp()
    for i = #Session.widgets, 1, -1 do UIManager:close(Session.widgets[i]) end
    Session.widgets = {}
end

-- Leaves the app: back to Kobo when started from NickelMenu, otherwise back to KOReader.
function Molytva:quitApp()
    self:closeApp()
    if Session.launched then
        UIManager:broadcastEvent(Event:new("Exit"))
    end
end

function Molytva:showApp(date, open_day)
    self:closeApp()
    date = date or today()
    if not self:showMonth(date.year, date.month, date) then return end
    if open_day then self:showDay(date) end
end

-- The pack is parsed once per session (JSON parsing is slow on e-readers); an update resets it.
function Molytva:loadPack()
    local user_root = DataStorage:getDataDir() .. "/molytva"
    local root = Pack.choose(user_root, self.path .. "/sample-pack")
    if Session.pack and Session.pack.root == root then return Session.pack end
    local ok, pack, err = pcall(Pack.load, root, json_decode)
    if not ok then err, pack = pack, nil end
    if not pack then message("Не вдалося відкрити пакет текстів: " .. tostring(err)) end
    Session.pack = pack
    return pack
end

function Molytva:openDocument(path, date)
    Session.return_file = path
    Session.return_date = date
    Session.pending_return = false
    self:closeApp()
    ReaderUI:showReader(path)
end

function Molytva:showMonth(year, month, focus)
    local pack = self:loadPack()
    if not pack then return end
    local rows = MonthView.rows(year, month, pack, today())
    local menu
    local py, pm = MonthView.shift(year, month, -1)
    local ny, nm = MonthView.shift(year, month, 1)
    local function go(y, m)
        return function()
            self:pop(menu)
            self:showMonth(y, m)
        end
    end
    local items = { { text = "‹ " .. MonthView.title(py, pm), action = go(py, pm) } }
    local focus_index = 1
    for _, row in ipairs(rows) do
        items[#items + 1] = {
            text = row.text, mandatory = row.mandatory, bold = row.bold,
            action = function() self:showDay(row.date) end,
        }
        if focus and Date.diff(row.date, focus) == 0 then focus_index = #items end
        if not focus and row.today then focus_index = #items end
    end
    items[#items + 1] = { text = MonthView.title(ny, nm) .. " ›", action = go(ny, nm) }

    local width, height = screen_size()
    local title = "Молитва · " .. MonthView.title(year, month)
    -- The only exit of the app: top left. The menu is on the top right.
    local title_bar = TitleBar:new{
        width = width,
        fullscreen = true,
        align = "center",
        title = title,
        left_icon = "exit",
        left_icon_tap_callback = function() self:quitApp() end,
        right_icon = "appbar.menu",
        right_icon_tap_callback = function() self:showAppMenu() end,
    }
    menu = Menu:new{
        title = title,
        custom_title_bar = title_bar,
        item_table = items,
        width = width, height = height,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        items_per_page = 10,
        items_max_lines = 2,
        -- Bold black separators between days, like the grid of the phone app.
        linesize = Device.screen:scaleBySize(3),
        line_color = Blitbuffer.COLOR_BLACK,
    }
    -- Menu calls close_callback after every choice, so handle choices here instead.
    function menu.onMenuSelect(_, item)
        item.action()
        return true
    end
    function menu.onCloseAllMenus()
        self:quitApp()
        return true
    end
    menu:switchItemTable(nil, items, focus_index)
    self:push(menu)
    return menu
end

-- Services in the order they are prayed during the day. Vespers and Presanctified of the next
-- liturgical day are served this evening (see Pack:day_view_service).
local SERVICE_ORDER = {
    { "midnight", "Опівнічна" }, { "matins", "Утреня" },
    { "hours", "Часи" }, { "liturgy", "Літургія" },
    { "vespers", "Вечірня (ввечері)" }, { "compline", "Повечір'я" },
    { "presanctified", "Передшеосвячена (ввечері)" },
}
-- Texts about the day, kept behind one button so the day screen stays short.
local MORE_ORDER = {
    { "ustav", "Устав (як служити)" }, { "readings", "Читання" },
    { "saints", "Святі дня" }, { "word", "Слово на день" },
}

-- True when the texts for this day are missing or the pack is a month old.
local function needs_update(pack, date)
    if pack.meta.format == 1 or not pack:day_data(date) then return true end
    local y,m,d = tostring(pack.meta.generated or ""):match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y then
        local ok_date, generated = pcall(Date.new,tonumber(y),tonumber(m),tonumber(d))
        if ok_date and Date.diff(date,generated)>30 then return true end
    end
    return false
end

local function pack_range(pack)
    if pack.meta.format == 2 and type(pack.meta.range) == "table" then
        return tostring(pack.meta.range["from"]) .. " — " .. tostring(pack.meta.range["to"])
    end
end

function Molytva:dayText(date, day, pack)
    local lines = {}
    if not pack:day_data(date) then
        local range = pack_range(pack)
        lines[#lines+1] = "Тексти служб на цей день не завантажені"
            .. (range and (" (є: " .. range .. ")") or "") .. "."
        lines[#lines+1] = "Меню → Оновити тексти."
        lines[#lines+1] = ""
    elseif Date.diff(date, today()) == 0 and needs_update(pack, date) then
        lines[#lines+1] = "Тексти давно не оновлювались: Меню → Оновити тексти."
        lines[#lines+1] = ""
    end
    if day.week_label then lines[#lines + 1] = day.week_label end
    local tone = day.tone and ("Глас " .. day.tone) or nil
    if day.matins_gospel then
        tone = (tone or "Глас не вказано") .. ", Євангеліє утрені " .. day.matins_gospel
    end
    if tone then lines[#lines + 1] = tone end
    if day.fast_label then lines[#lines + 1] = day.fast_label end
    if day.fast_period and day.fast_period ~= day.fast_label then
        lines[#lines + 1] = day.fast_period
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Святі дня:"
    local rank_names = { great = "велике свято", vigil = "бдіння", polyeleos = "полієлей" }
    for _, saint in ipairs(day.saints) do
        local rank = rank_names[saint.rank]
        lines[#lines + 1] = "• " .. saint.title .. (rank and (" (" .. rank .. ")") or "")
    end
    if #day.saints == 0 then lines[#lines + 1] = "Немає відомостей" end
    if #day.readings > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Читання:"
        for _, reading in ipairs(day.readings) do lines[#lines + 1] = reading end
    end
    return table.concat(lines, "\n")
end

function Molytva:showDay(date)
    local pack = self:loadPack()
    if not pack then return end
    local ok, day = pcall(Day.for_date, date, pack)
    if not ok then
        message("Не вдалося обчислити літургійний день: " .. tostring(day))
        return
    end

    local viewer
    local function replace_with(other)
        return function()
            self:pop(viewer)
            self:showDay(other)
        end
    end
    local function open(path) return function() self:openDocument(path, date) end end
    local buttons = {
        {
            { text = "‹ Попередній", callback = replace_with(Date.add(date, -1)) },
            { text = "Меню", callback = function() self:showAppMenu(date) end },
            { text = "Наступний ›", callback = replace_with(Date.add(date, 1)) },
        },
    }
    local row = {}
    local function add(text, callback)
        row[#row + 1] = { text = text, callback = callback }
        if #row == 2 then buttons[#buttons + 1] = row; row = {} end
    end
    for _, service in ipairs(SERVICE_ORDER) do
        local path = pack:day_view_service(date, service[1])
        if path then add(service[2], open(path)) end
    end
    local more = {}
    for _, service in ipairs(MORE_ORDER) do
        local path = pack:day_view_service(date, service[1])
        if path then more[#more + 1] = { service[2], open(path) } end
    end
    if day.proper_path then more[#more + 1] = { "Пропер дня", open(day.proper_path) } end
    if #more > 0 then
        add("Устав, читання, святі…", function() self:showChoice(UkrainianDate.format(date), more) end)
    end
    if #row > 0 then buttons[#buttons + 1] = row end
    if needs_update(pack, date) then
        buttons[#buttons + 1] = { { text = "Оновити тексти", callback = function() self:updateTexts() end } }
    end

    local width, height = screen_size()
    viewer = TextViewer:new{
        title = UkrainianDate.format(date),
        text = self:dayText(date, day, pack),
        buttons_table = buttons,
        width = width, height = height,
        covers_fullscreen = true,
        show_menu = false, -- the title bar keeps only ✕ (back to the calendar)
        close_callback = function() forget(viewer) end, -- TextViewer closes itself
    }
    self:push(viewer)
    return viewer
end

-- A list of {label, action} as a dialog; the action runs after the dialog is gone from the screen.
function Molytva:showChoice(title, entries)
    local dialog
    local buttons = {}
    for _, entry in ipairs(entries) do
        buttons[#buttons + 1] = { { text = entry[1], callback = function()
            UIManager:close(dialog)
            -- Let the screen redraw without the dialog first; otherwise e-ink shows a
            -- half-highlighted button while the next screen is being drawn.
            UIManager:tickAfterNext(entry[2])
        end } }
    end
    dialog = ButtonDialog:new{ title = title, buttons = buttons }
    Session.last_dialog = dialog
    UIManager:show(dialog)
    return dialog
end

function Molytva:showAppMenu(date)
    local pack = self:loadPack()
    local range = pack and pack_range(pack)
    local entries = {}
    if not date or Date.diff(date, today()) ~= 0 then
        entries[#entries + 1] = { "Сьогодні", function() self:showApp(today(), true) end }
    end
    entries[#entries + 1] = { "Інший день…", function() self:showDatePicker(date) end }
    entries[#entries + 1] = { "Повні Літургії", function() self:showServices() end }
    entries[#entries + 1] = { "Оновити тексти", function() self:updateTexts() end }
    entries[#entries + 1] = { "Налаштування", function() self:showSettingsDialog() end }
    entries[#entries + 1] = { "Про пакет", function() self:showPackInfo() end }
    return self:showChoice("Молитва\n" .. (range and ("Тексти: " .. range) or "Тексти не завантажені"), entries)
end

function Molytva:showDatePicker(date)
    date = date or today()
    Session.last_dialog = DateTimeWidget:new{
        year = date.year,
        month = date.month,
        day = date.day,
        title_text = "Інший день",
        ok_text = "Показати",
        cancel_text = "Закрити",
        callback = function(value)
            self:showApp(Date.new(value.year, value.month, value.day), true)
        end,
    }
    UIManager:show(Session.last_dialog)
end

function Molytva:showServices(pack)
    pack = pack or self:loadPack()
    if not pack then return end
    local items = {}
    for _, service in ipairs(pack.services) do
        if service.id ~= "about-pack" and service.id ~= "about" then
            items[#items + 1] = { text = service.title, service = service }
        end
    end
    if #items == 0 then
        message("Повні Літургії з'являться після «Оновити тексти»")
        return
    end
    local width, height = screen_size()
    local menu
    menu = Menu:new{
        title = "Повні Літургії",
        item_table = items,
        width = width, height = height,
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
    }
    function menu.onMenuSelect(_, selected)
        local path = pack:service_path(selected.service)
        if not path then
            message("Файл служби відсутній у пакеті")
            return true
        end
        self:openDocument(path, Session.return_date or today())
        return true
    end
    function menu.onCloseAllMenus()
        self:pop(menu)
        return true
    end
    self:push(menu)
end

-- Updating and settings ----------------------------------------------------------------------

local MONTHS_GENITIVE = { "січень", "лютий", "березень", "квітень", "травень", "червень",
    "липень", "серпень", "вересень", "жовтень", "листопад", "грудень" }

-- Human-readable name of an update step (an archive path or a build stage).
local function step_name(step)
    local path = step:match("^Завантаження (.+)$")
    if not path then
        if step == "Збирання пакета" then return "Складаю служби (кілька хвилин)" end
        if step == "Застосування пакета" then return "Зберігаю тексти" end
        return step
    end
    if path:find("calendars", 1, true) then return "Завантажую календарі" end
    if path:find("templates", 1, true) then return "Завантажую шаблони служб" end
    if path:find("zachala", 1, true) then return "Завантажую Євангельські зачала" end
    if path:find("benedict", 1, true) then return "Завантажую молитви благословення" end
    local y, m = path:match("assets/(%d%d%d%d)n?/(%d%d)/")
    if y then return "Завантажую тексти на " .. MONTHS_GENITIVE[tonumber(m)] .. " " .. y end
    return "Завантажую " .. path
end

local function update_progress_text(step, index, total)
    return string.format("Оновлення текстів «Молитви»\n\nКрок %d з %d\n%s\n\nНе вимикайте читалку.\nТоркніться, щоб скасувати.",
        index, total, step_name(step))
end
Molytva.update_progress_text = update_progress_text

function Molytva:updateTexts()
    if Session.updating then
        message("Оновлення текстів уже триває")
        return
    end
    logger.info("Molytva: update requested")
    if not NetworkMgr:isConnected() then
        UIManager:show(InfoMessage:new{
            text = "Оновлення текстів «Молитви»\n\nВмикаю Wi-Fi…\nПісля підключення почнеться завантаження.",
            timeout = 3,
        })
    end
    -- runWhenConnected always runs the callback once Wi-Fi is up (runWhenOnline may drop it).
    NetworkMgr:runWhenConnected(function()
        Session.updating = true
        Trapper:wrap(function()
          local fine, crash = pcall(function()
            logger.info("Molytva: update started")
            Trapper:info("Оновлення текстів «Молитви»\n\nПочинаю…", true)
            local DeviceLib = require("molytva_lib.device")
            local Updater = require("molytva_lib.updater")
            local socket = require("socket")
            local now = os.date("*t")
            local start = string.format("%04d-%02d", now.year, now.month)
            local ok, result, err = pcall(Updater.run, {
                fs = DeviceLib.fs, fetcher = DeviceLib.fetcher, archive = DeviceLib.archive,
                sample = function(name)
                    local file = assert(io.open(self.path .. "/sample-pack/calendar/" .. name .. ".json", "rb"))
                    local bytes = file:read("*a"); file:close(); return bytes
                end,
                decode = json_decode, calendar = self.settings:readSetting("calendar", "new-julian"),
                months_ahead = self.settings:readSetting("months_ahead", 1),
                delay = self.settings:readSetting("delay", 5),
                start = start, today = os.date("%Y-%m-%d"),
                sleep = socket.sleep,
                progress = function(step, index, total)
                    logger.info("Molytva: update step", index, total, step)
                    return Trapper:info(update_progress_text(step, index, total))
                end,
            })
            Trapper:reset()
            Session.updating = false
            NetworkMgr:afterWifiAction()
            if not ok then
                logger.warn("Molytva: update failed:", result)
                message("Не вдалося оновити тексти:\n" .. tostring(result)); return
            end
            if not result then
                logger.warn("Molytva: update stopped:", err)
                if err == "Скасовано" then message("Оновлення текстів скасовано"); return end
                message("Не вдалося оновити тексти:\n" .. tostring(err)); return
            end
            Session.pack = nil -- read the new texts
            logger.info("Molytva: update finished, updated:", result.updated)
            local state = result.updated and "Тексти оновлено" or "Тексти вже актуальні"
            local text = string.format("%s\nЗавантажено: %s — %s", state, result.range.from, result.range.to)
            if #result.warnings > 0 then
                text = text .. "\n\nПопередження:\n" .. table.concat(result.warnings, "\n", 1, math.min(#result.warnings, 5))
            end
            message(text)
            -- Redraw the app with the new texts if it is open.
            if result.updated and #Session.widgets > 0 then
                self:showApp(Session.return_date or today(), true)
            end
          end)
          Session.updating = false
          if not fine then
              Trapper:reset()
              logger.warn("Molytva: update crashed:", crash)
              message("Не вдалося оновити тексти:\n" .. tostring(crash))
          end
        end)
    end)
end

local CALENDAR_NAMES = { ["new-julian"] = "новоюліанський (Україна)", gregorian = "григоріанський (діаспора)" }

function Molytva:pauseDialog()
    UIManager:show(SpinWidget:new{
        title_text="Пауза між запитами (секунди)", value=self.settings:readSetting("delay",5),
        value_min=1, value_max=120, value_step=1, callback=function(widget)
            self.settings:saveSetting("delay",widget.value):flush()
        end,
    })
end

function Molytva:showSettingsDialog()
    local dialog
    local function reopen(change)
        return function()
            UIManager:close(dialog)
            change()
            UIManager:tickAfterNext(function() self:showSettingsDialog() end)
        end
    end
    local calendar = self.settings:readSetting("calendar", "new-julian")
    local months = self.settings:readSetting("months_ahead", 1)
    dialog = ButtonDialog:new{
        title = "Налаштування «Молитви»\nЗміни діють після «Оновити тексти»",
        buttons = {
            { { text = "Календар: " .. (CALENDAR_NAMES[calendar] or calendar), callback = reopen(function()
                local next_calendar = calendar == "new-julian" and "gregorian" or "new-julian"
                self.settings:saveSetting("calendar", next_calendar):flush()
            end) } },
            { { text = "Місяців наперед: " .. tostring(months), callback = reopen(function()
                self.settings:saveSetting("months_ahead", months % 3 + 1):flush()
            end) } },
            { { text = "Пауза між запитами: " .. tostring(self.settings:readSetting("delay", 5)) .. " с",
                callback = function()
                    UIManager:close(dialog)
                    UIManager:tickAfterNext(function() self:pauseDialog() end)
                end } },
            { { text = "Готово", callback = function() UIManager:close(dialog) end } },
        },
    }
    Session.last_dialog = dialog
    UIManager:show(dialog)
    return dialog
end

function Molytva:settingsMenu()
    local function choice(key,value)
        return {
            keep_menu_open = true,
            checked_func = function() return self.settings:readSetting(key) == value end,
            callback = function() self.settings:saveSetting(key,value):flush() end,
        }
    end
    local calendar_new = choice("calendar","new-julian"); calendar_new.text = "Новоюліанський — Україна"
    local calendar_gr = choice("calendar","gregorian"); calendar_gr.text = "Григоріанський — діаспора"
    local ahead = {}
    for n=1,3 do local item=choice("months_ahead",n); item.text=tostring(n); ahead[#ahead+1]=item end
    return {
        { text="Календар", sub_item_table={calendar_new,calendar_gr} },
        { text="Місяців наперед", sub_item_table=ahead },
        { text="Пауза між запитами", keep_menu_open=true, callback=function() self:pauseDialog() end },
    }
end

function Molytva:showPackInfo(pack)
    pack = pack or self:loadPack()
    if not pack then return end
    local details = {
        "Назва: " .. pack.meta.name,
        "Версія: " .. pack.meta.version,
        "Ліцензія: " .. pack.meta.license,
        "Джерело: " .. pack.meta.source,
    }
    if pack.meta.calendar then
        details[#details + 1] = "Календар: " .. (CALENDAR_NAMES[pack.meta.calendar] or pack.meta.calendar)
    end
    if pack.meta.generated then details[#details + 1] = "Створено: " .. pack.meta.generated end
    if pack.meta.format == 1 then
        details[#details + 1] = "Це демонстраційний пакет. Підключіть Wi-Fi і виберіть Меню → Оновити тексти."
    end
    if type(pack.meta.range) == "table" then
        details[#details + 1] = "Діапазон: " .. tostring(pack.meta.range["from"])
            .. " — " .. tostring(pack.meta.range["to"])
    end
    local viewer
    viewer = TextViewer:new{
        title = "Про пакет",
        text = table.concat(details, "\n"),
        show_menu = false,
        buttons_table = { { { text = "Закрити", callback = function() UIManager:close(viewer) end } } },
    }
    Session.last_dialog = viewer
    UIManager:show(Session.last_dialog)
end

function Molytva:addToMainMenu(menu_items)
    -- Top-level entry in the "main" tab (next to History and Favorites); one tap opens the app.
    -- Updating and settings live inside the app (Меню).
    menu_items.molytva = {
        text = "Молитва",
        sorting_hint = "main",
        callback = function() self:showApp(today(), true) end,
    }
end

return Molytva
