local flippedwords_data = require("flippedwords.flippedwords_data")
local restful = require("resty.restful")

local _M = {}

function _M:run()
    local body = restful:get_body_data()
    if not body or type(body.sendto) ~= "number" or type(body.contents) ~= "table" then
        return restful:unprocessable_entity()
    end

    local valid = ngx.re.match(body.sendto, "1\\d{10}")
    if not valid then
        return restful:unprocessable_entity()
    end

    local res, err = flippedwords_data:add_flippedwords(body);
    if err then
        return restful:internal_server_error()
    end

    return restful:wrap({id = res.id})
end


return _M















