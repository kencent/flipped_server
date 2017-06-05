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
    local uid = ngx.var.http_x_uid
    local authorization = ngx.var.http_authorization
    if not uid or not authorization then
        return unauthorized()
    end

    local match = ngx.re.match(authorization, "SRP (.*)")
    if not match or not match[1] then
        ngx.log(ngx.INFO, "not auth with invalid authorization,uid=", uid, "authorization=", authorization)
        return unauthorized()
    end

    local K = srp_store:get_K(uid)
    if not K then
        ngx.log(ngx.INFO, "not auth with no K,uid=", uid)
        return unauthorized()
    end

    ngx.log(ngx.DEBUG, "uid=" .. uid, ",K=", K)
    local aeskey = string.sub(utils:from_hex(K), 1, 32)
    local iv = utils:from_hex("bfd3814678afe0036efa67ca8da44e2e")
    local aes_256_cbc_with_iv = aes:new(aeskey, nil, aes.cipher(256, "cbc"), {iv = iv})
    local decrypt = aes_256_cbc_with_iv:decrypt(ngx.decode_base64(match[1]))
    ngx.log(ngx.DEBUG, "uid=" .. uid, ",decrypt=", decrypt)
    local token = decrypt and cjson.decode(decrypt) or nil

    --local now = math.floor(ngx.now() * 1000)
    if not token or not token.I or token.I ~= uid
        or not type(token.t) == "number" --or math.abs(token.t - now) > 15000
        or not type(token.clt) == "table" or not token.clt.p or not token.clt.v
        or not type(token.q) == "number" or not type(token.r) == "number"
        --or not type(token.sign) == "string" 
        then
        ngx.log(ngx.INFO, "not auth with invalid token=", token)
        return unauthorized()
    end

    -- 校验签名
    local sign = {uid, token.t, token.q, token.r, ngx.var.request_method, ngx.var.request_uri,
        ngx.var.request_body}
    sign = table.concat(sign)
    ngx.log(ngx.DEBUG, "sign=", sign)
    sign = ngx.encode_base64(ngx.hmac_sha1(K, table.concat(sign)))
    ngx.log(ngx.DEBUG, "sign=", sign)
    if token.sign ~= sign then
        ngx.log(ngx.INFO, "not auth with sign not match client sign=", token.sign, ",sign=", sign)
        return unauthorized()
    end

    return restful:wrap(token)
end

restful:say(run())

