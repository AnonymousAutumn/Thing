--!strict

---------------
-- Constants --
---------------
local RICH_TEXT_TAG_PATTERN: string = "(<[^<>]->)"
local DEFAULT_TEXT_COLOR: string = "#FFFFFF"

-----------
-- Module --
-----------
local TextFormatter = {}

-------------------
-- Text Processing --
-------------------
function TextFormatter.stripRichTextTags(text: string): string
	return string.gsub(text, RICH_TEXT_TAG_PATTERN, "")
end

function TextFormatter.countFormatPlaceholders(formatString: string): number
	local _, count = string.gsub(formatString, "%%s", "")
	return count
end

-----------------------
-- Formatting Logic --
-----------------------
function TextFormatter.formatWithTemplate(
	template: string,
	coloredName: string,
	colorValue: any,
	prefix: string
): string
	local placeholderCount: number = TextFormatter.countFormatPlaceholders(template)

	if placeholderCount >= 3 then
		local colorString: string = if typeof(colorValue) == "string"
			then colorValue
			else DEFAULT_TEXT_COLOR
		return string.format(template, colorString, coloredName, prefix)
	elseif placeholderCount == 2 then
		return string.format(template, coloredName, prefix)
	elseif placeholderCount == 1 then
		return string.format(template, coloredName)
	else
		return if prefix ~= "" then string.format("%s %s", coloredName, prefix) else coloredName
	end
end

return TextFormatter