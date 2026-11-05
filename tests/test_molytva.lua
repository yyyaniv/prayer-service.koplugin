local Date = require("molytva_lib.civil_date")
local Paschalion = require("molytva_lib.paschalion")
local Day = require("molytva_lib.liturgical_day")
local Pack = require("molytva_lib.pack")
local UkrainianDate = require("molytva_lib.uk_date")

local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if not ok then error(name .. ": " .. tostring(err), 0) end
    passed = passed + 1
    print("ok " .. name)
end
local function date(y, m, d) return Date.new(y, m, d) end
local function at(offset, year) return Date.add(Paschalion.pascha(year or 2026), offset) end
local empty = setmetatable({fixed = {}, movable = {}, meta = {format = 1}}, Pack)
local function fast(d, level, period, pack)
    local got, label, got_period = Day.fast(d, pack or empty)
    assert(got == level and got_period == period,
        Date.iso(d) .. ": got " .. tostring(got) .. "/" .. tostring(got_period))
    assert(label == (level == 2 and "Строгий піст" or (level == 1 and "Піст" or nil)))
end

test("Pascha and tone", function()
    assert(Date.iso(Paschalion.pascha(2026)) == "2026-04-12")
    assert(Day.tone(at(7)) == 1)
    assert(Day.tone(date(2026, 1, 7)) == 5)
    for i, expected in ipairs({1, 2, 3, 4, 5, 6, 8}) do assert(Day.tone(at(i - 1)) == expected) end
end)

test("strict fasting days", function()
    fast(at(-48), 2, "Великий піст")
    fast(at(-2), 2, "Страсний тиждень")
end)

test("individual fasting days and Sunday exceptions", function()
    fast(date(2026, 12, 24), 1, "Пилипівка")
    fast(date(2026, 1, 5), 1, nil)
    fast(date(2025, 1, 5), 0, nil)
    fast(date(2023, 12, 24), 0, "Пилипівка")
    fast(date(2026, 8, 29), 1, nil)
    fast(date(2028, 9, 14), 1, nil) -- Sunday
end)

test("great feast cancels fasting except Exaltation", function()
    local p = setmetatable({fixed = { ["11-20"] = {{title="Свято", rank="great"}},
        ["09-14"] = {{title="Хрест", rank="great"}} }, movable = {}}, Pack)
    fast(date(2026, 11, 20), 0, "Пилипівка", p)
    fast(date(2026, 9, 14), 1, nil, p)
end)

test("fast-free weeks", function()
    fast(date(2026, 1, 2), 0, "Суцільний тиждень")
    fast(date(2026, 12, 25), 0, "Суцільний тиждень")
    fast(at(-68), 0, "Суцільний тиждень")
    fast(at(5), 0, "Суцільний тиждень")
    fast(at(54), 0, "Суцільний тиждень")
end)

test("Great Lent first week and later weekdays", function()
    fast(at(-47), 1, "Великий піст")
    fast(at(-46), 1, "Великий піст")
    fast(at(-45), 1, "Великий піст")
    fast(at(-44), 1, "Великий піст")
    fast(at(-43), 0, "Великий піст")
    fast(at(-42), 0, "Великий піст")
    fast(at(-41), 1, "Великий піст")
    fast(at(-40), 0, "Великий піст")
end)

test("Holy Week including Palm Sunday and Saturday", function()
    fast(at(-7), 0, nil)
    for offset = -6, -3 do fast(at(offset), 1, "Страсний тиждень") end
    fast(at(-1), 0, "Страсний тиждень")
end)

test("three seasonal fasts and ordinary Friday", function()
    fast(date(2026, 6, 12), 1, "Петрів піст")
    fast(date(2026, 6, 11), 0, "Петрів піст")
    fast(date(2026, 8, 5), 1, "Успенський піст")
    fast(date(2026, 8, 6), 0, "Успенський піст")
    fast(date(2026, 11, 18), 1, "Пилипівка")
    fast(date(2026, 11, 19), 0, "Пилипівка")
    fast(date(2026, 10, 9), 1, nil)
    fast(date(2026, 10, 7), 0, nil)
end)

