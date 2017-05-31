local flippedwords_data = require("flippedwords_data")
local restful = require("restful")

local _M = {}

function _M:run()
    local res, err = flippedwords_data:my_flippedwords(ngx.var.http_x_uid);
    if err then
        return restful:internal_server_error()
    end

    local ret = {flippedwords = res}
    if type(res) == "table" and #res > 0 then
        restful:add_hypermedia(ret, "previous", "/my_flippedwords?" .. ngx.encode_args({id = res[#res].id}))
    end

    return restful:wrap(ret)
end


return _M