-- golosovanie s redstone knopkami + istoriya
-- sides.cfg zapominaet storony knopok

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

-- podklyuchenie monitora
local sides = getSides()
local mon = peripheral.wrap(sides.monitor)
if not mon then error("Monitor na storone " .. sides.monitor .. " ne najden") end
mon.setTextScale(0.75)   -- krupnee, chem 0.5, no ne slishkom
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

-- risovanie poloski (ispravleno: proporcionalno)
local function drawBar(yes, no, abst, total, waiting)
    local w = mon.getSize()
    local barWidth = w - 4
    if barWidth < 5 then barWidth = 5 end
    local y = 8  -- stroka dlya poloski (podberite pod vash monitor)
    
    local segments = {}
    local function addSegments(color, count)
        local len = math.floor(count / total * barWidth)
        for i = 1, len do table.insert(segments, color) end
    end
    
    addSegments(colors.green, yes)
    addSegments(colors.red, no)
    addSegments(colors.yellow, abst)
    addSegments(colors.gray, waiting)
    
    local x = 2
    for _, col in ipairs(segments) do
        mon.setCursorPos(x, y)
        mon.setBackgroundColor(col)
        mon.write(" ")
        x = x + 1
        if x > w then break end
    end
    mon.setBackgroundColor(colors.black)
end

-- funktsiya dlya vyvoda temy i nomera (vsegda sverkhu)
local function drawHeader(topic, num)
    local w = mon.getSize()
    local header = topic .. " " .. num
    local x = math.floor((w - #header) / 2)
    mon.setCursorPos(x, 1)
    mon.setBackgroundColor(colors.black)
    mon.setTextColor(colors.cyan)
    mon.write(header)
    -- risuem ramku
    mon.setCursorPos(1, 1)
    mon.write(string.rep("-", w))
    mon.setCursorPos(1, 2)
    mon.write(string.rep("-", w))
    mon.setCursorPos(1, 1)
end

-- istoriya soobshcheniy (budut nakoplyatsya)
local history = {}  -- massiv strok
local maxHistoryLines = 0 -- ustanovitsya pri zapuske

local function addHistoryLine(line)
    table.insert(history, line)
    -- ogranichim kolichestvo strok po vysote monitora
    local h = mon.getSize()
    local maxLines = h - 10 -- 10 strok zanyato temoy, uchastnikami, poloskoy
    while #history > maxLines do
        table.remove(history, 1)
    end
end

local function redrawHistory()
    local h = mon.getSize()
    local startY = 10 -- nachalo vyvoda istorii
    for i, line in ipairs(history) do
        mon.setCursorPos(2, startY + i - 1)
        mon.setTextColor(colors.lightGray)
        mon.write(string.sub(line, 1, mon.getSize() - 3))
    end
    -- ochistit ostal'nye stroki
    for y = startY + #history, h do
        mon.setCursorPos(2, y)
        mon.write(string.rep(" ", mon.getSize() - 3))
    end
end

-- sohranit tekushiy vopros i rezultat
local function addVoteResult(question, resultText)
    addHistoryLine(question .. ": " .. resultText)
    redrawHistory()
end

-- osnovnaya programma
print("Vvedite temu sobraniya:")
local meetingTopic = read()
print("Vvedite nomer sobraniya:")
local meetingNumber = read()

-- pokazhem temu na ves' monitor
drawHeader(meetingTopic, meetingNumber)
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
print("Nazhmite Enter dlya nachala")
read()

-- vyvedem uchastnikov na monitor (levaya chast)
local function drawParticipants()
    mon.setCursorPos(2, 4)
    mon.setTextColor(colors.lightGray)
    mon.write("Uchastniki ("..totalPeople.."):")
    for i = 1, math.min(8, totalPeople) do
        mon.setCursorPos(2, 4 + i)
        mon.write(" " .. participants[i])
    end
    if totalPeople > 8 then
        mon.setCursorPos(2, 13)
        mon.write(" ...")
    end
end

mon.clear()
drawHeader(meetingTopic, meetingNumber)
drawParticipants()

-- cikl golosovanij
while true do
    print("Vvedite vopros dlya golosovaniya:")
    local question = read()
    if question == "" then break end
    
    -- ochistim oblast' voprosa i poloski (no ne istoriyu)
    local w = mon.getSize()
    for y = 3, 9 do
        mon.setCursorPos(1, y)
        mon.write(string.rep(" ", w))
    end
    
    -- vyvodim vopros po tsentru
    local qx = math.floor((w - #question) / 2)
    mon.setCursorPos(qx, 3)
    mon.setTextColor(colors.white)
    mon.write(question)
    
    local votes = { za = 0, protiv = 0, vozderzh = 0 }
    local votedCount = 0
    local active = true
    
    -- sbros flagov knopok
    local lastZa = rs.getInput(sides.za)
    local lastProtiv = rs.getInput(sides.protiv)
    local lastVozderzh = rs.getInput(sides.vozderzh)
    local lastStop = rs.getInput(sides.stop)
    local lastExit = rs.getInput(sides.exit)
    
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
            mon.setCursorPos(1,1)
            print("EXIT knopka")
            os.exit()
        end
        
        -- obnovim informatsiyu o khode golosovaniya
        mon.setCursorPos(2, 5)
        mon.setTextColor(colors.yellow)
        mon.write("Progolosovalo: " .. votedCount .. " / " .. totalPeople)
        
        -- poloska
        drawBar(votes.za, votes.protiv, votes.vozderzh, totalPeople, totalPeople - votedCount)
        
        -- podskazka
        local h = mon.getSize()
        mon.setCursorPos(2, h-1)
        mon.setTextColor(colors.gray)
        mon.write("Z=Za X=Protiv C=Vozderzh STOP EXIT")
        
        os.sleep(0.05)
    end
    
    -- formiruem rezultat
    local resultText = ""
    if not active then
        resultText = "PRERVANO"
    elseif votedCount == totalPeople then
        if votes.za > votes.protiv then
            resultText = "PRINYATO (" .. votes.za .. " za, " .. votes.protiv .. " protiv)"
        elseif votes.protiv > votes.za then
            resultText = "OTKLONENO (" .. votes.za .. " za, " .. votes.protiv .. " protiv)"
        else
            resultText = "RAVENSTVO (" .. votes.za .. " za, " .. votes.protiv .. " protiv)"
        end
    else
        resultText = "PRERVANO DOSROCHNO"
    end
    
    addVoteResult(question, resultText)
    
    -- ne ochishchaem ekran, prosto perekhodim k sleduyushchemu voprosu
    print("Prodolzhit? (y/n):")
    if read() ~= "y" then break end
end

-- pri zavershenii programmy ochistim monitor
mon.clear()
mon.setCursorPos(1,1)
mon.setTextColor(colors.white)
mon.write("Programma zavershena")
sleep(1)
mon.clear()
print("Konec")
