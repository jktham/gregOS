local component = require("component")
local term = require("term")
local computer = require("computer")
local os = require("os")
local event = require("event")
local ui = require("ui")
local internet = require("internet")
local serialization = require("serialization")
local io = require("io")
local json = require("json")

local screen = component.proxy("dd730618-01f8-477e-a9a3-d02667fd2b8e") -- remote terminal
local gpu = component.proxy("ed18fff4-a38c-4b18-80aa-1f011d5a973a")
local keyboard = component.proxy("542de9d9-5acc-4f23-8080-6f05c923c186")
local screen2 = component.proxy("f0662e28-efbb-4f02-9ce9-2b2b228ce573") -- large monitor
local gpu2 = component.proxy("0e73190d-b210-42b1-a7e0-30e1f6106300")
local keyboard2 = component.proxy("a1252adc-f949-4075-87d8-d1b3a7c30744")
local modem = component.modem
local serverAddress = "a7990fee-66f4-47f3-96ef-328659df71a8"
local glasses = component.glasses
local widget1 = {}

local w, h = 160, 50
local w2, h2 = 40, 9
local w3, h3 = 0, 0

local refreshInterval = 0.1
local shouldQuit = false
local shouldReboot = false
local autocraftingRequestInterval = 8
local generatorAutoRequestInterval = 1

local deltaTime = 0.0
local uptime = 0.0
local playtime = 0.0
local mctime = 0.0
local rltime = 0.0

local serverStatus = "offline"
local glassesStatus = "offline"

local firstDraw = true
local currentPage = 0
local buttons = {}

local lastLine = ""
local lastLineRepeat = 0
local logString = ""
local eventLogString = ""
local logUpdated = false
local eventLogUpdated = false
local logLength = 21
local eventLogLength = 14

local generatorAutoEnabled = true
local generatorEnableLevel = 0.8
local generatorDisableLevel = 0.9

local craftingRequests = {}

local lastGeneratorAutoRequest = 0
local lastAutocraftingRequest = 0
local cpuIdleTime = {}
local energyHistory = {}
for i=1,100 do
	energyHistory[i] = 0
end

local data = {}
data.version = 0
data.time = 0
data.energy = 0
data.energyMax = 0
data.energyLevel = 0
data.energyRate = 0
data.generatorSignal = 0
data.generatorFuel = 0
data.energyRateGenerator = 0
data.items = {}
data.itemsCount = 0
data.itemsTypeCount = 0
data.craftingCpus = {}
data.cpuStatus = {}
data.energyRateFrontend = 0
data.energyRateLogistics = 0
data.energyRateProcessing = 0
data.craftingStatus = {}
data.spotify = {}
local prevData = data

