local services = require("services")

local _M = {}

function _M:run()
	return services.feedbackssvc:proxy()
end

return _M

