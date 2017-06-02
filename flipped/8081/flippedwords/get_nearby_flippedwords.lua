local flippedwords_data = require("flippedwords.flippedwords_data")
local restful = require("resty.restful")

local _M = {}

function _M:run()
    local args = ngx.req.get_uri_args()

    local res, err = flippedwords_data:nearby_flippedwords(args);
    if err then
        return restful:internal_server_error()
    end

    local ret = {flippedwords = res or {}}
    restful:add_hypermedia(ret, "previous", "/nearby_flippedwords?" .. ngx.encode_args({lat = args.lat, lng = args.lng}))
    if type(res) == "table" and #res > 0 then
        restful:add_hypermedia(ret, "next", "/nearby_flippedwords?" .. ngx.encode_args({lat = args.lat, lng = args.lng, id = res[#res].id}))
        for _, elem in ipairs(res) do
            elem.sendto = "1XXXXXXXXX" .. string.sub(elem.sendto, -1)
        end
    end

    return restful:wrap(ret)
end


return _M