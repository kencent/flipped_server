local flippedwords_data = require("flippedwords_data")
local restful = require("restful")

local _M = {}

function _M:run()
    local args = ngx.req.get_req_args()

    local res, err = flippedwords_data:nearby_flippedwords(args);
    if err then
        return restful:internal_server_error()
    end

    local ret = {flippedwords = res}
    restful:add_hypermedia(ret, "previous", "/nearby_flippedwords?" .. ngx.encode_args({lat = args.lat, lng = args.lng}))
    if type(res) == "table" and #res > 0 then
        restful:add_hypermedia(ret, "next", "/nearby_flippedwords?" .. ngx.encode_args({lat = args.lat, lng = args.lng, id = res[#res].id}))
    end

    return restful:wrap(ret)
end


return _M