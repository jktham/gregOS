local component = require("component")
local term = require("term")
local computer = require("computer")
local os = require("os")
local event = require("event")
local ui = require("ui")
local internet = require("internet")
local serialization = require("serialization")
local io = require("io")
local sides = require("sides")
local json = require("json")
local base64 = require("base64")

local screen = component.screen
local gpu = component.gpu
local keyboard = component.keyboard
local modem = component.modem
local clientAddress = "752f9aa2-6ca2-45b2-9467-767bb0d910ef"
local debug = component.debug
local chat = component.chat_box

local w, h = 160, 50

local refreshInterval = 0.1
local shouldQuit = false
local shouldReboot = false

local deltaTime = 0
local uptime = 0
local playtime = 0
local mctime = 0
local rltime = 0

local clientStatus = "offline"

local firstDraw = true
local buttons = {}

local lastLine = ""
local lastLineRepeat = 0
local logString = ""
local eventLogString = ""
local logUpdated = false
local eventLogUpdated = false
local logLength = 21
local eventLogLength = 14

local dataCollectionEnabled = true
local dataBroadcastEnabled = true
local dataUpdateInterval = 2.0
local lastDataUpdate = 0
local serializedData = ""
local craftingStatus = {}
local craftingTracker = {}
local numCraftingRequests = 0
local cpuStatus = {}

local perfTimers = {}
local longestUpdate = 0
local averageUpdate = 0
local lastUpdates = {}
local lastUpdateIndex = 1
local firstAuthAttempt = true

local spotify = {}
spotify.status = ""
spotify.auth = {}
spotify.auth.authCode = ""
spotify.auth.accessToken = ""
spotify.auth.refreshToken = ""
spotify.auth.expires = 0
spotify.player = {}

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

local function startTimer(name)
	for i, t in ipairs(perfTimers) do
		if t.name == name then
			t.start = computer.uptime()
			return
		end
	end
	local newTimer = {name=name, start=computer.uptime(), stop=0, delta=0}
	table.insert(perfTimers, newTimer)
end

local function stopTimer(name)
	for i, t in ipairs(perfTimers) do
		if t.name == name then
			t.stop = computer.uptime()
			t.delta = t.stop - t.start
			return
		end
	end
end

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

local function rebootClient()
	log("> broadcasting \"reboot\"")
	modem.send(clientAddress, 8000, "reboot")
	log("> broadcasting \"wake\"")
	modem.send(clientAddress, 8000, "wake")
end

local function toggleDataCollection()
	if dataCollectionEnabled then
		log("> disabling data collection")
		dataCollectionEnabled = false
	else
		log("> enabling data collection")
		dataCollectionEnabled = true
	end
end

local function toggleDataBroadcast()
	if dataBroadcastEnabled then
		log("> disabling data broadcast")
		dataBroadcastEnabled = false
	else
		log("> enabling data broadcast")
		dataBroadcastEnabled = true
	end
end

local function loadPage()
	log("> loading page")
	firstDraw = true

	buttons = {}
	table.insert(buttons, {x1=9, y1=18, x2=18, y2=18, label="[R] reboot", shortcut="r", action=reboot, arg=nil, id="reboot"})
	table.insert(buttons, {x1=9, y1=19, x2=16, y2=19, label="[Q] quit", shortcut="q", action=quit, arg=nil, id="quit"})
	table.insert(buttons, {x1=9, y1=20, x2=25, y2=20, label="[F] reboot client", shortcut="f", action=rebootClient, arg=nil, id="rebootClient"})
	table.insert(buttons, {x1=9, y1=21, x2=35, y2=21, label="[E] toggle data collection", shortcut="e", action=toggleDataCollection, arg=nil, id="toggleDataCollection"})
	table.insert(buttons, {x1=9, y1=22, x2=34, y2=22, label="[D] toggle data broadcast", shortcut="d", action=toggleDataBroadcast, arg=nil, id="toggleDataBroadcast"})

