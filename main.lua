local bit32 = require "engine.bit32"
require "engine.vec"
require "engine.print"
require "engine.animated_sprite"

local physics_engine = require "engine.physics_engine"

math.sign = function(number)
    return number > 0 and 1 or (number == 0 and 0 or -1)
end

math.lerp = function(a, b, t)
	return (b * t) + (a * (1.0 - t))
end

local player_force    = vec2(0,0)
local player_position = vec2(0,0)
local camera_position = vec2(0,0)
local cayote_time     = 0 -- 0 if in air, grounded otherwise
local jumping         = false
local player_direction = 1
local player_was_moving = false

G_TILE_SIZE  = 60
G_SHOW_DEBUG = false

local map_layers = {}

local function add_map_layer(_texture_path, _data)
	local tex = nil
	if _texture_path then 
		tex = love.graphics.newImage(_texture_path)
		tex:setFilter("nearest", "nearest", 0)
	end

	table.insert(map_layers, {image=tex, data=_data})
end

-- collision layer
add_map_layer(nil, {
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0, 1, 1 },
	{ 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
	{ 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
	{ 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1 },
	{ 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
	{ 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1 },
	{ 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1 },
	{ 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1 },
	{ 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }
})


add_map_layer("data/tileset_dirt.png", {
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0, 1, 1 },
	{ 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
	{ 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
	{ 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1 },
	{ 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
	{ 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1 },
	{ 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1 },
	{ 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1 },
	{ 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }
})

add_map_layer("data/tileset_grass.png", {
	{ 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 },
	{ 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 0, 0, 0, 1, 1 },
	{ 0, 1, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 1 },
	{ 0, 1, 1, 0, 0, 1, 1, 0, 0, 0, 1, 0, 0, 0, 1 },
	{ 0, 1, 0, 1, 1, 1, 1, 0, 0, 0, 0, 1, 0, 0, 1 },
	{ 0, 1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1 },
	{ 0, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1 },
	{ 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1 },
	{ 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 1, 1 },
	{ 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1 }
})

local function packUnorm4x8(_a, _b, _c, _d)
	return bit32.bor(_a, bit32.lshift(_b, 8), bit32.lshift(_c, 16), bit32.lshift(_d, 24))
end

local tileset_bitmask = {
	[packUnorm4x8(0,0,1,0)] = vec2(0, 0),
	[packUnorm4x8(0,1,0,1)] = vec2(1, 0),
	[packUnorm4x8(1,0,1,1)] = vec2(2, 0),
	[packUnorm4x8(0,0,1,1)] = vec2(3, 0),
	
	[packUnorm4x8(1,0,0,1)] = vec2(0, 1),
	[packUnorm4x8(0,1,1,1)] = vec2(1, 1),
	[packUnorm4x8(1,1,1,1)] = vec2(2, 1),
	[packUnorm4x8(1,1,1,0)] = vec2(3, 1),

	[packUnorm4x8(0,1,0,0)] = vec2(0, 2),
	[packUnorm4x8(1,1,0,0)] = vec2(1, 2),
	[packUnorm4x8(1,1,0,1)] = vec2(2, 2),
	[packUnorm4x8(1,0,1,0)] = vec2(3, 2),

	[packUnorm4x8(0,0,0,0)] = vec2(0, 3),
	[packUnorm4x8(0,0,0,1)] = vec2(1, 3),
	[packUnorm4x8(0,1,1,0)] = vec2(2, 3),
	[packUnorm4x8(1,0,0,0)] = vec2(3, 3),
}

local tileset_quads = {}
local function setup_tileset_quads(_tiles_x, _tiles_y, _image)
	local width  = _image:getWidth()  / _tiles_x
	local height = _image:getHeight() / _tiles_y
	for y = 1, _tiles_y do
		tileset_quads[y-1] = {}
		for x = 1, _tiles_x do
			tileset_quads[y-1][x-1] = love.graphics.newQuad((x-1) * width, (y-1) * height, width, height, _image)
		end
	end
end

setup_tileset_quads(4, 4, map_layers[2].image)

local function fetch_tile_bit(_data, _x, _y)
	return (_data[_y] and _data[_y][_x]) or 0
end

local function for_2d(_count_x, _count_y, _func)
	for y = 1, _count_x do
		for x = 1, _count_y do
			_func(x, y)
		end
	end
end

function love.load()
	love.graphics.setLineStyle("rough") 
	love.graphics.setLineWidth(1) 
end

math.clamp = function(number, min, max)
	return math.min(max, math.max(min, number))
end

local player_physics_entity = {
	_cur_pos = vec2(8.5,8),
	_old_pos = vec2(0,0),
	
	position = vec2(0,0),
	velocity = vec2(0,0),

	collider_bounds = vec2(0.25, 0.4),
	intersections = {}

}

function player_physics_entity:get_position(_alpha)
	return math.lerp(self._old_pos, self._cur_pos, _alpha)
end

local function aabb(_pos, _width, _height)
	return {
		min = vec(_pos),
		max = _pos + vec2(_width, _height)
	}
end

local function sweep_aabb(_aabb, _sweep)
	return {
		min = vec2(
			math.min(_aabb.min.X, _aabb.min.X + _sweep.X),
			math.min(_aabb.min.Y, _aabb.min.Y + _sweep.Y)
		),
		max = vec2(
			math.max(_aabb.max.X, _aabb.max.X + _sweep.X),
			math.max(_aabb.max.Y, _aabb.max.Y + _sweep.Y)
		)
	}
end

local function aabb_intersects_aabb(a, b) 
	return (a.min.X < b.max.X and a.max.X > b.min.X) and
		   (a.min.Y < b.max.Y and a.max.Y > b.min.Y)
end

function player_physics_entity:get_aabb()
	return aabb(
		self._cur_pos - self.collider_bounds, 
		self.collider_bounds.X * 2, self.collider_bounds.Y * 2
	)
end

function player_physics_entity:get_interpolated_aabb(_alpha)
	
	return aabb(
		self:get_position(_alpha) - self.collider_bounds, 
		self.collider_bounds.X * 2, self.collider_bounds.Y * 2
	)
end

function player_physics_entity:entity_physics_x_pos(_x_delta)
	local sweep = sweep_aabb(self:get_aabb(), vec2(_x_delta,0))
	self._cur_pos.X = self._cur_pos.X + _x_delta

	for tile_y = math.floor(sweep.min.Y), math.floor(sweep.max.Y) do
		for tile_x = math.floor(sweep.min.X), math.floor(sweep.max.X) do
			if fetch_tile_bit(map_layers[1].data, tile_x, tile_y) == 1 then
				local tile_aabb = aabb(vec2(tile_x, tile_y), 1, 1)
				local intersected = aabb_intersects_aabb(sweep, tile_aabb)
				
				if intersected then
					if _x_delta > 0 then
						local new_x = math.min(sweep.max.X, tile_aabb.min.X)
						self._cur_pos.X = new_x - self.collider_bounds.X
						self.velocity.X = 0
					elseif _x_delta < 0 then
						local new_x = math.max(sweep.min.X, tile_aabb.max.X)
						self._cur_pos.X = new_x + self.collider_bounds.X
						self.velocity.X = 0
					end

					table.insert(self.intersections, tile_aabb)
				end
			end
		end
	end
end

function player_physics_entity:entity_physics_y_pos(_y_delta)
	local sweep = sweep_aabb(self:get_aabb(), vec2(0, _y_delta))
	self._cur_pos.Y = self._cur_pos.Y + _y_delta
	
	for tile_y = math.floor(sweep.min.Y), math.floor(sweep.max.Y) do
		for tile_x = math.floor(sweep.min.X), math.floor(sweep.max.X) do
			if fetch_tile_bit(map_layers[1].data, tile_x, tile_y) == 1 then
				local tile_aabb = aabb(vec2(tile_x, tile_y), 1, 1)
				local intersected = aabb_intersects_aabb(sweep, tile_aabb)
				
				if intersected then
					if _y_delta >= 0 then
						local new_y = math.min(sweep.max.Y, tile_aabb.min.Y)
						self._cur_pos.Y = new_y - self.collider_bounds.Y
						cayote_time = 0.2
						self.velocity.Y = 0
					elseif _y_delta < 0 then
						local new_y = math.max(sweep.min.Y, tile_aabb.max.Y)
						self._cur_pos.Y = new_y + self.collider_bounds.Y
						self.velocity.Y = 0
					end
					
					table.insert(self.intersections, tile_aabb)
				end
			end
		end
	end
end

function player_physics_entity:entity_physics_tick()
	self.intersections = {}

	local force = vec2(
		player_force.X * 1,
		player_force.Y + 2 - (jumping and 55 or 0) 
	)

	jumping = false
	
	-- update
	self.velocity = self.velocity + force
	
	-- x damping
	if force.X == 0 then
		self.velocity.X = self.velocity.X - math.sign(self.velocity.X)
	end

	-- clamping
	self.velocity.X = math.clamp(self.velocity.X, -20, 20)
	self.velocity.Y = math.clamp(self.velocity.Y, -50000, 130)

	self._old_pos = vec(self._cur_pos)

	-- update Y position
	local y_delta = self.velocity.Y * 0.003
	self:entity_physics_y_pos(y_delta)

	-- update X position
	local x_delta = self.velocity.X * 0.003
	self:entity_physics_x_pos(x_delta)
end

local function physics_update(_dt)
	_clear_print_stack()
	player_physics_entity:entity_physics_tick()
end


local anim = create_animated_sprite(
	"data/leem.png", 
	{
		{name = "idle", anim_y = 0, anim_start = 0, anim_end = 6},
		
		{name = "sit_start", anim_y = 1, anim_start = 0, anim_end = 6},
		{name = "sit_stop",  anim_y = 1, anim_start = 6, anim_end = 0},

		{name = "spawn", anim_y = 2, anim_start = 0, anim_end = 15},
		
		{name = "hang", anim_y = 3, anim_start = 0, anim_end = 5},
		
		{name = "jump_start", anim_y = 4, anim_start = 0, anim_end = 2},
		{name = "fall",       anim_y = 4, anim_start = 2, anim_end = 2},
		
		{name = "walk", anim_y = 5, anim_start = 0, anim_end = 7}
	}
)

anim:set_animation("idle")

function love.update(_dt)
	local is_moving = player_force.X ~= 0
	
	if is_moving ~= player_was_moving then
		if not player_was_moving then
			anim:set_animation("walk")
		else
			anim:set_animation("idle")
		end
	end

	player_was_moving = is_moving

	anim:update(_dt)

	physics_engine:update(_dt)
	physics_engine:tick(physics_update)
	local alpha = physics_engine:get_alpha()

	cayote_time = math.max(0, cayote_time - _dt)
	
	player_position = player_physics_entity:get_position(alpha)
	camera_position = vec2(player_position.X - 9, player_position.Y - 6)
end

function love.keypressed(key, scancode, isrepeat)
	if scancode == "space" and cayote_time > 0 then
		jumping = true
		cayote_time = 0
	end

	if scancode == "a" then
		player_force.X = player_force.X - 1
		player_direction = 1
	elseif scancode == "d" then
		player_force.X = player_force.X + 1
		player_direction = -1
	end
end

function love.keyreleased(key, scancode, isrepeat)
	if scancode == "a" then
		player_force.X = player_force.X + 1
	elseif scancode == "d" then
		player_force.X = player_force.X - 1
	end
end

local function pos_world_to_screen(_vec)
	return vec2(
		(_vec.X - 1.0 - camera_position.X) * G_TILE_SIZE, 
		(_vec.Y - 1.0 - camera_position.Y) * G_TILE_SIZE
	)
end

function love.draw()
	love.graphics.clear()

	love.graphics.setColor(1,1,1,1)
	--love.graphics.draw(tex_grid_16)

	for_2d(10,15,function(_x, _y)
		local draw_pos = pos_world_to_screen(vec2(_x, _y))

		if (_x+_y) % 2 == 0 then
			love.graphics.setColor(1,1,1,1)
			love.graphics.rectangle("fill", draw_pos.X, draw_pos.Y, G_TILE_SIZE, G_TILE_SIZE)
		end
	end)

	for i = 1, #map_layers do
		if map_layers[i].image then
			for_2d(#map_layers[i].data,#map_layers[i].data[1],function(_x, _y)
				local a = fetch_tile_bit(map_layers[i].data, _x,   _y  )
				local b = fetch_tile_bit(map_layers[i].data, _x+1, _y  )
				local c = fetch_tile_bit(map_layers[i].data, _x,   _y+1)
				local d = fetch_tile_bit(map_layers[i].data, _x+1, _y+1)
		
				local idx = packUnorm4x8(a, b, c, d)
				local v4 = tileset_bitmask[idx]
				local quad = tileset_quads[v4.Y][v4.X]
				
				local draw_pos = pos_world_to_screen(vec2(_x+0.5, _y+0.5))
		
				love.graphics.setColor(1,1,1,1)
				love.graphics.draw(map_layers[i].image, quad, draw_pos.X, draw_pos.Y)
			end)
		end
	end

	if cayote_time > 0 then
		love.graphics.setColor(1,0,1,1)
		love.graphics.rectangle("fill", 1, 1, G_TILE_SIZE, G_TILE_SIZE)
	end
	
	local function draw_aabb(_aabb)
		local pos  = pos_world_to_screen(_aabb.min) 
		local size = pos_world_to_screen(_aabb.max) - pos_world_to_screen(_aabb.min)
		love.graphics.rectangle(
			"line", 
			pos.X * GLOBAL_window_config.scale, 
			pos.Y * GLOBAL_window_config.scale, 
			size.X * GLOBAL_window_config.scale, 
			size.Y * GLOBAL_window_config.scale
		)
	end

	local player_pos_screen = pos_world_to_screen(player_physics_entity:get_position(physics_engine:get_alpha()) - vec2(0, 0.08))
	
	anim:draw(player_pos_screen.X, player_pos_screen.Y, player_direction, 1)

	if G_SHOW_DEBUG then
		love.graphics.setColor(1,0,0,1)
		draw_aabb(player_physics_entity:get_aabb())
		love.graphics.setColor(0,1,0,1)
		draw_aabb(player_physics_entity:get_interpolated_aabb(physics_engine:get_alpha()))
		
		love.graphics.setColor(1,0,0,1)
		for i = 1, #player_physics_entity.intersections do
			draw_aabb(player_physics_entity.intersections[i])
		end

		_display_print()
	end
	
end