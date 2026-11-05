-- Format 2 pack builder. No KOReader modules: archives, writer and JSON are injected.
-- Lua patterns operate on UTF-8 bytes. Cyrillic reading references are matched as
-- non-space byte runs between punctuation, then compared as complete UTF-8 strings.
local M = {}
local array_tag = {}
function M.array(value) return setmetatable(value or {}, array_tag) end
local VERSION, SOURCE = require("molytva_lib.about").VERSION, "https://prayer-service.pp.ua"
local LICENSE = "Тексти © «Молитва Церкви» (prayer-service.pp.ua), А. Мартинишин; для особистого некомерційного користування з дозволу автора; комерційне використання заборонено"
local RANKS = { ["#"]="great", ["*"]="vigil", ["+"]="polyeleos", ["@"]="doxology", ["&"]="sixfold" }
local SERVICES = { {"u","ustav","Устав"}, {"s","saints","Святі дня"}, {"tv","vespers","Вечірня"}, {"tu","matins","Утреня"}, {"tc","hours","Часи"}, {"tn","compline","Повечір'я"}, {"o","midnight","Опівнічна"}, {"p","word","Слово на день"}, {"l","presanctified","Передшеосвячена"} }
local TAGS = {"antifon1","antifon2","antifon3","vhidne","tropari","trysviate","prokimen","apostol","aleluia","evanhelie","dostoino","prychasnii","vidpust"}
local TRYSVIATE = '<h4>Трисвяте</h4><p><b>Святий Боже, святий кріпкий, святий безсмертний, помилуй нас</b> <i>(3)</i>.' ..
    '<p><b>Слава Отцю, і Сину, і Святому Духові, і нині, і повсякчас, і на віки віків. Амінь.</b>' ..
    '<p><b>Святий безсмертний, помилуй нас.</b>' ..
    '<p><b>Святий Боже, святий кріпкий, святий безсмертний, помилуй нас.</b>'
