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

local _M = {
    STATUS_NEW = 0,
    STATUS_ISSUED = 100,
    STATUS_READ = 200,
}

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

function _M:get_flippedword(id)
    local sql = string.format("select %s from dbFlipped.Flipped where id=%d",
        flippedwords_field, id)
    local res, err = mysql:get(sql)
    if err then
        return nil, err
    end

    arrange_flippedwords({res})
    return res
end

function _M:add_flippedwords(body)
    local now = math.floor(ngx.now() * 1000)
    local day_first_milliseconds = utils:get_day_begin(math.floor(now / 1000)) * 1000
    -- 一天只能发一次
    local sql = string.format("select %s from dbFlipped.Flipped where uid=%s and ctime>%d limit 1",
        flippedwords_field, quote_sql_str(body.uid), day_first_milliseconds)
    local res, err = mysql:query(sql)
    if err then
        return nil, err
    end

    if type(res) == "table" and #res > 1000 then
        return nil, "no affected"
    end

    local geohash = ""
    if type(body.lat) == "number" and type(body.lng) == "number" then
        geohash = iwi.encode(body.lat, body.lng, GEOHASH_LENGTH)
    end

    sql = string.format("insert into dbFlipped.Flipped set contents=%s,uid=%d,sendto=%d,ctime=%d,lat=%f,lng=%f,geohash=%s,status=%d,statusupdatetime=%d",
        quote_sql_str(cjson.encode(body.contents)), body.uid, body.sendto, now, body.lat or 0, body.lng or 0, quote_sql_str(geohash), _M.STATUS_NEW, now)
    res, err = mysql:execute(sql)
    if err then
        return nil, err
    end

    local id = res.insert_id
    local is_sendto_day_first = false

    -- 接收人是不是当天第一次收到
    sql = string.format("select %s from dbFlipped.Flipped where sendto=%d and ctime>=%d limit 2",
        flippedwords_field, body.sendto, day_first_milliseconds)
    res = mysql:query(sql)
    if res and #res == 1 then
        is_sendto_day_first = true
    end

    return {id = id, ctime = now, sendto = body.sendto, is_sendto_day_first = is_sendto_day_first}
end

function _M:nearby_flippedwords(args)
    local lat = tonumber(args.lat)
    local lng = tonumber(args.lng)
    local page = 200
    local nearby_distance = 1000
    local ret = {}

    -- 用户授权了位置，查附近
    if type(lat) == "number" and type(lng) == "number" then
        local geohash = iwi.encode(lat, lng, GEOHASH_LENGTH)
        local neighbors = iwi.neighbors(geohash)
        local geohashs = { quote_sql_str(geohash) }
        for _, elem in pairs(neighbors) do
            table.insert(geohashs, quote_sql_str(elem))
        end

        local sql = string.format("select id,lat,lng from dbFlipped.Flipped where geohash in (%s) and status=%d",
            table.concat(geohashs, ","), _M.STATUS_NEW)
        local res, err = mysql:query(sql)
        if err then
            return nil, err 
        end

        local nearby = {}
        for _, elem in ipairs(res) do
            elem.distance = math.floor(iwi.distance(lat, lng, elem.lat, lng, iwi.kilometers) * 1000)
            if elem.distance <= nearby_distance then
                table.insert(nearby, elem)
            end
        end

        table.sort(nearby, function (a, b) 
            if a.distance < b.distance then
                return true
            end

            if a.distance > b.distance then
                return false
            end

            return a.id > b.id
        end)

        local ids = {}
        for _, elem in ipairs(nearby) do
            table.insert(ids, elem.id)
            if #ids >= page then
                break
            end
        end

        if #ids > 0 then
            sql = string.format("select %s from dbFlipped.Flipped where id in (%s)", 
                flippedwords_field, table.concat(ids, ","))
            res, err = mysql:query(sql)
            if err then
                return nil, err
            end

            for i, id in ipairs(ids) do
                for _, detail in ipairs(res) do
                    if id == detail.id then
                        detail.distance = nearby[i].distance
                        table.insert(ret, detail)
                        break
                    end
                end
            end
        end
    end

    -- 用户未授权位置或附近的不够，拿最新的补充
    if #ret < page then
        local sql = string.format("select %s from dbFlipped.Flipped where status=%d order by id desc limit %d",
            flippedwords_field, _M.STATUS_NEW, page)
        local res, err = mysql:query(sql)
        if err then
            return nil, err
        end

        for _, elem in ipairs(res) do
            local found = false
            for _, nearby in ipairs(ret) do
                if elem.id == nearby.id then
                    found = true
                    break
                end
            end

            if found == false then
                table.insert(ret, elem)
            end
        end
    end

    return arrange_flippedwords(ret)
end

function _M:my_flippedwords(uid, id)
    id = id or 0
    local sql = string.format("select %s from dbFlipped.Flipped where sendto=%d and id>%d order by id asc limit 200",
        flippedwords_field, uid, id)
    local res, err = mysql:query(sql)
    if err then
        return nil, err
    end

    if id > 0 then
        local now = math.floor(ngx.now() * 1000)
        sql = string.format("update dbFlipped.Flipped set status=%d,statusupdatetime=%d where sendto=%d and id<=%d", 
            _M.STATUS_ISSUED, now, uid, id)
        mysql:execute(sql)
    end
    
    return arrange_flippedwords(res)
end

function _M:mypub_flippedwords(uid, id)
    id = id or 4300000000
    local sql = string.format("select %s from dbFlipped.Flipped where uid=%d and id<%d order by id asc limit 30",
        flippedwords_field, uid, id)
    local res, err = mysql:query(sql)
    if err then
        return nil, err
    end

    return arrange_flippedwords(res)
end


function _M:read_flippedwords(uid, last_open_time)
    last_open_time = last_open_time or 0
    local mintime = math.floor(ngx.now() * 1000) - 30 * 86400 * 1000
    if last_open_time < mintime then
        last_open_time = mintime
    end

    local sql = string.format("select %s from dbFlipped.Flipped where uid=%d and status=%d and statusupdatetime>%d order by id asc",
        flippedwords_field, uid, uid, _M.STATUS_READ, last_open_time)
    local res, err = mysql:query(sql)
    if err then
        return nil, err
    end

    return arrange_flippedwords(res)
end


function _M:flippedwords_read(id)
    local now = math.floor(ngx.now() * 1000)
    local sql = string.format("update dbFlipped.Flipped set status=%d,statusupdatetime=%d where id=%d", 
        _M.STATUS_READ, now, id)
    local _, err = mysql:execute(sql)
    return err
end

return _M














