--!strict

local PassUIUtilities = {}

local TAG = "[PassUIUtilities]"

---------------
-- Functions --
---------------

--[[
	Safely waits for a child with timeout and error handling
	@param parent Instance - Parent to search in
	@param childName string - Name of child to find
	@param timeout number? - Timeout in seconds (default: 5)
	@return Instance? - Found child or nil
]]
function PassUIUtilities.safeWaitForChild(parent: Instance, childName: string, timeout: number?): Instance?
	local success, result = pcall(function()
		return parent:WaitForChild(childName, timeout or 5)
	end)
	if success then
		return result
	end
	warn(string.format("%s Failed to find child: %s in %s", TAG, childName, parent:GetFullName()))
	return nil
end

--[[
	Removes all children of a specific class from a container
	@param container Instance - Container to clear
	@param className string - Class name to remove (e.g., "TextButton")
	@return number - Count of removed children
]]
function PassUIUtilities.clearChildrenOfClass(container: Instance, className: string): number
	local removedCount = 0
	local children = container:GetChildren()
	for i = 1, #children do
		local child = children[i]
		if child:IsA(className) then
			child:Destroy()
			removedCount = removedCount + 1
		end
	end
	return removedCount
end

--[[
	Resets a gamepass scroll frame by clearing all TextButton children and resetting scroll position
	@param scrollFrame ScrollingFrame - Scroll frame to reset
	@return number - Count of removed items
]]
function PassUIUtilities.resetGamepassScrollFrame(scrollFrame: ScrollingFrame): number
	if not scrollFrame or not scrollFrame:IsA("ScrollingFrame") then
		warn(TAG .. " Invalid scroll frame for reset")
		return 0
	end
	local removedCount = PassUIUtilities.clearChildrenOfClass(scrollFrame, "TextButton")
	scrollFrame.CanvasPosition = Vector2.zero
	if removedCount > 0 then
		print(TAG .. " Reset scroll frame, removed " .. removedCount .. " items")
	end
	return removedCount
end

return PassUIUtilities