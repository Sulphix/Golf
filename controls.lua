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
local dragPos
local key = {
	use = keybinds:fromVanilla("key.use")
}

key.use.press = function ()
	if isHighlghitingBall then
		return true
	end
end

key.use.release = function ()
	if isHighlghitingBall then
		sounds:playSound("minecraft:entity.player.attack.sweep",ball.pos,1,1.5)
		local hit = ((ball.pos - dragPos) * 0.4)
		ball.vel = ball.vel + hit + vec(0,hit:length()*0.5,0)
		dragPos = vec(0,0,0)
		throw:clear()
	end
end
events.WORLD_RENDER:register(function (dt)
	if not player:isLoaded() then return end
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
	if isHighlghitingBall then
		host:setActionbar("YES")
	else
		host:setActionbar("...")
	end
end)