local ui = {}

function ui.drawText(gpu, x, y, str, width)
	str = tostring(str)
	if width then
		str = string.sub(str, 1, width)
		str = str .. string.rep(" ", width - string.len(str))
	end
	gpu.set(x, y, str)
end

function ui.drawLog(gpu, x1, y1, x2, y2, logString)
	local lines = {}
	for line in logString:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	for i=1, #lines do
		ui.drawText(gpu, x1, y1 + #lines - i, lines[#lines+1 - i], x2-x1+1)
	end
end

function ui.drawBox(gpu, x1, y1, x2, y2, title)
	gpu.fill(x1, y1, x2-x1, y2-y1, " ")
	gpu.fill(x1, y1, x2-x1, 1, "─")
	gpu.fill(x1, y1, 1, y2-y1, "│")
	gpu.fill(x1, y2, x2-x1, 1, "─")
	gpu.fill(x2, y1, 1, y2-y1, "│")
	gpu.fill(x1, y1, 1, 1, "┌")
	gpu.fill(x2, y1, 1, 1, "┐")
	gpu.fill(x1, y2, 1, 1, "└")
	gpu.fill(x2, y2, 1, 1, "┘")
	if title then
		gpu.set(x1+1, y1, " " .. title .. " ")
	end
end

function ui.inArea(x, y, x1, y1, x2, y2)
	if x >= x1 and x <= x2 and y >= y1 and y <= y2 then
		return true
	end
end

return ui
