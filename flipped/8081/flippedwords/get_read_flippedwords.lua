local flippedwords_data = require("flippedwords.flippedwords_data")
local restful = require("resty.restful")

local _M = {}

function _M:run()
    local uid = tonumber(ngx.var.http_x_uid)
    if not uid then
        return restful:unprocessable_entity()
    end

    local res, err = flippedwords_data:read_flippedwords(uid, ngx.var.arg_last_open_time);
    if err then
        return restful:internal_server_error("系统繁忙")
    end

    local ret = {flippedwords = res or {}}
    if type(res) == "table" and #res > 0 then
        for _, elem in ipairs(res) do
        	restful:add_hypermedia(elem, "detail", "/flippedwords/" .. elem.id)
        end
    end

    return restful:wrap(ret)
end


return _M