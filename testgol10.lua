-- =========================================
--   PARLIAMENT SYSTEM FIXED VERSION
--   CC:TWEAKED (ASCII ONLY)
-- =========================================

local CONFIG_FILE = "vote_config"

local monitor = peripheral.find("monitor")
if not monitor then error("Monitor not found") end

monitor.setTextScale(0.5)

-- =========================================
-- CONFIG
-- =========================================

local config = {}

local function saveConfig()
    local f = fs.open(CONFIG_FILE, "w")
    f.write(textutils.serialize(config))
    f.close()
end

local function loadConfig()
    if fs.exists(CONFIG_FILE) then
        local f = fs.open(CONFIG_FILE, "r")
        config = textutils.unserialize(f.readAll())
        f.close()
        return true
    end
    return false
end

local function setupConfig()
    term.clear()
    term.setCursorPos(1,1)

    print("FIRST SETUP")
    print()

    write("YES side: ") config.yes = read()
    write("NO side: ") config.no = read()
    write("ABSTAIN side: ") config.abstain = read()
    write("STOP (button): ") config.stop = read()

    saveConfig()

    print("Saved")
    sleep(1)
end

if not loadConfig() then setupConfig() end

-- =========================================
-- SETUP MEETING
-- =========================================

term.clear()
term.setCursorPos(1,1)

write("Meeting title: ")
local meetingTitle = read()

write("Meeting number: ")
local meetingNumber = read()

-- =========================================
-- PARTICIPANTS
-- =========================================

local participants = {}

print()
print("Participants (0 = finish)")
print()

while true do
    local name = read()
    if name == "0" then break end
    table.insert(participants, name)
end

local participantCount = #participants

-- =========================================
-- LAYOUT
-- =========================================

local mw, mh = monitor.getSize()

local splitX = math.floor(mw * 0.35) -- fixed better balance
local historyY = math.floor(mh * 0.55)

local history = {}

-- =========================================
-- DRAW HELPERS
-- =========================================

local function clear()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
end

local function put(x,y,text,color,bg)
    if color then monitor.setTextColor(color) end
    if bg then monitor.setBackgroundColor(bg) end
    monitor.setCursorPos(x,y)
    monitor.write(text)
    monitor.setBackgroundColor(colors.black)
end

local function center(y,text,color)
    local x = math.floor((mw - #text) / 2)
    put(x,y,text,color)
end

-- =========================================
-- FRAME
-- =========================================

local function drawFrame()

    clear()

    -- vertical split
    for y=1,mh do
        put(splitX,y,"|",colors.gray)
    end

    -- horizontal split (history)
    for x=1,mw do
        put(x,historyY,"-",colors.gray)
    end

    center(1,"MEETING #" .. meetingNumber,colors.cyan)
    center(2,meetingTitle,colors.white)

    put(2,4,"PARTICIPANTS",colors.lime)
    put(splitX+2,4,"ACTIVE VOTE",colors.orange)
    put(splitX+2,historyY+1,"HISTORY",colors.orange)
end

-- =========================================
-- PARTICIPANTS
-- =========================================

local function drawParticipants()

    put(2,5,"COUNT: "..participantCount,colors.green)

    local y = 7
    for i,name in ipairs(participants) do
        put(2,y,i..". "..name,colors.white)
        y = y + 1
    end
end

-- =========================================
-- HISTORY
-- =========================================

local function drawHistory()

    local startY = historyY + 2
    local max = mh - startY + 1

    while #history > max do
        table.remove(history,1)
    end

    for i,v in ipairs(history) do

        local result = (v.yes > v.no) and "ACCEPT" or "REJECT"
        local col = (result == "ACCEPT") and colors.green or colors.red

        local text =
            v.topic ..
            " Y:"..v.yes..
            " N:"..v.no..
            " A:"..v.abstain

        put(splitX+2,startY+i-1,text,col)
    end
end

-- =========================================
-- VOTE WINDOW
-- =========================================

local function drawVote(topic,yes,no,abstain)

    local x0 = splitX + 2
    local width = mw - x0 - 2

    local total = participantCount
    local done = yes + no + abstain
    local wait = total - done

    local function part(v)
        return math.floor((v/total)*width)
    end

    local g = part(yes)
    local r = part(no)
    local a = part(abstain)
    local gray = width - (g+r+a)

    local yBar = 7

    put(x0,5,"TOPIC: "..topic,colors.white)

    local x = x0

    for i=1,g do put(x,yBar," ",nil,colors.green) x=x+1 end
    for i=1,r do put(x,yBar," ",nil,colors.red) x=x+1 end
    for i=1,a do put(x,yBar," ",nil,colors.yellow) x=x+1 end
    for i=1,gray do put(x,yBar," ",nil,colors.gray) x=x+1 end

    put(x0,yBar+2,
        "Y:"..yes.." N:"..no.." A:"..abstain.." W:"..wait,
        colors.white)
end

-- =========================================
-- INIT DRAW
-- =========================================

drawFrame()
drawParticipants()
drawHistory()

-- =========================================
-- VOTING
-- =========================================

local voteRunning = false

local function runVote()

    if voteRunning then return end
    voteRunning = true

    -- IMPORTANT: explicit topic ask HERE
    term.setCursorPos(1,20)
    term.clearLine()
    write("VOTE TOPIC: ")
    local topic = read()

    local yes,no,abstain = 0,0,0
    local votes = 0

    drawFrame()

    while votes < participantCount and voteRunning do

        os.pullEvent("redstone")

        if redstone.getInput(config.yes) then
            yes = yes + 1
            votes = votes + 1

        elseif redstone.getInput(config.no) then
            no = no + 1
            votes = votes + 1

        elseif redstone.getInput(config.abstain) then
            abstain = abstain + 1
            votes = votes + 1

        elseif redstone.getInput(config.stop) then
            voteRunning = false
            break
        end

        drawFrame()
        drawParticipants()
        drawVote(topic,yes,no,abstain)
        drawHistory()
    end

    table.insert(history,{
        topic = topic,
        yes = yes,
        no = no,
        abstain = abstain
    })

    drawHistory()

    local result = (yes > no) and "ACCEPTED" or "REJECTED"
    local col = (yes > no) and colors.green or colors.red

    put(splitX+2,historyY-1,"RESULT: "..result,col)

    voteRunning = false
end

-- =========================================
-- MAIN LOOP
-- =========================================

term.clear()
print("Commands: vote / exit")

while true do
    write("> ")
    local c = read()

    if c == "vote" then
        runVote()
    elseif c == "exit" then
        break
    end
end
