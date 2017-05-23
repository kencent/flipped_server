local restful = require("restful")
local credis = require("credis")
local cmysql = require("cmysql")
local cjson = require("cjson.safe")
local random = require("resty.random")
local str = require("resty.string")
local srp = require("srp")

local N_num_bits = "2048"
local _M = {}

local function set_srp_tmp(key, value)
end

local function get_srp_tmp(key)
end

local function get_srp_persist(key)
end

local function del_srp_tmp(key)
end

local function set_srp_persist(key, value)
end

local function get_arg_phone()
    local phone = ngx.var.arg_phone
    if not phone then
        return nil
    end

    local valid = ngx.re.match(phone, "1[3-8]\\d{9}")
    if not valid then
        return nil
    end

    return phone
end

local function get_password(phone)
    -- 达到获取验证码的上限，返回获取验证码太频繁

    -- 一分钟内发送过短信了，直接返回成功

    -- 生成随机6位数，生成盐
    local s = str.to_hex(random.bytes(16, true))
    local password = tonumber(str.to_hex(random.bytes(8)), 16) % 1000000
    password = string.format("%06d", password)
    ngx.log(ngx.DEBUG, "phone=", phone, ",s=", s, ",password=", password)

    local g, N = srp.get_default_gN(N_num_bits)
    local v = srp.create_verifier(phone, password, s, N, g)

    -- 写srp临时存储
    local err = set_srp_tmp(phone, {s = s, v = v})
    if err then
        return restful:internal_server_error("获取验证码失败")
    end

    -- 增加验证码发送次数

    -- 发送短信
    return restful:wrap({password = password, s = s})
end

local function get_B(phone)
    local A = ngx.var.arg_a
    if not A then
        return restful:unprocessable_entity("参数非法")
    end

    local g, N = srp.get_default_gN(N_num_bits)
    if srp.Verify_mod_N(A, N) == 0 then
        return restful:unprocessable_entity()
    end

    local srp_data = get_srp_tmp(phone)
    if not srp_data then
        srp_data = get_srp_persist(phone)
    end

    if not srp_data or not srp_data.v or not srp_data.s then
        return restful:forbidden("非法请求")
    end

    local b = str.to_hex(random.bytes(32, true))
    local B = srp.Calc_B(b, N, g, srp_data.v)
    ngx.log(ngx.DEBUG, "phone=", phone, ",b=", b, ",B=", B)
    srp_data = {v = srp_data.v, s = srp_data.s, b = b, A = A, B = B}

    local err = set_srp_tmp(phone, srp_data)
    if err then
        return restful:internal_server_error("系统繁忙")
    end

    return restful:wrap({B = B})
end

-- TODO: 考虑N_num_bits变了怎么办
local function get_M2(phone)
    local client_M1 = ngx.var.arg_m1
    if not client_M1 then
        return restful:unprocessable_entity("参数非法")
    end

    local srp_data = get_srp_tmp(phone)
    if not srp_data or not srp_data.A or not srp_data.B or not srp_data.b
        or not srp_data.v or not srp_data.s then
        return restful:forbidden("非法请求")
    end

    local g, N = srp.get_default_gN(N_num_bits)
    local server_key = srp.Calc_server_key(srp_data.A, srp_data.B, N, srp_data.v, srp_data.b);
    local server_M1 = srp.Calc_M1(N, g, phone, srp_data.s, srp_data.A, srp_data.B, server_key);
    ngx.log(ngx.DEBUG, "phone=", phone, ",server_key=", server_key, ",server_M1=", server_M1)
    if client_M1 ~= server_M1 then
        return restful:unprocessable_entity("验证码错误")
    end

    local server_M2 = srp.Calc_M2(srp_data.A, server_M1, server_key)
    ngx.log(ngx.DEBUG, "phone=", phone, "server_M2=", server_M2)
    local err = del_srp_tmp(phone)
    if err then
        ngx.log(ngx.ERR, "failed to del srp tmp,phone=", phone)
    end

    srp_data = {key = server_key, v = srp_data.v, s = srp_data.s}
    err = set_srp_persist(phone, srp_data)
    if err then
        return restful:internal_server_error("系统繁忙")
    end

    return {M2 = server_M2}
end

function _M:run()
    local phone = get_arg_phone()
    if not phone then
        return restful:unprocessable_entity("手机号不合法")
    end

    -- TODO: phone调用srp接口的频率限制



    local srp_arg = ngx.var[2]
    if not srp_arg then
        return restful:method_not_allowed()
    end

    if srp_arg == "password" then
        return get_password(phone)
    elseif srp_arg == "B" then
        return get_B(phone)
    elseif srp_arg == "M2" then
        return get_M2(phone)
    end

    return restful:method_not_allowed()
end

return _M






