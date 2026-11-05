-- State shared by all plugin instances (FileManager and ReaderUI each create their own).
-- require() caches this table for the whole KOReader session.
return {
    launched = false,      -- started from a launcher (NickelMenu): closing the app quits KOReader
    return_date = nil,     -- day to show again after a service document is closed
    return_file = nil,     -- service document opened from the app
    pending_return = false,
    widgets = {},          -- app screens currently shown
}