end

local function getCraftingStatus()
	startTimer("getCraftingStatus")
	log("> getting crafting status")
	for i=1,numCraftingRequests do
		craftingStatus[i] = "idle"
		if craftingTracker[i] ~= nil then
			local done, error = craftingTracker[i].isDone()
			local canceled, _ = craftingTracker[i].isCanceled()
			if done then
				craftingStatus[i] = "done"
			elseif canceled then
				craftingStatus[i] = "canceled"
			elseif error then
				craftingStatus[i] = "error"
			else
				craftingStatus[i] = "crafting"
			end
		end
	end
	stopTimer("getCraftingStatus")
end

local function autocraft(requests)
	startTimer("autocraft")
	numCraftingRequests = #requests
	for i, r in ipairs(requests) do
		local storedAmount = 0
		for _, item in ipairs(data.items) do
			if item.name == r.name then
				storedAmount = item.size
			end
		end
		if storedAmount < r.amount then
			local amount = math.min(r.amount - storedAmount, r.batch)
			if craftingStatus[i] ~= "crafting" then
				local craftable = component.me_controller.getCraftables({label=r.name})[1]
				if craftable ~= nil then
					local cpuName = ""
					local cpuIndex = 0
					for k=1,3 do
						for l,c in ipairs(data.craftingCpus) do
							if c.name == "passive " .. tostring(k) then
								if not c.busy and cpuName == "" then
									cpuName = c.name
									cpuIndex = l
								end
							end
						end
					end
					if cpuName ~= "" then
						local _, e
						local tracker = craftable.request(amount, true, cpuName)
						_, e = tracker.isDone()
						if e then
							amount = math.floor(amount/2)
							tracker = craftable.request(amount, true, cpuName)
							_, e = tracker.isDone()
							if e then
								amount = 1
								tracker = craftable.request(amount, true, cpuName)
								_, e = tracker.isDone()
							end
						end
						if not e then
							cpuStatus[cpuIndex] = amount .. " " .. r.name
						end
						craftingTracker[i] = tracker
					end
				end
			end
		else
			craftingTracker[i] = nil
		end
	end
	getCraftingStatus()
	stopTimer("autocraft")
end

local function craft(requests)
	startTimer("craft")
	for i, r in ipairs(requests) do
		if r.amount > 0 then
			local craftable = component.me_controller.getCraftables({label=r.name})[1]
			if craftable ~= nil then
				local cpuName = ""
				local cpuIndex = 0
				for k=1,3 do
					for l,c in ipairs(data.craftingCpus) do
						if c.name == "passive " .. tostring(k) then
							if not c.busy and cpuName == "" then
								cpuName = c.name
								cpuIndex = l
							end
						end
					end
				end
				if cpuName ~= "" then
					local tracker = craftable.request(r.amount, true, cpuName)
					local _, e = tracker.isDone()
					if not e then
						cpuStatus[cpuIndex] = string.format("%.0f", r.amount) .. " " .. r.name
					end
				end
			end
		end
	end
	stopTimer("craft")
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

local function chatMessageHandler(id, address, player, message)
	eventLog(id, string.sub(address, 1, 4), player, message)
	if spotify.auth.authCode == "" then
		spotify.auth.authCode = message
	end
end

local function modemHandler(id, localAddress, remoteAddress, port, distance, name, message)
	eventLog(id, string.sub(localAddress, 1, 4), string.sub(remoteAddress, 1, 4), name, (function() if message then return string.sub(message, 1, 32) else return message end end)())
	if name == "reboot" then
		reboot()
	elseif name == "confirm_on" and remoteAddress == clientAddress then
		log("> client online")
		clientStatus = "online"
	elseif name == "confirm_off" and remoteAddress == clientAddress then
		log("> client offline")
		clientStatus = "offline"
	elseif name == "check" then
		log("> broadcasting \"confirm_on\"")
		modem.broadcast(8000, "confirm_on")
	elseif name == "proxy" then
		log("> received proxy request \"" .. message .. "\"")
		if message == "generator.enable" then
			component.redstone.setOutput(sides.east, 1)
		elseif message == "generator.disable" then
			component.redstone.setOutput(sides.east, 0)
		end
	elseif name == "autocraft" then
		log("> received autocraft request \"" .. message .. "\"")
		autocraft(serialization.unserialize(message))
	elseif name == "craft" then
		log("> received craft request \"" .. message .. "\"")
		craft(serialization.unserialize(message))
	end