local DOSTOINO = '<b>Достойно є воістину величати блаженною Тебе, Богородицю, ' ..
    'присноблаженну і пренепорочну і Матір Бога нашого. Чеснішу від херувимів ' ..
    'і незрівнянно славнішу від серафимів, що без зотління Бога Слово породила, ' ..
    'сущу Богородицю, Тебе величаємо.</b>'

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
local function replace(s, old, new) return (s:gsub(old:gsub("([^%w])", "%%%1"), function() return new end)) end
local function escape_html(s) return (s:gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&#x27;")) end
local entities = {amp="&",lt="<",gt=">",quot='"',apos="'",nbsp="\194\160"}
local function unescape(s)
    return (s:gsub("&(#?[%w]+);", function(e)
        if entities[e] then return entities[e] end
        local n = e:match("^#x(%x+)$") or e:match("^#X(%x+)$")
        if n then n = tonumber(n,16) else n = tonumber(e:match("^#(%d+)$")) end
        if n and n < 128 then return string.char(n) end
        return "&" .. e .. ";"
    end))
end
local function plain(s)
    -- HTMLParser emits character data; tags separate text but do not add spaces.
    return trim(replace(unescape(s:gsub("<[^>]*>", "")), "\194\160", " "))
end
local function split_br(s)
    local out = M.array()
    s = s:gsub("<[bB][rR]%s*/?>", "\0")
    for part in (s .. "\0"):gmatch("([^%z]*)%z") do
        local p = plain(part)
        if p ~= "" then out[#out+1] = p end
    end
    return out
end
local function json_string(s)
    local escapes = { ['"']='\\"', ['\\']='\\\\', ['\b']='\\b', ['\f']='\\f', ['\n']='\\n', ['\r']='\\r', ['\t']='\\t' }
    return '"' .. s:gsub('[%z\1-\31\\"]', function(c) return escapes[c] or string.format("\\u%04x", c:byte()) end) .. '"'
end
local function encode(value, level)
    level = level or 0
    local kind = type(value)
    if kind == "string" then return json_string(value) end
    if kind == "number" then return tostring(value) end
    if kind == "boolean" then return tostring(value) end
    if kind ~= "table" then error("unsupported JSON value: " .. kind) end
    local keys, array = {}, true
    for k in pairs(value) do keys[#keys+1] = k; if type(k) ~= "number" then array = false end end
    if #keys == 0 then return getmetatable(value) == array_tag and "[]" or "{}" end
    if array then
        for i=1,#keys do if value[i] == nil then array = false; break end end
    end
    if array then table.sort(keys) else table.sort(keys, function(a,b) return tostring(a) < tostring(b) end) end
    local parts = {}
    for _, k in ipairs(keys) do
        parts[#parts+1] = string.rep(" ", 2*level+2) .. (array and "" or json_string(tostring(k)) .. ": ") .. encode(value[k], level+1)
    end
    return (array and "[" or "{") .. "\n" .. table.concat(parts, ",\n") .. "\n" .. string.rep(" ", 2*level) .. (array and "]" or "}")
end
M.encode = function(value) return encode(value) .. "\n" end

-- Minimal decoder for tests and the bundled sample calendars. Device code injects json.decode.
function M.decode(s)
    local pos = 1
    local function ws() pos = (s:find("%S", pos) or (#s+1)) end
    local value
    local function string_value()
        assert(s:sub(pos,pos) == '"'); pos = pos+1
        local out = {}
        while true do
            local c = s:sub(pos,pos); assert(c ~= "", "unterminated JSON string")
            if c == '"' then pos=pos+1; return table.concat(out) end
            if c == "\\" then
                local e = s:sub(pos+1,pos+1)
                local map = { ['"']='"', ['\\']='\\', ['/']='/', b='\b', f='\f', n='\n', r='\r', t='\t' }
                if e == "u" then
                    local n = assert(tonumber(s:sub(pos+2,pos+5),16)); pos=pos+6
                    if n < 128 then c=string.char(n) elseif n < 2048 then c=string.char(192+math.floor(n/64),128+n%64)
                    else c=string.char(224+math.floor(n/4096),128+math.floor(n/64)%64,128+n%64) end
                else c=assert(map[e]); pos=pos+2 end
            else pos=pos+1 end
            out[#out+1]=c
        end
    end
    function value()
        ws(); local c=s:sub(pos,pos)
        if c == '"' then return string_value() end
        if c == "{" or c == "[" then
            pos=pos+1; local t={}; ws(); local closing = c == "{" and "}" or "]"
            if s:sub(pos,pos) == closing then pos=pos+1; return t end
            while true do
                local key
                if c == "{" then ws(); key=string_value(); ws(); assert(s:sub(pos,pos)==":"); pos=pos+1
                else key=#t+1 end
                t[key]=value(); ws(); local delim=s:sub(pos,pos); pos=pos+1
                if delim == closing then return t end
                assert(delim == ",", "invalid JSON delimiter")
            end
        end
        local lit=s:match("^[%w%.%-]+", pos); assert(lit, "invalid JSON")
        pos=pos+#lit
        if lit == "null" then return nil end
        if lit == "true" then return true end
        if lit == "false" then return false end
        return assert(tonumber(lit), "invalid JSON number")
    end
    local result=value(); ws(); assert(pos>#s, "trailing JSON"); return result
end

function M.months_from(start, count)
    local y,m=start:match("^(%d%d%d%d)%-(%d%d)$"); y,m=tonumber(y),tonumber(m)
    assert(y and m and m>=1 and m<=12 and count>=1, "Invalid month range")
    local out={}
    for i=0,count-1 do local n=m-1+i; out[#out+1]={y+math.floor(n/12), n%12+1} end
    return out
end
function M.paths(start,count,calendar)
    local suffix=calendar=="gregorian" and "n" or ""
    local paths={"assets/txt/calendars.zip","assets/txt/templates.zip","zachala/zachala.zip","benedict/benedict.zip"}
    for _,ym in ipairs(M.months_from(start,count)) do paths[#paths+1]=string.format("assets/%04d%s/%02d/files.zip",ym[1],suffix,ym[2]) end
    return paths
end
local function week_label(code)
    if code == "***" then return nil end
    local n,k=code:match("^(%d%d)([edpms])$"); assert(n,"Unknown week code: "..code); n=tonumber(n)
    if k=="m" then return "М'ясопусний тиждень" end
    if k=="s" then return "Сиропусний тиждень" end
    if k=="e" then return "Тиждень "..n.."-й після Пасхи" end
    if k=="d" then return "Тиждень "..n.."-й по Зісланні" end
    return "Тиждень "..n.."-й Великого посту"
end
function M.parse_calendar_row(row)
    row=row:gsub("^\239\187\191", ""):gsub("[\r\n]+$", "")
    local fields={}; for part in (row.."|"):gmatch("(.-)|") do fields[#fields+1]=part end
    assert(#fields==10 and fields[1]:match("^%d%d%d%d%d%d%d%d$"),"Malformed calendar row")
    local saints=M.array()
    for _,item in ipairs(split_br(fields[8])) do
        if not item:find("Тиждень .* по Зісланні") then
            local marker=item:sub(1,1); local saint={title=item}
            if RANKS[marker] then saint.title=trim(item:sub(2)); saint.rank=RANKS[marker] end
            saints[#saints+1]=saint
        end
    end
    local tone=fields[10]:gsub("%*", " ")
    local result={weekday=tonumber(fields[3]),day_type=tonumber(fields[4]),period=tonumber(fields[5]),fast=tonumber(fields[6]),saints=saints,readings=split_br(fields[9])}
    result.week=week_label(fields[2]); result.rank=RANKS[fields[7]]
    result.tone=tonumber(tone:match("Гл%.%s*(%d+)")); result.matins_gospel=tonumber(tone:match("Єв%.%s*(%d+)"))
    return fields[1],result
end
local function text(archive,name)
    local bytes=assert(archive:read(name),"Missing archive file: "..name)
    return bytes:gsub("^\239\187\191", "")
end
local function has(archive,name) return archive.names[name] == true end
local function archive_names(archive)
    local set={}; for _,name in ipairs(archive:list()) do set[name]=true end
    archive.names=set; return archive
end
local function document(title,body,style)
    return '<!DOCTYPE html>\n<html xmlns="http://www.w3.org/1999/xhtml" lang="uk"><head>' ..
        '<meta charset="utf-8" /><title>'..escape_html(title)..'</title><link rel="stylesheet" href="'..(style or "../../style.css")..'" /></head><body>\n'..body..'\n</body></html>\n'
end
local function write_html(writer,path,title,body,archive,style)
    if archive then
        body=body:gsub('<[iI][mM][gG][^>]*>',function(tag)
            local src=tag:match('[sS][rR][cC]=["\']([^"\']+)["\']')
            if not src or not src:match("^[%w_%.%-]+%.[jJ][pP][eE]?[gG]$") and not src:match("^[%w_%.%-]+%.[pP][nN][gG]$") and not src:match("^[%w_%.%-]+%.[gG][iI][fF]$") then return "" end
            if not has(archive,src) then return "" end
            writer:write(path:match("^(.*)/").."/"..src,archive:read(src)); return tag
        end)
    end
    writer:write(path,document(title,body,style))
end
-- Literal prefix check replaces regex alternation, and leaves unrelated placeholders intact.
local function expand(s,zachala,warnings)
    return (s:gsub("#([a-z][a-z]%d%d%d[a-z]?)",function(stem)
        local prefix=stem:sub(1,2)
        if prefix~="ap" and prefix~="mt" and prefix~="mr" and prefix~="lk" and prefix~="iv" then return "#"..stem end
        local name=stem..".html"
        if not has(zachala,name) then warnings[#warnings+1]="missing zachalo "..name; return "" end
        return text(zachala,name)
    end))
end
local function extract_tag(s,tag)
    local found=s:match("<"..tag..">(.-)</"..tag..">") or ""
    return replace(found,"\194\160"," ")
end
local function assemble(propers,templates,zachala,warnings)
    local name=propers:match("<[uU][sS][tT][aA][vV][^>]*liturgia=([a-z0-9_]+)%s*/>")
    if not name then error("No Liturgy template in bDD") end
    local template=templates[name..".html"]
    if not template then error("Missing Liturgy template: "..name..".html") end
    local v={}; for _,tag in ipairs(TAGS) do v[tag]=expand(extract_tag(propers,tag),zachala,warnings) end
    for _,tag in ipairs({"antifon1","antifon2","antifon3"}) do v[tag]=replace(replace(v[tag],"<b><i>","<h4>"),"</i></b>","</h4>") end
    v.vhidne=replace(v.vhidne,"<p>"," ")
    if v.trysviate=="" then v.trysviate=TRYSVIATE end
    if v.dostoino=="" then v.dostoino=DOSTOINO end
    for _,pair in ipairs({{"apostol","ap"},{"evanhelie","ev"}}) do
        local raw=v[pair[1]]; local pos=raw:find("<p>",6,true)
        v[pair[2].."_title"]=pos and raw:sub(1,pos-1) or ""
        v[pair[2].."_text"]=pos and raw:sub(pos) or raw
    end
    local order={}; for _,tag in ipairs(TAGS) do order[#order+1]=tag end
    for _,tag in ipairs({"ap_title","ap_text","ev_title","ev_text"}) do order[#order+1]=tag end
    for _,tag in ipairs(order) do template=replace(template,"#"..tag,v[tag]) end
    local unresolved={}; for tag in template:gmatch("#[a-z_]+%d*") do unresolved[tag]=true end
    if next(unresolved) then local a={}; for k in pairs(unresolved) do a[#a+1]=k end; table.sort(a); error("Unresolved Liturgy placeholder: "..table.concat(a,", ")) end
    return replace(template,"\194\160"," "),name
end
local function reading_file(line)
    local kind
    if line:sub(1,5)=="Ап." then kind="ap" elseif line:sub(1,5)=="Єв." then kind="ev" else return nil end
    local dash=line:find("–",1,true) or line:find("-",1,true)
    local rest=dash and line:sub(dash + (line:sub(dash,dash)=="-" and 1 or #"–")):match("^%s*(.+)")
    if not rest then return nil end
    rest=rest:gsub("^%d%s+", "")
    local book,num=rest:match("^([^%.%s]+)%.%s*(.*)$")
    if not book then return nil end
    num=num:gsub("^зач%.%s*", ""):match("^(%d+)")
    if not num then return nil end
    local prefix=kind=="ap" and "ap" or ({["Мт"]="mt",["Мр"]="mr",["Лк"]="lk",["Йо"]="iv",["Ів"]="iv"})[book]
    return prefix and string.format("%s%03d.html",prefix,tonumber(num)) or nil
end
local function eink_style(s)
    s=s:gsub("/%*.-%*/", "")
    -- Match a declaration boundary and remove only colour/background declarations.
    s=s:gsub("([;{%s])([%w%-]+%s*:%s*[^;{}]*;?)",function(boundary,decl)
        local low=decl:match("^([%w%-]+)%s*:"):lower()
        if low=="color" or low=="border-color" or low:match("^background") then return boundary end
        return boundary..decl
    end)
    return trim(s).."\nbody { color: black; background: white; font-size: 1.1em; line-height: 1.35; }\nh1,h2,h3,h4 { font-weight: bold; }\ni,em,.rubric { font-style: italic; }\n"
end
local function days_in_month(y,m)
    local n={31,28,31,30,31,30,31,31,30,31,30,31}; if m==2 and y%4==0 and (y%100~=0 or y%400==0) then return 29 end; return n[m]
end
function M.build(args)
    local start,count,calendar=args.start,args.months,args.calendar or "new-julian"
    local months=M.months_from(start,count); local paths=M.paths(start,count,calendar)
    local archives={}; for _,path in ipairs(paths) do archives[path]=archive_names(assert(args.archive(path),"Missing cached archive: "..path)) end
    local writer=args.writer; local json=args.encode or M.encode
    local function write_json(path,v) writer:write(path,json(v)) end
    local template_zip=archives[paths[2]]; local templates={}
    for name in pairs(template_zip.names) do if name:match("%.html$") then templates[name]=text(template_zip,name) end end
    for _,name in ipairs({"fixed","movable"}) do
        local value=args.sample(name); if type(value)=="string" then value=(args.decode or M.decode)(value) end
        write_json("calendar/"..name..".json",value)
    end
    local years={}; local suffix=calendar=="gregorian" and "n" or ""
    for _,ym in ipairs(months) do
        local year=ym[1]
        if not years[year] then
            local filename=string.format("calendar%02d%s.txt",year%100,suffix)
            local cal=archives[paths[1]]; assert(has(cal,filename),"Missing calendar file: "..filename)
            local entries={}
            for row in (text(cal,filename).."\n"):gmatch("(.-)\n") do
                if trim(row)~="" then local key,value=M.parse_calendar_row(row); entries[key:sub(5,6).."-"..key:sub(7,8)]=value end
            end
            years[year]=entries; write_json("calendar/"..year..".json",entries)
        end
    end
    local zachala=archives[paths[3]]; local benedict=archives[paths[4]]
    local report={counts={},missing=M.array(),warnings=M.array(),liturgy_templates={}}; local index={}
    local function count(service) report.counts[service]=(report.counts[service] or 0)+1 end
    for _,ym in ipairs(months) do
        local y,m=ym[1],ym[2]; local archive=archives[string.format("assets/%04d%s/%02d/files.zip",y,suffix,m)]
        for d=1,days_in_month(y,m) do
            local date=string.format("%04d-%02d-%02d",y,m,d); local dd=string.format("%02d",d); local dir="days/"..date
            local available=M.array()
            for _,svc in ipairs(SERVICES) do
                local filename=svc[1]:sub(1,1)..dd..svc[1]:sub(2)..".html"
                if has(archive,filename) then
                    write_html(writer,dir.."/"..svc[2]..".html",svc[3].." — "..date,text(archive,filename),archive)
                    available[#available+1]=svc[2]; count(svc[2])
                else report.missing[#report.missing+1]=date..":"..svc[2] end
            end
            local bfile="b"..dd..".html"
            if has(archive,bfile) then
                local propers=text(archive,bfile); local warnings={}
                write_html(writer,dir.."/liturgy-propers.html","Змінні частини Літургії — "..date,expand(propers,zachala,warnings),archive)
                available[#available+1]="liturgy-propers"; count("liturgy-propers")
                local ok,body,name=pcall(assemble,propers,templates,zachala,warnings)
                if ok then
                    write_html(writer,dir.."/liturgy.html","Літургія — "..date,body,archive)
                    report.liturgy_templates[date]=name; available[#available+1]="liturgy"; count("liturgy")
                else report.warnings[#report.warnings+1]=date..": "..tostring(body) end
                local unique={}; for _,w in ipairs(warnings) do unique[w]=true end
                local sorted={}; for w in pairs(unique) do sorted[#sorted+1]=w end; table.sort(sorted)
                for _,w in ipairs(sorted) do report.warnings[#report.warnings+1]=date..": "..w end
            else
                report.missing[#report.missing+1]=date..":liturgy"
                report.missing[#report.missing+1]=date..":liturgy-propers"
            end
            local lines=#available>1 and (years[y][string.format("%02d-%02d",m,d)] or {}).readings or nil
            local parts=M.array()
            for _,line in ipairs(lines or {}) do
                local name=reading_file(line)
                if name then
                    if has(zachala,name) then
                        parts[#parts+1]="<h2>"..escape_html(line).."</h2>"..text(zachala,name)
                        if has(benedict,name) then parts[#parts+1]="<h3>Розважання владики Венедикта</h3>"..text(benedict,name) end
                    else report.warnings[#report.warnings+1]=date..": missing zachalo "..name end
                end
            end
            if #parts>0 then
                write_html(writer,dir.."/readings.html","Читання — "..date,table.concat(parts,"\n"),zachala)
                available[#available+1]="readings"; count("readings")
            else report.missing[#report.missing+1]=date..":readings" end
            table.sort(available); index[date]=available
        end
    end
    write_json("days/index.json",index)
    local services=M.array({{id="about-pack",title="Про пакет",file="services/about-pack.html"}})
    write_html(writer,"services/about-pack.html","Про пакет","<h1>Молитва Церкви</h1><p>Пакет для особистого некомерційного користування. Комерційне використання текстів заборонено.</p>",nil,"../style.css")
    for _,pair in ipairs({{"liz","Літургія Івана Золотоустого"},{"lvv","Літургія Василія Великого"}}) do
        local name,title=pair[1],pair[2]
        local generic=templates[name..".html"]:gsub("#[a-z_]+%d*","")
        write_html(writer,"services/"..name..".html",title,generic,template_zip,"../style.css")
        services[#services+1]={id=name,title=title,file="services/"..name..".html"}
    end
    write_json("services/index.json",services)
    writer:write("style.css",eink_style(text(template_zip,"style.css")))
    local last=months[#months]
    write_json("pack.json",{format=2,id="molytva-cerkvy",name="Молитва Церкви",version=VERSION,calendar=calendar,
        generated=args.generated or os.date("%Y-%m-%d"),range={from=start,to=string.format("%04d-%02d",last[1],last[2])},license=LICENSE,source=SOURCE})
    write_json("build-report.json",report)
    for _,archive in pairs(archives) do if archive.close then archive:close() end end
    return report
end
return M
