local restful = require("resty.restful")
local credis = require("resty.credis")
local cjson = require("cjson.safe")
local random = require("resty.random")
local str = require("resty.string")
local http = require("resty.http")
local resty_sha256 = require("resty.sha256")
local srp = require("srp")
local srp_store = require("srp_store")

local redis_conf = {
    host = "10.135.79.26",
    password = "flipped@redis"
}

local redis = credis:new(redis_conf)
local countdown = 60
local password_validtime = 3600
local B_validtime = 3600
local STATUS_PASSWORD_ALREADY_SEND = 2
local STATUS_AFTER_EXCHANGE_RAND = 3

local function get_phone()
    local phone = ngx.var.http_x_uid
    if not phone then
        return nil
    end

    local valid = ngx.re.match(phone, "1\\d{10}")
    if not valid then
        return nil
    end

    return phone
end

local function send_password(phone, password)
    local appid = "1400031910"
    local appkey = "3774316461786106739a79d6632f96da"
    local now = math.floor(ngx.now() * 1000)
    math.randomseed(now)
    local rd = math.random(1000000000, 9999999999)
    local time = math.floor(now / 1000)

    local sha256 = resty_sha256:new()
    sha256:update("appkey=" ..  appkey .. "&random=" .. rd .. "&time=" .. time .. "&mobile=" .. phone)
    local sig = sha256:final()
    sig = str.to_hex(sig)
    ngx.log(ngx.DEBUG, "phone=", phone, ",sig=", sig)

    local httpc = http:new()
    httpc:set_timeout(10000)
    local res, err = httpc:request_uri("https://yun.tim.qq.com/v5/tlssmssvr/sendsms?" 
        .. ngx.encode_args({sdkappid = appid, random = rd}), {
            body = cjson.encode({
                tel = {
                    nationcode = "86",
                    mobile = tostring(phone),
                },
                type = 0,
                msg = "【小情绪】您的登录验证码是" .. password .. "，请于" .. math.floor(password_validtime / 60) .. "分钟内填写。如非本人操作，请忽略本短信。",
                sig = sig,
                time = time
            }),
            method = "POST",
            ssl_verify = false,
        })

    if res then
        if res.status >= 400 then
            err = "status " .. res.status
        else
            ngx.log(ngx.DEBUG, "send_password body=", res.body)
            local body = cjson.decode(res.body or "")
            if body and body.result ~= 0 then
                err = body.result .. " " .. body.errmsg
            end
        end
    end

    if err then
        ngx.log(ngx.ERR, "failed to send password,phone=", phone, ",err=", err)
        return err
    end

    return nil
end

local function get_password(phone)
    local now = ngx.time()

    local if_modified_since = restful:if_modified_since()
    if if_modified_since and if_modified_since > now then
        return restful:not_modified()
    end

    local srp_data, err = srp_store:get_srp_tmp(phone)
    if err then
        ngx.log(ngx.ERR, "failed to get srp tmp data,phone=", phone, ",err=", err)
        return restful:internal_server_error("获取验证码失败")
    end

    -- 一分钟内发送过了
    if type(srp_data) == "table" and type(srp_data.last_send_time) == "number"
        and srp_data.last_send_time + countdown > now then
        return {s = srp_data.s, N_num_bits = srp_store.N_num_bits, 
            countdown = srp_data.last_send_time + countdown - now,
            validtime = srp_data.last_send_time + password_validtime - now}
    end

    -- 获取验证码次数超过频率限制
    local sms_freq_key = "SMSFQ" .. phone
    local send_times
    send_times, err = redis:do_cmd("get", sms_freq_key)
    if err then
        return restful:internal_server_error("获取验证码失败")
    end

    send_times = tonumber(send_times) or 0
    if send_times >= 3000 then
        return restful:too_many_requests("获取验证码次数过多，请稍后重试")
    end

    -- 生成随机6位数，生成盐
    local s = str.to_hex(random.bytes(16, true))
    local password = tonumber(str.to_hex(random.bytes(8)), 16) % 1000000
    password = string.format("%06d", password)
    ngx.log(ngx.DEBUG, "phone=", phone, ",s=", s, ",password=", password)

    local g, N = srp.get_default_gN(srp_store.N_num_bits)
    local v = srp.create_verifier(phone, password, s, N, g)

    -- 写srp临时存储
    err = srp_store:set_srp_tmp(phone, {last_send_time = now, s = s, v = v, status = STATUS_PASSWORD_ALREADY_SEND}, password_validtime)
    if err then
        return restful:internal_server_error("获取验证码失败")
    end

    -- 发送验证码
    err = send_password(phone, password)
    if err then
        srp_store:del_srp_tmp(phone)
        return restful:internal_server_error("获取验证码失败")
    end

    -- 增加发送验证码次数
    if send_times == 0 then
        _, err = redis:do_cmd("setex", sms_freq_key, 3600, 1)
    else
        _, err = redis:do_cmd("incr", sms_freq_key)
    end

    if err then
        ngx.log(ngx.ERR, "failed to set sms freq,phone=", phone, ",err=", err)
    end

    return restful:ok({s = s, N_num_bits = srp_store.N_num_bits,
        countdown = countdown, validtime = srp_store.validtime}, now + countdown)
