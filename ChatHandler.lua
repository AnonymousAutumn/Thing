--!strict

--------------
-- Services --
--------------
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TextChatService = game:GetService("TextChatService")

-----------
-- Types --
-----------
export type ChatTagProperties = {
	COLOR: string | UIGradient,
	TAG: string,
}

---------------
-- Constants --
---------------
local TEMPLATE_RICHTEXT: string = "<font color='%s'><b>%s</b></font> %s"
local DEFAULT_TEXT_COLOR: string = "#FFFFFF"
local LOG_PREFIX: string = "[ChatHandler]"

----------------
-- References --
----------------
local network: Folder = ReplicatedStorage:WaitForChild("Network")
local remotes = network:WaitForChild("Remotes")
local remoteEvents = remotes:WaitForChild("Events")
local sendMessageEvent = remoteEvents:WaitForChild("SendMessage")

local Modules = ReplicatedStorage:WaitForChild("Modules")

local ValidationUtils = require(Modules.Utilities.ValidationUtils)

-- Submodules
local GradientProcessor = require(script.GradientProcessor)
local TextFormatter = require(script.TextFormatter)
local TagResolver = require(script.TagResolver)
local MessageDisplay = require(script.MessageDisplay)

-----------------------
-- Chat Tag Creation --
-----------------------
local function createChatTag(
	tagColorOrGradient: any,
	playerName: string,
	message: TextChatMessage?
): string
	local prefix: string = if message and message.PrefixText then message.PrefixText else ""
	local nameString: string = tostring(playerName)
	local formattedName: string
	local colorString: string = DEFAULT_TEXT_COLOR
	local usesGradient: boolean = false

	-- Handle Folder with UIGradient child
	if ValidationUtils.isValidFolder(tagColorOrGradient) then
		local gradient: UIGradient? = tagColorOrGradient:FindFirstChildOfClass("UIGradient")

		if gradient then
			usesGradient = true
			formattedName = GradientProcessor.processGradientText(
				gradient,
				nameString,
				TextFormatter.stripRichTextTags
			)
		else
			-- Fallback: check for COLOR StringValue
			local colorValue: Instance? = tagColorOrGradient:FindFirstChild("COLOR")
			if ValidationUtils.isValidStringValue(colorValue) then
				colorString = (colorValue :: StringValue).Value
			end
			formattedName = string.format("<font color='%s'>%s</font>", colorString, nameString)
		end
	-- Handle direct UIGradient
	elseif GradientProcessor.isValidUIGradient(tagColorOrGradient) then
		usesGradient = true
		formattedName = GradientProcessor.processGradientText(
			tagColorOrGradient,
			nameString,
			TextFormatter.stripRichTextTags
		)
	-- Handle string color
	elseif typeof(tagColorOrGradient) == "string" then
		colorString = tagColorOrGradient
		formattedName = string.format("<font color='%s'>%s</font>", colorString, nameString)
	-- Fallback to default color
	else
		formattedName = string.format("<font color='%s'>%s</font>", DEFAULT_TEXT_COLOR, nameString)
	end

	-- Gradient text is already colorized per-character
	if usesGradient then
		return string.format("<b>%s</b> %s", formattedName, prefix)
	else
		return string.format(TEMPLATE_RICHTEXT, colorString, formattedName, prefix)
	end
end

------------------------
-- Message Processing --
------------------------
local function onIncomingMessage(message: TextChatMessage): TextChatMessageProperties
	local properties: TextChatMessageProperties = Instance.new("TextChatMessageProperties")
	local tagColor, tagName = TagResolver.getChatTagProperties(message)

	if tagColor and tagName then
		properties.PrefixText = createChatTag(tagColor, tagName, message)
	end

	return properties
end

--------------------
-- Initialization --
--------------------
TextChatService.OnIncomingMessage = onIncomingMessage
sendMessageEvent.OnClientEvent:Connect(MessageDisplay.displayRobuxTransaction)