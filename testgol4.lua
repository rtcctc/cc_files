-- golosovanie s redstone knopkami + zapominanie storon
-- vse storony, krome odnoy, zanyaty knopkami. Odna storona - monitor.

local configFile = "sides.cfg"

local function loadSides()
    if fs.exists(configFile) then
        local f = fs.open(configFile, "r")
        local data = f.readAll()
        f.close()
        local sides = textutils.unserialise(data)
        if sides then return sides end
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
    
    print("=== PERVIY ZAPUSK: NASTROYKA STORON ===")
    print("Storony: front, back, left, right, top, bottom")
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
    print("Nastroiki sohraneny v " .. configFile)
    print("Nazhmite Enter dlya prodolzheniya")
    read()
    return sides
end

-- podklyuchenie monitora na zadannoy storone
local sides = getSides()
local mon = peripheral.wrap(sides.monitor)
if not mon then
    error("Monitor na storone " .. sides.monitor .. " ne najden")
end
mon.setTextScale(0.5)
mon.clear()

-- funktsiya oprosa knopki (front signala)
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

-- risovanie poloski (bez cifr)
local function drawBar(yes, no, abst, total, waiting)
    local w = mon.getSize()
    local barWidth = w - 4
    if barWidth < 5 then barWidth = 5 end
    local y = 8
    
    local seg = {}
    local function addSegment(color, count)
        for i = 1, math.floor(count / total * barWidth) do
            table.insert(seg, color)
        end
    end
    addSegment(colors.green, yes)
    addSegment(colors.red, no)
    addSegment(colors.yellow, abst)
    addSegment(colors.gray, waiting)
    
    local x = 2
    for _, col in ipairs(seg) do
        mon.setCursorPos(x, y)
        mon.setBackgroundColor(col)
        mon.write(" ")
        x = x + 1
        if x > w then break end
    end
    mon.setBackgroundColor(colors.black)
end

local function showUI(topic, num, question, participants, votes, votedCount, totalPeople)
    mon.clear()
    mon.setCursorPos(2,1)
    mon.setTextColor(colors.cyan)
    mon.write(topic .. " " .. num)
    
    mon.setCursorPos(2,3)
    mon.setTextColor(colors.white)
    mon.write("Vopros: " .. question)
    
    mon.setCursorPos(2,4)
    mon.write("Uchastnikov: " .. totalPeople .. "   Progolosovalo: " .. votedCount)
    
    local leftX = 2
    local startY = 6
    mon.setCursorPos(leftX, startY)
    mon.setTextColor(colors.lightGray)
    mon.write("Uchastniki:")
    for i = 1, math.min(10, #participants) do
        mon.setCursorPos(leftX, startY + i)
        mon.write(" " .. participants[i])
    end
    
    local waiting = totalPeople - votedCount
    drawBar(votes.za, votes.protiv, votes.vozderzh, totalPeople, waiting)
    
    local h = mon.getSize()
    mon.setCursorPos(2, h-2)
    mon.setTextColor(colors.gray)
    mon.write("Knopki: ZA | PROTIV | VOZDERZH | STOP | EXIT")
end

-- osnovnaya programma
print("Vvedite temu sobraniya:")
local meetingTopic = read()
print("Vvedite nomer sobraniya:")
local meetingNumber = read()

mon.clear()
mon.setCursorPos(2,2)
mon.setTextColor(colors.cyan)
mon.write(meetingTopic .. " " .. meetingNumber)
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

print("Spisok ("..totalPeople.."):")
for i,v in ipairs(participants) do print(i..". "..v) end
print("Nazhmite Enter dlya nachala golosovaniy")
read()

-- cikl golosovanij
while true do
    print("Vvedite vopros dlya golosovaniya:")
    local question = read()
    if question == "" then break end
    
    local votes = { za = 0, protiv = 0, vozderzh = 0 }
    local votedCount = 0
    local active = true
    
    -- obnovit sostoyaniya knopok
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
        if pressed then print("EXIT knopka") os.exit() end
        
        showUI(meetingTopic, meetingNumber, question, participants, votes, votedCount, totalPeople)
        os.sleep(0.05)
    end
    
    mon.clear()
    mon.setCursorPos(2,5)
    mon.setTextColor(colors.white)
    if votedCount == totalPeople then
        if votes.za > votes.protiv then
            mon.write("REZULTAT: PRINYATO (ZA bolshe)")
        elseif votes.protiv > votes.za then
            mon.write("REZULTAT: OTKLONENO (PROTIV bolshe)")
        else
            mon.write("REZULTAT: RAVENSTVO")
        end
    else
        mon.write("GOLOSOVANIE PRERVANO DOSROCHNO")
    end
    mon.setCursorPos(2,7)
    mon.write("ZA: " .. votes.za .. "   PROTIV: " .. votes.protiv .. "   VOZDERZH: " .. votes.vozderzh)
    sleep(4)
    
    print("Prodolzhit golosovaniya? (y/n):")
    if read() ~= "y" then break end
end
print("Programma zavershena")
