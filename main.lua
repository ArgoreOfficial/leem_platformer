local bit32 = require "engine.bit32"
require "engine.vec"

local render_canvas = love.graphics.newCanvas(GLOBAL_window_config.width, GLOBAL_window_config.height)
render_canvas:setFilter("nearest", "nearest", 0)

local tex_tileset_grass = love.graphics.newImage("data/tileset_grass.png")
local tex_tileset_dirt  = love.graphics.newImage("data/tileset_dirt.png")

function love.load()
	love.graphics.setLineStyle("rough") 
	love.graphics.setLineWidth(1) 
end

function love.update(_dt)
	
end

function love.keypressed(key, scancode, isrepeat)
	
end

function love.keyreleased(key, scancode, isrepeat)
	
end

local map = {
	{ 0, 0, 0, 0, 0, 0, 0, 0, },
	{ 0, 0, 0, 0, 0, 1, 1, 0, },
	{ 0, 1, 1, 0, 0, 1, 0, 0, },
	{ 0, 1, 1, 0, 0, 1, 1, 0, },
	{ 0, 0, 0, 1, 1, 1, 1, 0, },
	{ 0, 0, 0, 1, 1, 0, 0, 0, },
	{ 0, 0, 1, 1, 1, 0, 0, 0, },
	{ 0, 0, 0, 0, 0, 0, 0, 0, },
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

local function draw_tile_rect(_mode, _x, _y, _size)
	local offset = _mode == "line" and 1 or 0

	love.graphics.rectangle(
		_mode, 
		(_x-1) * _size + offset, 
		(_y-1) * _size + offset, 
		_size - offset, _size - offset)
end

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

function love.draw()
	love.graphics.setCanvas(render_canvas)
	
	love.graphics.setColor(1,1,1,1)
	--love.graphics.draw(tex_grid_16)

	local tile_size = 16
	for_2d(10,15,function(_x, _y)
		local draw_pos = vec2((_x - 1.0) * tile_size, (_y-1.0) * tile_size)
		
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
		
		local draw_pos = vec2((_x - 0.5) * tile_size, (_y-0.5) * tile_size)

		love.graphics.setColor(1,1,1,1)
		love.graphics.draw(tex_tileset_dirt,  quad, draw_pos.X, draw_pos.Y)
		love.graphics.draw(tex_tileset_grass, quad, draw_pos.X, draw_pos.Y)
	end)
	
	love.graphics.setCanvas()
	
	love.graphics.setColor(1,1,1,1)
	love.graphics.draw(render_canvas, 0, 0, 0, GLOBAL_window_config.scale, GLOBAL_window_config.scale)
	
end