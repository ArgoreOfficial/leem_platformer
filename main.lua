local bit32 = require "engine.bit32"
require "engine.vec"
require "engine.print"

local physics_engine = require "engine.physics_engine"

math.sign = function(number)
    return number > 0 and 1 or (number == 0 and 0 or -1)
end

math.lerp = function(a, b, t)
	return (b * t) + (a * ( 1.0 - t))
end

local render_canvas = love.graphics.newCanvas(GLOBAL_window_config.width, GLOBAL_window_config.height)
render_canvas:setFilter("nearest", "nearest", 0)

local tex_tileset_grass = love.graphics.newImage("data/tileset_grass.png")
tex_tileset_grass:setFilter("nearest", "nearest", 0)

local tex_tileset_dirt  = love.graphics.newImage("data/tileset_dirt.png")
tex_tileset_dirt:setFilter("nearest", "nearest", 0)

local player_move_wish = vec2(0,0)
local player_position  = vec2(0,0)
local camera_position  = vec2(0,0)
local cayote_frames    = 0 -- 0 if in air, grounded otherwise

local map = {
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
}

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

setup_tileset_quads(4, 4, tex_tileset_grass)

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
	render_canvas:setFilter("nearest","nearest")
end

math.clamp = function(number, min, max)
	return math.min(max, math.max(min, number))
end

local player_physics_entity = {
	_cur_pos = vec2(8.5,8),
	_old_pos = vec2(0,0),
	
	position = vec2(0,0),
	velocity = vec2(0,0),

	collider_bounds = vec2(4/16, 4/16),
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
			if fetch_tile_bit(map, tile_x, tile_y) == 1 then
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
			if fetch_tile_bit(map, tile_x, tile_y) == 1 then
				local tile_aabb = aabb(vec2(tile_x, tile_y), 1, 1)
				local intersected = aabb_intersects_aabb(sweep, tile_aabb)
				
				if intersected then
					if _y_delta >= 0 then
						local new_y = math.min(sweep.max.Y, tile_aabb.min.Y)
						self._cur_pos.Y = new_y - self.collider_bounds.Y
						cayote_frames = 10
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

function player_physics_entity:entity_physics_tick(_dt)
	self.intersections = {}

	-- update
	self.velocity = self.velocity + player_move_wish * 120 * _dt
	self.velocity = self.velocity + vec2(0, 120 * _dt)
	
	player_move_wish.Y = 0

	-- x damping
	self.velocity.X = self.velocity.X - math.sign(self.velocity.X)

	-- clamping
	self.velocity.X = math.clamp(self.velocity.X, -10, 10)
	self.velocity.Y = math.clamp(self.velocity.Y, -50, 1000 * _dt)

	self._old_pos = vec(self._cur_pos)

	-- update Y position
	local y_delta = self.velocity.Y * _dt * 0.3
	self:entity_physics_y_pos(y_delta)

	-- update X position
	local x_delta = self.velocity.X * _dt * 0.3
	self:entity_physics_x_pos(x_delta)
	cayote_frames = math.max(0, cayote_frames - 1)
end

local function physics_update(_dt)
	player_physics_entity:entity_physics_tick(_dt)
end

function love.update(_dt)
	physics_engine:update(_dt)
	physics_engine:tick(physics_update)
	local alpha = physics_engine:get_alpha()

	player_position = player_physics_entity:get_position(alpha)
	camera_position = vec2(player_position.X - 9, player_position.Y - 6)
end

function love.keypressed(key, scancode, isrepeat)
	if scancode == "space" and cayote_frames > 0 then
		player_move_wish.Y = player_move_wish.Y - 8
		cayote_frames = 0
	end

	if scancode == "a" then
		player_move_wish.X = player_move_wish.X - 1
	elseif scancode == "d" then
		player_move_wish.X = player_move_wish.X + 1
	end
end

function love.keyreleased(key, scancode, isrepeat)
	if scancode == "a" then
		player_move_wish.X = player_move_wish.X + 1
	elseif scancode == "d" then
		player_move_wish.X = player_move_wish.X - 1
	end
end

local function pos_world_to_screen(_vec)
	return vec2(
		(_vec.X - 1.0 - camera_position.X) * 16, 
		(_vec.Y - 1.0 - camera_position.Y) * 16
	)
end

function love.draw()
	love.graphics.setCanvas(render_canvas)
	love.graphics.clear()

	love.graphics.setColor(1,1,1,1)
	--love.graphics.draw(tex_grid_16)

	local tile_size = 16
	for_2d(10,15,function(_x, _y)
		local draw_pos = pos_world_to_screen(vec2(_x, _y))

		if (_x+_y) % 2 == 0 then
			love.graphics.setColor(1,1,1,1)
			love.graphics.rectangle("fill", draw_pos.X, draw_pos.Y, tile_size, tile_size)
		end
	end)

	for_2d(#map,#map[1],function(_x, _y)
		local a = fetch_tile_bit(map, _x,   _y  )
		local b = fetch_tile_bit(map, _x+1, _y  )
		local c = fetch_tile_bit(map, _x,   _y+1)
		local d = fetch_tile_bit(map, _x+1, _y+1)

		local idx = packUnorm4x8(a, b, c, d)
		local v4 = tileset_bitmask[idx]
		local quad = tileset_quads[v4.Y][v4.X]
		
		local draw_pos = pos_world_to_screen(vec2(_x+0.5, _y+0.5))

		love.graphics.setColor(1,1,1,1)
		love.graphics.draw(tex_tileset_dirt,  quad, draw_pos.X, draw_pos.Y)
		love.graphics.draw(tex_tileset_grass, quad, draw_pos.X, draw_pos.Y)
	end)
	
	if cayote_frames > 0 then
		love.graphics.setColor(1,0,1,1)
		love.graphics.rectangle("fill", 1, 1, 16, 16)
	end

	local function draw_aabb_world(_aabb)
		local pos  = pos_world_to_screen(_aabb.min) 
		local size = pos_world_to_screen(_aabb.max) - pos_world_to_screen(_aabb.min)
		love.graphics.rectangle("line", pos.X, pos.Y, size.X, size.Y)
	end
	
	local function draw_aabb(_aabb)
		local pos  = pos_world_to_screen(_aabb.min) 
		local size = pos_world_to_screen(_aabb.max) - pos_world_to_screen(_aabb.min)
		love.graphics.rectangle("line", pos.X * 4, pos.Y * 4, size.X * 4, size.Y * 4)
	end

	love.graphics.setCanvas()
	love.graphics.setColor(1,1,1,1)
	love.graphics.draw(render_canvas, 0, 0, 0, GLOBAL_window_config.scale, GLOBAL_window_config.scale)
	
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