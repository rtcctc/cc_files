-- голосование с редстоун-кнопками, красивый интерфейс
-- запоминание сторон в sides.cfg

local configFile = "sides.cfg"

local function loadSides()
    if fs.exists(configFile) then
        local f = fs.open(configFile, "r")
        local data = f.readAll()
        f.close()
        return textutils.unserialise(data)
    end
    return nil
end

local function saveSides(sides)
    local f = fs.open(configFile, "w")
    f.write(textutils.serialise(sides))
    f.close()
end

local function getSides()
    local sides = loadSides()
    if sides then return sides end
    
    print("=== PERVY ZAPUSK: NASTROYKA STORON ===")
    print("Dostupny storony: front, back, left, right, top, bottom")
    print("Vvedite storonu dlya MONITORA (naprimer front):")
    local monSide = read()
    print("Vvedite storonu dlya ZA:")
    local zaSide = read()
    print("Vvedite storonu dlya PROTIV:")
    local protivSide = read()
    print("Vvedite storonu dlya VOZDERZHALSYA:")
    local vozderzhSide = read()
    print("Vvedite storonu dlya DOSROCHNOGO OSTANOVA (STOP):")
    local stopSide = read()
    print("Vvedite storonu dlya VYHODA IZ PROGRAMMY (EXIT):")
    local exitSide = read()
    
    sides = {
        monitor = monSide,
        za = zaSide,
        protiv = protivSide,
        vozderzh = vozderzhSide,
        stop = stopSide,
        exit = exitSide
    }
    saveSides(sides)
    print("Nastroiki sohraneny. Nazhmite Enter")
    read()
    return sides
end

-- podklyuchenie monitora
local sides = getSides()
local mon = peripheral.wrap(sides.monitor)
if not mon then error("Monitor na storone " .. sides.monitor .. " ne najden") end
mon.clear()
-- NE menyaem masshtab (standardny)

-- opros knopki (front)
local function wasPressed(side, lastState)
    local cur = rs.getInput(side)
    if cur and not lastState then
        return true, cur
    else
        return false, cur
    end
end

-- sostoyaniya knopok
local lastZa = false
local lastProtiv = false
local lastVozderzh = false
local lastStop = false
local lastExit = false