end

local function getTime()
	startTimer("getTime")
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
	stopTimer("getTime")
end

local function getSpotify()
	startTimer("getSpotify")
	log("> getting spotify")

	-- put api authentication here (maybe don't if you're on a server though)
	local client_id = ""
	local client_secret = ""
	local redirect_uri = ""
	
	if client_id == "" or client_secret == "" or redirect_uri == "" then
		return
	end

	if firstAuthAttempt then
		local file = io.open("refreshToken.txt", "r")
		if file then
			local refreshToken = file:read()
			file:close()
			if refreshToken then
				spotify.auth.refreshToken = refreshToken
				spotify.auth.expires = 1
				firstAuthAttempt = false
			end
		end
	end

	if firstAuthAttempt and spotify.auth.authCode == "" and spotify.auth.refreshToken == "" then
		spotify.status = "waiting for auth code"
		local authUrl = "https://accounts.spotify.com/authorize?response_type=code&client_id=" .. client_id .. "&redirect_uri=" .. redirect_uri .. "&scope=user-read-playback-state"
		local authMsg = {text="click to authenticate spotify api, then paste code in chat", clickEvent={action="open_url", value=authUrl}}
		debug.runCommand("/tellraw @a " .. json:encode(authMsg))
		firstAuthAttempt = false
	end

	if spotify.auth.authCode ~= "" and spotify.auth.accessToken == "" and spotify.auth.refreshToken == "" then
		spotify.status = "getting access token"
		local body = {grant_type="authorization_code", code=spotify.auth.authCode, redirect_uri=redirect_uri}
		local headers = {Authorization="Basic " .. base64.encode(client_id .. ":" .. client_secret)}

		local handle = internet.request("https://accounts.spotify.com/api/token", body, headers)
		local response = ""
		for chunk in handle do
			response = response .. chunk
		end

		local r = json:decode(response)
		if r then
			spotify.auth.accessToken = r.access_token
			spotify.auth.refreshToken = r.refresh_token
			spotify.auth.expires = data.time + r.expires_in / 2

			local file = io.open("refreshToken.txt", "w")
			if file then
				file:write(spotify.auth.refreshToken)
				file:close()
			end
		end
	end

	if spotify.auth.accessToken ~= "" then
		spotify.status = "authenticated"
		local headers = {Authorization="Bearer " .. spotify.auth.accessToken}

		local handle = internet.request("https://api.spotify.com/v1/me/player", {}, headers)
		local response = ""
		for chunk in handle do
			response = response .. chunk
		end

		local r = json:decode(response)
		if r then
			spotify.player = r
		end
	end

	if spotify.auth.expires ~= 0 and spotify.auth.expires < data.time then
		spotify.status = "refreshing access token"
		local body = {grant_type="refresh_token", refresh_token=spotify.auth.refreshToken}
		local headers = {Authorization="Basic " .. base64.encode(client_id .. ":" .. client_secret)}

		local handle = internet.request("https://accounts.spotify.com/api/token", body, headers)
		local response = ""
		for chunk in handle do
			response = response .. chunk
		end

		local r = json:decode(response)
		if r then
			spotify.auth.accessToken = r.access_token
			spotify.auth.expires = data.time + r.expires_in / 2
		end
	end

	stopTimer("getSpotify")
end

