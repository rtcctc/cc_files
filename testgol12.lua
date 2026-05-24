-- =========================================
-- ADVANCED PARLIAMENT SYSTEM (FIXED)
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
    write("STOP side: ") config.stop = read()

    saveConfig()
    print("Saved")
    sleep(1)
end

if not loadConfig() then setupConfig() end

-- =========================================
-- MEETING
-- =========================================

term.clear()
term.setCursorPos(1,1)

write("Meeting topic: ")
local meetingTitle = read()

write("Meeting number: ")
local meetingNumber = read()

-- =========================================
-- PARTICIPANTS
-- =========================================

local participants = {}

print("Participants (0 = finish)")
while true do
    local name = read()
    if name == "0" then break end
    table.insert(participants, name)
end

local participantCount = #participants

-- =========================================
-- UI
-- =========================================

local mw, mh = monitor.getSize()

local splitX = 22
local voteHistory = {}

-- =========================================
-- DRAW HELPERS
-- =========================================

local function clear()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
end

local function writeAt(x,y,text,color,bg)
    if color then monitor.setTextColor(color) end
    if bg then monitor.setBackgroundColor(bg) end
    monitor.setCursorPos(x,y)
    monitor.write(text)
    monitor.setBackgroundColor(colors.black)
end

local function centerText(y,text,color)
    local x = math.floor((mw - #text) / 2)
    writeAt(x,y,text,color)
end

-- =========================================
-- FRAME
-- =========================================

local function drawFrame()

    clear()

    for y=1,mh do
        writeAt(splitX,y,"|",colors.gray)
    end

    for x=1,mw do
        writeAt(x,4,"-",colors.gray)
    end

    centerText(1,"MEETING #" .. meetingNumber,colors.cyan)
    centerText(2,meetingTitle,colors.white)

    writeAt(2,5,"PARTICIPANTS",colors.lime)
    writeAt(splitX+2,5,"ACTIVE VOTE",colors.orange)
    writeAt(splitX+2,7,"TOPIC WINDOW",colors.white)
    writeAt(splitX+2,14,"HISTORY",colors.orange)
end

-- =========================================
-- PARTICIPANTS
-- =========================================

local function drawParticipants()

    local y = 7
    writeAt(2,6,"COUNT: "..participantCount,colors.green)

    for i,name in ipairs(participants) do
        writeAt(2,y,i..". "..name,colors.white)
        y = y + 1
    end
end

-- =========================================
-- HISTORY (WITH STATUS FIX)
-- =========================================

local function drawHistory()

    local startX = splitX + 2
    local startY = 15

    local max = mh - startY + 1

    while #voteHistory > max do
        table.remove(voteHistory,1)
    end

    for i,v in ipairs(voteHistory) do

        local text = v.topic ..
            " Y:"..v.yes..
            " N:"..v.no..
            " A:"..v.abstain

        local color = colors.gray

        if v.status == "ACCEPTED" then color = colors.green end
        if v.status == "REJECTED" then color = colors.red end
        if v.status == "CANCELLED" then color = colors.lightGray end

        writeAt(startX,startY+i-1,text,color)
    end
end

-- =========================================
-- VOTE WINDOW (IMPORTANT FIX)
-- =========================================

local function drawVoteWindow(topic,yes,no,abstain)

    local x0 = splitX + 2
    local width = mw - x0 - 2

    local total = participantCount

    local g = math.floor((yes/total)*width)
    local r = math.floor((no/total)*width)
    local a = math.floor((abstain/total)*width)
    local w = width - (g+r+a)

    local yBar = 9

    -- IMPORTANT: DO NOT FULL CLEAR, ONLY VOTE AREA
    for y=6,12 do
        writeAt(x0,y,string.rep(" ",width))
    end

    writeAt(x0,6,"ACTIVE VOTE",colors.orange)
    writeAt(x0,7,"TOPIC: "..topic,colors.white)

    local x = x0

    for i=1,g do writeAt(x,yBar," ",nil,colors.green) x=x+1 end
    for i=1,r do writeAt(x,yBar," ",nil,colors.red) x=x+1 end
    for i=1,a do writeAt(x,yBar," ",nil,colors.yellow) x=x+1 end
    for i=1,w do writeAt(x,yBar," ",nil,colors.gray) x=x+1 end

    writeAt(x0,11,"Y:"..yes.." N:"..no.." A:"..abstain,colors.white)
end

-- =========================================
-- INIT
-- =========================================

drawFrame()
drawParticipants()
drawHistory()

-- =========================================
-- VOTE
-- =========================================

local voteRunning = false

local function runVote()

    if voteRunning then return end
    voteRunning = true

    term.clear()
    term.setCursorPos(1,1)
    print("NEW VOTE")
    print("Topic:")
    local topic = read()

    local yes,no,abstain = 0,0,0
    local votes = 0

    drawFrame()
    drawParticipants()

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
        drawVoteWindow(topic,yes,no,abstain)
        drawHistory()
    end

    local status = "REJECTED"

    if voteRunning == false and votes < participantCount then
        status = "CANCELLED"
    elseif yes > no then
        status = "ACCEPTED"
    end

    table.insert(voteHistory,{
        topic = topic,
        yes = yes,
        no = no,
        abstain = abstain,
        status = status
    })

    drawHistory()

    local col = colors.red
    if status == "ACCEPTED" then col = colors.green end
    if status == "CANCELLED" then col = colors.lightGray end

    writeAt(splitX+2,13,"RESULT: "..status,col)

    voteRunning = false
end

-- =========================================
-- MAIN
-- =========================================

term.clear()
print("vote / exit")

while true do
    write("> ")
    local c = read()

    if c == "vote" then runVote()
    elseif c == "exit" then break end
end
