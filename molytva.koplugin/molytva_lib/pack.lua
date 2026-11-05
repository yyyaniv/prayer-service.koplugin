-- Text-pack I/O and lookup. Pass a JSON decoder; this module has no KOReader dependency.
local Date = require("molytva_lib.civil_date")
local M = {}
M.__index = M

local rank_order = { great = 1, major = 2, ordinary = 3 }

local function exists(path)
    local file = io.open(path, "rb")
    if file then file:close(); return true end
    return false
end

local function read_json(path, decoder)
    local file, err = io.open(path, "rb")
    if not file then return nil, "Не вдалося відкрити " .. path .. ": " .. tostring(err) end
    local content = file:read("*a")
    file:close()
    local ok, value = pcall(decoder, content)
    if not ok or type(value) ~= "table" then
        return nil, "Некоректний JSON у " .. path .. ": " .. tostring(value)
    end
    return value
end

local function safe_service_path(path)
    return type(path) == "string" and path:match("^services/.+%.html$")
        and not path:find("..", 1, true) and not path:find("//", 1, true)
        and not path:find("\\", 1, true) and not path:find("%c")
end

function M.choose(user_root, bundled_root, file_exists)
    file_exists = file_exists or exists
    if file_exists(user_root .. "/pack.json") then return user_root end
    return bundled_root
end

function M.load(root, decoder, file_exists)
    assert(type(decoder) == "function", "JSON decoder required")
    file_exists = file_exists or exists
    local meta, err = read_json(root .. "/pack.json", decoder)
    if not meta then return nil, err end
    if meta.format ~= 1 and meta.format ~= 2 then
        return nil, "Невідомий формат пакета: " .. tostring(meta.format) .. ". Підтримуються формати 1 і 2."
    end
    for _, key in ipairs({ "id", "name", "version", "license", "source" }) do
        if type(meta[key]) ~= "string" or meta[key] == "" then
            return nil, "У pack.json відсутнє поле " .. key
        end
    end
    if meta.format == 2 and (meta.calendar ~= "new-julian" and meta.calendar ~= "gregorian"
        or type(meta.generated) ~= "string" or type(meta.range) ~= "table"
        or type(meta.range["from"]) ~= "string" or type(meta.range["to"]) ~= "string") then
        return nil, "У pack.json відсутні календар або діапазон формату 2"
    end
    local fixed, fixed_err = read_json(root .. "/calendar/fixed.json", decoder)
    if not fixed then return nil, fixed_err end
    local movable, movable_err = read_json(root .. "/calendar/movable.json", decoder)
    if not movable then return nil, movable_err end
    local services, services_err = read_json(root .. "/services/index.json", decoder)
    if not services then return nil, services_err end
    for _, service in ipairs(services) do
        if type(service.id) ~= "string" or type(service.title) ~= "string"
            or not safe_service_path(service.file) then
            return nil, "Некоректний запис у services/index.json"
        end
    end
    return setmetatable({
        root = root, meta = meta, fixed = fixed, movable = movable,
        services = services, file_exists = file_exists, decoder = decoder, years = {},
    }, M)
end

function M:day_data(date)
    if self.meta.format ~= 2 then return nil end
    local year = date.year
    if self.years[year] == nil then
        local path = self.root .. "/calendar/" .. tostring(year) .. ".json"
        if self.file_exists(path) then
            self.years[year] = read_json(path, self.decoder) or false
        else
            self.years[year] = false
        end
    end
    local entries = self.years[year]
    if not entries then return nil end
    local day = entries[string.format("%02d-%02d", date.month, date.day)]
    if not day then return nil end
    -- KOReader JSON decoders may represent JSON null as a truthy sentinel.
    if type(day.week) ~= "string" then day.week = nil end
    if type(day.tone) ~= "number" then day.tone = nil end
    if type(day.matins_gospel) ~= "number" then day.matins_gospel = nil end
    for _, saint in ipairs(day.saints or {}) do
        if type(saint.rank) ~= "string" then saint.rank = nil end
    end
    return day
end

function M:day_service(date, service_id)
    if self.meta.format ~= 2 or type(service_id) ~= "string"
        or not service_id:match("^[a-z][a-z-]*$") then return nil end
    local iso = Date.iso(date)
    local path = self.root .. "/days/" .. iso .. "/" .. service_id .. ".html"
    if self.file_exists(path) then return path end
    return nil
end

function M:day_view_service(date, service_id)
    if service_id == "vespers" or service_id == "presanctified" then
        return self:day_service(Date.add(date, 1), service_id)
    end
    return self:day_service(date, service_id)
end

function M:feasts(date, offset)
    local key = string.format("%02d-%02d", date.month, date.day)
    local entries = {}
    for _, source in ipairs({ self.fixed[key] or {}, self.movable[tostring(offset)] or {} }) do
        for _, feast in ipairs(source) do
            if type(feast.title) == "string" and rank_order[feast.rank] then
                entries[#entries + 1] = { title = feast.title, rank = feast.rank }
            end
        end
    end
    table.sort(entries, function(a, b)
        if rank_order[a.rank] ~= rank_order[b.rank] then
            return rank_order[a.rank] < rank_order[b.rank]
        end
        return a.title < b.title
    end)
    return entries
end

function M:day_file(date, offset)
    local candidates = {
        "days/" .. Date.iso(date) .. ".html",
        "days/p" .. tostring(offset) .. ".html",
        string.format("days/%02d-%02d.html", date.month, date.day),
    }
    for _, relative in ipairs(candidates) do
        local path = self.root .. "/" .. relative
        if self.file_exists(path) then return path end
    end
    return nil
end

function M:service_path(service)
    if not safe_service_path(service.file) then return nil end
    local path = self.root .. "/" .. service.file
    if self.file_exists(path) then return path end
    return nil
end

return M
