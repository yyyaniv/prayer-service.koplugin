local Date = require("molytva_lib.civil_date")
local M = {}

function M.pascha(year)
    -- 1899 is needed to find the tone in January 1900.
    assert(year >= 1899 and year <= 2099, "Pascha conversion supports 1900–2099")
    local a, b, c = year % 4, year % 7, year % 19
    local d = (19 * c + 15) % 30
    local e = (2 * a + 4 * b - d + 34) % 7
    local month = math.floor((d + e + 114) / 31)
    local day = (d + e + 114) % 31 + 1
    -- Meeus gives a Julian calendar date. 1900–2099 differ by 13 days.
    return Date.add(Date.new(year, month, day), year == 1899 and 12 or 13)
end

return M
