local cmysql = require("resty.cmysql")
local iwi = require("iwi")
local cjson = require("cjson.safe")
local utils = require("resty.utils")

local mysql_conf = {
    host = "10.135.79.26",
    user = "flipped",
    password = "Flipped_mysql_2017"
}

local mysql = cmysql:new(mysql_conf)
local GEOHASH_LENGTH = 5
local quote_sql_str = ngx.quote_sql_str
local flippedwords_field = "id,sendto,ctime,contents,lat,lng"
local STATUS_NEW = 0
local STATUS_ISSUED = 100
--local STATUS_READED = 200

local _M = {}

local function arrange_flippedwords(res)
    if type(res) ~= "table" then
        return res
    end

    for _, elem in ipairs(res) do
        if elem.id then
            elem.id = tonumber(elem.id)
        end

        if elem.ctime then
            elem.ctime = tonumber(elem.ctime)
        end
    end

    return res
end

function _M:add_flippedwords(body)
    local now = ngx.now() * 1000
    local day_first_milliseconds = utils:get_day_begin(math.floor(now / 1000)) * 1000
    -- 一天只能发一次
    local sql = string.format("select %s from dbFlipped.Flipped where sendfrom=%s and ctime>%d",
        flippedwords_field, quote_sql_str(body.sendfrom), day_first_milliseconds)
    local res, err = mysql:query(sql)
    if err then
        return nil, err
    end

    if type(res) == "table" and #res > 0 then
        return nil, "no affected"
    end

    local geohash = ""
    if type(body.lat) == "number" and type(body.lng) == "number" then
        geohash = iwi.encode(body.lat, body.lng, GEOHASH_LENGTH)
    end

    sql = string.format("insert into dbFlipped.Flipped set contents=%s,sendfrom=%d,sendto=%d,ctime=%d,lat=%f,lng=%f,geohash=%s,status=%d",
        quote_sql_str(cjson.encode(body.contents)), body.sendfrom, body.sendto, now, body.lat or 0, body.lng or 0, quote_sql_str(geohash), STATUS_NEW)
    res, err = mysql:execute(sql)
    if err then
        return nil, err
    end

    return {id = tonumber(res.insert_id)}
end

function _M:nearby_flippedwords(args)
    local id = tonumber(args.id) or 4200000000
    local lat = tonumber(args.lat)
    local lng = tonumber(args.lng)
    local page = 100

    -- 用户授权了位置，查附近
    if type(lat) == "number" and type(lng) == "number" then
        local geohash = iwi.encode(lat, lng, GEOHASH_LENGTH)
        local neighbors = iwi.neighbors(geohash)
        local geohashs = { quote_sql_str(geohash) }
        for _, elem in pairs(neighbors) do
            table.insert(geohashs, quote_sql_str(elem))
        end

        local ret = {}
        local maxid = id
        while true do
            local sql = string.format("select %s from dbFlipped.Flipped where geohash in (%s) and id<%d order by id desc limit %d",
                flippedwords_field, table.concat(geohashs, ","), maxid, page)
            local res, err = mysql:query(sql)
            if err then
                return nil, err 
            end

            -- 只返回1km以内的
            for _, elem in ipairs(res) do
                local distance = iwi.distance(lat, lng, elem.lat, lng, iwi.kilometers)
                if distance <= 1 then
                    table.insert(ret, elem)
                    if #ret >= page then
                        break
                    end
                end

                maxid = elem.id
            end

            if #ret >= page or #res < page then
                break
            end
        end

        return arrange_flippedwords(ret)
    -- 用户未授权位置，查最新
    else
        local sql = string.format("select %s from dbFlipped.Flipped where id<%d order by id desc limit %d",
            flippedwords_field, id, page)
        local res, err = mysql:query(sql)
        if err then
            return nil, err
        end

        return arrange_flippedwords(res)
    end
end

function _M:my_flippedwords(uid, id)
    id = id or 0
    local sql = string.format("select %s from dbFlipped.Flipped where id>%d and sendto=%d order by id asc limit 500",
        flippedwords_field, id, uid)
    ngx.log(ngx.DEBUG, "sql=", sql)
    local res, err = mysql:query(sql)
    if err then
        return nil, err
    end

    sql = string.format("update dbFlipped.Flipped set status=%d where sendto=%d and id<=%d", 
        STATUS_ISSUED, uid, id)
    mysql:execute(sql)
    return arrange_flippedwords(res)
end

return _M














