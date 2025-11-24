--!strict

-----------
-- Types --
-----------
export type ButtonConfig = {
	button: TextButton,
	onClick: (button: TextButton) -> (),
	sounds: {
		hover: Sound?,
		click: Sound?,
	}?,
	connectionTracker: any?, -- ConnectionManager instance
}

---------------
-- Variables --
---------------
local isUserOnTouchDevice = false
local inputCategorizerModule = nil

----------------------
-- Private Functions --
----------------------

-- Determines the primary interaction signal based on device type
local function getPrimaryInteractionSignal(button: TextButton): RBXScriptSignal
	return isUserOnTouchDevice and button.TouchTap or button.MouseButton1Down
end

-- Plays a sound safely
local function playSound(sound: Sound?): ()
	if sound and sound:IsA("Sound") then
		sound:Play()
	end
end

-- Sets up hover audio feedback for non-touch devices
local function setupHoverAudioFeedback(button: TextButton, hoverSound: Sound?, connectionTracker: any?): ()
	if isUserOnTouchDevice then
		return -- Touch devices don't have hover
	end

	local connection = button.MouseEnter:Connect(function()
		playSound(hoverSound)
	end)

	if connectionTracker and connectionTracker.track then
		connectionTracker:track(connection)
	end
end

-- Sets up the primary interaction handler
local function setupPrimaryInteractionHandler(button: TextButton, onClick: (button: TextButton) -> (), clickSound: Sound?, connectionTracker: any?): ()
	local primarySignal = getPrimaryInteractionSignal(button)

	local connection = primarySignal:Connect(function()
		-- Play click sound before callback if provided
		playSound(clickSound)
		onClick(button)
	end)

	if connectionTracker and connectionTracker.track then
		connectionTracker:track(connection)
	end
end

---------------
-- Public API --
---------------
local UIButtonHandler = {}

--[[
	Initializes the button handler with device detection

	@param inputCategorizer - The InputCategorizer module (optional)
]]
function UIButtonHandler.initialize(inputCategorizer: any?): ()
	if inputCategorizer then
		inputCategorizerModule = inputCategorizer
		isUserOnTouchDevice = inputCategorizer.getLastInputCategory() == "Touch"
	end
end

--[[
	Sets up a button with interaction handlers

	@param config - Button configuration
]]
function UIButtonHandler.setupButton(config: ButtonConfig): ()
	if not config.button or not config.button:IsA("TextButton") then
		return
	end

	local hoverSound = config.sounds and config.sounds.hover
	local clickSound = config.sounds and config.sounds.click

	-- Setup primary interaction (Touch or Mouse click)
	setupPrimaryInteractionHandler(
		config.button,
		config.onClick,
		clickSound,
		config.connectionTracker
	)

	-- Setup hover audio for non-touch devices
	setupHoverAudioFeedback(
		config.button,
		hoverSound,
		config.connectionTracker
	)
end

--[[
	Sets up multiple buttons at once

	@param buttons - Array of buttons
	@param onClick - Click handler function
	@param sounds - Optional sounds configuration
	@param connectionTracker - Optional connection tracker
]]
function UIButtonHandler.setupButtons(
	buttons: { TextButton },
	onClick: (button: TextButton) -> (),
	sounds: { hover: Sound?, click: Sound? }?,
	connectionTracker: any?
): ()
	for _, button in buttons do
		UIButtonHandler.setupButton({
			button = button,
			onClick = onClick,
			sounds = sounds,
			connectionTracker = connectionTracker,
		})
	end
end

--[[
	Sets up all TextButton descendants in a container

	@param container - The container GuiObject
	@param onClick - Click handler function
	@param sounds - Optional sounds configuration
	@param connectionTracker - Optional connection tracker
	@param watchForNew - If true, will setup buttons added in the future
]]
function UIButtonHandler.setupAllButtons(
	container: GuiObject,
	onClick: (button: TextButton) -> (),
	sounds: { hover: Sound?, click: Sound? }?,
	connectionTracker: any?,
	watchForNew: boolean?
): ()
	-- Setup existing buttons
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("TextButton") then
			UIButtonHandler.setupButton({
				button = descendant,
				onClick = onClick,
				sounds = sounds,
				connectionTracker = connectionTracker,
			})
		end
	end

	-- Watch for new buttons if requested
	if watchForNew then
		local connection = container.DescendantAdded:Connect(function(descendant)
			if descendant:IsA("TextButton") then
				UIButtonHandler.setupButton({
					button = descendant,
					onClick = onClick,
					sounds = sounds,
					connectionTracker = connectionTracker,
				})
			end
		end)

		if connectionTracker and connectionTracker.track then
			connectionTracker:track(connection)
		end
	end
end

--[[
	Checks if the user is on a touch device

	@return boolean - True if on touch device
]]
function UIButtonHandler.isOnTouchDevice(): boolean
	return isUserOnTouchDevice
end

--[[
	Gets the primary interaction signal for a button based on device type

	@param button - The button to get the signal for
	@return RBXScriptSignal - TouchTap or MouseButton1Down
]]
function UIButtonHandler.getPrimarySignal(button: TextButton): RBXScriptSignal
	return getPrimaryInteractionSignal(button)
end

--------------
-- Return  --
--------------
return UIButtonHandler