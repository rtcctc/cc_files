-- golosovanie na monitor 6x3 (textScale 0.5)
-- knopki podklyucheny k redstone, storony zapominayutsya v sides.cfg
-- vse teksty na latinice (translit)

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
    print("=== PERVIY ZAPUSK: NASTROYKA STORON ===")
    print("Storony: front, back, left, right, top, bottom")
    print("Vvedite storonu dlya MONITORA (naprimer front):")
    local monSide = read()
    print("Storona dlya ZA:")
    local zaSide = read()
    print("Storona dlya PROTIV:")
    local protivSide = read()
    print("Storona dlya VOZDERZHALSYA:")
    local vozderzhSide = read()
    print("Storona dlya DOSROCHNOGO OSTANOVA (STOP):")
    local stopSide = read()
    print("Storona dlya VYHODA IZ PROGRAMMY (EXIT):")
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

local sides = getSides()
local mon = peripheral.wrap(sides.monitor)
if not mon then error("Monitor na storone " .. sides.monitor .. " ne najden") end
mon.setTextScale(0.5)   -- 24x12 simvolov
mon.clear()

-- sostoianiya knopok
local lastZa = false
local lastProtiv = false
local lastVozderzh = false
local lastStop = false
local lastExit = false

local function wasPressed(side, last)
    local cur = rs.getInput(side)
    if cur and not last then return true, cur else return false, cur end
end

-- risovanie cvetnoy poloski (proporcionalno)
local function drawBar(yes, no, abst, total, waiting)
    local w = mon.getSize()
    local barWidth = w - 6
    if barWidth < 4 then barWidth = 4 end
    local y = 8  -- stoka dlya poloski (na 24x12)
    local segments = {}
    local function addSeg(col, cnt)
        local len = math.floor(cnt / total * barWidth)
        for i = 1, len do table.insert(segments, col) end
    end
    addSeg(colors.green, yes)
    addSeg(colors.red, no)
    addSeg(colors.yellow, abst)
    addSeg(colors.gray, waiting)
    local x = 3
    for _, col in ipairs(segments) do
        mon.setCursorPos(x, y)
        mon.setBackgroundColor(col)
        mon.write(" ")
        x = x + 1
        if x > w then break end
    end
    mon.setBackgroundColor(colors.black)
end

-- istoriya
local history = {}

local function addHistoryLine(line)
    table.insert(history, line)
    local h = mon.getSize()
    local maxLines = h - 11  -- mesto pod istoriyu (nachinaya s 10 stroki)
    while #history > maxLines do table.remove(history, 1) end
end

local function redrawHistory()
    local h = mon.getSize()
    local startY = 10
    for i, line in ipairs(history) do
        mon.setCursorPos(3, startY + i - 1)
        mon.setTextColor(colors.lightGray)
        mon.write(line)
    end
    for y = startY + #history, h - 1 do
        mon.setCursorPos(3, y)
        mon.write(string.rep(" ", mon.getSize() - 5))
    end
end

