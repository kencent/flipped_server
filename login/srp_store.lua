local credis = require("resty.credis")
local cmysql = require("resty.cmysql")
local cjson = require("cjson.safe")
local utils = require("resty.utils")
local quote_sql_str = ngx.quote_sql_str

local _M = {
    N_num_bits = "2048",
}

local redis_conf = {
    host = "10.135.79.26",
    password = "flipped@redis"
}

local mysql_conf = {
    host = "10.135.79.26",
    user = "flipped",
    password = "Flipped_mysql_2017"
}

local redis = credis:new(redis_conf)
local mysql = cmysql:new(mysql_conf)
local longvalidtime = 7 * 86400
local validtime = 1800
local K_tmp_validtime = 600

local function get_srp_tb(I)
    local hash = utils:hash(I) % 1000
    local db, tb = math.floor(hash / 100), hash % 100
    return string.format("dbLogin_%d.SRP_%d", db, tb)
end


local function get_srp_tmp_key(I)
    return "SRPTMP" .. I
end

function _M:get_K(I)
    local key = get_srp_tmp_key(I)
    local res, err = credis:do_cmd("get", key)
    if err then
        ngx.log(ngx.ERR, "failed to get K from redis,I=", I, ",err=", err)
    end

    if res then
        return res
    end

    local now = ngx.time()
    local sql = string.format("select key from %s where I=%s and validtime>%d",
        get_srp_tb(I), quote_sql_str(I), now)
    res, err = mysql:get(sql)
    if err then
        ngx.log(ngx.ERR, "failed to get K from mysql,I=", I, ",err=", err)
        return nil, err
    end

    local K = res.key
    credis:do_cmd("setex", K_tmp_validtime, K)
    return K
end

function _M:set_srp_tmp(I, value, expire)
    local res, err = redis:do_cmd("setex", get_srp_tmp_key(I), expire, cjson.encode(value))
    ngx.log(ngx.DEBUG, "res=", cjson.encode(res), ",err=", err)
    return err
end

function _M:get_srp_tmp(I)
    local data, err = redis:do_cmd("get", get_srp_tmp_key(I))
    if err then
        return nil, err
    end

    return type(data) == "string" and cjson.decode(data) or nil
end


function _M:get_srp_persist(I)
    local now = ngx.time()
    local sql = string.format("select v,s,key,validtime from %s where I=%s and longvalidtime>%d",
        get_srp_tb(I), quote_sql_str(I), now)
    local data, err = mysql:get(sql)
    if err and err == "not found" then
        return nil
    end

    if err then
        return nil, err
    end

    return data
end

function _M:del_srp_tmp(I)
    return redis:do_cmd("del", get_srp_tmp_key(I))
end

function _M:set_srp_persist(I, value)
    local now = ngx.time()
    local sql = string.format("replace into %s set v=%s,s=%s,K=%s,validtime=%d,longvalidtime=%d,I=%s", 
        get_srp_tb(I), quote_sql_str(value.v), quote_sql_str(value.s), 
        quote_sql_str(value.K), now + validtime, now + longvalidtime, quote_sql_str(I))

    local _, err = mysql:execute(sql)
    if not err then
        _M:del_srp_tmp(I)
    end

    return err
end

return _M







