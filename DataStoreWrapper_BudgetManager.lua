--!strict

--[[
	DataStoreWrapper_BudgetManager

	Manages DataStore request budgets to prevent exceeding rate limits.
	Waits for sufficient budget before allowing operations to proceed.

	Returns: Table with budget management function:
		- waitForRequestBudget: Blocks until budget is available or timeout occurs

	Usage:
		local BudgetManager = require(script.DataStoreWrapper_BudgetManager)
		local success = BudgetManager.waitForRequestBudget(
			Enum.DataStoreRequestType.GetAsync,
			5,
			function() print("Budget wait occurred") end
		)
		if success then
			-- Proceed with DataStore operation
		end
]]

local BudgetManager = {}

--------------
-- Services --
--------------
local DataStoreService = game:GetService("DataStoreService")

---------------
-- Constants --
---------------
local TAG = "[BudgetManager]"

local DEFAULT_BUDGET_TIMEOUT = 5 -- seconds

function BudgetManager.waitForRequestBudget(
	requestType: Enum.DataStoreRequestType,
	maxWaitSeconds: number,
	onBudgetWait: () -> ()
): boolean
	assert(typeof(requestType) == "EnumItem", "requestType must be a DataStoreRequestType enum")
	assert(typeof(maxWaitSeconds) == "number" and maxWaitSeconds > 0, "maxWaitSeconds must be a positive number")
	assert(typeof(onBudgetWait) == "function", "onBudgetWait must be a function")

	local waitStartTime = os.clock()

	while DataStoreService:GetRequestBudgetForRequestType(requestType) < 1 do
		if os.clock() - waitStartTime > maxWaitSeconds then
			warn(TAG .. " " .. string.format("Budget timeout after %d seconds for request type %s",
				maxWaitSeconds, tostring(requestType)))
			return false
		end
		task.wait(0.1)
	end

	onBudgetWait()
	return true
end

return BudgetManager