-- funkcii dlya risovaniya ramok
local function drawFrame(x1, y1, x2, y2, title)
    -- verhnyaya liniya
    mon.setCursorPos(x1, y1)
    mon.write("+" .. string.rep("-", x2 - x1 - 1) .. "+")
    -- nizhnyaya liniya
    mon.setCursorPos(x1, y2)
    mon.write("+" .. string.rep("-", x2 - x1 - 1) .. "+")
    -- bokovye linii
    for y = y1+1, y2-1 do
        mon.setCursorPos(x1, y)
        mon.write("|")
        mon.setCursorPos(x2, y)
        mon.write("|")
    end
    -- zagolovok
    if title then
        local tx = x1 + math.floor((x2 - x1 - #title) / 2)
        mon.setCursorPos(tx, y1)
        mon.setBackgroundColor(colors.black)
        mon.setTextColor(colors.cyan)
        mon.write(title)
    end
end

local function drawParticipants(participants, startX, startY, width, height)
    drawFrame(startX, startY, startX+width, startY+height, "UCHASTNIKI")
    local maxLines = height - 2
    for i = 1, math.min(#participants, maxLines) do
        mon.setCursorPos(startX+2, startY+i)
        mon.setTextColor(colors.lightGray)
        mon.write(string.sub(participants[i], 1, width-4))
    end
    if #participants > maxLines then
        mon.setCursorPos(startX+2, startY+maxLines)
        mon.write("... i esche " .. (#participants - maxLines))
    end
end

local function drawVotingPanel(question, votes, votedCount, totalPeople, startX, startY, width, height)
    drawFrame(startX, startY, startX+width, startY+height, "GOLOSOVANIE")
    local y = startY + 2
    mon.setCursorPos(startX+2, y)
    mon.setTextColor(colors.white)
    mon.write("Vopros: " .. string.sub(question, 1, width-12))
    y = y + 2
    mon.setCursorPos(startX+2, y)
    mon.write("Progolosovalo: " .. votedCount .. " / " .. totalPeople)
    y = y + 2
    
    -- cvetnaya poloska
    local barWidth = width - 6
    if barWidth < 5 then barWidth = 5 end
    local function addSegment(color, count)
        local len = math.floor(count / totalPeople * barWidth)
        for i = 1, len do
            mon.setCursorPos(startX+3 + i -1, y)
            mon.setBackgroundColor(color)
            mon.write(" ")
        end
        return len
    end
    mon.setCursorPos(startX+3, y)
    mon.setBackgroundColor(colors.black)
    local used = 0
    used = used + addSegment(colors.green, votes.za)
    used = used + addSegment(colors.red, votes.protiv)
    used = used + addSegment(colors.yellow, votes.vozderzh)
    used = used + addSegment(colors.gray, totalPeople - votedCount)
    for i = used+1, barWidth do
        mon.setCursorPos(startX+3 + i -1, y)
        mon.setBackgroundColor(colors.black)
        mon.write(" ")
    end
    mon.setBackgroundColor(colors.black)
    
    y = y + 2
    mon.setCursorPos(startX+2, y)
    mon.setTextColor(colors.green)
    mon.write("ZA: ")
    mon.setTextColor(colors.white)
    mon.write(votes.za .. "   ")
    mon.setTextColor(colors.red)
    mon.write("PROTIV: " .. votes.protiv .. "   ")
    mon.setTextColor(colors.yellow)
    mon.write("VOZDERZH: " .. votes.vozderzh)
end

local function drawHelp(monWidth, monHeight)
    drawFrame(2, monHeight-4, monWidth-2, monHeight-1, "UPRAVLENIE")
    mon.setCursorPos(4, monHeight-3)
    mon.setTextColor(colors.gray)
    mon.write("Knopki: ZA | PROTIV | VOZDERZH | STOP | EXIT")
end

-- osnovnaya programma
print("Vvedite temu sobraniya:")
local meetingTopic = read()
print("Vvedite nomer sobraniya:")
local meetingNumber = read()

mon.clear()
drawFrame(2, 2, mon.getSize()-1, 4, meetingTopic .. " " .. meetingNumber)
sleep(2)

print("Vvodite imena uchastnikov (0 - konetc):")
local participants = {}
while true do
    local name = read()
    if name == "0" then break end
    if name ~= "" then table.insert(participants, name) end
end
local totalPeople = #participants
if totalPeople == 0 then error("Net uchastnikov") end

print("Spisok uchastnikov ("..totalPeople.."):")
for i,v in ipairs(participants) do print(i..". "..v) end
print("Nazhmite Enter dlya pokaza na monitor")
read()

-- pokazat uchastnikov na monitor pered golosovaniyami
mon.clear()
local w, h = mon.getSize()
drawParticipants(participants, 2, 2, 20, h-5) -- levaya chast, shirina 20
drawFrame(w-20, 2, w-2, 4, "GOTOV K RABOTE")
mon.setCursorPos(w-18, 4)
mon.write("Nazhmite knopku")
mon.setCursorPos(w-18, 5)
mon.write("ENTER na PC")
drawHelp(w, h)
print("Nazhmite Enter dlya starta golosovaniy")
read()

-- cikl golosovanij
while true do
    print("Vvedite vopros dlya golosovaniya:")
    local question = read()
    if question == "" then break end
    
    local votes = { za = 0, protiv = 0, vozderzh = 0 }
    local votedCount = 0
    local active = true
    
    lastZa = rs.getInput(sides.za)
    lastProtiv = rs.getInput(sides.protiv)
    lastVozderzh = rs.getInput(sides.vozderzh)
    lastStop = rs.getInput(sides.stop)
    lastExit = rs.getInput(sides.exit)
    
    while active and votedCount < totalPeople do
        local pressed, cur
        
        pressed, cur = wasPressed(sides.za, lastZa)
        lastZa = cur
        if pressed then votes.za = votes.za + 1 votedCount = votedCount + 1 end
        
        pressed, cur = wasPressed(sides.protiv, lastProtiv)
        lastProtiv = cur
        if pressed then votes.protiv = votes.protiv + 1 votedCount = votedCount + 1 end
        
        pressed, cur = wasPressed(sides.vozderzh, lastVozderzh)
        lastVozderzh = cur
        if pressed then votes.vozderzh = votes.vozderzh + 1 votedCount = votedCount + 1 end
        
        pressed, cur = wasPressed(sides.stop, lastStop)
        lastStop = cur
        if pressed then active = false break end
        
        pressed, cur = wasPressed(sides.exit, lastExit)
        lastExit = cur
        if pressed then
            mon.clear()
            print("Exit by knopka")
            os.exit()
        end
        
        -- obnovit interfeys
        mon.clear()
        w, h = mon.getSize()
        drawParticipants(participants, 2, 2, 20, h-5)
        drawVotingPanel(question, votes, votedCount, totalPeople, w-28, 2, 26, 8)
        drawHelp(w, h)
        
        os.sleep(0.05)
    end
    
    -- pokazat rezultat
    mon.clear()
    local resY = 5
    mon.setCursorPos(3, resY)
    mon.setTextColor(colors.white)
    if votedCount == totalPeople then
        if votes.za > votes.protiv then
            mon.write(">>> REZULTAT: PRINYATO (ZA > PROTIV) <<<")
        elseif votes.protiv > votes.za then
            mon.write(">>> REZULTAT: OTKLONENO (PROTIV > ZA) <<<")
        else
            mon.write(">>> REZULTAT: RAVENSTVO <<<")
        end
    else
        mon.write(">>> GOLOSOVANIE PRERVANO DOSROCHNO <<<")
    end
    mon.setCursorPos(3, resY+2)
    mon.write("ZA: " .. votes.za .. "   PROTIV: " .. votes.protiv .. "   VOZDERZH: " .. votes.vozderzh)
    sleep(4)
    
    print("Prodolzhit golosovaniya? (y/n):")
    if read() ~= "y" then break end
end

-- ochistka monitora pri vyhode
mon.clear()
print("Programma zavershena")
