local bit32 = require "engine.bit32"
require "engine.vec"
require "engine.print"

local physics_engine = require "engine.physics_engine"

math.sign = function(number)
    return number > 0 and 1 or (number == 0 and 0 or -1)
end

local render_canvas = love.graphics.newCanvas(GLOBAL_window_config.width, GLOBAL_window_config.height)
render_canvas:setFilter("nearest", "nearest", 0)

local tex_tileset_grass = love.graphics.newImage("data/tileset_grass.png")
local tex_tileset_dirt  = love.graphics.newImage("data/tileset_dirt.png")

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
	_cur_pos = vec2(4,0),
	_old_pos = vec2(0,0),
	
	position = vec2(0,0),
	velocity = vec2(0,0)
}

function player_physics_entity:get_position(_alpha)
	return math.lerp(self._cur_pos, self._old_pos, _alpha)
end

local function entity_physics_tick(_entity, _dt)
-- update
	_entity.velocity = _entity.velocity + player_move_wish * (50)
	if cayote_frames < 5 then
		_entity.velocity = _entity.velocity + vec2(0, 120 * _dt)
	end
	player_move_wish.Y = 0

	-- x damping
	_entity.velocity.X = _entity.velocity.X - math.sign(_entity.velocity.X)

	-- clamping
	_entity.velocity.X = math.clamp(_entity.velocity.X, -32, 32)
	_entity.velocity.Y = math.clamp(_entity.velocity.Y, -50, 1000 * _dt)

	_entity._old_pos = vec(_entity._cur_pos)

	local old_pos = vec2(_entity._cur_pos.X, _entity._cur_pos.Y)
	
	-- update Y position
	_entity._cur_pos.Y = _entity._cur_pos.Y + _entity.velocity.Y * _dt * 0.3

	if fetch_tile_bit(map, math.floor(old_pos.X), math.floor(_entity._cur_pos.Y)) ~= 0 then
		local delta = _entity.velocity.Y > 0 and math.ceil(old_pos.Y) or math.floor(old_pos.Y)
		delta = delta - _entity._cur_pos.Y

		_entity._cur_pos.Y = _entity._cur_pos.Y + delta + math.sign(delta) * _dt
		_entity.velocity.Y = 0

		if delta < 0 then
			cayote_frames = 2
		end
	else
		cayote_frames = math.max(0, cayote_frames - 1)
	end

	-- update X position
	_entity._cur_pos.X = _entity._cur_pos.X + _entity.velocity.X * _dt * 0.3

	if fetch_tile_bit(map, math.floor(_entity._cur_pos.X), math.floor(old_pos.Y)) ~= 0 then
		local delta = _entity.velocity.X > 0 and math.ceil(old_pos.X) or math.floor(old_pos.X)
		delta = delta - _entity._cur_pos.X

		_entity._cur_pos.X = _entity._cur_pos.X + delta + math.sign(delta) * _dt
		_entity.velocity.X = 0
	end
end

local function physics_update(_dt)
	entity_physics_tick(player_physics_entity, _dt)
end

math.lerp = function(a, b, t)
	return (a * t) + (b * ( 1.0 - t))
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
	local camera_offset = vec2(
		math.floor(camera_position.X * 16) / 16,
		math.floor(camera_position.Y * 16) / 16
	)
	
	return vec2(
		math.floor((_vec.X - 1.0 - camera_offset.X) * 16), 
		math.floor((_vec.Y - 1.0 - camera_offset.Y) * 16)
	)
end

function love.draw()
	love.graphics.setCanvas(render_canvas)
	love.graphics.clear()

	love.graphics.setColor(1,1,1,1)
	--love.graphics.draw(tex_grid_16)

	local tile_size = 16
	for_2d(10,15,function(_x, _y)
		
		local camera_offset = vec2(
			math.floor(camera_position.X * 16) / 16,
			math.floor(camera_position.Y * 16) / 16
		)
		
		local draw_pos = vec2(
			(_x - 1.0 - camera_offset.X) * tile_size, 
			(_y - 1.0 - camera_offset.Y) * tile_size
		)
		
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
		
		local camera_offset = vec2(
			math.floor(camera_position.X * 16) / 16,
			math.floor(camera_position.Y * 16) / 16
		)

		local draw_pos = vec2(
			(_x - 0.5 - camera_offset.X) * tile_size, 
			(_y - 0.5 - camera_offset.Y) * tile_size
		)

		love.graphics.setColor(1,1,1,1)
		love.graphics.draw(tex_tileset_dirt,  quad, draw_pos.X, draw_pos.Y)
		love.graphics.draw(tex_tileset_grass, quad, draw_pos.X, draw_pos.Y)
	end)
	
	love.graphics.setColor(1,0,0,1)
	local player_rect_pos = pos_world_to_screen(player_position + vec2(-4/16,-4/16))
	local player_rect_size = pos_world_to_screen(player_position + vec2(4/16,4/16)) - player_rect_pos
	love.graphics.rectangle("line", player_rect_pos.X, player_rect_pos.Y, player_rect_size.X, player_rect_size.Y)

	if cayote_frames > 0 then
		love.graphics.setColor(1,0,1,1)
		love.graphics.rectangle("fill", 1, 1, 16, 16)
	end


	love.graphics.setCanvas()
	
	love.graphics.setColor(1,1,1,1)
	love.graphics.draw(render_canvas, 0, 0, 0, GLOBAL_window_config.scale, GLOBAL_window_config.scale)
	
	
	_display_print()
end