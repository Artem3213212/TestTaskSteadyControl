local etlua=require('etlua')
local cjson=require("cjson")

--functions

local function starts_with(str,start)
   return str:sub(1,#start)==start
end

local CompileXMLContainerData=etlua.compile([[<?xml version="1.0" encoding="UTF-8"?>
<container name="<%-Name%>">
  <%for _,i in pairs(Data) do%>
    <object>
        <name><%-i.name%></name>
        <hash><%-i.hash%></hash>
        <bytes><%-i.bytes%></bytes>
        <content_type><%-i.content_type%></content_type>
        <last_modified><%-i.last_modified%></last_modified>
    </object>
  <%end%>
</container>]])
local CompileXMLUserData=etlua.compile([[<?xml version="1.0" encoding="UTF-8"?>
<account name="<%-Name%>">
  <%for _,i in pairs(Data) do%>
    <object>
        <name><%-i.name%></name>
        <count><%-i.count%></count>
        <bytes><%-i.bytes%></bytes>
        <last_modified><%-i.last_modified%></last_modified>
    </object>
  <%end%>
</container>]])

local CompilePlainData=etlua.compile([[<%for _,i in pairs(Data) do%><%-i.name%>
<%end%>]])

--classes

local TEntity={}--abstract
local TIterableEntity={}--abstract
setmetatable(TIterableEntity,{__index=TEntity})


local TUser={}
setmetatable(TUser,{__index=TIterableEntity})
local TContainer={}
setmetatable(TContainer,{__index=TIterableEntity})
local TObject={}
setmetatable(TObject,{__index=TEntity})

--TEntity

function TEntity:OpenHeaders()
  self.ReqHeaders=ngx.req.get_headers()
  self.ReqArgs=ngx.req.get_uri_args()
end

function TEntity:InitResponceId()
  ngx.header['X-Trans-Id']=self.ReqHeaders['X-Trans-Id'] or tostring(ngx.time())
  ngx.header['X-Openstack-Request-Id']=self.ReqHeaders['X-Openstack-Request-Id'] or tostring(ngx.time())
  ngx.header['Date']=ngx.http_time(ngx.time())
end

function TEntity:HEAD()
  self:OpenHeaders()
  self:InitResponceId()
  self:InitResponceMetadata()
  ngx.status=200
  ngx.print('')
end

--TIterableEntity

function TIterableEntity:GetFormatNum()
  local CT2Num={
    ['text/plain']=1,
    ['application/json']=2,
    ['application/xml']=3,
    ['text/xml']=3
  }
  local FormatToNum={
    ['plain']=1,
    ['json']=2,
    ['xml']=3
  }
  local ReqCT=self.ReqHeaders['Content-Type']
  local Format=self.ReqArgs['format']
  return Format and FormatToNum[Format]or (ReqCT and CT2Num[ReqCT] or 1)
end

function TIterableEntity:CompileData()
  local Num2CT={
    'text/plain',
    'application/json',
    'application/xml'
  }
  local CTNum=self:GetFormatNum()
  ngx.header['Content-Type']=Num2CT[CTNum]
  
  local limit=self.ReqArgs['limit']
  local marker=self.ReqArgs['marker']
  local end_marker=self.ReqArgs['end_marker']
  local prefix=self.ReqArgs['prefix'] or self.ReqArgs['path']
  local delimiter=self.ReqArgs['delimiter'] --unsupported
  
  local WasMarker=not marker
  local Data={}
  for _,i in pairs(self.ContentList)do
    if WasMarker and(not prefix or starts_with(i.name,prefix)) then
      Data[#Data+1]=i
    elseif i.name==marker then
      WasMarker=true
    end
    if #Data==limit or i.name==end_marker then
      break
    end
  end
  ngx.print(self.DataCompileres[CTNum](self.Name,Data))
end

function TIterableEntity:GET()
  self:OpenHeaders()
  self:InitResponceId()
  self:InitResponceMetadata()
  ngx.status=200
  self:CompileData()
end



--TUser
TUser.DataCompileres={
  function(Name,Data)
    return CompilePlainData({Data=Data})
  end,
  function(Name,Data)
    return cjson.encode(Data)
  end,
  function(Name,Data)
    return CompileXMLUserData({Name=Name,Data=Data})
  end
}
function TUser:InitResponceMetadata()
  ngx.header['X-Timestamp']=self.LastModiffiedTimeStamp
  ngx.header['X-Account-Container-Count']=self.ContainerCount
  ngx.header['X-Account-Object-Count']=self.ObjectCount
  ngx.header['X-Account-Bytes-Used']=self.BytesUsed
  ngx.header['X-Account-Storage-Policy-name-Bytes-Used']=self.ContainerCount
  ngx.header['X-Account-Storage-Policy-name-Container-Count']=self.ObjectCount
  ngx.header['X-Account-Storage-Policy-name-Object-Count']=self.BytesUsed
end

--TContainer
TContainer.DataCompileres={
  function(Name,Data)
    return CompilePlainData({Data=Data})
  end,
  function(Name,Data)
    return cjson.encode(Data)
  end,
  function(Name,Data)
    return CompileXMLContainerData({Name=Name,Data=Data})
  end
}
function TContainer:InitResponceMetadata()
  ngx.header['X-Timestamp']=self.LastModiffiedTimeStamp
  ngx.header['X-Container-Meta-name']=self.Name
  ngx.header['X-Container-Object-Count']=self.ObjectCount
  ngx.header['X-Container-Bytes-Used']=self.BytesUsed
  ngx.header['Accept-Ranges']=''
end

--TObject
function TObject:InitResponceMetadata()
  ngx.header['Content-Length']=tostring(#self.Data)
  ngx.header['ETag']=self.MD5
  ngx.header['Last-Modified']=ngx.http_time(self.LastModiffiedTimeStamp)
  ngx.header['X-Timestamp']=self.LastModiffiedTimeStamp
  ngx.header['X-Static-Large-Object']='false'
  ngx.header['Content-Type']=self.mimetype
end
function TObject:GET()
  self:OpenHeaders()
  if not self.ReqHeaders['Range'] then
    self:InitResponceId()
    self:InitResponceMetadata()
    ngx.header['Accept-Ranges']=''
    ngx.status=200
    ngx.print(self.Data)
  else
    ngx.status=501
    ngx.print('')
  end
end

return {TObject=TObject,TContainer=TContainer,TUser=TUser}