-- shapka s temoj (stroki 1-3)
local function drawHeader(topic, num)
    local w = mon.getSize()
    local header = topic .. " " .. num
    local x = math.floor((w - #header) / 2)
    mon.setCursorPos(1, 1)
    mon.setTextColor(colors.white)
    mon.write(string.rep("=", w))
    mon.setCursorPos(x, 2)
    mon.setTextColor(colors.cyan)
    mon.write(header)
    mon.setCursorPos(1, 3)
    mon.write(string.rep("=", w))
end

-- levy blok: uchastniki (nachinaya so stroki 4)
local participants = {}
local function drawParticipants()
    local yStart = 4
    mon.setCursorPos(2, yStart)
    mon.setTextColor(colors.lightGray)
    mon.write("Uchastniki (" .. #participants .. "):")
    for i = 1, math.min(6, #participants) do
        mon.setCursorPos(2, yStart + i)
        mon.write(" - " .. participants[i])
    end
    if #participants > 6 then
        mon.setCursorPos(2, yStart + 7)
        mon.write(" ...")
    end
end

-- pravy blok: tekushee golosovanie (na pravoi polovine)
local function drawVotingArea(question, votedCount, totalPeople)
    local w = mon.getSize()
    local rightX = math.floor(w / 2) + 2
    mon.setCursorPos(rightX, 4)
    mon.setTextColor(colors.yellow)
    mon.write("TEKUSHEE:")
    mon.setCursorPos(rightX, 5)
    mon.setTextColor(colors.white)
    mon.write(question)
    mon.setCursorPos(rightX, 6)
    mon.write("Progolosovalo: " .. votedCount .. "/" .. totalPeople)
end

-- podskazka v nizu
local function drawHelp()
    local h = mon.getSize()
    mon.setCursorPos(2, h)
    mon.setTextColor(colors.gray)
    mon.write("[Z=Za] [X=Protiv] [C=Vozderzh] [STOP] [EXIT]")
end

-- SBROS flagov knopok pered golosovaniem
local function resetButtonsState()
    lastZa = rs.getInput(sides.za)
    lastProtiv = rs.getInput(sides.protiv)
    lastVozderzh = rs.getInput(sides.vozderzh)
    lastStop = rs.getInput(sides.stop)
    lastExit = rs.getInput(sides.exit)
end

-- ========== OSNOVNAYa PROGRAMMA ==========
print("Vvedite temu sobraniya:")
local meetingTopic = read()
print("Vvedite nomer sobraniya:")
local meetingNumber = read()

mon.clear()
drawHeader(meetingTopic, meetingNumber)
sleep(2)

print("Vvodite imena uchastnikov (0 - konetc):")
while true do
    local name = read()
    if name == "0" then break end
    if name ~= "" then table.insert(participants, name) end
end
local totalPeople = #participants
if totalPeople == 0 then error("Net uchastnikov") end

print("Spisok ("..totalPeople.."):")
for i, v in ipairs(participants) do print(i..". "..v) end
print("Nazhmite Enter dlya nachala")
read()

mon.clear()
drawHeader(meetingTopic, meetingNumber)
drawParticipants()
drawHelp()

-- cikl golosovanij
while true do
    print("Vvedite vopros dlya golosovaniya:")
    local question = read()
    if question == "" then break end

    -- ochistka pravoi oblasti i poloski
    local w = mon.getSize()
    local rightX = math.floor(w / 2) + 2
    for y = 4, 9 do
        mon.setCursorPos(rightX, y)
        mon.write(string.rep(" ", w - rightX + 1))
    end

    drawVotingArea(question, 0, totalPeople)

    local votes = { za = 0, protiv = 0, vozderzh = 0 }
    local votedCount = 0
    local active = true

    resetButtonsState()

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
        if pressed then active = false end

        pressed, cur = wasPressed(sides.exit, lastExit)
        lastExit = cur
        if pressed then
            mon.clear()
            mon.setCursorPos(1,1)
            print("EXIT knopka")
            os.exit()
        end

        -- obnovlenie ekrana
        drawVotingArea(question, votedCount, totalPeople)
        drawBar(votes.za, votes.protiv, votes.vozderzh, totalPeople, totalPeople - votedCount)
        drawHelp()
        os.sleep(0.05)
    end

    -- formirovanie rezultata
    local resultText
    if not active then
        resultText = "GOLOSOVANIE PRERVANO"
    elseif votedCount == totalPeople then
        if votes.za > votes.protiv then
            resultText = "PRINYATO (" .. votes.za .. " za, " .. votes.protiv .. " protiv)"
        elseif votes.protiv > votes.za then
            resultText = "OTKLONENO (" .. votes.za .. " za, " .. votes.protiv .. " protiv)"
        else
            resultText = "RAVENSTVO (" .. votes.za .. " za, " .. votes.protiv .. " protiv)"
        end
    else
        resultText = "DOSROCHNO OSTATOVLENO"
    end

    addHistoryLine(question .. ": " .. resultText)
    redrawHistory()
    drawHelp()

    print("Prodolzhit? (y/n):")
    if read() ~= "y" then break end
end

mon.clear()
mon.setCursorPos(2,2)
mon.setTextColor(colors.green)
mon.write("Programma zavershena")
sleep(2)
mon.clear()
print("Konec")
