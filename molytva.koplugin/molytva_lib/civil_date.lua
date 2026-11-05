-- Gregorian civil dates, represented without os.time or a device timezone.
local M = {}

function M.jdn(year, month, day)
    local a = math.floor((14 - month) / 12)
    local y = year + 4800 - a
    local m = month + 12 * a - 3
    return day + math.floor((153 * m + 2) / 5) + 365 * y
        + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400) - 32045
end

function M.from_jdn(jdn)
    local a = jdn + 32044
    local b = math.floor((4 * a + 3) / 146097)
    local c = a - math.floor(146097 * b / 4)
    local d = math.floor((4 * c + 3) / 1461)
    local e = c - math.floor(1461 * d / 4)
    local m = math.floor((5 * e + 2) / 153)
    return {
        year = 100 * b + d - 4800 + math.floor(m / 10),
        month = m + 3 - 12 * math.floor(m / 10),
        day = e - math.floor((153 * m + 2) / 5) + 1,
    }
end

function M.new(year, month, day)
    assert(type(year) == "number" and type(month) == "number" and type(day) == "number", "invalid date")
    local date = M.from_jdn(M.jdn(year, month, day))
    assert(date.year == year and date.month == month and date.day == day, "invalid date")
    return date
end

function M.add(date, days)
    return M.from_jdn(M.jdn(date.year, date.month, date.day) + days)
end

function M.diff(a, b)
    return M.jdn(a.year, a.month, a.day) - M.jdn(b.year, b.month, b.day)
end

function M.iso(date)
    return string.format("%04d-%02d-%02d", date.year, date.month, date.day)
end

function M.weekday(date)
    -- Monday = 1, Sunday = 7.
    return M.jdn(date.year, date.month, date.day) % 7 + 1
end

return M
