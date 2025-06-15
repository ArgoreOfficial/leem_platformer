local physics_engine = {}
physics_engine.time_step = 1 / 30

local accumulator = 0

function physics_engine:update(_delta_time)
	if _delta_time > 0.25 then
		_delta_time = 0.25
	end
    
    accumulator = accumulator + _delta_time
end

function physics_engine:tick(_callback, _time_step)
	_time_step = _time_step or physics_engine.time_step
	while accumulator >= _time_step do
		_callback(_time_step);
		accumulator = accumulator - _time_step;
	end
end

function physics_engine:get_alpha()
	return math.min(accumulator / physics_engine.time_step)
end


return physics_engine