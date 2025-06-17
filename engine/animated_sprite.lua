local methods = {}
local meta = {__index = methods}

function _G.create_animated_sprite(_image_path, _animations)
	local image = love.graphics.newImage(_image_path)
	image:setFilter("nearest", "nearest", 0)

	local self = setmetatable({ 
		image = image, 
		current_animation = "",
		current_animation_time = 0,
		animation_framerate = 1 / 8,
		animation_quads = {}
	}, meta)

	for i = 1, #_animations do
		local name       = _animations[i].name
		local anim_y     = _animations[i].anim_y
		local anim_start = _animations[i].anim_start
		local anim_end   = _animations[i].anim_end
		local delta = math.sign(anim_end - anim_start)
		if delta == 0 then delta = 1 end
		
		self.animation_quads[name] = {}
		for frame = anim_start, anim_end, delta do
			table.insert(self.animation_quads[name], love.graphics.newQuad(frame * 60, anim_y * 60, 60, 60, image))
		end
	end

	return self
end

function methods:set_animation(_name)
	self.current_animation = _name
	self.current_animation_time = 0
end

function methods:update(_dt)
	self.current_animation_time = self.current_animation_time + _dt
end

function methods:draw(_x, _y, _sx, _sy)
	love.graphics.setColor(1,1,1,1)
	if not self.animation_quads[self.current_animation] then 
		return 
	end

	local frame = math.floor((self.current_animation_time / self.animation_framerate) % (#self.animation_quads[self.current_animation]))
	local quad  = self.animation_quads[self.current_animation][frame + 1]

	love.graphics.draw(self.image, quad, _x, _y, 0, -_sx, _sy, 30, 30)
end