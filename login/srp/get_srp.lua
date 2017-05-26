local restful = require("restful")
local credis = require("credis")
local cmysql = require("cmysql")
local cjson = require("cjson.safe")
local random = require("resty.random")
local str = require("resty.string")
local utils = require("resty.utils")
local srp = require("srp")
local quote_sql_str = ngx.quote_sql_str

local _M = {}

local N_num_bits = "2048"
local STATUS_PASSWORD_ALREADY_SEND = 2

local redis_conf = {
    host = "127.0.0.1",
    password = "flipped@redis"
}

local mysql_conf = {
    host = "127.0.0.1",
    user = "flipped",
    password = "flipped_admin"
}

local redis = credis:new(redis_conf)
local mysql = cmysql:new(mysql_conf)
--local SRP_KEY_PREFIX = "SRPKEY"
--local SMS_FREQ_PREFIX = "SMSFREQ"
--local SRP_FREQ_PREFIX = "SRPFREQ"

local function get_srp_tmp_key(I)
    return "SRPTMP" .. I
end

local function get_password_key(I)
    return "SRPPWD" .. I
end

local function set_srp_tmp(I, value, expire)
    local _, err = redis:do_cmd("setex", get_srp_tmp_key(I), cjson.encode(value), expire)
    return err
end

local function get_srp_tmp(I)
    local data, err = redis:do_cmd("get", get_srp_tmp_key(I))
    if err then
        return nil, err
    end

    return type(data) == "string" and cjson.decode(data) or nil
end

local function get_srp_tb(I)
    local hash = utils:hash(I) % 1000
    local db, tb = math.floor(hash / 100), hash % 100
    return string.format("dbLogin_%d.SRP_%d", db, tb)
end

local function get_srp_persist(I)
    local sql = string.format("select v,s,key,expire from %s where I=%s",
        get_srp_tb(I), quote_sql_str(I))
    local data, err = mysql:get(sql)
    if err and err == "not found" then
        return nil
    end

    if err then
        return nil, err
    end

    return data
end

local function del_srp_tmp(I)
    return redis:do_cmd("del", get_srp_tmp_key(I))
end

local function set_srp_persist(I, value, expire)
    local sql = string.format("update %s set v=%s,s=%s,key=%s,expire=%d where I=%s", 
        get_srp_tb(I), quote_sql_str(value.v), quote_sql_str(value.s), 
        quote_sql_str(value.key), ngx.time() + expire, quote_sql_str(I))
    local _, err = mysql:execute(sql)
    return err
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
    local now = ngx.time()
    local countdown = 60
    local validtime = 300

    local if_modified_since = restful:if_modified_since()
    if if_modified_since and if_modified_since > now then
        return restful:not_modified()
    end

    local srp_data, err = get_srp_tmp(phone)
    if err then
        ngx.log(ngx.ERR, "failed to get srp tmp data,phone=", phone, ",err=", err)
        return restful:internal_server_error("获取验证码失败")
    end

    -- 一分钟内发送过了
    if type(srp_data) == "table" and type(srp_data.last_send_time) == "number"
        and srp_data.last_send_time + countdown > now then
        return {s = srp_data.s, N_num_bits = N_num_bits, 
            countdown = srp_data.last_send_time + countdown - now,
            validtime = srp_data.last_send_time + validtime - now}
    end

    -- 获取验证码次数超过频率限制
    local sms_freq_key = "SMSFREQ" .. phone
    local send_times
    send_times, err = redis:do_cmd("get", sms_freq_key)
    if err then
        return restful:internal_server_error("获取验证码失败")
    end

    send_times = tonumber(send_times) or 0
    if send_times >= 3 then
        return restful:forbidden("获取验证码次数过多，请稍后重试")
    end

    -- 生成随机6位数，生成盐
    local s = str.to_hex(random.bytes(16, true))
    local password = tonumber(str.to_hex(random.bytes(8)), 16) % 1000000
    password = string.format("%06d", password)
    ngx.log(ngx.DEBUG, "phone=", phone, ",s=", s, ",password=", password)

    local g, N = srp.get_default_gN(N_num_bits)
    local v = srp.create_verifier(phone, password, s, N, g)

    -- 写srp临时存储
    err = set_srp_tmp(phone, {last_send_time = now, s = s, v = v, status = STATUS_PASSWORD_ALREADY_SEND}, validtime)
    if err then
        return restful:internal_server_error("获取验证码失败")
    end

    -- TODO: 使用短信发送password

    -- 增加发送验证码次数
    if send_times == 0 then
        _, err = redis:do_cmd("setex", sms_freq_key, 1, 1800)
    else
        _, err = redis:do_cmd("incr", sms_freq_key)
    end

    if err then
        ngx.log(ngx.ERR, "failed to set sms freq,phone=", phone, ",err=", err)
    end

    return restful:ok({s = s, N_num_bits = N_num_bits,
        countdown = countdown, validtime = validtime}, now + countdown)
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

    local srp_data, err = get_srp_tmp(phone)
    if err then
        return restful:internal_server_error("系统繁忙")
    end

    if not srp_data then
        srp_data, err = get_srp_persist(phone)
        if err then
            return restful:internal_server_error("系统繁忙")
        end
    end

    if not srp_data or not srp_data.v or not srp_data.s then
        return restful:forbidden("非法请求")
    end

    local b = str.to_hex(random.bytes(32, true))
    local B = srp.Calc_B(b, N, g, srp_data.v)
    ngx.log(ngx.DEBUG, "phone=", phone, ",b=", b, ",B=", B)
    srp_data = {v = srp_data.v, s = srp_data.s, b = b, A = A, B = B}

    err = set_srp_tmp(phone, srp_data)
    if err then
        return restful:internal_server_error("系统繁忙")
    end

    return restful:wrap({B = B})
end

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

    srp_data = {key = server_key, v = srp_data.v, s = srp_data.s}
    local err = set_srp_persist(phone, srp_data)
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



    local srp_arg = ngx.var[1]
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






