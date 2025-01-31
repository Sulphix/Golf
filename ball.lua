---@diagnostic disable: unused-local, redefined-local
--[[______   __
  / ____/ | / / by: GNamimates, Discord: "@gn8.", Youtube: @GNamimates
 / / __/  |/ / Golf Ball ball
/ /_/ / /|  / 
\____/_/ |_/ Source: link]]

local ball = {
	lpos = vec(0,0,0),
	pos = vec(0,0,0),
	vel = vec(0,0,0),
	isUnderwater = false,
}

local cfg = require"cfg"

local TEXTURE_SHADOW = textures["textures.shadow"]
local SHADOW_RES = TEXTURE_SHADOW:getDimensions()
local MODEL_SHADOW = models:newPart("shadow","WORLD")
MODEL_SHADOW:newSprite("board"):setRenderType("BLURRY")
:texture(TEXTURE_SHADOW,SHADOW_RES:unpack()):rot(90,0,0):pos(cfg.RADIUS*16,0.5,cfg.RADIUS*16):scale((SHADOW_RES.x/16)*cfg.RADIUS*2,(SHADOW_RES.x/16)*cfg.RADIUS*2,0)
--- caches
local side2dir = {
   ["north"] = vectors.vec3(0,0,1),
   ["east"]  = vectors.vec3(1,0,0),
   ["south"] = vectors.vec3(0,0,-1),
   ["west"]  = vectors.vec3(-1,0,0),
   ["up"]    = vectors.vec3(0,1,0),
   ["down"]  = vectors.vec3(0,-1,0),
}


events.ENTITY_INIT:register(function ()
	ball.pos = player:getPos():add(-2,1,0)
end)



events.TICK:register(function ()
	ball.lpos = ball.pos
	ball.pos = ball.pos + ball.vel
	ball.vel = ball.vel + cfg.GRAVITY
	
	local i = 1
	local blocks = {}
	for z = -cfg.CHECK_RADIUS, cfg.CHECK_RADIUS do
		for y = -cfg.CHECK_RADIUS, cfg.CHECK_RADIUS do
			for x = -cfg.CHECK_RADIUS, cfg.CHECK_RADIUS do
				local offset = vec(x,y,z)
				local bpos = ball.pos:floor() + offset
				local block = world.getBlockState(bpos)
				if block:hasCollision() then
					for key, value in pairs(block:getCollisionShape()) do
						blocks[i] = {value[1] + bpos - cfg.RADIUS, value[2] + bpos + cfg.RADIUS}
						i = i + 1
					end
				end
			end
		end
	end
	local _, hit,face = raycast:aabb(ball.lpos, ball.pos+ball.vel, blocks)
	if face then
		local norm = side2dir[face]
		local flat = (ball.vel - norm * ball.vel:dot(norm))
		local absorbed = (flat - ball.vel)
		local bounces = absorbed:length()*10 > cfg.BOUNCINESS
		ball.vel = flat * cfg.FRICTION + absorbed * (bounces and (cfg.BOUNCINESS) or 0)
		ball.pos = hit + cfg.MARGIN * norm
		if bounces then
			local block = world.getBlockState(hit-norm*(cfg.RADIUS+cfg.MARGIN))
			local bsounds = block:getSounds()
			if bsounds.hit then
				sounds[bsounds["step"]]:pitch(2):pos(hit):play()
			end
		end
	end
	local block = world.getBlockState(ball.pos)
	if #block:getFluidTags() > 0 then
		if not ball.isUnderwater then
			ball.isUnderwater = true
			sounds["minecraft:entity.generic.splash"]:pos(ball.pos):pitch(1):play()
			for _ = 1, 10, 1 do
				particles["minecraft:splash"]:pos(ball.pos):spawn()
			end
			particles["minecraft:cloud"]:pos(ball.pos):spawn()
		end
		ball.vel = ball.vel * 0.7
	else
		if ball.isUnderwater then
			ball.isUnderwater = false
		end
	end
	
	-- shadow
	local sto = ball.lpos + vec(0,-5,0)
	local _,shit = raycast:block(ball.lpos,sto)
	if (sto - shit):lengthSquared() ~= 0 then
		MODEL_SHADOW:setPos(shit*16):setVisible(true)
	else
		MODEL_SHADOW:setVisible(true)
	end
end)

cfg.MODEL_BALL.postRender = function (delta, context, part)
	cfg.MODEL_BALL:setPos(math.lerp(ball.lpos, ball.pos, delta) * 16)
end

return ball