local function log(...)
	local args = table.pack(...)
	local newLine = ""
	local sep = ""
	for i = 1, args.n do
		newLine = newLine .. sep .. tostring(args[i])
	  sep = ", "
	end
	if newLine == lastLine then
		local lines = {}
		for line in logString:gmatch("[^\r\n]+") do
			table.insert(lines, line)
		end

		lastLineRepeat = lastLineRepeat + 1
		lines[#lines] = lastLine .. " (" .. lastLineRepeat+1 .. ")"

		logString = ""
		for _, line in ipairs(lines) do
			logString = logString .. line .. "\n"
		end
	else
		lastLineRepeat = 0
		lastLine = newLine
		logString = logString .. newLine .. "\n"
	end

	local lines = {}
	for line in logString:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	logString = ""
	local i = 0
	for _, line in ipairs(lines) do
		i = i+1
		if i > #lines - logLength then
			logString = logString .. line .. "\n"
		end
	end

	logUpdated = true
end

local function eventLog(...)
	local args = table.pack(...)
	local sep = ""
	for i = 1, args.n do
		eventLogString = eventLogString .. sep .. tostring(args[i])
	  sep = ", "
	end
	eventLogString = eventLogString .. "\n"

	local lines = {}
	for line in eventLogString:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end
	eventLogString = ""
	local i = 0
	for _, line in ipairs(lines) do
		i = i+1
		if i > #lines - eventLogLength then
			eventLogString = eventLogString .. line .. "\n"
		end
	end

	eventLogUpdated = true
end

local function reboot()
	log("> rebooting")
	shouldQuit = true
	shouldReboot = true
end

local function quit()
	log("> quitting")
	shouldQuit = true
end

local function rebootServer()
	log("> broadcasting \"reboot\"")
	modem.send(serverAddress, 8000, "reboot")
	log("> broadcasting \"wake\"")
	modem.send(serverAddress, 8000, "wake")
end

local function toggleGenerator()
	if data.generatorSignal == 0 then
		log("> broadcasting proxy request \"generator.enable\"")
		modem.send(serverAddress, 8000, "proxy", "generator.enable")
	else
		log("> broadcasting proxy request \"generator.disable\"")
		modem.send(serverAddress, 8000, "proxy", "generator.disable")
	end
end

local function toggleGeneratorMode()
	if generatorAutoEnabled then
		log("> setting generator to manual")
		generatorAutoEnabled = false
	else
		log("> setting generator to auto")
		generatorAutoEnabled = true
	end
end

local function craft(requests)
	log("> sending crafting request")
	modem.send(serverAddress, 8000, "craft", serialization.serialize(requests))
end

local function loadPage(page)
	log("> loading page " .. page)
	firstDraw = true
	currentPage = page

	if currentPage == 1 then
		buttons = {}
		table.insert(buttons, {x1=9, y1=18, x2=18, y2=18, label="[R] reboot", shortcut="r", action=reboot, arg=nil, id="reboot"})
		table.insert(buttons, {x1=9, y1=19, x2=16, y2=19, label="[Q] quit", shortcut="q", action=quit, arg=nil, id="quit"})
		table.insert(buttons, {x1=9, y1=20, x2=25, y2=20, label="[F] reboot server", shortcut="f", action=rebootServer, arg=nil, id="rebootServer"})
		table.insert(buttons, {x1=9, y1=21, x2=24, y2=21, label="[1] admin client", shortcut="1", action=loadPage, arg=1, id="loadPage1"})
		table.insert(buttons, {x1=9, y1=22, x2=24, y2=22, label="[2] power client", shortcut="2", action=loadPage, arg=2, id="loadPage2"})
		table.insert(buttons, {x1=9, y1=23, x2=28, y2=23, label="[3] logistics client", shortcut="3", action=loadPage, arg=3, id="loadPage3"})
		table.insert(buttons, {x1=9, y1=25, x2=28, y2=25, label="[E] toggle generator", shortcut="e", action=toggleGenerator, arg=nil, id="toggleGenerator"})
		table.insert(buttons, {x1=9, y1=26, x2=33, y2=26, label="[G] toggle generator mode", shortcut="g", action=toggleGeneratorMode, arg=nil, id="toggleGeneratorMode"})

	elseif currentPage == 2 then
		buttons = {}
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="r", action=reboot, arg=nil, id="reboot"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="q", action=quit, arg=nil, id="quit"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="f", action=rebootServer, arg=nil, id="rebootServer"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="1", action=loadPage, arg=1, id="loadPage1"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="2", action=loadPage, arg=2, id="loadPage2"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="3", action=loadPage, arg=3, id="loadPage3"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="e", action=toggleGenerator, arg=nil, id="toggleGenerator"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="g", action=toggleGeneratorMode, arg=nil, id="toggleGeneratorMode"})

	elseif currentPage == 3 then
		buttons = {}
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="r", action=reboot, arg=nil, id="reboot"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="q", action=quit, arg=nil, id="quit"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="f", action=rebootServer, arg=nil, id="rebootServer"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="1", action=loadPage, arg=1, id="loadPage1"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="2", action=loadPage, arg=2, id="loadPage2"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="3", action=loadPage, arg=3, id="loadPage3"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="e", action=toggleGenerator, arg=nil, id="toggleGenerator"})
		table.insert(buttons, {x1=0, y1=0, x2=0, y2=0, label="", shortcut="g", action=toggleGeneratorMode, arg=nil, id="toggleGeneratorMode"})

		for i,r in ipairs(craftingRequests) do
			table.insert(buttons, {x1=137, y1=7+i, x2=137, y2=7+i, label="1", shortcut="", action=craft, arg={{name=r.name, amount=1}}, id="craft"})
			table.insert(buttons, {x1=142, y1=7+i, x2=142, y2=7+i, label="8", shortcut="", action=craft, arg={{name=r.name, amount=8}}, id="craft"})
			table.insert(buttons, {x1=147, y1=7+i, x2=148, y2=7+i, label="64", shortcut="", action=craft, arg={{name=r.name, amount=64}}, id="craft"})
		end
	end
