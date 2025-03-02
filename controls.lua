local cfg = require"cfg"
local ball = require"ball"
local Trail = require"lib.trail"

local throw = Trail.new()
:setDuration(2)

---@param pos Vector3
---@param dir Vector3
---@param planeDir Vector3
---@param planePos Vector3
---@return Vector3?
local function ray2PlaneIntersection(pos,dir,planePos,planeDir)
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
local key = {
	use = keybinds:fromVanilla("key.use")
}


function pings.shoot(vel)
	sounds:playSound("minecraft:entity.player.attack.sweep",ball.pos,0.3,1.6)
	sounds:playSound("minecraft:block.wood.step",ball.pos,1,2)
	ball.vel = ball.vel + vel
	dragPos = vec(0,0,0)
	throw:clear()
	isThrown = true
	thrownTime = 0
end

key.use.press = function ()
	if isHighlghitingBall then
		return true
	end
end

key.use.release = function ()
	if isHighlghitingBall then
		local hit = ((ball.pos - dragPos) * 0.3)
		pings.shoot(hit + vec(0,hit:length()*0.3,0))
	end
end
events.POST_WORLD_RENDER:register(function (dt)
	if not player:isLoaded() then return end
	
	ball.update(dt)
	local cpos = player:getPos(dt):add(0,player:getEyeHeight())
	local cdir = player:getLookDir()
	local diff = (ball.pos-cpos)
	if not key.use:isPressed() then
		isHighlghitingBall = cdir:dot(diff:normalize()) > 0.998
	else
		if isHighlghitingBall then
			dragPos = ray2PlaneIntersection(cpos,cdir,ball.pos,vec(0,1,0))
			local cross = (ball.pos-dragPos):copy():cross(vec(0,1,0)):normalize()
			throw:setLeads(ball.pos-cross,ball.pos+cross,cfg.RADIUS)
			throw:setLeads(dragPos-cross,dragPos+cross,0)
		end
	end
	
	if isThrown then
		thrownTime = thrownTime + 1
		renderer:setCameraPivot(math.lerp(cpos,math.lerp(ball.lpos,ball.pos,dt) - client:getCameraDir() * 2,math.min(thrownTime / 10,1)))
		renderer:renderRightArm(false)
		renderer:renderLeftArm(false)
		renderer:setRenderHUD(false)
	end
	
	if isThrown and (ball.lpos-ball.pos):length() < 0.02 then
		thrownTimer = thrownTimer - 1
		if thrownTimer < 0 then
			isThrown = false
			renderer:setCameraPivot()
			renderer:renderLeftArm()
			renderer:renderRightArm()
			renderer:setRenderHUD(true)
			thrownTimer = 20
		end
	end
	if isHighlghitingBall then
		cfg.MODEL_BALL:setPrimaryRenderType("EMISSIVE_SOLID")
	else
		cfg.MODEL_BALL:setPrimaryRenderType("CUTOUT")
	end
end)