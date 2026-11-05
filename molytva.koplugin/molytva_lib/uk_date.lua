local Date = require("molytva_lib.civil_date")
local M = {}

local weekdays = { "понеділок", "вівторок", "середа", "четвер", "п’ятниця", "субота", "неділя" }
local months = { "січня", "лютого", "березня", "квітня", "травня", "червня",
    "липня", "серпня", "вересня", "жовтня", "листопада", "грудня" }

function M.format(date)
    return string.format("%s, %d %s %d", weekdays[Date.weekday(date)], date.day, months[date.month], date.year)
end

return M
