-- Transactional updater; all external effects are injected for Lua 5.1 tests.
local Builder = require("molytva_lib.builder")
local M = {}
local function read_json(fs,path,decode)
    local raw=fs:read(path)
    if not raw then return nil end
    local ok,value=pcall(decode,raw)
    if ok and type(value)=="table" then return value end
    return nil
end
local function month_prefix(path) return path:match("^assets/%d%d%d%dn?/%d%d/files%.zip$") ~= nil end
local function cached_path(path) return "molytva-cache/prayer-service.pp.ua/"..path end
function M.run(opts)
    local fs,fetcher=assert(opts.fs),assert(opts.fetcher)
    local decode,encode=opts.decode or Builder.decode,opts.encode or Builder.encode
    local calendar=opts.calendar or "new-julian"
    assert(calendar=="new-julian" or calendar=="gregorian","Invalid calendar")
    local ahead=opts.months_ahead or 1
    assert(ahead==1 or ahead==2 or ahead==3,"Invalid months ahead")
    local start=assert(opts.start,"Start month required")
    local paths=Builder.paths(start,ahead+1,calendar)
    local meta_path="molytva-cache/prayer-service.pp.ua/cache-meta.json"
    local meta=read_json(fs,meta_path,decode) or {}
    local warnings={}; local changed=false; local available=0
    local pause=opts.sleep or function() end
    local delay=opts.delay or 5
    local progress=opts.progress or function() return true end
    for i,path in ipairs(paths) do
        if not progress("Завантаження "..path,i,#paths) then return nil,"Скасовано" end
        if i>1 then pause(delay) end
        local cache=cached_path(path)
        local status,body,modified=fetcher:fetch(path,meta[path])
        if status==304 then
            if not fs:exists(cache) then return nil,"304 without cached archive: "..path end
        elseif status==200 then
            if type(body)~="string" then return nil,"Empty download: "..path end
            local tmp=cache..".download"
            local ok,err=fs:write(tmp,body)
            if not ok then return nil,"Cache write failed: "..tostring(err) end
            ok,err=fs:rename(tmp,cache)
            if not ok then fs:remove_tree(tmp); return nil,"Cache rename failed: "..tostring(err) end
            if modified then meta[path]=modified end
            changed=true
        elseif status==404 and month_prefix(path) then
            warnings[#warnings+1]="Ще не опубліковано: "..path
        else return nil,"HTTP "..tostring(status).." for "..path..(body and (": "..tostring(body)) or "") end
        if i>4 and fs:exists(cache) then available=available+1 end
    end
    local meta_ok,meta_err=fs:write(meta_path..".new",encode(meta))
    if not meta_ok then return nil,"Cannot save cache metadata: "..tostring(meta_err) end
    meta_ok,meta_err=fs:rename(meta_path..".new",meta_path)
    if not meta_ok then return nil,"Cannot activate cache metadata: "..tostring(meta_err) end
    local cal=assert(opts.archive(cached_path(paths[1])),"Missing calendar archive")
    local calnames={}; for _,name in ipairs(cal:list()) do calnames[name]=true end
    if cal.close then cal:close() end
    local months=Builder.months_from(start,ahead+1); local suffix=calendar=="gregorian" and "n" or ""
    local usable=0
    for n,ym in ipairs(months) do
        local filename=string.format("calendar%02d%s.txt",ym[1]%100,suffix)
        if not fs:exists(cached_path(paths[4+n])) then
            if n==1 then
                warnings[#warnings+1]="Архів поточного місяця ще недоступний"
                local prior=read_json(fs,"molytva/pack.json",decode)
                return {updated=false,range=prior and prior.range or {from=start,to=start},warnings=warnings}
            end
            break
        end
        if not calnames[filename] then
            if n==1 then return nil,"Missing calendar file: "..filename end
            warnings[#warnings+1]="Ще немає календаря: "..filename
            break
        end
        usable=usable+1
    end
    local current=read_json(fs,"molytva/pack.json",decode)
    local last=months[usable]
    local range_to=string.format("%04d-%02d",last[1],last[2])
    if not changed and current and current.calendar==calendar and current.range
        and current.range["from"]==start and current.range["to"]==range_to then
        return {updated=false,range={from=start,to=range_to},warnings=warnings}
    end
    if not progress("Збирання пакета",#paths+1,#paths+2) then return nil,"Скасовано" end
    local temp="molytva.new"
    fs:remove_tree(temp)
    local writer={write=function(_,path,bytes)
        local ok,err=fs:write(temp.."/"..path,bytes)
        if not ok then error("Write failed: "..tostring(err)) end
    end}
    local ok,report=pcall(Builder.build,{start=start,months=usable,calendar=calendar,writer=writer,
        archive=function(path) return assert(opts.archive(cached_path(path)),"Missing archive: "..path) end,
        sample=opts.sample,decode=decode,encode=encode,generated=opts.today or os.date("%Y-%m-%d")})
    if not ok then fs:remove_tree(temp); return nil,"Build failed: "..tostring(report) end
    if not progress("Застосування пакета",#paths+2,#paths+2) then fs:remove_tree(temp); return nil,"Скасовано" end
    local live="molytva"; local old="molytva.old"; local older="molytva.older"
    -- Keep the existing backup until activation succeeds, then replace it.
    fs:remove_tree(older)
    local had_old=fs:exists(old)
    if had_old then
        local parked,park_err=fs:rename(old,older)
        if not parked then fs:remove_tree(temp); return nil,"Cannot preserve backup: "..tostring(park_err) end
    end
    local had_live=fs:exists(live)
    if had_live then
        local moved,err=fs:rename(live,old)
        if not moved then
            if had_old then fs:rename(older,old) end
            fs:remove_tree(temp)
            return nil,"Cannot preserve old pack: "..tostring(err)
        end
    end
    local swapped,err=fs:rename(temp,live)
    if not swapped then
        local restored=true
        if had_live then restored=fs:rename(old,live) end
        if had_old then fs:rename(older,old) end
        fs:remove_tree(temp)
        return nil,"Cannot activate new pack: "..tostring(err)..(restored and "" or "; rollback failed")
    end
    if had_old then fs:remove_tree(older) end
    for _,w in ipairs(report.warnings) do warnings[#warnings+1]=w end
    return {updated=true,range={from=start,to=range_to},warnings=warnings,report=report}
end
return M
