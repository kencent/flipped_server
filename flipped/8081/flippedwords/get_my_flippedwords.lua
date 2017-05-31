local flippedwords_data = require("flippedwords.flippedwords_data")
local restful = require("resty.restful")

local _M = {}

function _M:run()
    local res, err = flippedwords_data:my_flippedwords(ngx.var.http_x_uid, ngx.var.arg_id);
    if err then
        return restful:internal_server_error()
    end

    local ret = {flippedwords = res or {}}
    if type(res) == "table" and #res > 0 then
        restful:add_hypermedia(ret, "previous", "/my_flippedwords?" .. ngx.encode_args({id = res[#res].id}))
    end

    return restful:wrap(ret)
end


return _M