--[[______   __
  / ____/ | / / by: GNamimates, Discord: "@gn8.", Youtube: @GNamimates
 / / __/  |/ / Golf Ball ball
/ /_/ / /|  / 
\____/_/ |_/ Source: link]]


local lpos = vec(0,0,0)
local pos = vec(0,0,0)
local vel = vec(0,0,0)
local isUnderwater = false

--- PROPERTIES
local RADIUS = 0.13
local BOUNCINESS = 0.3
local FRICTION = 0.9
local GRAVITY = vec(0,-0.02,0)

--- AUTO GENERATED
local CHECK_RADIUS = math.ceil(RADIUS)
local MARGIN = 0.01
--- Model
local MODEL_BALL = models.ball
MODEL_BALL:setParentType("WORLD")
MODEL_BALL:scale(RADIUS)

local TEXTURE_SHADOW = textures["textures.shadow"]
local SHADOW_RES = TEXTURE_SHADOW:getDimensions()
local MODEL_SHADOW = models:newPart("shadow","WORLD")
MODEL_SHADOW:newSprite("board"):setRenderType("BLURRY")
:texture(TEXTURE_SHADOW,SHADOW_RES:unpack()):rot(90,0,0):pos(RADIUS*16,0.5,RADIUS*16):scale((SHADOW_RES.x/16)*RADIUS*2,(SHADOW_RES.x/16)*RADIUS*2,0)
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
	pos = player:getPos():add(2,1,0)
end)



events.TICK:register(function ()
	lpos = pos
	pos = pos + vel
	vel = vel + GRAVITY
	
	local i = 1
	local blocks = {}
	for z = -CHECK_RADIUS, CHECK_RADIUS do
		for y = -CHECK_RADIUS, CHECK_RADIUS do
			for x = -CHECK_RADIUS, CHECK_RADIUS do
				local offset = vec(x,y,z)
				local bpos = pos:floor() + offset
				local block = world.getBlockState(bpos)
				if block:hasCollision() then
					for key, value in pairs(block:getCollisionShape()) do
						blocks[i] = {value[1] + bpos - RADIUS, value[2] + bpos + RADIUS}
						i = i + 1
					end
				end
			end
		end
	end
	local _, hit,face = raycast:aabb(lpos, pos+vel, blocks)
	if face then
		local norm = side2dir[face]
		local flat = (vel - norm * vel:dot(norm))
		local absorbed = (flat - vel)
		local bounces = absorbed:length()*10 > BOUNCINESS
		vel = flat * FRICTION + absorbed * (bounces and (BOUNCINESS) or 0)
		pos = hit + MARGIN * norm
		if bounces then
			local block = world.getBlockState(hit-norm*(RADIUS+MARGIN))
			local bsounds = block:getSounds()
			if bsounds.hit then
				sounds[bsounds["step"]]:pitch(2):pos(hit):play()
			end
		end
	end
	--local block = world.getBlockState(pos)
	--if #block:getFluidTags() > 0 then
	--	vel = vel * (1 + 1 / vel:length())
	--end
	
	-- shadow
	local sto = lpos + vec(0,-5,0)
	local _,shit = raycast:block(lpos,sto)
	if (sto - shit):lengthSquared() ~= 0 then
		MODEL_SHADOW:setPos(shit*16):setVisible(true)
	else
		MODEL_SHADOW:setVisible(true)
	end
end)

MODEL_BALL.postRender = function (delta, context, part)
	MODEL_BALL:setPos(math.lerp(lpos, pos, delta) * 16)
end
