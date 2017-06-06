local services = require("services")
local restful = require("resty.restful")
local resty_sha256 = require("resty.sha256")
local http = require("resty.http")
local str = require("resty.string")
local cjson = require("cjson.safe")
local utf8_simple = require("resty.utf8_simple")

local _M = {}

local function send_flippedwords_by_sms(body)
	local abstract = ""
	if type(body.contents) ~= "table" then
		return
	end

	for _, content in ipairs(body.contents) do
		if content.type == "text" and type(content.text) == "string" then
			abstract = abstract .. content.text
		end
	end

	if utf8_simple.len(abstract) > 5 then
		abstract = utf8_simple.sub(abstract, 1, 5)
	end

	if abstract == "" then
		return
	end

	local appid = "1400031910"
    local appkey = "3774316461786106739a79d6632f96da"
    local now = math.floor(ngx.now() * 1000)
    math.randomseed(now)
    local rd = math.random(1000000000, 9999999999)
    local time = math.floor(now / 1000)

    local sha256 = resty_sha256:new()
    sha256:update("appkey=" ..  appkey .. "&random=" .. rd .. "&time=" .. time .. "&mobile=" .. body.sendto)
    local sig = sha256:final()
    sig = str.to_hex(sig)

    local httpc = http:new()
    httpc:set_timeout(10000)
    local res, err = httpc:request_uri("https://yun.tim.qq.com/v5/tlssmssvr/sendsms?" 
        .. ngx.encode_args({sdkappid = appid, random = rd}), {
            body = cjson.encode({
                tel = {
                    nationcode = "86",
                    mobile = tostring(body.sendto),
                },
                type = 0,
                msg = "【动了个心】算了，向你透露一点吧，有人好像对你有点心动，TA说：“" .. abstract .. "”，更多对你心动的话，只能用微信小程序“动了个心”看了，就酱！",
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
            ngx.log(ngx.DEBUG, "send_flippedwords_by_sms body=", res.body)
            res.body = cjson.decode(res.body or "")
            if res.body and res.body.result ~= 0 then
                err = res.body.result .. " " .. res.body.errmsg
            end
        end
    end

    if err then
        ngx.log(ngx.ERR, "failed to send_flippedwords_by_sms,phone=", body.sendto, ",err=", err)
        return err
    end

    return nil
end

function _M:run()
	local body = restful:get_body_data()

	local res = services.flippedsvc:proxy()
	if res.err then
		return res
	end

	-- 当天第一次收到，则直接发送短信
	if res.is_sendto_day_first then
		--send_flippedwords_by_sms(body)
	end
end

return _M

