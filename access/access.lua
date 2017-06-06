--local cjson = require("cjson.safe")
local location = require("resty.location")

local authorization = ngx.var.http_authorization
local uid = ngx.var.http_x_uid
if not authorization or not uid then
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
    return
end

local authsvc = location:new("/auth")
local res = authsvc:proxy()
if res.status == ngx.HTTP_UNAUTHORIZED then
	ngx.header["WWW-Authenticate"] = res.header["WWW-Authenticate"]
end 

local body = res.body
if not body or not body.I or body.I ~= uid
    or not type(body.t) == "number"
    or not type(body.clt) == "table" or not body.clt.p or not body.clt.v
    or not type(body.q) == "number" then
	ngx.log(ngx.INFO, "exit with invalid body=", res.body)
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
    return
end

ngx.req.clear_header("Authorization")
ngx.req.set_header("x-seq", body.q)
ngx.req.set_header("x-ts", body.t)
ngx.req.set_header("x-platform", body.clt.p)
ngx.req.set_header("x-version", body.clt.v)
ngx.exit(ngx.OK)



