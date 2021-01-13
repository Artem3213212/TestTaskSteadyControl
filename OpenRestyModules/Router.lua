local lfs=require("lfs")
local Cfg=require("Config")
local puremagic=require('puremagic')
local Classes=require('Classes')

local function starts_with(str,start)
   return str:sub(1,#start)==start
end


local function ReadFile(Name)
  local f,err=io.open(Name, "r")
  if not f then
    ngx.log(ngx.ERR,err)
  end
  local content=f:read("*all")
  f:close()
  return content
end

local BaseRoutes={
  ['/v3/auth/tokens']={
    POST=function()
      local h=ngx.req.get_headers()
      ngx.header['X-Subject-Token']=tostring(ngx.time())
      ngx.status=201
      ngx.req.read_body()
      ngx.log(ngx.NOTICE,ngx.req.get_body_data())
      ngx.header.content_type='application/json'
      ngx.print([[{
    "token": {
        "audit_ids": [
            "3T2dc1CGQxyJsHdDu1xkcw"
        ],
        "catalog": [
            {
                "endpoints": [
                    {
                        "enabled": true,
                        "id": "068d1b359ee84b438266cb736d81de97",
                        "interface": "public",
                        "links": {
                            "self": "https://agstudio.languagerobbers.ru:2087/v1/admin"
                        },
                        "region": "RegionOne",
                        "region_id": "RegionOne",
                        "url": "https://agstudio.languagerobbers.ru:2087/v1/admin"
                    },
                    {
                        "enabled": true,
                        "id": "8bfc846841ab441ca38471be6d164ced",
                        "interface": "admin",
                        "links": {
                            "self": "https://agstudio.languagerobbers.ru:2087/v1/admin"
                        },
                        "region": "RegionOne",
                        "region_id": "RegionOne",
                        "url": "https://agstudio.languagerobbers.ru:2087/v1/admin"
                    },
                    {
                        "enabled": true,
                        "id": "beb6d358c3654b4bada04d4663b640b9",
                        "interface": "internal",
                        "links": {
                            "self": "https://agstudio.languagerobbers.ru:2087/v1/admin"
                        },
                        "region": "RegionOne",
                        "region_id": "RegionOne",
                        "url": "https://agstudio.languagerobbers.ru:2087/v1/admin"
                    }
                ],
                "links": {
                    "self": "https://agstudio.languagerobbers.ru:2087/"
                },
                "type": "object-store",
                "id": "050726f278654128aba89757ae25950c",
                "name": "keystone"
            }
        ],
        "expires_at": "2015-11-07T02:58:43.578887Z",
        "is_domain": false,
        "issued_at": "2015-11-07T01:58:43.578929Z",
        "methods": [
            "password"
        ],
        "project": {
            "domain": {
                "id": "default",
                "name": "Default"
            },
            "id": "a6944d763bf64ee6a275f1263fae0352",
            "name": "admin"
        },
        "roles": [
            {
                "id": "51cc68287d524c759f47c811e6463340",
                "name": "admin"
            }
        ],
        "user": {
            "domain": {
                "id": "default",
                "name": "Default"
            },
            "id": "ee4dfb6e5540447cb3741905149d9b6e",
            "name": "admin",
            "password_expires_at": "2016-11-06T15:32:17.000000"
        }
    }
}]])
      ngx.exit(ngx.OK)
    end
  },
  ['/info']={
    GET=function()
      ngx.status=200
      ngx.header.content_type='application/json'
      ngx.print('{"swift":{"version":"1.11.0"},"slo":{"max_manifest_segments":1000,"max_manifest_size":2097152,"min_segment_size":1},"staticweb":{},"tempurl":{}}')
      ngx.exit(ngx.OK)
    end
  },
  ['/v1/endpoints']={
    GET=function()
      ngx.status=201
      ngx.print('')
      ngx.exit(ngx.OK)
    end
  }
}

local DataRoutes={}

local UserData={}
local TotalContainers=0
local TotalObjects=0
local TotalBytes=0
for folder in lfs.dir(Cfg.WebDataDir) do
  if folder~='.' and folder~='..' and lfs.attributes(folder,"mode")=="directory" then
    local ObjectCount=0
    local BytesUsed=0
    local ContainerData={}
    
    for file in lfs.dir(Cfg.WebDataDir.."/"..folder) do
      if file~='.' and file~='..' then
        local Path=Cfg.WebDataDir..'/'..folder..'/'..file
        local Data=ReadFile(Path)
        local MD5=ngx.md5(Data)
        local LastModiffiedTimeStamp=lfs.attributes(Path,'modification')
        DataRoutes['/'..folder..'/'..file]=setmetatable({
          LastModiffiedTimeStamp=LastModiffiedTimeStamp,
          mimetype=#Data==0 and 'application/octet-stream' or puremagic.via_path(Path,file),
          MD5=MD5,
          Data=Data
        },{__index=Classes.TObject})
        ObjectCount=ObjectCount+1
        BytesUsed=BytesUsed+#Data
        ContainerData[#ContainerData+1]={
          hash=MD5,
          last_modified=os.date("!%Y-%m-%dT%TZ",LastModiffiedTimeStamp),
          content_type=#Data==0 and 'application/octet-stream' or puremagic.via_path(Path,file),
          bytes=#Data,
          name=file
        }
      end
    end
    
    local LastModiffiedTimeStamp=lfs.attributes(Cfg.WebDataDir.."/"..folder,'modification')
    DataRoutes['/'..folder]=setmetatable({
      LastModiffiedTimeStamp=LastModiffiedTimeStamp,
      Name=folder,
      ObjectCount=ObjectCount,
      BytesUsed=BytesUsed,
      ContentList=ContainerData
    },{__index=Classes.TContainer})
    
    TotalContainers=TotalContainers+1
    TotalObjects=TotalObjects+ObjectCount
    TotalBytes=TotalBytes+BytesUsed
    UserData[#UserData+1]={
      count=ObjectCount,
      last_modified=os.date("!%Y-%m-%dT%TZ",LastModiffiedTimeStamp),
      bytes=BytesUsed,
      name=folder
    }
  end
end

DataRoutes['']=setmetatable({
  Name='User',
  LastModiffiedTimeStamp=os.date("!%Y-%m-%dT%TZ",0),
  ContainerCount=TotalContainers,
  ObjectCount=TotalObjects,
  BytesUsed=TotalBytes,
  ContentList=UserData
},{__index=Classes.TUser})

local function SearchInRoutes(Routes,URL)
  local Route=Routes[URL]
  if Route then
    local Action=Route[ngx.req.get_method()]
    ngx.log(ngx.NOTICE,URL..'\n'..ngx.req.get_method()..'\n'..(Action and '1' or '2')..'\n')
    if Action then
      Action(Route)
    else
      ngx.status=501
      ngx.print('')
    end
    ngx.exit(ngx.OK)
  end
end

return function()
  local URL=ngx.var.uri
  SearchInRoutes(BaseRoutes,URL)
  if starts_with(URL,'/v1/') then
    local SubURL
    local l=string.find(URL,'/',5)
    if l then
      SubURL=string.sub(URL,l)
    else
      SubURL=''
    end
    SearchInRoutes(DataRoutes,SubURL)
  end
end