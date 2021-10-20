local COLORS = {
	['red'] = 'AA0000',
	['green'] = '00AA00',
	['blue'] = '0000AA'
}

local default_properties = {
	['rvisible'] = false,
	['rcolor'] = 0xFFFFFF,
	['ropacity'] = 0xFF,
	['rfont'] = 'Arial',
	['rsize'] = 8,
	['rtext'] = '',
	['rpos'] = { x = 0, y = 0 },
	['rflags'] = 0,
	['ondragprocess'] = function () end
}

local renders = {}

local render_draggable = nil
local drag_offsets = {0, 0}

function create()
	while not isOpcodesAvailable() do wait(100) end
	local render = {}
	table.insert(renders, render)
	for k, v in pairs(default_properties) do
		render[k] = v
	end
	render.show = function ()
		render.rvisible = true
		return render
	end
	render.hide = function ()
		render.rvisible = false
		return render
	end
	render.toggle = function ()
		render.rvisible = not render.rvisible
		return render
	end
	render.text = function (rtext)
		render.rtext = rtext
		return render
	end
	render.font = function (rfont)
		render.dxfont = nil
		render.rfont = rfont
		return render
	end
	render.size = function (rsize)
		render.dxfont = nil
		render.rsize = tonumber(rsize)
		return render
	end
	render.pos = function (rpos)
		local rx, ry = getScreenResolution()
		if rpos.x < 0 then rpos.x = rx + rpos.x end
		if rpos.y < 0 then rpos.y = ry + rpos.y end
		render.rpos = rpos
		return render
	end
	render.color = function (rcolor)
		if COLORS[rcolor] then rcolor = COLORS[rcolor] end
		if type(rcolor) == 'string' then rcolor = tonumber(rcolor, 16) end
		render.rcolor = rcolor
		return render
	end
	render.opacity = function (ropacity)
		render.ropacity = math.ceil(tonumber(ropacity) * 2.55)
		return render
	end
	render.flags = function (rflags)
		if type(rflags) == 'number' then
			render.rflags = rflags
			return
		end
		local font_flags = {
			NONE      = 0x0,
			BOLD      = 0x1,
			ITALICS   = 0x2,
			BORDER    = 0x4,
			SHADOW    = 0x8,
			UNDERLINE = 0x10,
			STRIKEOUT = 0x20
		}
		local flag_value = 0
		for flag in string.gmatch(rflags:upper(), '%S+') do
			if font_flags[flag] then flag_value = flag_value + font_flags[flag] end
		end
		render.rflags = flag_value
		return render
	end
	render.fadeto = function (value, duration, callback)
		local from = render.ropacity / 2.55
		local start = os.clock()
		lua_thread.create(function ()
			while true do
				wait(1)
				local m = (os.clock() - start) / duration
				if m < 1 then
					render.opacity(from + (value - from) * m)
				else
					render.opacity(value)
					if callback then callback() end
					break
				end
			end
		end)
		return render
	end
	render.fadein = function (duration)
		render.opacity(0)
		render.show()
		render.fadeto(100, duration)
		return render
	end
	render.fadeout = function (duration)
		render.fadeto(0, duration, function () render.hide() end)
		return render
	end
	render.fadetoggle = function (duration)
		if render.rvisible then render.fadeout(duration) else render.fadein(duration) end
		return render
	end
	render.slide = function (axis, value, duration)
		axis = axis:lower()
		local from = render.rpos[axis]
		local start = os.clock()
		lua_thread.create(function ()
			while true do
				wait(1)
				local m = (os.clock() - start) / duration
				if m < 1 then
					render.rpos[axis] = from + (value - from) * m
				else
					render.rpos[axis] = value
					break
				end
			end
		end)
		return render
	end
	render.blink = function (interval, times)
		times = times * 2
		lua_thread.create(function ()
			while times > 0 do
				wait(interval * 1000)
				render.toggle()
				times = times - 1
			end
		end)
	end
	render.dragstart = function ()
		render.rdraggable = true
	end
	render.dragstop = function ()
		render.rdraggable = false
	end
	return render
end

function getRenderRect(render)
	if not render.dxfont then render.dxfont = renderCreateFont(render.rfont, render.rsize, render.rflags) end
	local top = render.rpos.y - 10
	local left = render.rpos.x - 10
	local width = 0
	local height = 0
	for line in render.rtext:gmatch('[^\n]+') do
		local line_width = renderGetFontDrawTextLength(render.dxfont, line)
		if line_width > width then width = line_width end
		if height > 0 then
			height = height + renderGetFontDrawHeight(render.dxfont, line) * 1.25
		else
			height = 0.001 -- костыль для пропуска первой строчки при подсчете общей высоты
		end
	end
	return {
		['top'] = top,
		['left'] = left,
		['right'] = left + width + 20,
		['bottom'] = top + height + 20
	}
end

lua_thread.create(function ()
	while true do
		wait(1)
		for k, v in pairs(renders) do
			if v.rvisible then process(v) end
		end
		if wasKeyPressed(0x1) then
			for k, v in pairs(renders) do
				if v.rdraggable then
					local rect = getRenderRect(v)
					local mx, my = getCursorPos()
					if mx > rect.left and mx < rect.right and my > rect.top and my < rect.bottom then
						render_draggable = v
						drag_offsets = { mx - v.rpos.x, my - v.rpos.y }
					end
				end
			end
		end
		if wasKeyReleased(0x1) then render_draggable = nil end
		if render_draggable then
			local mx, my = getCursorPos()
			render_draggable.pos({ x = mx - drag_offsets[1], y = my - drag_offsets[2] })
			render_draggable.ondragprocess()
		end
	end
end)

function process(render)
	if not render.dxfont then render.dxfont = renderCreateFont(render.rfont, render.rsize, render.rflags) end
	local color = bit.bor(render.rcolor, bit.lshift(render.ropacity, 24))
	local offset = 0
	for line in render.rtext:gmatch('[^\n]+') do
		renderFontDrawText(render.dxfont, line, render.rpos.x, render.rpos.y + math.ceil(offset * 1.5), color)
		offset = offset + render.rsize
	end
end

return { ['create'] = create }