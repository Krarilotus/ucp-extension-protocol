-- Only startup/lobby work. Use UCP's VFS and streaming SHA256 implementation;
-- no filesystem reads, hashing or admission polling enters the simulation loop.
local M={}
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
        return a<b
      end)
      local items={'t'..#keys..':'}
      for _,key in ipairs(keys) do items[#items+1]=encode(key,depth+1)..encode(v[key],depth+1) end
      seen[v]=nil;return table.concat(items)
    elseif kind=='string' then
      assert(#v<=1048576,'Multiplayer setting is too long');return 's'..#v..':'..v
    elseif kind=='number' then
      assert(v==v and v~=math.huge and v~=-math.huge,'Invalid multiplayer setting number')
      local text=string.format('%.17g',v);return 'n'..#text..':'..text
    elseif kind=='boolean' then return v and 'b1' or 'b0'
    elseif kind=='nil' then return 'z' end
    error('Unsupported multiplayer setting type: '..kind)
  end
  return encode(value,0)
end

function M.capture(extensions,config)
  assert(type(extensions)=='table','Active extensions are unavailable')
  local files,visited,order,count,total={},{},{},0,0
  local function normalized(path)
    assert(type(path)=='string' and not path:find('[%z\r\n]'),'Invalid admission asset path')
    return path:gsub('\\','/'):gsub('/+$','')
  end
  local function add(path,key)
    if files[key] then return end
    count=count+1;assert(count<=50000,'Too many multiplayer assets')
    local f=assert(io.open(path,'rb'),'Missing multiplayer asset: '..path)
    local ok,digest=pcall(function()
      local feed=sha.sha256()
      local size=0
      while true do
        local chunk,reason=f:read(65536)
        assert(not reason,reason)
        if not chunk or #chunk==0 then break end
        size=size+#chunk;total=total+#chunk
        assert(size<=1073741824 and total<=4294967296,'Multiplayer assets exceed admission bounds')
        feed(chunk)
      end
      return feed()
    end)
    local closed=f:close()
    assert(ok and closed,digest or 'Cannot close multiplayer asset')
    files[key]=digest
  end
  local function walk(path,key,depth)
    assert(depth<=16,'Multiplayer asset directory nesting is too deep')
    if visited[path] then return end
    visited[path]=true
    count=count+1;assert(count<=50000,'Too many multiplayer asset directories')
    local present={}
    for _,file in ipairs(ucp.internal.io.files(path..'/')) do
      file=normalized(file)
      assert(file:sub(1,#path+1)==path..'/','Multiplayer asset escaped its parent')
      present[file]=true;add(file,key..file:sub(#path+1))
    end
    for _,child in ipairs(ucp.internal.io.directories(path..'/')) do
      child=normalized(child)
      assert(child:sub(1,#path+1)==path..'/','Multiplayer directory escaped its parent')
      -- Same UCP 3.0.7 archive/folder shadowing rule as Recorder replay-assets.
      local folder=not present[child..'.zip'] or pcall(ucp.internal.io.files,child..'/')
      if child:sub(#path+2)~='.git' and folder then walk(child,key..child:sub(#path+1),depth+1) end
    end
  end
  for i,extension in ipairs(extensions) do
    assert(i<=256,'Too many active multiplayer extensions')
    local kind=extension:type()=='ModuleLoader' and 'modules' or 'plugins'
    local key='ucp/'..kind..'/'..extension.name..'-'..extension.version
    order[i]=key
    local root=normalized(ucp.internal.resolveAliasedPath(key..'/'))
    if #ucp.internal.io.files(root..'/')>0 then walk(root,key,0)
    else add(key..'.zip',key..'.zip') end
  end
  local seenOptions={}
  local function options(value,depth)
    assert(depth<=32,'Multiplayer settings nesting is too deep')
    if type(value)=='table' then
      assert(not seenOptions[value],'Cyclic multiplayer settings');seenOptions[value]=true
      for _,item in pairs(value) do options(item,depth+1) end
      seenOptions[value]=nil
    elseif type(value)=='string' and value:find('[/\\]') and not value:find('[%z\r\n]') then
      local key=normalized(value)
      local path=normalized(ucp.internal.resolveAliasedPath(key))
      local opened,file=pcall(io.open,path,'rb')
      if opened and file then assert(file:close());add(path,'option/'..key)
      else
        local ok,children=pcall(ucp.internal.io.files,path..'/')
        if ok and type(children)=='table' then walk(path,'option/'..key,0) end
      end
    end
  end
  options(config,0)
  add('ucp/ucp-version.yml','ucp/ucp-version.yml')
  return sha.sha256(M.canonical({order=order,files=files}))
end
return M
