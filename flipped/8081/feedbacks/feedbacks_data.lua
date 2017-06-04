local cmysql = require("resty.cmysql")
local cjson = require("cjson.safe")

local mysql_conf = {
    host = "10.135.79.26",
    user = "flipped",
    password = "Flipped_mysql_2017"
}

local mysql = cmysql:new(mysql_conf)
local quote_sql_str = ngx.quote_sql_str

local _M = {}

function _M:add_feedbacks(body)
    local now = math.floor(ngx.now() * 1000)
    local sql = string.format("insert into dbFlipped.FeedBacks set contents=%s,uid=%d,ctime=%d",
        quote_sql_str(cjson.encode(body.contents)), body.uid, now)
    local _, err = mysql:execute(sql)
    if err then
        return nil, err
    end

    return nil
end 

return _M













