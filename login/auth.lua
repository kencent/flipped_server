local restful = require("resty.restful")
local cjson = require("cjson.safe")
local aes = require("resty.aes")
local srp_store = require("srp_store")
local utils = require("resty.utils")


local function unauthorized()
    ngx.header["WWW-Authenticate"] = "SRP realm=\"flipped\", N_num_bits=\"" .. srp_store.N_num_bits .. "\""
    return restful:unauthorized()
end

local function run()
    local authentication = ngx.var.http_authentication
    local phone = ngx.var.http_x_uid
    if not authentication or not phone then
        return unauthorized()
    end

    local K = srp_store:get_K(phone)
    if not K then
        return unauthorized()
    end

    K = string.sub(K, 1, 32)
    local iv = utils:from_hex("bfd3814678afe0036efa67ca8da44e2e")
    local aes_256_cbc_with_iv = aes:new(K, nil, aes.cipher(256, "cbc"), {iv = iv})
    local decrypt = aes_256_cbc_with_iv:decrypt(authentication)
    if decrypt then
        decrypt = cjson.decode(decrypt)
    end

    local now = ngx.time()
    if not decrypt or not decrypt.I or decrypt.I ~= phone
        or not type(decrypt.t) == "number" or math.abs(decrypt.t - now) > 15
        or not type(decrypt.clt) == "table" or not decrypt.clt.p or not decrypt.clt.v
        or not type(decrypt.r) == "number" then
        return unauthorized()
    end

    return restful:wrap(decrypt)
end

restful:say(run())

