local Date = require("molytva_lib.civil_date")
local Paschalion = require("molytva_lib.paschalion")
local M = {}

-- Each day of Bright Week has its own tone; tone 7 is skipped.
local bright_week_tones = { 1, 2, 3, 4, 5, 6, 8 }

local function month_day(date)
    return date.month * 100 + date.day
end

function M.pascha_offset(date)
    return Date.diff(date, Paschalion.pascha(date.year))
end

function M.tone(date)
    local offset = M.pascha_offset(date)
    if offset >= 0 and offset <= 6 then return bright_week_tones[offset + 1], "Світлий тиждень" end
    if offset == -7 then return nil, "Квітна неділя" end
    if offset >= -6 and offset <= -1 then return nil, "Страсний тиждень" end
    local thomas = Date.add(Paschalion.pascha(date.year), 7)
    if Date.diff(date, thomas) < 0 then
        thomas = Date.add(Paschalion.pascha(date.year - 1), 7)
    end
    return math.floor(Date.diff(date, thomas) / 7) % 8 + 1, nil
end

function M.fast(date, pack)
    local md = month_day(date)
    local offset = M.pascha_offset(date)
    local weekday = Date.weekday(date)
    local period
    if offset >= -48 and offset <= -8 then period = "Великий піст"
    elseif offset >= -6 and offset <= -1 then period = "Страсний тиждень"
    elseif offset >= 57 and md <= 628 then period = "Петрів піст"
    elseif md >= 801 and md <= 814 then period = "Успенський піст"
    elseif md >= 1115 and md <= 1224 then period = "Пилипівка" end
    local level = 0
    if offset == -48 or offset == -2 then level = 2
    elseif md == 914 then level = 1
    elseif (md == 1224 or md == 105) and weekday ~= 7 then level = 1
    elseif md == 829 then level = 1
    else
        local great = false
        if pack then
            for _, feast in ipairs(pack:feasts(date, offset)) do
                if feast.rank == "great" then great = true; break end
            end
        end
        if great then level = 0
        elseif md >= 1225 or md <= 104 or (offset >= -70 and offset <= -64)
            or (offset >= 0 and offset <= 6) or (offset >= 49 and offset <= 55) then
            period = "Суцільний тиждень"
        elseif offset >= -48 and offset <= -8 then
            if weekday == 1 or weekday == 3 or weekday == 5
                or (offset <= -44 and weekday <= 5) then level = 1 end
        elseif offset >= -6 and offset <= -1 then
            if offset >= -6 and offset <= -3 then level = 1 end
        elseif period == "Петрів піст" or period == "Успенський піст" or period == "Пилипівка" then
            if weekday == 3 or weekday == 5 then level = 1 end
        elseif weekday == 5 then level = 1 end
    end
    local label = level == 2 and "Строгий піст" or (level == 1 and "Піст" or nil)
    return level, label, period
end

function M.fast_label(date, pack)
    local _, label = M.fast(date, pack)
    return label
end

function M.for_date(date, pack)
    local offset = M.pascha_offset(date)
    local calculated_tone, calculated_week = M.tone(date)
    local data = pack:day_data(date)
    local level, label, period = M.fast(date, pack)
    if data then
        level = type(data.fast) == "number" and data.fast or 0
        label = level == 2 and "Строгий піст" or (level == 1 and "Піст" or nil)
        if data.period == 3 then label = "Загальниця"; period = "Суцільний тиждень" end
    end
    local feasts = pack:feasts(date, offset)
    local bright = offset >= 0 and offset <= 6
    local tone = calculated_tone
    local week_label = calculated_week
    if data then
        -- Accept only real values: a JSON null may decode to a non-nil sentinel on device.
        tone = type(data.tone) == "number" and data.tone or nil
        if type(data.week) == "string" then week_label = data.week end
    end
    if bright then tone = calculated_tone end
    return {
        date = date,
        pascha_offset = offset,
        feasts = feasts,
        saints = data and data.saints or feasts,
        readings = data and data.readings or {},
        tone = tone,
        matins_gospel = data and type(data.matins_gospel) == "number" and data.matins_gospel or nil,
        week_label = week_label,
        fast_level = level,
        fast_label = label,
        fast_period = period,
        proper_path = pack:day_file(date, offset),
    }
end

return M
