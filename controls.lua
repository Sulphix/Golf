local cfg = require "cfg"
local ball = require "ball"
local Trail = require "lib.trail"

local throw = Trail.new()
	:setDuration(2)

---@param pos Vector3
---@param dir Vector3
---@param planeDir Vector3
---@param planePos Vector3
---@return Vector3?
local function ray2PlaneIntersection(pos, dir, planePos, planeDir)
	local dn = dir:normalized()
	local pdn = planeDir:normalized()

	local dot = dn:dot(pdn)
	if math.abs(dot) < 1e-6 then return nil end
	local dtp = pdn:dot(planePos - pos) / dot
	local ip = pos + dn * dtp
	return ip
end

local isHighlghitingBall = false
local isThrown = false
local thrownTimer = 20
local thrownTime = 0
local dragPos
local cameraFollow = true -- camera follow toggle
local key = {
	use = keybinds:fromVanilla("key.use"),
	switchClub = keybinds:fromVanilla("key.sneak"),
}

local swingType = "putter" --default that everyone uses

local swingConfigs = {
	putter = {
		power = 0.2,
		heightMultiplier = 0.05,
		name = "Putter",
	}, --normal putter
	chipper = {
		power = 0.15,
		heightMultiplier = 0.9,
		name = "Chipper",
	}, --high loft, low power
	driver = {
		power = 0.9,
		heightMultiplier = 0.2,
		name = "Driver",
	}, --low loft, high power
}


function pings.shoot(vel)
	sounds:playSound("minecraft:entity.player.attack.sweep", ball.pos, 0.3, 1.6)
	sounds:playSound("minecraft:block.wood.step", ball.pos, 1, 2)
	ball.vel = ball.vel + vel
	dragPos = vec(0, 0, 0)
	throw:clear()
	isThrown = true
	thrownTime = 0
end

key.use.press = function()
	if isHighlghitingBall then
		return true
	end
end

key.use.release = function()
	if isHighlghitingBall then
		local config = swingConfigs[swingType]
		local hit = ((ball.pos - dragPos) * config.power)
		pings.shoot(hit + vec(0, hit:length() * config.heightMultiplier, 0))
	end
end

key.switchClub.press = function()
	if isHighlghitingBall then
		if swingType == "putter" then
			swingType = "chipper"
		elseif swingType == "chipper" then
			swingType = "driver"
		else
			swingType = "putter"
		end
		host:setActionbar("Switched to " .. swingConfigs[swingType].name)
		return true
	end
end

cfg.MODEL_BALL.postRender = function(delta, context, part)
	ball.update(delta)
end

events.POST_WORLD_RENDER:register(function(dt)
	if not player:isLoaded() then return end

	local cpos = player:getPos(dt):add(0, player:getEyeHeight())
	local cdir = player:getLookDir()
	local diff = (ball.pos - cpos)
	if not key.use:isPressed() then
		isHighlghitingBall = cdir:dot(diff:normalize()) > 0.998
	else
		if isHighlghitingBall then
			dragPos = ray2PlaneIntersection(cpos, cdir, ball.pos, vec(0, 1, 0)) or (ball.pos + cdir * 5) --backup when ray misses plane
			local cross = (ball.pos - dragPos):copy():cross(vec(0, 1, 0)):normalize()
			throw:setLeads(ball.pos - cross, ball.pos + cross, cfg.RADIUS)
			throw:setLeads(dragPos - cross, dragPos + cross, 0)
		end
	end

	if isThrown then
		thrownTime = thrownTime + 1
		if cameraFollow then
			renderer:setCameraPivot(math.lerp(cpos,
				math.lerp(ball.lpos, ball.pos, dt) - client:getCameraDir() * 2,
				math.min(thrownTime / 10, 1)))
			renderer:renderRightArm(false)
			renderer:renderLeftArm(false)
			renderer:setRenderHUD(false)
		end
	end

	if isThrown and (ball.lpos - ball.pos):length() < 0.02 then
		thrownTimer = thrownTimer - 1
		if thrownTimer < 0 then
			isThrown = false
			if cameraFollow then
				renderer:setCameraPivot()
				renderer:renderLeftArm()
				renderer:renderRightArm()
				renderer:setRenderHUD(true)
			end
			thrownTimer = 20
		end
	end
	if isHighlghitingBall then
		cfg.MODEL_BALL:setPrimaryRenderType("EMISSIVE_SOLID")
	else
		cfg.MODEL_BALL:setPrimaryRenderType("CUTOUT")
	end
end)

-- Function to allow ball.lua to control camera follow
function pings.setCameraFollow(enabled)
	cameraFollow = enabled
end

-- Export function for ball.lua to read camera follow state
function getCameraFollow()
	return cameraFollow
end