local function getData()
	startTimer("getData")
	prevData = data
	data = {}
	data.version = prevData.version + 1
	data.time = uptime
	data.energy = component.energy_device.getEnergyStored()
	data.energyMax = component.energy_device.getMaxEnergyStored()
	if data.energyMax == 0 then
		data.energyLevel = 0
	else
		data.energyLevel = data.energy / (data.energyMax)
	end
	data.energyRate = (data.energy - prevData.energy) / (data.time - prevData.time) / 20
	data.generatorSignal = component.redstone.getOutput(sides.east)
	data.generatorFuel = component.inventory_controller.getSlotStackSize(5, 2)
	data.energyRateGenerator = component.proxy("adcf02ad-fb54-4a67-af39-8b8a2e1a4b18").getTransferRate()
	local rawItems = component.me_controller.getItemsInNetwork()
	data.items = {}
	for i=1,#rawItems do
		table.insert(data.items, {size=rawItems[i].size, name=rawItems[i].label})
	end
	data.itemsCount = 0
	for i=1,#data.items do
		data.itemsCount = data.itemsCount + data.items[i].size
	end
	data.itemsTypeCount = #data.items
	data.craftingCpus = component.me_controller.getCpus()
	data.energyRateFrontend = component.proxy("a74320fd-4c17-45b9-bb59-5ffecd84e382").getTransferRate()
	data.energyRateLogistics = component.proxy("57e7fb95-1d8d-4665-befd-7d0ea4736d65").getTransferRate()
	data.energyRateProcessing = component.proxy("a11448f8-c446-4ea7-8e30-001fefed25fb").getTransferRate()

	getCraftingStatus()
	data.craftingStatus = craftingStatus
	for i,c in ipairs(data.craftingCpus) do
		if not c.busy then
			cpuStatus[i] = nil
		end
	end
	data.cpuStatus = cpuStatus
	pcall(getSpotify)
	data.spotify = spotify

	serializedData = serialization.serialize(data)
	stopTimer("getData")
end

local function sendData()
	startTimer("sendData")
	log("> broadcasting data")
	modem.broadcast(8000, "data", serializedData)
	stopTimer("sendData")
end

local function update()
	startTimer("update")
	deltaTime = computer.uptime() - uptime
	uptime = computer.uptime()
	playtime = (os.time() * 1000/60/60 - 6000) / 20 / 3600
	mctime = os.time() + 3600
	rltime = rltime + deltaTime
	if uptime - lastDataUpdate >= dataUpdateInterval then
		lastDataUpdate = uptime
		if dataCollectionEnabled then
			getData()
		end
		if dataBroadcastEnabled then
			sendData()
		end
	end
	for i,t in ipairs(perfTimers) do
		if t.name == "update" then
			if t.delta > longestUpdate then
				longestUpdate = t.delta
			end
			lastUpdates[lastUpdateIndex] = t.delta
			lastUpdateIndex = lastUpdateIndex + 1
			if lastUpdateIndex > 10 then
				lastUpdateIndex = 1
			end
		end
	end
	local sum = 0
	for i=1,#lastUpdates do
		sum = sum + lastUpdates[i]
	end
	averageUpdate = sum / 10
	stopTimer("update")
end

local function init()
	startTimer("init")
	log("> initializing")
	component.setPrimary("screen", screen.address)
	component.setPrimary("gpu", gpu.address)
	component.setPrimary("keyboard", keyboard.address)
	gpu.bind(screen.address)
	term.bind(gpu)

	modem.open(8000)
	modem.setWakeMessage("wake")
	log("> broadcasting \"confirm_on\"")
	modem.broadcast(8000, "confirm_on")
	log("> broadcasting \"check\"")
	modem.broadcast(8000, "check")

	event.listen("key_down", keyDownHandler)
	event.listen("touch", touchHandler)
	event.listen("chat_message", chatMessageHandler)
	event.listen("modem_message", modemHandler)

	gpu.setResolution(w, h)

	term.clear()
	gpu.fill(1, 1, w, h, " ")
	loadPage()

	pcall(getTime)
	pcall(getSpotify)
	stopTimer("init")
