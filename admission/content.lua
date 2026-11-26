local M={}
-- The digest is compared between PCs, so strings sort byte by byte (Lua's `<` uses
-- strcoll) and numbers are not formatted as decimals; the framework's setup digest
-- follows the same rules.
function M.lessBytes(a,b)
  for i=1,math.min(#a,#b) do
    local x,y=a:byte(i),b:byte(i)
    if x~=y then return x<y end
  end
  return #a<#b
end
local function number(v)
  local integer=math.tointeger(v)
  if integer then return 'i'..string.format('%d',integer) end
  return 'f'..(string.pack('<d',v):gsub('.',function(c) return string.format('%02x',c:byte()) end))
end
function M.canonical(value)
  local count,seen=0,{}
  local function encode(v,depth)
    count=count+1
    assert(count<=100000 and depth<=32,'Multiplayer settings exceed admission bounds')
    local kind=type(v)
    if kind=='table' then
      assert(not seen[v],'Cyclic multiplayer settings');seen[v]=true
      local keys={}
      for k in pairs(v) do
        assert(type(k)=='string' or type(k)=='number','Invalid multiplayer setting key')
        keys[#keys+1]=k
      end
      table.sort(keys,function(a,b)
        if type(a)~=type(b) then return type(a)<type(b) end
        if type(a)=='string' then return M.lessBytes(a,b) end
        return a<b
      end)
      local items={'t'..#keys..':'}
      for _,key in ipairs(keys) do items[#items+1]=encode(key,depth+1)..encode(v[key],depth+1) end
      seen[v]=nil;return table.concat(items)
    elseif kind=='string' then
      assert(#v<=1048576,'Multiplayer setting is too long');return 's'..#v..':'..v
    elseif kind=='number' then
      assert(v==v and v~=math.huge and v~=-math.huge,'Invalid multiplayer setting number')
      local text=number(v);return 'n'..#text..':'..text
    elseif kind=='boolean' then return v and 'b1' or 'b0'
    elseif kind=='nil' then return 'z' end
    error('Unsupported multiplayer setting type: '..kind)
  end
  return encode(value,0)
end
return M