end

local function keyDownHandler(id, address, char, code, player)
	eventLog(id, string.sub(address, 1, 4), char, code, player)
	for _, b in pairs(buttons) do
		if char == string.byte(b.shortcut) then
			b.action(b.arg)
		end
	end
end

local function touchHandler(id, address, x, y, button, player)
	eventLog(id, string.sub(address, 1, 4), x, y, button, player)
	for _, b in pairs(buttons) do
		if ui.inArea(x, y, b.x1, b.y1, b.x2, b.y2) and button == 0 then
			b.action(b.arg)
		end
	end
end

local function modemHandler(id, localAddress, remoteAddress, port, distance, name, message)
	eventLog(id, string.sub(localAddress, 1, 4), string.sub(remoteAddress, 1, 4), name, (function() if message then return string.sub(message, 1, 32) else return message end end)())
	if name == "reboot" then
		reboot()
	elseif name == "confirm_on" and remoteAddress == serverAddress then
		log("> server online")
		serverStatus = "online"
	elseif name == "confirm_off" and remoteAddress == serverAddress then
		log("> server offline")
		serverStatus = "offline"
	elseif name == "check" then
		log("> broadcasting \"confirm_on\"")
		modem.broadcast(8000, "confirm_on")
	elseif name == "data" then
		log("> received data")
		data = serialization.unserialize(message)
	end
end

local function glassesScreenSizeHandler(id, address, user, width, height, scale)
	eventLog(id, string.sub(address, 1, 4), user, width, height, scale)
	w3, h3 = width, height
end

local function getTime()
	log("> getting time")
	local handle = internet.request("https://www.timeapi.io/api/Time/current/zone?timeZone=Europe/Amsterdam")
	local response = ""
	for chunk in handle do
		response = response .. chunk
	end

	local t = json:decode(response)
	if t then
		rltime = os.time({year=t.year, month=t.month, day=t.day, hour=t.hour, min=t.minute, sec=t.second})
	end
end

local function init()
	log("> initializing")
	component.setPrimary("screen", screen.address)
	component.setPrimary("gpu", gpu.address)
	component.setPrimary("keyboard", keyboard.address)
	gpu.bind(screen.address)
	gpu2.bind(screen2.address)
	term.bind(gpu)

	modem.open(8000)
	modem.setWakeMessage("wake")
	log("> broadcasting \"confirm_on\"")
	modem.broadcast(8000, "confirm_on")
	log("> broadcasting \"check\"")
	modem.broadcast(8000, "check")

	event.listen("key_down", keyDownHandler)
	event.listen("touch", touchHandler)
	event.listen("modem_message", modemHandler)
	event.listen("glasses_screen_size", glassesScreenSizeHandler)

	gpu.setResolution(w, h)
	gpu2.setResolution(w2, h2)
	glasses.requestResolutionEvents()

	term.clear()
	gpu.fill(1, 1, w, h, " ")
	gpu2.fill(1, 1, w2, h2, " ")
	glasses.removeAll()

	loadPage(1)
	widget1 = glasses.addText2D()
	widget1.addTranslation(0, 0, 0)

	craftingRequests = {}
	table.insert(craftingRequests, {name="Microprocessor", amount=16, batch=4})
	table.insert(craftingRequests, {name="Integrated Processor", amount=16, batch=4})
	table.insert(craftingRequests, {name="Processor Assembly", amount=16, batch=4})
	table.insert(craftingRequests, {name="Logic Processor", amount=16, batch=8})
	table.insert(craftingRequests, {name="Engineering Processor", amount=16, batch=8})
	table.insert(craftingRequests, {name="Calculation Processor", amount=16, batch=8})
	table.insert(craftingRequests, {name="Steel Ingot", amount=64, batch=16})
	table.insert(craftingRequests, {name="Dark Steel Ingot", amount=64, batch=16})
	table.insert(craftingRequests, {name="Cupronickel Ingot", amount=64, batch=16})
	table.insert(craftingRequests, {name="Pulsating Polymer Clay", amount=0, batch=0})

	pcall(getTime)
