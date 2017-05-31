local location = require("resty.location")

local FLIPPED_PORT = 8081
local flippedsvc = location:new("/__flippedsvc__", FLIPPED_PORT)

local _M = {
	flippedsvc = flippedsvc
}


return _M



