-- tiny JSON decoder for stubs (null -> sentinel, like luajson)
local NULL=setmetatable({},{__tostring=function() return "null" end})
local function decode(s)
  local i=1
  local function ws() i=s:find("[^ \t\r\n]",i) or #s+1 end
  local val
  local function str() local j=i+1 local out={} while true do local c=s:sub(j,j) if c=='"' then break elseif c=='\\' then local n=s:sub(j+1,j+1) local map={n="\n",t="\t",r="\r",['"']='"',["\\"]="\\",["/"]="/",b="\b",f="\f"} if n=="u" then out[#out+1]="?" j=j+6 else out[#out+1]=map[n] j=j+2 end else out[#out+1]=c j=j+1 end end i=j+1 return table.concat(out) end
  function val() ws() local c=s:sub(i,i)
    if c=="{" then i=i+1 local t={} ws() if s:sub(i,i)=="}" then i=i+1 return t end while true do ws() local k=str() ws() i=i+1 t[k]=val() ws() local d=s:sub(i,i) i=i+1 if d=="}" then return t end end
    elseif c=="[" then i=i+1 local t={} ws() if s:sub(i,i)=="]" then i=i+1 return t end while true do t[#t+1]=val() ws() local d=s:sub(i,i) i=i+1 if d=="]" then return t end end
    elseif c=='"' then return str()
    elseif s:sub(i,i+3)=="true" then i=i+4 return true elseif s:sub(i,i+4)=="false" then i=i+5 return false elseif s:sub(i,i+3)=="null" then i=i+4 return NULL
    else local n=s:match("^-?%d+%.?%d*[eE]?[-+]?%d*",i) i=i+#n return tonumber(n) end end
  return val()
end
_G.__jsondecode=decode
