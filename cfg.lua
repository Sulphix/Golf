--- PROPERTIES
local cfg = {
RADIUS = 0.13,
BOUNCINESS = 0.3,
FRICTION = 0.9,
GRAVITY = vec(0,-0.02,0),
MARGIN = 0.01, -- best untouched
--- Model
MODEL_BALL = models.ball,
}


-- AUTO GENERATED
cfg.CHECK_RADIUS = math.ceil(cfg.RADIUS)
cfg.MODEL_BALL:setParentType("WORLD")
:scale(cfg.RADIUS)

return cfg