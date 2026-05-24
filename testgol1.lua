-- Sistema golosovaniya na monitor 6x3
-- Klavishi: Z - Za, X - Protiv, C - Vozderzhalcya
-- Ctrl+T - vyhod iz programmy
-- Ctrl+V - dosrochnoe okonchanie golosovaniya

local function connectToMonitor()
    local monitor = peripheral.find("monitor") or peripheral.find("advanced_monitor")
    if not monitor then
        error("Monitor ne najden")
    end
    return monitor
end

local function clearMonitor(monitor)
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

local function drawColoredLine(monitor, startX, y, length, color)
    for i = 1, length do
        monitor.setCursorPos(startX + i - 1, y)
        monitor.setBackgroundColor(color)
        monitor.write(" ")
    end
    monitor.setBackgroundColor(colors.black)
end

local function updateDisplay(monitor, meetingTopic, question, participants, votes, totalVotes, waiting)
    clearMonitor(monitor)
    local width, height = monitor.getSize()
    
    local totalTopic = meetingTopic .. ": " .. question
    local titleX = math.max(1, math.floor((width - #totalTopic) / 2))
    monitor.setCursorPos(titleX, 1)
    monitor.setTextColor(colors.white)
    monitor.write(totalTopic)
    
    -- Levaya chast: uchastniki
    local leftX = 2
    local yStart = 3
    monitor.setCursorPos(leftX, yStart)
    monitor.setTextColor(colors.lightGray)
    monitor.write("Uchastniki: " .. participants.count)
    for i = 1, participants.count do
        monitor.setCursorPos(leftX, yStart + i)
        monitor.write("  - " .. participants.list[i])
    end
    
    -- Pravaya chast: rezultaty
    local halfWidth = math.floor(width / 2)
    local rightX = halfWidth + 2
    monitor.setCursorPos(rightX, yStart - 1)
    monitor.write("Golosovanie: " .. question)
    
    local lineLength = 20
    local startDrawX = rightX + 2
    drawColoredLine(monitor, startDrawX, yStart + 2, lineLength, colors.green)
    drawColoredLine(monitor, startDrawX, yStart + 3, lineLength, colors.red)
    drawColoredLine(monitor, startDrawX, yStart + 4, lineLength, colors.yellow)
    
    if waiting then
        drawColoredLine(monitor, startDrawX, yStart + 5, lineLength, colors.gray)
    end
    
    monitor.setCursorPos(rightX + 2, yStart + 2)
    monitor.write("Za: " .. votes.for .. "   ")
    monitor.setCursorPos(rightX + 2, yStart + 3)
    monitor.write("Protiv: " .. votes.against)
    monitor.setCursorPos(rightX + 2, yStart + 4)
    monitor.write("Vozderzhalcya: " .. votes.abstained)
    
    if waiting then
        monitor.setCursorPos(rightX + 2, yStart + 5)
        monitor.write("Ozhidaetsya: " .. waiting)
    end
    
    if totalVotes > 0 then
        monitor.setCursorPos(rightX, height - 3)
        monitor.write("Progolosovalo: " .. totalVotes .. "/" .. participants.count)
    end
    
    monitor.setCursorPos(1, height)
    monitor.setTextColor(colors.gray)
    monitor.write("[Ctrl+T] Exit  |  [Ctrl+V] Stop voting")
end

local function getVote()
    local keys = {
        [string.byte('z')] = "for",
        [string.byte('x')] = "against",
        [string.byte('c')] = "abstained"
    }
    while true do
        local event, key = os.pullEvent("key")
        if keys[key] then
            return keys[key]
        end
    end
end

local function main()
    print("Podklyuchenie k monitoru...")
    local monitor = connectToMonitor()
    pcall(function() monitor.setTextScale(2) end)
    
    print("Vvedite temu sobraniya:")
    local meetingTopic = read()
    print("Vvedite nomer sobraniya:")
    local meetingNumber = read()
    
    clearMonitor(monitor)
    local width = monitor.getSize()
    local totalTopic = meetingTopic .. " " .. meetingNumber
    local titleX = math.max(1, math.floor((width - #totalTopic) / 2))
    monitor.setCursorPos(titleX, 2)
    monitor.setTextColor(colors.lightBlue)
    monitor.write(totalTopic)
    sleep(3)
    
    print("Vvedite imena uchastnikov. Dlya okonchaniya vvedite 0:")
    local participantsList = {}
    while true do
        local name = read()
        if name == "0" then break end
        if name ~= "" then
            table.insert(participantsList, name)
        end
    end
    
    local participants = { count = #participantsList, list = participantsList }
    if participants.count == 0 then
        error("Spisok uchastnikov pust")
    end
    
    print("Spisok uchastnikov (" .. participants.count .. "):")
    for i, name in ipairs(participants.list) do
        print(i .. ". " .. name)
    end
    print("Nazhmite Enter dlya prodolzheniya...")
    read()
    
    local voted = {}
    for i = 1, participants.count do voted[i] = false end
    
    while true do
        print("Vvedite temu golosovaniya:")
        local question = read()
        if question == "" then break end
        
        local votes = { for = 0, against = 0, abstained = 0 }
        local totalVotes = 0
        for i = 1, participants.count do voted[i] = false end
        
        local votingActive = true
        local coVote = coroutine.create(function()
            while totalVotes < participants.count and votingActive do
                updateDisplay(monitor, meetingTopic, question, participants, votes, totalVotes, participants.count - totalVotes)
                local vote = getVote()
                if vote == "for" then
                    votes.for = votes.for + 1
                elseif vote == "against" then
                    votes.against = votes.against + 1
                elseif vote == "abstained" then
                    votes.abstained = votes.abstained + 1
                end
                totalVotes = totalVotes + 1
            end
        end)
        
        local coStop = coroutine.create(function()
            while true do
                local event, p1 = os.pullEvent()
                if event == "key" and p1 == 47 then -- V
                    votingActive = false
                    break
                elseif event == "terminate" then
                    print("Programma ostanovlena")
                    os.exit()
                end
            end
        end)
        
        while coroutine.status(coVote) ~= "dead" and votingActive do
            coroutine.resume(coVote)
            coroutine.resume(coStop)
            os.sleep(0.05)
        end
        
        updateDisplay(monitor, meetingTopic, question, participants, votes, totalVotes, 0)
        
        if totalVotes == participants.count then
            if votes.for > votes.against then
                monitor.setCursorPos(1, 10)
                monitor.write("REZULTAT: PRINYATO!")
            elseif votes.against > votes.for then
                monitor.setCursorPos(1, 10)
                monitor.write("REZULTAT: OTKLONENO!")
            else
                monitor.setCursorPos(1, 10)
                monitor.write("REZULTAT: RAVENSTVO!")
            end
        else
            monitor.setCursorPos(1, 10)
            monitor.write("GOLOSOVANIE PRERVANO!")
        end
        sleep(5)
        
        print("Prodolzhit? (y/n):")
        local cont = read()
        if cont ~= "y" then
            break
        end
    end
    print("Programma zavershena")
end

local ok, err = pcall(main)
if not ok then
    print("Oshibka: " .. tostring(err))
    print("Nazhmite lyubuyu klavishu")
    os.pullEvent("key")
end
