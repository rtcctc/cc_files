-- =========================================
--   PARLIAMENT VOTE SYSTEM (CC:TWEAKED)
--   TOP: ACTIVE VOTE
--   BOTTOM: HISTORY
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

print("Participants (0 = end)")
while true do
    local n = read()
    if n == "0" then break end
    table.insert(participants, n)
end

local participantCount = #participants

-- =========================================
-- UI LAYOUT
-- =========================================

local mw, mh = monitor.getSize()

local historyStartY = math.floor(mh / 2) + 2
local voteAreaHeight = historyStartY - 2

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

local function center(y,text,color)
    local x = math.floor((mw - #text) / 2)
    writeAt(x,y,text,color)
end

-- =========================================
-- STATIC FRAME
-- =========================================

local function drawFrame()

    clear()

    -- separator line
    for x=1,mw do
        writeAt(x,historyStartY,"-",colors.gray)
    end

    center(1,"MEETING #" .. meetingNumber,colors.cyan)
    center(2,meetingTitle,colors.white)

    writeAt(2,4,"ACTIVE VOTE",colors.orange)
    writeAt(2,historyStartY+1,"HISTORY",colors.orange)
end

-- =========================================
-- HISTORY
-- =========================================

local function drawHistory()

    local y = historyStartY + 2

    local max = mh - y + 1

    while #voteHistory > max do
        table.remove(voteHistory,1)
    end

    for i=1,max do
        writeAt(2,y+i-1,string.rep(" ",mw-2))
    end

    for i,v in ipairs(voteHistory) do

        local result = v.yes > v.no and "ACCEPT" or "REJECT"

        local col = (result=="ACCEPT") and colors.green or colors.red

        local text =
            v.topic ..
            " Y:"..v.yes..
            " N:"..v.no..
            " A:"..v.abstain

        writeAt(2,y+i-1,text,col)
    end
end

-- =========================================
-- ACTIVE VOTE WINDOW
-- =========================================

local function drawVote(topic,yes,no,abstain)

    local x0 = 2
    local x1 = mw - 2

    local width = x1 - x0

    local total = participantCount
    local done = yes + no + abstain
    local wait = total - done

    local function part(n)
        return math.floor((n/total)*width)
    end

    local g = part(yes)
    local r = part(no)
    local y = part(abstain)
    local gr = width - (g+r+y)

    local barY = 6

    writeAt(x0,4,"VOTE: "..topic,colors.white)

    local x = x0

    for i=1,g do writeAt(x,barY," ",nil,colors.green) x=x+1 end
    for i=1,r do writeAt(x,barY," ",nil,colors.red) x=x+1 end
    for i=1,y do writeAt(x,barY," ",nil,colors.yellow) x=x+1 end
    for i=1,gr do writeAt(x,barY," ",nil,colors.gray) x=x+1 end

    writeAt(x0,barY+2,"Y:"..yes.." N:"..no.." A:"..abstain.." W:"..wait,colors.white)
end

-- =========================================
-- INIT DRAW
-- =========================================

drawFrame()
drawHistory()

-- =========================================
-- VOTING
-- =========================================

local voteRunning = false

local function runVote()

    if voteRunning then return end
    voteRunning = true

    term.setCursorPos(1,20)
    term.clearLine()

    write("Topic: ")
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
        drawVote(topic,yes,no,abstain)
        drawHistory()
    end

    local accepted = yes > no

    table.insert(voteHistory,{
        topic = topic,
        yes = yes,
        no = no,
        abstain = abstain
    })

    drawHistory()

    writeAt(2,historyStartY-1,
        "RESULT: " .. (accepted and "ACCEPTED" or "REJECTED"),
        accepted and colors.green or colors.red
    )

    voteRunning = false
end

-- =========================================
-- MAIN LOOP
-- =========================================

term.clear()
print("vote / stopvote / exit")

while true do
    write("> ")
    local c = read()

    if c == "vote" then runVote()
    elseif c == "stopvote" then voteRunning = false
    elseif c == "exit" then break end
end
