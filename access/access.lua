local cjson = require("cjson.safe")

local authorization = ngx.var.http_authorization
local uid = ngx.var.http_x_uid
if not authorization or not uid then
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
    return
end

local res = ngx.location.capture("/auth")
if res.status == ngx.HTTP_UNAUTHORIZED then
	ngx.header["WWW-Authenticate"] = res.header["WWW-Authenticate"]
end

if res.status ~= ngx.HTTP_OK then
	ngx.log(ngx.INFO, "exit with status=", res.status)
	ngx.exit(res.status)
    return
end

local body = cjson.decode(res.body)
--local now = math.floor(ngx.now() * 1000)
if not body or not body.I or body.I ~= uid
    --or not type(body.t) == "number" or math.abs(body.t - now) > 15000
    or not type(body.clt) == "table" or not body.clt.p or not body.clt.v
    or not type(body.q) == "number" or not type(body.r) == "number" then
	ngx.log(ngx.INFO, "exit with invalid body=", res.body)
    ngx.exit(ngx.HTTP_UNAUTHORIZED)
    return
end

ngx.req.set_header("x-platform", body.clt.p)
ngx.req.set_header("x-version", body.clt.v)
ngx.exit(ngx.OK)



