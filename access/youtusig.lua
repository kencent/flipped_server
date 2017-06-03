local restful = require("resty.restful")

local a = 1251789367
local b = "flipped"
local k = "AKIDL8pNlynueFgx3yDJjy1tdEi4FH8n2aif"
local t = ngx.time()
local e = t + 7 * 86400
math.randomseed(t)
local r = math.random(10000, 99999)
local u = "0"
local f = ""

local sig = "a=" .. a .. "&b=" .. b .. "&k=" .. k .. "&e=" .. e .. "&t=" .. t .. "&r=" .. r .. "&u=" .. u .. "&f=" .. f
ngx.log(ngx.DEBUG, "sig=", sig)
sig = ngx.encode_base64(ngx.hmac_sha1("1sZ4OYefYGnBOQHxiMpAKK9oOrBKK9mI", sig) .. sig)
restful:say(restful:wrap({sig = sig}))
