-- Rows for the month calendar screen (like the list view of the «Молитва Церкви» phone app).
local Date = require("molytva_lib.civil_date")
local Day = require("molytva_lib.liturgical_day")

local M = {}

M.month_names = { "Січень", "Лютий", "Березень", "Квітень", "Травень", "Червень",
    "Липень", "Серпень", "Вересень", "Жовтень", "Листопад", "Грудень" }
M.weekday_short = { "Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Нд" }

function M.days_in_month(year, month)
    if month == 12 then return 31 end
    return Date.diff(Date.new(year, month + 1, 1), Date.new(year, month, 1))
end

function M.shift(year, month, delta)
    local index = year * 12 + (month - 1) + delta
    return math.floor(index / 12), index % 12 + 1
end

-- "A; B", but "A. B" after a title ending with a period (a sentence or an abbreviation
-- like "ісп."), so neither ".;" appears nor abbreviation dots get lost.
function M.join_titles(titles)
    local out = {}
    for i, title in ipairs(titles) do
        out[#out + 1] = title
        if i < #titles then out[#out + 1] = title:sub(-1) == "." and " " or "; " end
    end
    return table.concat(out)
end

function M.title(year, month)
    return M.month_names[month] .. " " .. tostring(year)
end

-- Short marks shown on the right of a row: fast and feast rank.
local function marks(day)
    local parts = {}
    for _, saint in ipairs(day.saints or {}) do
        if saint.rank == "great" then parts[#parts + 1] = "свято"; break end
    end
    if day.fast_level == 2 then parts[#parts + 1] = "строгий піст"
    elseif day.fast_level == 1 then parts[#parts + 1] = "піст" end
    if day.fast_label == "Загальниця" then parts[#parts + 1] = "загальниця" end
    return table.concat(parts, " · ")
end

-- Returns rows { date, text, mandatory, bold, today } for every day of the month.
-- Days that fail to compute still get a row, so one bad entry never hides the month.
function M.rows(year, month, pack, today)
    local rows = {}
    for d = 1, M.days_in_month(year, month) do
        local date = Date.new(year, month, d)
        local weekday = Date.weekday(date)
        local ok, day = pcall(Day.for_date, date, pack)
        local titles = {}
        if ok then
            for _, saint in ipairs(day.saints or {}) do
                titles[#titles + 1] = (tostring(saint.title):gsub("%s+$", ""))
            end
        end
        local is_today = today ~= nil and Date.diff(date, today) == 0
        local great = false
        if ok then
            for _, saint in ipairs(day.saints or {}) do
                if saint.rank == "great" then great = true end
            end
        end
        rows[#rows + 1] = {
            date = date,
            text = string.format("%d %s  %s", d, M.weekday_short[weekday],
                #titles > 0 and M.join_titles(titles) or "—"),
            mandatory = ok and marks(day) or nil,
            bold = is_today or weekday == 7 or great,
            today = is_today,
        }
    end
    for _, row in ipairs(rows) do
        if row.today then
            row.mandatory = "сьогодні" .. ((row.mandatory and row.mandatory ~= "") and (" · " .. row.mandatory) or "")
        end
        if row.mandatory == "" then row.mandatory = nil end
    end
    return rows
end

return M
