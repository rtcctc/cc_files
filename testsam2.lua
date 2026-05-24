-- =========================================
--   Parliament Vote System for CC:Tweaked
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

    write("Side for YES button: ")
    config.yes = read()

    write("Side for NO button: ")
    config.no = read()

    write("Side for ABSTAIN button: ")
    config.abstain = read()

    write("Side for STOP button: ")
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
print("Type 0 to finish")
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
-- DRAW UI
-- =========================================

local function clearMonitor()

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
end

local function centerText(y, text, color)

    local w, h = monitor.getSize()

    monitor.setTextColor(color or colors.white)

    local x = math.floor((w - #text) / 2)

    monitor.setCursorPos(x, y)
    monitor.write(text)
end

local function drawBorders()

    local w, h = monitor.getSize()

    monitor.setTextColor(colors.gray)

    -- Vertical line
    for y = 1, h do
        monitor.setCursorPos(math.floor(w / 2), y)
        monitor.write("|")
    end

    -- Horizontal line
    for x = 1, w do
        monitor.setCursorPos(x, 5)
        monitor.write("-")
    end
end

local function drawParticipants()

    monitor.setTextColor(colors.lime)

    monitor.setCursorPos(2, 3)
    monitor.write("Participants: " .. participantCount)

    local y = 7

    for i, name in ipairs(participants) do

        monitor.setCursorPos(2, y)
        monitor.setTextColor(colors.white)
        monitor.write(i .. ". " .. name)

        y = y + 1
    end
end

local function drawBaseUI()

    clearMonitor()

    drawBorders()

    centerText(1, "MEETING #" .. meetingNumber, colors.cyan)
    centerText(2, meetingTitle, colors.white)

    drawParticipants()
end

drawBaseUI()

-- =========================================
-- VOTE BAR
-- =========================================

local function drawVoteBar(yes, no, abstain)

    local w, h = monitor.getSize()

    local total = participantCount

    local pending = total - yes - no - abstain

    local startX = math.floor(w / 2) + 2
    local barY = 10

    local barWidth = math.floor(w / 2) - 5

    monitor.setCursorPos(startX, 7)
    monitor.setTextColor(colors.orange)
    monitor.write("VOTING")

    local function calc(value)
        return math.floor((value / total) * barWidth)
    end

    local greenW = calc(yes)
    local redW = calc(no)
    local yellowW = calc(abstain)

    local used = greenW + redW + yellowW
    local grayW = barWidth - used

    local x = startX

    -- YES
    monitor.setBackgroundColor(colors.green)

    for i = 1, greenW do
        monitor.setCursorPos(x, barY)
        monitor.write(" ")
        x = x + 1
    end

    -- NO
    monitor.setBackgroundColor(colors.red)

    for i = 1, redW do
        monitor.setCursorPos(x, barY)
        monitor.write(" ")
        x = x + 1
    end

    -- ABSTAIN
    monitor.setBackgroundColor(colors.yellow)

    for i = 1, yellowW do
        monitor.setCursorPos(x, barY)
        monitor.write(" ")
        x = x + 1
    end

    -- WAITING
    monitor.setBackgroundColor(colors.gray)

    for i = 1, grayW do
        monitor.setCursorPos(x, barY)
        monitor.write(" ")
        x = x + 1
    end

    monitor.setBackgroundColor(colors.black)

    -- Stats

    monitor.setCursorPos(startX, 12)
    monitor.setTextColor(colors.green)
    monitor.write("YES: " .. yes)

    monitor.setCursorPos(startX, 13)
    monitor.setTextColor(colors.red)
    monitor.write("NO: " .. no)

    monitor.setCursorPos(startX, 14)
    monitor.setTextColor(colors.yellow)
    monitor.write("ABSTAIN: " .. abstain)

    monitor.setCursorPos(startX, 15)
    monitor.setTextColor(colors.lightGray)
    monitor.write("WAIT: " .. pending)
end

-- =========================================
-- VOTING
-- =========================================

local voteRunning = false

local function runVote()

    if voteRunning then
        print("Vote already running")
        return
    end

    voteRunning = true

    term.setCursorPos(1,20)
    term.clearLine()

    write("Vote topic: ")
    local topic = read()

    drawBaseUI()

    local w, h = monitor.getSize()

    local rightX = math.floor(w / 2) + 2

    monitor.setCursorPos(rightX, 4)
    monitor.setTextColor(colors.white)
    monitor.write(topic)

    local yes = 0
    local no = 0
    local abstain = 0

    local votes = 0

    drawVoteBar(yes, no, abstain)

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

        drawVoteBar(yes, no, abstain)
    end

    monitor.setCursorPos(rightX, 18)

    if yes > no then

        monitor.setTextColor(colors.green)
        monitor.write("RESULT: ACCEPTED")

    else

        monitor.setTextColor(colors.red)
        monitor.write("RESULT: REJECTED")
    end

    voteRunning = false
end

-- =========================================
-- MAIN LOOP
-- =========================================

term.clear()

print("Commands:")
print("vote      - start voting")
print("stopvote  - stop current vote")
print("exit      - shutdown")
print()

while true do

    write("> ")

    local cmd = read()

    if cmd == "vote" then

        runVote()

    elseif cmd == "stopvote" then

        voteRunning = false

    elseif cmd == "exit" then

        term.clear()
        term.setCursorPos(1,1)

        print("Program stopped")

        break
    end
end