end

local function exit()
	log("> exiting")
	term.clear()
	gpu.fill(1, 1, w, h, " ")
	gpu2.fill(1, 1, w2, h2, " ")
	glasses.removeAll()

	event.ignore("key_down", keyDownHandler)
	event.ignore("touch", touchHandler)
	event.ignore("modem_message", modemHandler)
	event.ignore("glasses_screen_size", glassesScreenSizeHandler)

	log("> broadcasting \"confirm_off\"")
	modem.broadcast(8000, "confirm_off")

	if shouldReboot then
		computer.shutdown(true)
	end
end

local function update()
	deltaTime = computer.uptime() - uptime
	uptime = computer.uptime()
	playtime = (os.time() * 1000/60/60 - 6000) / 20 / 3600
	mctime = os.time() + 3600
	rltime = rltime + deltaTime

	if generatorAutoEnabled and uptime - lastGeneratorAutoRequest >= generatorAutoRequestInterval then
		lastGeneratorAutoRequest = uptime
		if data.energyLevel <= generatorEnableLevel and data.generatorSignal == 0 then
			log("> auto broadcasting proxy request \"generator.enable\"")
			modem.send(serverAddress, 8000, "proxy", "generator.enable")
		end
		if data.energyLevel >= generatorDisableLevel and data.generatorSignal == 1 then
			log("> auto broadcasting proxy request \"generator.disable\"")
			modem.send(serverAddress, 8000, "proxy", "generator.disable")
		end
	end

	if uptime - lastAutocraftingRequest >= autocraftingRequestInterval then
		lastAutocraftingRequest = uptime
		log("> sending autocrafting requests")
		modem.send(serverAddress, 8000, "autocraft", serialization.serialize(craftingRequests))
	end

	energyHistory[math.ceil(uptime/36)] = data.energyLevel
end

