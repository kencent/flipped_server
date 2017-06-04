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
        return restful:internal_server_error("系统繁忙")
    end

    local uid = tonumber(ngx.var.http_x_uid)
    if uid and res.sendto == uid and res.status ~= flippedwords_data.STATUS_READ then
        err = flippedwords_data:flippedwords_read(id)
        if not err then
            res.status = flippedwords_data.STATUS_READ
        end
    end

    res.sendto = "1" .. string.sub(res.sendto, 2, 3) .. "******" .. string.sub(res.sendto, -2)
    return restful:wrap(res)
end


return _M