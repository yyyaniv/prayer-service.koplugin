local B = require("molytva_lib.builder")
local U = require("molytva_lib.updater")
local passed=0
local function test(name,fn) fn(); passed=passed+1; print("ok - "..name) end
local function archive(files)
    return {list=function() local n={}; for k in pairs(files) do n[#n+1]=k end; return n end,
        read=function(_,name) return files[name] end}
end
local rows={}
for i,code in ipairs({"01e","02d","03p","00m","00s","***"}) do
    rows[#rows+1]=string.format("202601%02d|%s|1|3|2|1|*|<b>#Святий</b><br>Тиждень 2-й по Зісланні|Ап. – Кол. зач. 1<br>Єв. – Лк. зач. 2|Гл. 5. Єв. 1",i,code)
end
local files={
    ["assets/txt/calendars.zip"]={ ["calendar26.txt"]=table.concat(rows,"\r\n") },
    ["assets/txt/templates.zip"]={ ["liz.html"]="<div>#trysviate|#dostoino|#ap_title|#ap_text|#ev_title|#ev_text|#vhidne|#antifon1</div>",
        ["lvv.html"]="<p>#trysviate</p>", ["style.css"]="body { color: red; font-size: 12px; }" },
    ["zachala/zachala.zip"]={ ["ap001.html"]="<p>Апостол</p>", ["lk002.html"]="<p>Євангеліє</p>" },
    ["benedict/benedict.zip"]={ ["ap001.html"]="<p>Розважання</p>" },
    ["assets/2026/01/files.zip"]={ ["u01.html"]="<img src=\"icon.jpg\"><p>Устав</p>", ["icon.jpg"]="synthetic image",
        ["s01.html"]="<p>Святий</p>", ["b01.html"]='<ustav custom=n liturgia=liz /><antifon1><b><i>Антифон</i></b></antifon1><vhidne><p>Вхід</vhidne><apostol><p>Назва</p><p>#ap001\194\160</p></apostol><evanhelie><p>Євангеліє</p><p>#lk002 #mt003</p></evanhelie>' },
}
local function build()
    local out={}; local writer={write=function(_,p,s) out[p]=s end}
    local report=B.build{start="2026-01",months=1,archive=function(path) return archive(assert(files[path])) end,
        writer=writer,sample=function() return "{}" end,generated="2026-01-01"}
    return out,report
end
test("Python-compatible sorted JSON and escaping",function()
    local actual=B.encode({b=B.array({"line\n\t\"\\",true}),a={},z=B.array()})
    assert(actual=='{\n  "a": {},\n  "b": [\n    "line\\n\\t\\\"\\\\",\n    true\n  ],\n  "z": []\n}\n')
end)
test("calendar codes, ranks, fasting, readings, and absent null fields",function()
    local out=build(); local c=B.decode(out["calendar/2026.json"])
    assert(c["01-01"].week=="Тиждень 1-й після Пасхи")
    assert(c["01-02"].week=="Тиждень 2-й по Зісланні")
    assert(c["01-03"].week=="Тиждень 3-й Великого посту")
    assert(c["01-04"].week=="М'ясопусний тиждень")
    assert(c["01-05"].week=="Сиропусний тиждень")
    assert(c["01-06"].week==nil and not out["calendar/2026.json"]:find('"week": null',1,true))
    assert(c["01-01"].rank=="vigil" and c["01-01"].saints[1].rank=="great")
    assert(c["01-01"].fast==1 and c["01-01"].period==2 and c["01-01"].tone==5 and c["01-01"].matins_gospel==1)
end)
test("all saint and day rank symbols",function()
    local expected={ ["#"]="great",["*"]="vigil",["+"]="polyeleos",["@"]="doxology",["&"]="sixfold" }
    for marker,rank in pairs(expected) do
        local _,entry=B.parse_calendar_row("20260101|01e|1|0|0|0|"..marker.."|"..marker.."Святий||")
        assert(entry.rank==rank and entry.saints[1].rank==rank)
    end
end)
test("liturgy defaults, NBSP, zachala, missing warning, readings and image",function()
    local out,report=build()
    assert(out["days/2026-01-01/liturgy.html"]:find("Святий Боже",1,true))
    assert(out["days/2026-01-01/liturgy.html"]:find("Достойно є",1,true))
    assert(out["days/2026-01-01/liturgy.html"]:find("Апостол",1,true))
    assert(not out["days/2026-01-01/liturgy.html"]:find("\194\160",1,true))
    assert(not out["days/2026-01-01/liturgy.html"]:find("#mt003",1,true))
    assert(out["days/2026-01-01/readings.html"]:find("Розважання",1,true))
    assert(out["days/2026-01-01/icon.jpg"]=="synthetic image")
    assert(report.warnings[1]=="2026-01-01: missing zachalo mt003.html")
end)
test("builder deterministic",function()
    local a,b=build(),build()
    for path,bytes in pairs(a) do assert(b[path]==bytes,path) end
end)
local function fake_fs()
    local data={}
    local fs={data=data,fail_swap=false}
    function fs:exists(path)
        if data[path] then return true end
        for k in pairs(data) do if k:sub(1,#path+1)==path.."/" then return true end end
        return false
    end
    function fs:read(path) return data[path] end
    function fs:write(path,bytes) data[path]=bytes; return true end
    function fs:remove_tree(path)
        for k in pairs(data) do if k==path or k:sub(1,#path+1)==path.."/" then data[k]=nil end end
        return true
    end
    function fs:rename(from,to)
        if self.fail_swap and from=="molytva.new" then return nil,"simulated swap failure" end
        local moved={}; for k,v in pairs(data) do
            if k==from or k:sub(1,#from+1)==from.."/" then moved[to..k:sub(#from+1)]=v; data[k]=nil end
        end
        if next(moved)==nil then return nil,"missing source" end
        for k,v in pairs(moved) do data[k]=v end
        return true
    end
    return fs
end
test("updater paths, pauses, 304 and atomic rollback",function()
    local fs=fake_fs(); local calls={}; local pauses={}; local unchanged=false
    local fetcher={fetch=function(_,path,modified)
        calls[#calls+1]={path,modified}
        if path:find("2027n/02",1,true) then return 404,"missing" end
        if unchanged then return 304,nil end
        return 200,"synthetic zip","Wed, 01 Jan 2026 00:00:00 GMT"
    end}
    local cal_files={ ["calendar26n.txt"]=files["assets/txt/calendars.zip"]["calendar26.txt"], ["calendar27n.txt"]="20270101|***|1|0|0|0|-|||" }
    local archive_for=function(path)
        if path:find("calendars.zip",1,true) then return archive(cal_files) end
        local p=path:gsub("^molytva%-cache/prayer%-service%.pp%.ua/","")
        if p:find("2027n/01",1,true) then return archive({["u01.html"]="<p>New year</p>"}) end
        p=p:gsub("2026n/12","2026/01")
        return archive(files[p] or {})
    end
    local opts={fs=fs,fetcher=fetcher,archive=archive_for,sample=function() return "{}" end,
        calendar="gregorian",months_ahead=2,start="2026-12",today="2026-12-01",delay=5,
        sleep=function(s) pauses[#pauses+1]=s end}
    local result,err=U.run(opts)
    assert(result,err)
    assert(#calls==7 and calls[5][1]=="assets/2026n/12/files.zip" and calls[6][1]=="assets/2027n/01/files.zip")
    assert(#pauses==6 and pauses[1]==5 and #result.warnings>=1)
    assert(fs:exists("molytva/pack.json"))
    local original=fs:read("molytva/pack.json")
    unchanged=true; calls={}; pauses={}
    local second,err2=U.run(opts)
    assert(second and not second.updated,err2)
    assert(fs:read("molytva/pack.json")==original and #pauses==6 and calls[2][2]~=nil)
    unchanged=false; fs.fail_swap=true
    local third,err3=U.run(opts)
    assert(not third and err3:find("Cannot activate",1,true))
    assert(fs:read("molytva/pack.json")==original)
end)
test("unpublished current month is a warning",function()
    local fs=fake_fs()
    local fetcher={fetch=function(_,path)
        if path:find("files.zip",1,true) then return 404,"not published" end
        return 200,"synthetic zip","Wed, 01 Jan 2026 00:00:00 GMT"
    end}
    local result,err=U.run{fs=fs,fetcher=fetcher,start="2026-11",months_ahead=1,
        archive=function() return archive({["calendar26.txt"]=""}) end,
        sample=function() return "{}" end}
    assert(result and not result.updated and #result.warnings>=2,err)
    assert(not fs:exists("molytva/pack.json"))
end)
test("missing next-year calendar is a warning",function()
    local fs=fake_fs(); local paths=B.paths("2026-12",2,"new-julian")
    for _,path in ipairs(paths) do fs:write("molytva-cache/prayer-service.pp.ua/"..path,"cached") end
    fs:write("molytva/pack.json",B.encode({calendar="new-julian",range={from="2026-12",to="2026-12"}}))
    local result,err=U.run{fs=fs,fetcher={fetch=function() return 304,nil end},start="2026-12",months_ahead=1,
        archive=function() return archive({["calendar26.txt"]=""}) end,
        sample=function() return "{}" end}
    assert(result and not result.updated and result.range.to=="2026-12" and #result.warnings==1,err)
end)
print(string.format("%d builder/updater tests passed",passed))
