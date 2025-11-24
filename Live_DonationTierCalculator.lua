--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Configuration = ReplicatedStorage:WaitForChild("Configuration")
local GameConfig = require(Configuration.GameConfig)

---------------
-- Constants --
---------------
local DONATION_TIER_CONFIGURATIONS = GameConfig.LIVE_DONATION_CONFIG.LEVEL_THRESHOLD_CUSTOMIZATION
local HIGH_TIER_THRESHOLD = 2 -- Level >= 2 considered high tier

-----------
-- Types --
-----------
export type DonationTierInfo = {
	Level: number,
	Lifetime: number,
	Color: Color3,
}

-----------
-- Module --
-----------
local DonationTierCalculator = {}

--[[
	Determines tier info based on donation amount

	Iterates through tier configurations from highest to lowest
	to find the appropriate tier for the given amount.

	@param donationAmount number - Amount donated
	@return DonationTierInfo - Tier configuration
]]
function DonationTierCalculator.determineTierInfo(donationAmount: number): DonationTierInfo
	for tierLevel = #DONATION_TIER_CONFIGURATIONS, 1, -1 do
		local tierConfiguration = DONATION_TIER_CONFIGURATIONS[tierLevel]
		if donationAmount >= tierConfiguration.Threshold then
			return {
				Level = tierLevel,
				Lifetime = tierConfiguration.Lifetime,
				Color = tierConfiguration.Color,
			}
		end
	end

	-- Default to lowest tier if amount doesn't meet any threshold
	local lowest = DONATION_TIER_CONFIGURATIONS[1]
	return {
		Level = 1,
		Lifetime = lowest.Lifetime,
		Color = lowest.Color,
	}
end

--[[
	Checks if donation qualifies as high tier

	High tier donations receive special display treatment (countdown bars, etc)

	@param tierInfo DonationTierInfo - Tier information
	@return boolean - True if high tier
]]
function DonationTierCalculator.isHighTier(tierInfo: DonationTierInfo): boolean
	return tierInfo.Level >= HIGH_TIER_THRESHOLD
end

--[[
	Gets the minimum threshold for high tier donations

	@return number - Minimum tier level for high tier
]]
function DonationTierCalculator.getHighTierThreshold(): number
	return HIGH_TIER_THRESHOLD
end

return DonationTierCalculator