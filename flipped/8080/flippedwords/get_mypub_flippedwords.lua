local services = require("services")

local _M = {}

function _M:run()
	return services.flippedsvc:proxy()
end

return _M