local function draw()
	if currentPage == 1 then
		if firstDraw then
			firstDraw = false
			ui.drawBox(gpu, 3, 2, 158, 49, "1 2 3 | ADMIN CLIENT")
			gpu.setForeground(0x000000)
			gpu.setBackground(0xFFFFFF)
			gpu.set(5, 2, "1")
			gpu.setForeground(0xFFFFFF)
			gpu.setBackground(0x000000)
			ui.drawBox(gpu, 6, 4, 46, 14, "STATUS")
			ui.drawBox(gpu, 6, 16, 46, 28, "CONTROLS")
			ui.drawBox(gpu, 49, 4, 94, 28, "DATA")
			ui.drawBox(gpu, 97, 4, 155, 28, "LOG")
			ui.drawBox(gpu, 97, 30, 155, 47, "EVENT LOG")
			ui.drawBox(gpu, 49, 30, 94, 47, "SPOTIFY")
		end

		if logUpdated then
			ui.drawLog(gpu, 100, 6, 152, 27, logString)
		end
		if eventLogUpdated then
			ui.drawLog(gpu, 100, 32, 152, 46, eventLogString)
		end
		if w3 > 0 then
			glassesStatus = "online"
		end

		ui.drawText(gpu, 9, 6, "uptime: " .. string.format("%.2f", uptime) .. " s", 35)
		ui.drawText(gpu, 9, 7, "playtime: " .. string.format("%.2f", playtime) .. " h", 35)
		ui.drawText(gpu, 9, 8, "mctime: " .. os.date("%d.%m.%Y %H:%M:%S", mctime), 35)
		ui.drawText(gpu, 9, 9, "rltime: " .. os.date("%d.%m.%Y %H:%M:%S", rltime), 35)
		ui.drawText(gpu, 9, 11, "server: " .. serverStatus, 35)
		ui.drawText(gpu, 9, 12, "glasses: " .. glassesStatus, 35)

		for _, b in pairs(buttons) do
			if b.id == "toggleGenerator" then
				if data.generatorSignal == 0 then
					b.label = "[E] enable generator"
					b.x2 = 28
				else
					b.label = "[E] disable generator"
					b.x2 = 29
				end
			end
			if b.id == "toggleGeneratorMode" then
				if generatorAutoEnabled then
					b.label = "[G] disable generator manager"
					b.x2 = 37
				else
					b.label = "[G] enable generator manager"
					b.x2 = 36
				end
			end
		end

		for _, b in pairs(buttons) do
			ui.drawText(gpu, b.x1, b.y1, b.label, 35)
		end

		local keys = {}
		for k, v in pairs(data) do
			table.insert(keys, k)
		end
		table.sort(keys)
		local y = 6
		for i, k in ipairs(keys) do
			local v = data[k]
			if type(v) == "table" then
				v = "{" .. #v .. "}"
			end
			ui.drawText(gpu, 52, y, k .. ": " .. v, 40)
			y = y+1
		end

		if data.spotify then
			ui.drawText(gpu, 52, 32, "status: " .. tostring(data.spotify.status), 40)

			-- if data.spotify.auth then
			-- 	ui.drawText(gpu, 52, 34, "authCode: " .. data.spotify.auth.authCode, 40)
			-- 	ui.drawText(gpu, 52, 35, "accessToken: " .. data.spotify.auth.accessToken, 40)
			-- 	ui.drawText(gpu, 52, 36, "refreshToken: " .. data.spotify.auth.refreshToken, 40)
			-- 	ui.drawText(gpu, 52, 37, "expires: " .. string.format("%.2f", math.max(0, data.spotify.auth.expires - data.time)) .. " s", 40)
			-- end

			if data.spotify.player and data.spotify.player.item then
				local state = ""
				if data.spotify.player.is_playing then
					state = "playing"
				else
					state = "paused"
				end
				ui.drawText(gpu, 52, 34, "state: " .. state .. ", " .. string.format("%.2f", data.spotify.player.progress_ms/1000) .. " / " .. string.format("%.2f", data.spotify.player.item.duration_ms/1000), 40)
				ui.drawText(gpu, 52, 35, "track: " .. data.spotify.player.item.name, 40)
				ui.drawText(gpu, 52, 36, "album: " .. data.spotify.player.item.album.name, 40)
				ui.drawText(gpu, 52, 37, "artist: " .. data.spotify.player.item.artists[1].name, 40)
			end
		end

	elseif currentPage == 2 then
		if firstDraw then
			firstDraw = false
			ui.drawBox(gpu, 3, 2, 158, 49, "1 2 3 | POWER CLIENT")
			gpu.setForeground(0x000000)
			gpu.setBackground(0xFFFFFF)
			gpu.set(7, 2, "2")
			gpu.setForeground(0xFFFFFF)
			gpu.setBackground(0x000000)
			ui.drawBox(gpu, 6, 4, 111, 27, "STORAGE")
			ui.drawBox(gpu, 6, 29, 57, 47, "GENERATION")
			ui.drawBox(gpu, 60, 29, 111, 47, "CONSUMPTION")
			ui.drawBox(gpu, 114, 4, 155, 47, "FUEL")
		end

		for _, b in pairs(buttons) do
			ui.drawText(gpu, b.x1, b.y1, b.label)
		end

		local timeleft = 0
		if data.energyRate < 0 then
			timeleft = data.energy / data.energyRate / 20 * -1
		elseif data.energyRate > 0 then
			timeleft = (data.energyMax - data.energy) / data.energyRate / 20 * -1
		end

		ui.drawText(gpu, 9, 6, "energy: " .. string.format("%.0f", data.energy) .. " / " .. string.format("%.0f", data.energyMax) .. " RF (" .. string.format("%.4f", data.energyLevel ).. ")", 100)
		ui.drawText(gpu, 9, 7, "rate: " .. string.format("%.0f", data.energyRate) .. " RF/t", 100)
		ui.drawText(gpu, 9, 8, "time left: " .. string.format("%.2f", timeleft) .. " s", 100)

		local energyGraph = {}
		for i=1,10 do
			energyGraph[i] = ""
			for j=math.max(1,#energyHistory-99),#energyHistory do
				if energyHistory[j] >= i/10 then
					energyGraph[i] = energyGraph[i] .. "─"
				else
					energyGraph[i] = energyGraph[i] .. " "
				end
			end
		end
		for i=1,10 do
			ui.drawText(gpu, 9, 9+(10-i+1), energyGraph[i], 100)
		end
		ui.drawText(gpu, 9, 20, string.rep("─", 100), 100)

		local bar = ""
		for i=1,100 do
			if i%10 == 0 then
				if i/100 <= data.energyLevel then
					bar = bar .. "█"
				else
					bar = bar .. "▒"
				end
			else
				if i/100 <= data.energyLevel then
					bar = bar .. "▓"
				else
					bar = bar .. "░"
				end
			end
		end
		ui.drawText(gpu, 9, 21, bar, 100)
		ui.drawText(gpu, 9, 22, bar, 100)

		local generatorStatus = ""
		if data.generatorSignal == 1 then
			generatorStatus = "online"
		else
			generatorStatus = "offline"
		end
		local generatorMode = ""
		if generatorAutoEnabled then
			generatorMode = "auto"
		else
			generatorMode = "manual"
		end
		ui.drawText(gpu, 9, 31, "generator: " .. generatorStatus, 46)
		ui.drawText(gpu, 9, 32, "rate: " .. string.format("%.0f", data.energyRateGenerator) .. " RF/t", 46)
		ui.drawText(gpu, 9, 34, "mode: " .. generatorMode, 46)
		ui.drawText(gpu, 9, 35, "enable below: " .. string.format("%.2f", generatorEnableLevel), 46)
		ui.drawText(gpu, 9, 36, "disable above: " .. string.format("%.2f", generatorDisableLevel), 46)

		ui.drawText(gpu, 63, 31, "total: " .. string.format("%.0f", data.energyRateFrontend + data.energyRateLogistics + data.energyRateProcessing) .. " RF/t", 46)
		ui.drawText(gpu, 63, 33, "frontend: " .. string.format("%.0f", data.energyRateFrontend) .. " RF/t", 46)
		ui.drawText(gpu, 63, 34, "logistics: " .. string.format("%.0f", data.energyRateLogistics) .. " RF/t", 46)
		ui.drawText(gpu, 63, 35, "processing: " .. string.format("%.0f", data.energyRateProcessing) .. " RF/t", 46)


	elseif currentPage == 3 then
		if firstDraw then
			firstDraw = false
			ui.drawBox(gpu, 3, 2, 158, 49, "1 2 3 | LOGISTICS CLIENT")
			gpu.setForeground(0x000000)
			gpu.setBackground(0xFFFFFF)
			gpu.set(9, 2, "3")
			gpu.setForeground(0xFFFFFF)
			gpu.setBackground(0x000000)
			ui.drawBox(gpu, 6, 4, 46, 47, "CPUS")
			ui.drawBox(gpu, 49, 4, 155, 47, "AUTOCRAFTING")
		end

		for _, b in pairs(buttons) do
			ui.drawText(gpu, b.x1, b.y1, b.label)
		end

		local y = 6
		for i, c in ipairs(data.craftingCpus) do
			if not c.busy then
				cpuIdleTime[i] = uptime
			end
			local busyTime = 0
			if cpuIdleTime[i] then
				busyTime = uptime - cpuIdleTime[i]
			end
			ui.drawText(gpu, 9, y, "id: " .. i .. ", name: " .. c.name, 35)
			ui.drawText(gpu, 9, y+1, "processors: " .. string.format("%.0f", c.coprocessors) .. ", storage: " .. string.format("%.0f", c.storage), 35)
			ui.drawText(gpu, 9, y+2, "busy: " .. tostring(c.busy) .. ", time: " .. string.format("%.2f", busyTime) .. " s", 35)
			ui.drawText(gpu, 9, y+3, "crafting: " .. tostring(data.cpuStatus[i]), 35)
			y = y + 5
		end

		ui.drawText(gpu, 52, 6, "id")
		ui.drawText(gpu, 57, 6, "name")
		ui.drawText(gpu, 87, 6, "amount")
		ui.drawText(gpu, 97, 6, "stored")
		ui.drawText(gpu, 107, 6, "batch")
		ui.drawText(gpu, 117, 6, "status")
		ui.drawText(gpu, 137, 6, "manual request")
		y = 8
		for i, r in ipairs(craftingRequests) do
			local storedAmount = 0
			for _, item in ipairs(data.items) do
				if item.name == r.name then
					storedAmount = item.size
				end
			end
			local status = data.craftingStatus[i]
			if not status then
				status = "unknown"
			end
			ui.drawText(gpu, 52, y, i, 4)
			ui.drawText(gpu, 57, y, r.name, 29)
			ui.drawText(gpu, 87, y, string.format("%.0f", r.amount), 9)
			ui.drawText(gpu, 97, y, string.format("%.0f", storedAmount), 9)
			ui.drawText(gpu, 107, y, string.format("%.0f", r.batch), 9)
			ui.drawText(gpu, 117, y, status, 9)
			y = y + 1
		end
		ui.drawText(gpu, 52, y+1, "next request: " .. string.format("%.2f", autocraftingRequestInterval - (uptime - lastAutocraftingRequest)) .. " s", 20)
	end

	-- monitor
	local energyUsageSign = ""
	if data.energyRate < 0 then
		energyUsageSign = "-"
	elseif data.energyRate > 0 then
		energyUsageSign = "+"
	end
	local energyBar = ""
	for i=0,w2-5 do
		if data.energyLevel >= i/(w2-5) then
			energyBar = energyBar .. "▒"
		else
			energyBar = energyBar .. "░"
		end
	end
	local generatorStatus = ""
	if (data.generatorSignal == 1) then
		generatorStatus = "online"
	else
		generatorStatus = "offline"
	end
	local busyCpuCount = 0
	for i, c in ipairs(data.craftingCpus) do
		if c.busy then
			busyCpuCount = busyCpuCount + 1
		end
	end

	gpu2.fill(1, 1, w2, h2, " ")
	gpu2.fill(1, 1, w2, 1, "▀")
	gpu2.fill(1, h2, w2, 1, "▄")
	gpu2.fill(1, 1, 1, h2, "█")
	gpu2.fill(w2, 1, 1, h2, "█")
	gpu2.set(3, 2, "RF: " .. string.format("%.0f", tostring(data.energy)) .. " / " .. string.format("%.0f", tostring(data.energyMax)) .. " (" .. energyUsageSign .. string.format("%.0f", tostring(math.abs(data.energyRate))) .. " RF/t)")
	gpu2.set(3, 3, "Generators " .. generatorStatus .. ", " .. string.format("%.0f", tostring(data.generatorFuel)) .. " fuel")
	gpu2.set(3, 4, "ME: " .. string.format("%.0f", tostring(data.itemsCount)) .. " items, " .. string.format("%.0f", tostring(data.itemsTypeCount)) .. " types")
	gpu2.set(3, 5, busyCpuCount .. " / " .. #data.craftingCpus .. " cpus active")
	gpu2.set(3, 8, energyBar)

	-- glasses
	widget1.setText(string.format("%.0f", tostring(data.energy)) .. " / " .. string.format("%.0f", tostring(data.energyMax)) .. " (" .. energyUsageSign .. string.format("%.0f", tostring(math.abs(data.energyRate))) .. " RF/t)")
	widget1.modifiers()[1].set(6, h3-10, 0)
end

local function run()
	init()

	while not shouldQuit do
		update()
		draw()
		os.sleep(refreshInterval)
	end

	exit()
end

run()
