-- =========================================
--   PARLIAMENT SYSTEM FINAL VERSION
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
    write("STOP side: ") config.stop = read()

    saveConfig()
    print("Saved")
    sleep(1)
end

if not loadConfig() then setupConfig() end

-- =========================================
-- MEETING INFO
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

print("Participants (0 = finish)")
while true do
    local name = read()
    if name == "0" then break end
    table.insert(participants, name)
end

local participantCount = #participants

-- =========================================
-- UI SETUP
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

    -- separator
    for y=1,mh do
        writeAt(splitX,y,"|",colors.gray)
    end

    -- top line
    for x=1,mw do
        writeAt(x,4,"-",colors.gray)
    end

    centerText(1,"MEETING #" .. meetingNumber,colors.cyan)
    centerText(2,meetingTitle,colors.white)

    writeAt(2,5,"PARTICIPANTS",colors.lime)

    writeAt(splitX+2,14,"HISTORY",colors.orange)
    writeAt(splitX+2,15,"----------------------",colors.gray)
end

-- =========================================
-- PARTICIPANTS
-- =========================================

local function drawParticipants()

    writeAt(2,6,"COUNT: "..participantCount,colors.green)

    local y = 7
    for i,name in ipairs(participants) do
        writeAt(2,y,i..". "..name,colors.white)
        y = y + 1
    end
end

-- =========================================
-- HISTORY
-- =========================================

local function drawHistory()

    local startX = splitX + 2
    local startY = 16   -- shifted down (important)

    local max = mh - startY + 1

    while #voteHistory > max do
        table.remove(voteHistory,1)
    end

    for i,v in ipairs(voteHistory) do

        local text = v.topic ..
            " Y:"..v.yes..
            " N:"..v.no..
            " A:"..v.abstain

        local col = colors.gray

        if v.status == "ACCEPTED" then col = colors.green end
        if v.status == "REJECTED" then col = colors.red end
        if v.status == "CANCELLED" then col = colors.lightGray end

        writeAt(startX,startY+i-1,text,col)
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

    local g = math.floor((yes/total)*width)
    local r = math.floor((no/total)*width)
    local a = math.floor((abstain/total)*width)
    local w = width - (g+r+a)

    local barY = 9

    -- clear vote area only
    for y=6,12 do
        writeAt(x0,y,string.rep(" ",width))
    end

    writeAt(x0,6,"TOPIC: "..topic,colors.white)

    local x = x0

    for i=1,g do writeAt(x,barY," ",nil,colors.green) x=x+1 end
    for i=1,r do writeAt(x,barY," ",nil,colors.red) x=x+1 end
    for i=1,a do writeAt(x,barY," ",nil,colors.yellow) x=x+1 end
    for i=1,w do writeAt(x,barY," ",nil,colors.gray) x=x+1 end

    writeAt(x0,11,
        "Y:"..yes.." N:"..no.." A:"..abstain.." W:"..wait,
        colors.white)
end

-- =========================================
-- INIT DRAW (NO VOTE WINDOW HERE!)
-- =========================================

drawFrame()
drawParticipants()
drawHistory()

-- =========================================
-- VOTE SYSTEM
-- =========================================

local voteRunning = false

local function runVote()

    if voteRunning then return end
    voteRunning = true

    -- CLEAR AND ASK TOPIC (VISIBLE FIX)
    term.clear()
    term.setCursorPos(1,1)

    print("NEW VOTE")
    print("Enter topic:")
    local topic = read()

    local yes,no,abstain = 0,0,0
    local votes = 0

    -- FIRST REAL RENDER ONLY NOW
    drawFrame()
    drawParticipants()
    drawHistory()

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

    local status

    if not voteRunning and votes < participantCount then
        status = "CANCELLED"
    elseif yes > no then
        status = "ACCEPTED"
    else
        status = "REJECTED"
    end

    table.insert(voteHistory,{
        topic = topic,
        yes = yes,
        no = no,
        abstain = abstain,
        status = status
    })

    drawHistory()

    writeAt(splitX+2,13,
        "RESULT: "..status,
        status=="ACCEPTED" and colors.green
        or status=="REJECTED" and colors.red
        or colors.lightGray
    )

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

    if c == "vote" then runVote()
    elseif c == "exit" then break end
end