end

local function get_B(phone)
    local A = ngx.var.arg_a
    if not A then
        return restful:unprocessable_entity("参数非法")
    end

    local g, N = srp.get_default_gN(srp_store.N_num_bits)
    if srp.Verify_mod_N(A, N) == 0 then
        return restful:unprocessable_entity()
    end

    local now = ngx.time()
    local srp_data, err = srp_store:get_srp_tmp(phone)
    if err then
        return restful:internal_server_error("系统繁忙")
    end

    -- 前置状态是验证码已发送，则要求临时srp存储还在
    if srp_data then
        if not srp_data.v or not srp_data.s 
            or not srp_data.status or not srp_data.staus == STATUS_PASSWORD_ALREADY_SEND then
            return restful:forbidden("非法请求")
        end
    -- 前置状态是key已过期，则要求持久srp存储存在，且key已过期
    else
        srp_data, err = srp_store:get_srp_persist(phone)
        if err then
            return restful:internal_server_error("系统繁忙")
        end

        if not srp_data or not srp_data.v or not srp_data.s or not srp_data.K
            or not srp_data.validtime or srp_data.validtime > now then
            return restful:forbidden("非法请求")
        end
    end

    local b = str.to_hex(random.bytes(32, true))
    local B = srp.Calc_B(b, N, g, srp_data.v)
    ngx.log(ngx.DEBUG, "phone=", phone, ",b=", b, ",B=", B)
    srp_data = {v = srp_data.v, s = srp_data.s, b = b, A = A, B = B, status = STATUS_AFTER_EXCHANGE_RAND}

    err = srp_store:set_srp_tmp(phone, srp_data, B_validtime)
    if err then
        return restful:internal_server_error("系统繁忙")
    end

    return restful:wrap({B = string.lower(B)})
end

local function get_M2(phone)
    local client_M1 = ngx.var.arg_m1
    if not client_M1 then
        return restful:unprocessable_entity("参数非法")
    end

    local srp_data = srp_store:get_srp_tmp(phone)
    if not srp_data or not srp_data.A or not srp_data.B or not srp_data.b
        or not srp_data.v or not srp_data.s 
        or not srp_data.status or not srp_data.status == STATUS_AFTER_EXCHANGE_RAND then
        return restful:forbidden("非法请求")
    end

    local g, N = srp.get_default_gN(srp_store.N_num_bits)
    local server_key = srp.Calc_server_key(srp_data.A, srp_data.B, N, srp_data.v, srp_data.b);
    local server_M1 = srp.Calc_M1(N, g, phone, srp_data.s, srp_data.A, srp_data.B, server_key);
    local server_M2 = srp.Calc_M2(srp_data.A, server_M1, server_key)
    ngx.log(ngx.DEBUG, "phone=", phone, ",server_key=", server_key, ",client_M1=", client_M1, 
        ",server_M1=", server_M1, ",server_M2=", server_M2)
    if string.lower(client_M1) ~= string.lower(server_M1) then
        local wrong_password_key = "WPFQ" .. phone
        local wrong_times, err = redis:do_cmd("get", wrong_password_key)
        if err then
            return restful:internal_server_error("系统繁忙")
        end 

        wrong_times = tonumber(wrong_times) or 0
        -- 验证码错误次数达到3次， 验证码失效，需删除srp tmp存储
        local max_wrong_times = 3000
        if wrong_times + 1 >= max_wrong_times then
            if not srp_store:del_srp_tmp(phone) then
                redis:do_cmd("del", wrong_password_key)
            end

            return restful:too_many_requests("输入错误的验证码达到" .. max_wrong_times .. "次，请重新获取验证码")
        end

        if wrong_times == 0 then
            _, err = redis:do_cmd("setex", wrong_password_key, password_validtime, 1)
        else
            _, err = redis:do_cmd("incr", wrong_password_key)
        end

        if err then
            ngx.log(ngx.ERR, "failed to set wrong times,phone=", phone, ",err=", err)
        end
        
        return restful:unprocessable_entity("验证码错误，还有" .. max_wrong_times - wrong_times - 1 .. "次机会")
    end

    srp_data = {K = server_key, v = srp_data.v, s = srp_data.s}
    local err = srp_store:set_srp_persist(phone, srp_data)
    if err then
        return restful:internal_server_error("系统繁忙")
    end

    return restful:wrap({M2 = string.lower(server_M2)})
end

local function run()
    local phone = get_phone()
    if not phone then
        return restful:unprocessable_entity("手机号不合法")
    end

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

restful:say(run())







