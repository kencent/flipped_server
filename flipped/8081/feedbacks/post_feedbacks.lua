local feedbacks_data = require("feedbacks.feedbacks_data")
local restful = require("resty.restful")

local _M = {}

function _M:run()
    local body = restful:get_body_data()
    body.sendto = tonumber(body.sendto)
    if type(body.contents) ~= "table" then
        return restful:unprocessable_entity()
    end

    body.uid = ngx.var.http_x_uid
    local _, err = feedbacks_data:add_feedbacks(body);
    if err then
        return restful:internal_server_error()
    end

    return nil
end


return _M