end

local function exit()
	log("> exiting")
	term.clear()
	gpu.fill(1, 1, w, h, " ")

	event.ignore("key_down", keyDownHandler)
	event.ignore("touch", touchHandler)
	event.ignore("chat_message", chatMessageHandler)
	event.ignore("modem_message", modemHandler)

	log("> broadcasting \"confirm_off\"")
	modem.broadcast(8000, "confirm_off")

	if shouldReboot then
		computer.shutdown(true)
	end
end

local function draw()
	startTimer("draw")
	if firstDraw then
		firstDraw = false
		ui.drawBox(gpu, 3, 2, 158, 49, "PROXY SERVER")
		ui.drawBox(gpu, 6, 4, 46, 14, "STATUS")
		ui.drawBox(gpu, 6, 16, 46, 28, "CONTROLS")
		ui.drawBox(gpu, 49, 4, 94, 28, "DATA")
		ui.drawBox(gpu, 6, 30, 46, 47, "DIAGNOSTICS")
		ui.drawBox(gpu, 49, 30, 94, 47, "COMPONENTS")
		ui.drawBox(gpu, 97, 4, 155, 28, "LOG")
		ui.drawBox(gpu, 97, 30, 155, 47, "EVENT LOG")
	end

	if logUpdated then
		ui.drawLog(gpu, 100, 6, 152, 27, logString)
	end
	if eventLogUpdated then
		ui.drawLog(gpu, 100, 32, 152, 46, eventLogString)
	end

	ui.drawText(gpu, 9, 6, "uptime: " .. string.format("%.2f", uptime) .. " s", 35)
	ui.drawText(gpu, 9, 7, "playtime: " .. string.format("%.2f", playtime) .. " h", 35)
	ui.drawText(gpu, 9, 8, "mctime: " .. os.date("%d.%m.%Y %H:%M:%S", mctime), 35)
	ui.drawText(gpu, 9, 9, "rltime: " .. os.date("%d.%m.%Y %H:%M:%S", rltime), 35)
	ui.drawText(gpu, 9, 11, "client: " .. clientStatus, 35)

	for _, b in pairs(buttons) do
		if b.id == "toggleDataCollection" then
			if dataCollectionEnabled then
				b.label = "[E] disable data collection"
				b.x2 = 35
			else
				b.label = "[E] enable data collection"
				b.x2 = 34
			end
		end
		if b.id == "toggleDataBroadcast" then
			if dataBroadcastEnabled then
				b.label = "[D] disable data broadcast"
				b.x2 = 34
			else
				b.label = "[D] enable data broadcast"
				b.x2 = 33
			end
		end
	end

	for _, b in pairs(buttons) do
		ui.drawText(gpu, b.x1, b.y1, b.label, 35)
	end

	ui.drawText(gpu, 9, 32, "memory used: " .. computer.totalMemory() - computer.freeMemory() .. " / " .. computer.totalMemory(), 35)
	ui.drawText(gpu, 9, 33, "longest update: " .. string.format("%.2f", longestUpdate), 35)
	ui.drawText(gpu, 9, 34, "average update: " .. string.format("%.2f", averageUpdate), 35)
	for i, t in ipairs(perfTimers) do
		ui.drawText(gpu, 9, 35+i, t.name .. ": " .. string.format("%.2f", t.delta) .. " (" .. string.format("%.2f", t.start) .. ")", 35)
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

	y = 32
	for a, t in component.list() do
		if y <= 45 and t ~= "computer" and t ~= "eeprom" and t ~= "filesystem" and t ~= "gpu" and t ~= "screen" and t ~= "keyboard" and t ~= "internet" and t ~= "modem" then
			ui.drawText(gpu, 52, y, t .. ": " .. a, 40)
			y = y+1
		end
	end

	stopTimer("draw")
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
