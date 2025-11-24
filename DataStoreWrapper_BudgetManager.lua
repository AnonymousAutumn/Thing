--!strict

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