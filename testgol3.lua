-- Sistema golosovaniya s redstone knopkami
-- Nastrojka storon vypolnitsya pri zapuske

local mon = peripheral.find("monitor") or peripheral.find("advanced_monitor")
if not mon then error("Monitor ne najden") end
mon.setTextScale(0.5)
mon.clear()

-- zapros storon
print("=== NASTROJKA REDSTONE KNOPOK ===")
print("Vvedite storonu dlya ZA (naprimer: front, back, left, right, top, bottom):")
local zaSide = read()
print("Vvedite storonu dlya PROTIV:")
local protivSide = read()
print("Vvedite storonu dlya VOZDERZHALSYA:")
local vozderzhSide = read()
print("Vvedite storonu dlya DOSROCHNOGO OSTANOVA golosovaniya:")
local stopVoteSide = read()
print("Vvedite storonu dlya VYHODA IZ PROGRAMMY:")
local exitSide = read()

-- funktsiya proverki nazhatiya knopki (perekhod signala 0->1)
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

-- vspomogatelnye funktsii dlya risovaniya poloski
local function drawBar(yes, no, abst, total, waiting)
    local w = mon.getSize()
    local barWidth = w - 4
    if barWidth < 5 then barWidth = 5 end
    local y = 8
    
    local segments = {}
    if yes > 0 then
        for i = 1, math.floor(yes / total * barWidth) do
            table.insert(segments, colors.green)
        end
    end
    if no > 0 then
        for i = 1, math.floor(no / total * barWidth) do
            table.insert(segments, colors.red)
        end
    end
    if abst > 0 then
        for i = 1, math.floor(abst / total * barWidth) do
            table.insert(segments, colors.yellow)
        end
    end
    if waiting > 0 then
        for i = 1, math.floor(waiting / total * barWidth) do
            table.insert(segments, colors.gray)
        end
    end
    
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

local function showUI(topic, num, question, participants, votes, totalVoted, totalPeople)
    mon.clear()
    mon.setCursorPos(2,1)
    mon.setTextColor(colors.cyan)
    mon.write(topic .. " " .. num)
    
    mon.setCursorPos(2,3)
    mon.setTextColor(colors.white)
    mon.write("Vopros: " .. question)
    
    mon.setCursorPos(2,4)
    mon.write("Uchastnikov: " .. totalPeople .. "   Progolosovalo: " .. totalVoted)
    
    -- spisok uchastnikov (levaya chast)
    local leftX = 2
    local startY = 6
    mon.setCursorPos(leftX, startY)
    mon.setTextColor(colors.lightGray)
    mon.write("Uchastniki:")
    for i = 1, math.min(10, #participants) do
        mon.setCursorPos(leftX, startY + i)
        mon.write(" " .. participants[i])
    end
    
    -- poloska
    local waiting = totalPeople - totalVoted
    drawBar(votes.za, votes.protiv, votes.vozderzh, totalPeople, waiting)
    
    -- podskazka o knopkah
    local h = mon.getSize()
    mon.setCursorPos(2, h-2)
    mon.setTextColor(colors.gray)
    mon.write("Knopki: ZA | PROTIV | VOZDERZH | STOP VOTE | EXIT")
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
    
    -- sbros flagov dlya oprosa knopok
    lastZa = rs.getInput(zaSide)
    lastProtiv = rs.getInput(protivSide)
    lastVozderzh = rs.getInput(vozderzhSide)
    lastStop = rs.getInput(stopVoteSide)
    lastExit = rs.getInput(exitSide)
    
    while active and votedCount < totalPeople do
        -- proverka knopki ZA
        local pressed, cur = wasPressed(zaSide, lastZa)
        lastZa = cur
        if pressed then
            votes.za = votes.za + 1
            votedCount = votedCount + 1
        end
        
        -- knopka PROTIV
        pressed, cur = wasPressed(protivSide, lastProtiv)
        lastProtiv = cur
        if pressed then
            votes.protiv = votes.protiv + 1
            votedCount = votedCount + 1
        end
        
        -- knopka VOZDERZH
        pressed, cur = wasPressed(vozderzhSide, lastVozderzh)
        lastVozderzh = cur
        if pressed then
            votes.vozderzh = votes.vozderzh + 1
            votedCount = votedCount + 1
        end
        
        -- knopka DOSROCHNOGO OSTANOVA
        pressed, cur = wasPressed(stopVoteSide, lastStop)
        lastStop = cur
        if pressed then
            active = false
            break
        end
        
        -- knopka VYHODA IZ PROGRAMMY
        pressed, cur = wasPressed(exitSide, lastExit)
        lastExit = cur
        if pressed then
            print("Vykhod po knopke EXIT")
            os.exit()
        end
        
        showUI(meetingTopic, meetingNumber, question, participants, votes, votedCount, totalPeople)
        os.sleep(0.05)
    end
    
    -- otobrazit rezultat
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
