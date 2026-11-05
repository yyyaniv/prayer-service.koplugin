-- KOReader adapters for the pure builder/updater.
local Archiver = require("ffi/archiver")
local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local https = require("ssl.https")
local socket = require("socket")
local socketutil = require("socketutil")
local M = {}
local root = DataStorage:getDataDir()
if root:sub(1,1) ~= "/" then root = lfs.currentdir() .. "/" .. root end
local function full(path) return root.."/"..path end
local function mkdirs(path)
    local current=""
    for component in path:gmatch("[^/]+") do
        current=current.."/"..component
        if lfs.attributes(current,"mode")~= "directory" then
            local ok,err=lfs.mkdir(current)
            if not ok then return nil,err end
        end
    end
    return true
end
local function remove_tree(path)
    local mode=lfs.attributes(path,"mode")
    if mode=="directory" then
        for name in lfs.dir(path) do
            if name~="." and name~=".." then
                local ok,err=remove_tree(path.."/"..name)
                if not ok then return nil,err end
            end
        end
        return lfs.rmdir(path)
    elseif mode then return os.remove(path) end
    return true
end
M.fs={}
function M.fs:exists(path) return lfs.attributes(full(path),"mode")~=nil end
function M.fs:read(path)
    local f=io.open(full(path),"rb"); if not f then return nil end
    local bytes=f:read("*a"); f:close(); return bytes
end
function M.fs:write(path,bytes)
    local ok,err=mkdirs(full(path):match("^(.*)/"))
    if not ok then return nil,err end
    local f; f,err=io.open(full(path),"wb")
    if not f then return nil,err end
    local wrote; wrote,err=f:write(bytes); f:close()
    if not wrote then return nil,err end
    return true
end
function M.fs:rename(from,to) return os.rename(full(from),full(to)) end
function M.fs:remove_tree(path) return remove_tree(full(path)) end
function M.archive(path)
    local reader=Archiver.Reader:new()
    assert(reader:open(full(path)),reader.err or ("Cannot open "..path))
    -- libarchive reads sequentially; random access makes ffi/archiver reopen and rescan the
    -- archive, so read every file once, in order, and serve later reads from memory.
    local names, contents = {}, {}
    for entry in reader:iterate() do
        if entry.mode=="file" then
            names[#names+1]=entry.path
            contents[entry.path]=reader:extractToMemory(entry.path)
        end
    end
    reader:close()
    return {
        list=function() return names end,
        read=function(_,name) return contents[name] end,
        close=function() contents={} end,
    }
end
M.fetcher={}
function M.fetcher:fetch(path,modified)
    local chunks={}
    local About=require("molytva_lib.about")
    local headers={ ["User-Agent"]="molytva.koplugin/"..About.VERSION.." (+"..About.URL..")" }
    if modified then headers["If-Modified-Since"]=modified end
    local request={url="https://prayer-service.pp.ua/"..path,method="GET",
        headers=headers,sink=socketutil.table_sink(chunks)}
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT,socketutil.FILE_TOTAL_TIMEOUT)
    local ok,code,response_headers,status=pcall(function()
        return socket.skip(1,https.request(request))
    end)
    socketutil:reset_timeout()
    if not ok then return nil,tostring(code) end
    if not response_headers then return nil,tostring(status or code) end
    if code==304 then return 304,nil,response_headers["last-modified"] end
    if code==200 then return 200,table.concat(chunks),response_headers["last-modified"] end
    return code,tostring(status or "")
end
return M