test("feast lookup and v1 day file", function()
    local p = setmetatable({root="/pack", fixed={["04-12"]={{title="Велике",rank="great"}}}, movable={},
        file_exists=function(path) return path == "/pack/days/04-12.html" end}, Pack)
    assert(p:feasts(date(2026,4,12),0)[1].title == "Велике")
    assert(p:day_file(date(2026,4,12),0) == "/pack/days/04-12.html")
end)

local root = os.getenv("MOLYTVA_TEST_DIR") .. "/fixtures/format2"
local function decode(content)
    if content:find('"format":2',1,true) then return {format=2,id="synthetic",name="Test",version="2",license="test",source="local",
        calendar="new-julian",generated="2026-11-05",range={["from"]="2026-11",["to"]="2026-11"}} end
    if content:find('"format":1',1,true) then return {format=1,id="synthetic",name="Test",version="1",license="test",source="local"} end
    if content:match('^%s*{}') then return {} end
    if content:find('"id":"about"',1,true) then return {{id="about",title="About",file="services/about.html"}} end
    if content:find('"11-04"',1,true) then return {
        ["11-04"]={week="Synthetic week",tone=5,matins_gospel=3,fast=2,
            period=0,saints={{title="Synthetic saint",rank="vigil"}},readings={"Synthetic reading"}},
        ["11-08"]={week={},tone={},matins_gospel={},fast=0,period=3,
            saints={{title="Null rank",rank={}}},readings={}}} end
    error("unexpected JSON fixture")
end

test("format 2 lazy years and day data precedence", function()
    local p = assert(Pack.load(root, decode))
    assert(next(p.years) == nil)
    local d = Day.for_date(date(2026,11,4),p)
    assert(d.tone == 5 and d.matins_gospel == 3 and d.week_label == "Synthetic week")
    assert(d.fast_level == 2 and d.fast_label == "Строгий піст")
    assert(d.saints[1].rank == "vigil" and d.readings[1] == "Synthetic reading")
    assert(p.years[2026] ~= nil and p.years[2025] == nil)
    local null_day = Day.for_date(date(2026,11,8),p)
    assert(null_day.week_label == nil and null_day.tone == nil and null_day.matins_gospel == nil)
    assert(null_day.fast_label == "Загальниця" and null_day.saints[1].rank == nil)
    assert(p:day_data(date(2025,11,4)) == nil and p.years[2025] == false)
end)

test("format 2 service paths and next-day vespers", function()
    local p = assert(Pack.load(root, decode))
    local d = date(2026,11,4)
    assert(p:day_service(d,"ustav") == root .. "/days/2026-11-04/ustav.html")
    assert(p:day_view_service(d,"vespers") == root .. "/days/2026-11-05/vespers.html")
    assert(p:day_view_service(d,"ustav") == root .. "/days/2026-11-04/ustav.html")
    assert(p:day_service(d,"vespers") == nil)
    assert(p:day_service(d,"../outside") == nil)
    assert(p:day_service(d,"/outside") == nil)
    assert(p:day_service(d,"nonexistent") == nil)
end)

test("format 1 still loads and unknown format rejects", function()
    local p = assert(Pack.load(os.getenv("MOLYTVA_TEST_DIR") .. "/fixtures/format1",decode))
    assert(p:day_data(date(2026,11,4)) == nil and p:day_service(date(2026,11,4),"ustav") == nil)
    local bad, err = Pack.load(os.getenv("MOLYTVA_TEST_DIR") .. "/fixtures/unknown-format",function() return {format=3} end)
    assert(bad == nil and err:find("Невідомий формат",1,true))
end)

test("service path safety and Ukrainian date", function()
    local p = setmetatable({root="/pack",file_exists=function(path) return path == "/pack/services/ok.html" end},Pack)
    assert(p:service_path({file="services/ok.html"}))
    assert(p:service_path({file="services/../outside.html"}) == nil)
    assert(UkrainianDate.format(date(2026,11,4)) == "середа, 4 листопада 2026")
end)
print(string.format("%d tests passed", passed))
