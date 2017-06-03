local flippedwords_data = require("flippedwords.flippedwords_data")
local restful = require("resty.restful")

local _M = {}

function _M:run()
    local body = restful:get_body_data()
    body.sendto = tonumber(body.sendto)
    if not body or type(body.sendto) ~= "number" or type(body.contents) ~= "table" then
        return restful:unprocessable_entity()
    end

    local valid = ngx.re.match(body.sendto, "1\\d{10}")
    if not valid then
        return restful:unprocessable_entity()
    end

    body.sendfrom = ngx.var.http_x_uid
    local res, err = flippedwords_data:add_flippedwords(body);
    if err and err == "no affected" then
        return restful:too_many_requests("今天已经发过了，请明天再来！")
    end

    if err then
        return restful:internal_server_error()
    end

    return restful:wrap({id = res.id})
end


return _M















