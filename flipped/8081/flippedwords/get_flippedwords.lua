local flippedwords_data = require("flippedwords.flippedwords_data")
local restful = require("resty.restful")

local _M = {}

function _M:run()
	local id = tonumber(ngx.var[2])
	if not id then
		return restful:unprocessable_entity()
	end

    local res, err = flippedwords_data:get_flippedword(id);
    if err then
        return restful:internal_server_error()
    end

    return restful:wrap(res)
end


return _M