-- =========================================
--        ADVANCED PARLIAMENT SYSTEM
--              CC:Tweaked
-- =========================================

local CONFIG_FILE = "vote_config"

local monitor = peripheral.find("monitor")

if not monitor then
    error("Monitor not found")
end

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

    print("=== FIRST SETUP ===")
    print()

    write("YES button side: ")
    config.yes = read()

    write("NO button side: ")
    config.no = read()

    write("ABSTAIN button side: ")
    config.abstain = read()

    write("STOP button side: ")
    config.stop = read()

    saveConfig()

    print()
    print("Config saved")
    sleep(2)
end

if not loadConfig() then
    setupConfig()
end

-- =========================================
-- MEETING DATA
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

print()
print("Enter participants")
print("0 = finish")
print()

while true do

    local name = read()

    if name == "0" then
        break
    end

    table.insert(participants, name)
end

local participantCount = #participants

-- =========================================
-- UI SETTINGS
-- =========================================

local mw, mh = monitor.getSize()

local splitX = 22

local voteHistory = {}

-- =========================================
-- DRAW HELPERS
-- =========================================

local function clear()

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
end

local function writeAt(x,y,text,color,bg)

    if color then
        monitor.setTextColor(color)
    end

    if bg then
        monitor.setBackgroundColor(bg)
    end

    monitor.setCursorPos(x,y)
    monitor.write(text)

    monitor.setBackgroundColor(colors.black)
end

local function centerText(y,text,color)

    local x = math.floor((mw - #text) / 2)

    writeAt(x,y,text,color)
end

-- =========================================
-- STATIC UI
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
    writeAt(splitX + 2,5,"VOTE HISTORY",colors.orange)
end

-- =========================================
-- PARTICIPANTS
-- =========================================

local function drawParticipants()

    local y = 7

    writeAt(2,6,"Count: " .. participantCount,colors.green)

    for i,name in ipairs(participants) do
        writeAt(2,y,i .. ". " .. name,colors.white)
        y = y + 1
    end
end

-- =========================================
-- HISTORY
-- =========================================

local function drawHistory()

    local startX = splitX + 2
    local startY = 7

    local maxEntries = mh - startY - 1

    while #voteHistory > maxEntries do
        table.remove(voteHistory,1)
    end

    for i=1,maxEntries do
        writeAt(startX,startY + i - 1,
            string.rep(" ",mw - startX))
    end

    for i,entry in ipairs(voteHistory) do

        local text =
            entry.topic ..
            " [" ..
            entry.yes .. "/" ..
            entry.no .. "/" ..
            entry.abstain .. "]"

        local color = entry.accepted and colors.green or colors.red

        writeAt(startX,startY + i - 1,text,color)
    end
end

-- =========================================
-- VOTE WINDOW (TOP RIGHT FIXED POSITION)
-- =========================================

local function drawVoteWindow(topic,yes,no,abstain)

    local startX = splitX + 2
    local width = mw - startX - 2

    local total = participantCount
    local voted = yes + no + abstain
    local waiting = total - voted

    local greenW = math.floor((yes / total) * width)
    local redW = math.floor((no / total) * width)
    local yellowW = math.floor((abstain / total) * width)
    local grayW = width - (greenW + redW + yellowW)

    local yBar = 9  -- ВАЖНО: чуть выше истории

    -- CLEAR ONLY VOTE AREA (НЕ ВСЁ)
    for y=6,12 do
        writeAt(startX,y,string.rep(" ",width))
    end

    writeAt(startX,6,"ACTIVE VOTE",colors.orange)
    writeAt(startX,7,"TOPIC: "..topic,colors.white)

    local x = startX

    for i=1,greenW do writeAt(x,yBar," ",nil,colors.green) x=x+1 end
    for i=1,redW do writeAt(x,yBar," ",nil,colors.red) x=x+1 end
    for i=1,yellowW do writeAt(x,yBar," ",nil,colors.yellow) x=x+1 end
    for i=1,grayW do writeAt(x,yBar," ",nil,colors.gray) x=x+1 end

    writeAt(startX,yBar+2,
        "Y:"..yes.." N:"..no.." A:"..abstain.." W:"..waiting,
        colors.white)
end

-- =========================================
-- INIT
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

    -- FIX: visible input prompt
    term.clear()
    term.setCursorPos(1,1)
    print("=== NEW VOTE ===")
    print("Enter topic:")

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

    local accepted = yes > no

    table.insert(voteHistory,{
        topic = topic,
        yes = yes,
        no = no,
        abstain = abstain,
        accepted = accepted
    })

    drawHistory()

    writeAt(splitX+2,5,
        "RESULT: "..(accepted and "ACCEPTED" or "REJECTED"),
        accepted and colors.green or colors.red
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
