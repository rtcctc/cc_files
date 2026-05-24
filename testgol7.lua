-- голосование с кнопками, чёткий интерфейс на 6x3
-- sides.cfg запоминает стороны

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
    
    print("=== ПЕРВЫЙ ЗАПУСК: НАСТРОЙКА СТОРОН ===")
    print("Стороны: front, back, left, right, top, bottom")
    print("Введите сторону для МОНИТОРА (например front):")
    local monSide = read()
    print("Введите сторону для ЗА:")
    local zaSide = read()
    print("Введите сторону для ПРОТИВ:")
    local protivSide = read()
    print("Введите сторону для ВОЗДЕРЖАЛСЯ:")
    local vozderzhSide = read()
    print("Введите сторону для ДОСРОЧНОГО ОСТАНОВА (STOP):")
    local stopSide = read()
    print("Введите сторону для ВЫХОДА (EXIT):")
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
    print("Настройки сохранены в " .. configFile)
    print("Нажмите Enter для продолжения")
    read()
    return sides
end

local sides = getSides()
local mon = peripheral.wrap(sides.monitor)
if not mon then error("Монитор на стороне " .. sides.monitor .. " не найден") end
mon.setTextScale(0.5)  -- мелкий шрифт, чтобы влезло много строк
mon.clear()

-- состояния кнопок
local lastZa = false
local lastProtiv = false
local lastVozderzh = false
local lastStop = false
local lastExit = false

local function wasPressed(side, last)
    local cur = rs.getInput(side)
    if cur and not last then
        return true, cur
    else
        return false, cur
    end
end

-- рисование цветной полоски (пропорционально)
local function drawBar(yes, no, abst, total, waiting)
    local w = mon.getSize()
    local barWidth = w - 6
    if barWidth < 4 then barWidth = 4 end
    local y = 9  -- строка, где будет полоска (подстроено под монитор 12x6)
    
    local seg = {}
    local function add(c, cnt)
        local len = math.floor(cnt / total * barWidth)
        for i = 1, len do table.insert(seg, c) end
    end
    add(colors.green, yes)
    add(colors.red, no)
    add(colors.yellow, abst)
    add(colors.gray, waiting)
    
    local x = 3
    for _, col in ipairs(seg) do
        mon.setCursorPos(x, y)
        mon.setBackgroundColor(col)
        mon.write(" ")
        x = x + 1
        if x > w then break end
    end
    mon.setBackgroundColor(colors.black)
end

local history = {}  -- строки истории

local function addHistory(msg)
    table.insert(history, msg)
    local h = mon.getSize()
    local maxLines = h - 11
    while #history > maxLines do table.remove(history, 1) end
end

local function redrawHistory()
    local h = mon.getSize()
    local startY = 11
    for i, line in ipairs(history) do
        mon.setCursorPos(3, startY + i - 1)
        mon.setTextColor(colors.lightGray)
        mon.write(line)
    end
    -- очистить лишние строки
    for y = startY + #history, h do
        mon.setCursorPos(3, y)
        mon.write(string.rep(" ", mon.getSize() - 4))
    end
end

-- отрисовка верхней рамки с темой собрания
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
    mon.setTextColor(colors.white)
    mon.write(string.rep("=", w))
end

-- отрисовка левой панели (участники)
local participantsList = {}
local function drawParticipants()
    local y = 4
    mon.setCursorPos(2, y)
    mon.setTextColor(colors.lightGray)
    mon.write("Участники (" .. #participantsList .. "):")
    for i = 1, math.min(6, #participantsList) do
        mon.setCursorPos(2, y + i)
        mon.write(" - " .. participantsList[i])
    end
    if #participantsList > 6 then
        mon.setCursorPos(2, y + 7)
        mon.write(" ...")
    end
end

-- отрисовка правой области (текущее голосование)
local function drawVotingArea(question, votedCount, totalPeople)
    local w = mon.getSize()
    local rightX = 15  -- начало правой колонки (при ширине 24 символа)
    mon.setCursorPos(rightX, 4)
    mon.setTextColor(colors.yellow)
    mon.write("ТЕКУЩЕЕ:")
    mon.setCursorPos(rightX, 5)
    mon.setTextColor(colors.white)
    mon.write(question)
    mon.setCursorPos(rightX, 6)
    mon.write("Проголосовало: " .. votedCount .. "/" .. totalPeople)
end

-- подсказка внизу
local function drawHelp()
    local h = mon.getSize()
    mon.setCursorPos(2, h-1)
    mon.setTextColor(colors.gray)
    mon.write("[Z=Za] [X=Protiv] [C=Vozderzh] [STOP] [EXIT]")
end

-- основная программа
print("Введите тему собрания:")
local meetingTopic = read()
print("Введите номер собрания:")
local meetingNumber = read()

mon.clear()
drawHeader(meetingTopic, meetingNumber)
sleep(2)

print("Вводите имена участников (0 - конец):")
while true do
    local name = read()
    if name == "0" then break end
    if name ~= "" then table.insert(participantsList, name) end
end
local totalPeople = #participantsList
if totalPeople == 0 then error("Нет участников") end

print("Список ("..totalPeople.."):")
for i,v in ipairs(participantsList) do print(i..". "..v) end
print("Нажмите Enter для начала")
read()

mon.clear()
drawHeader(meetingTopic, meetingNumber)
drawParticipants()
drawHelp()

local function resetVoting()
    lastZa = rs.getInput(sides.za)
    lastProtiv = rs.getInput(sides.protiv)
    lastVozderzh = rs.getInput(sides.vozderzh)
    lastStop = rs.getInput(sides.stop)
    lastExit = rs.getInput(sides.exit)
end

while true do
    print("Введите вопрос для голосования:")
    local question = read()
    if question == "" then break end
    
    -- очищаем правую область и полоску
    for y = 4, 10 do
        mon.setCursorPos(15, y)
        mon.write(string.rep(" ", mon.getSize() - 14))
    end
    
    drawVotingArea(question, 0, totalPeople)
    
    local votes = { za=0, protiv=0, vozderzh=0 }
    local votedCount = 0
    local active = true
    
    resetVoting()
    
    while active and votedCount < totalPeople do
        local pressed, cur
        
        pressed, cur = wasPressed(sides.za, lastZa)
        lastZa = cur
        if pressed then votes.za = votes.za+1 votedCount = votedCount+1 end
        
        pressed, cur = wasPressed(sides.protiv, lastProtiv)
        lastProtiv = cur
        if pressed then votes.protiv = votes.protiv+1 votedCount = votedCount+1 end
        
        pressed, cur = wasPressed(sides.vozderzh, lastVozderzh)
        lastVozderzh = cur
        if pressed then votes.vozderzh = votes.vozderzh+1 votedCount = votedCount+1 end
        
        pressed, cur = wasPressed(sides.stop, lastStop)
        lastStop = cur
        if pressed then active = false end
        
        pressed, cur = wasPressed(sides.exit, lastExit)
        lastExit = cur
        if pressed then
            mon.clear()
            mon.setCursorPos(1,1)
            print("Выход по кнопке EXIT")
            os.exit()
        end
        
        -- обновляем информацию
        drawVotingArea(question, votedCount, totalPeople)
        drawBar(votes.za, votes.protiv, votes.vozderzh, totalPeople, totalPeople - votedCount)
        drawHelp()
        os.sleep(0.05)
    end
    
    -- формируем результат
    local resultText
    if not active then
        resultText = "ГОЛОСОВАНИЕ ПРЕРВАНО"
    elseif votedCount == totalPeople then
        if votes.za > votes.protiv then
            resultText = "ПРИНЯТО ("..votes.za.." за, "..votes.protiv.." против)"
        elseif votes.protiv > votes.za then
            resultText = "ОТКЛОНЕНО ("..votes.za.." за, "..votes.protiv.." против)"
        else
            resultText = "РАВЕНСТВО ("..votes.za.." за, "..votes.protiv.." против)"
        end
    else
        resultText = "ДОСРОЧНО ОСТАНОВЛЕНО"
    end
    
    addHistory(question .. ": " .. resultText)
    redrawHistory()
    
    print("Продолжить голосования? (y/n):")
    if read() ~= "y" then break end
end

mon.clear()
mon.setCursorPos(2,2)
mon.setTextColor(colors.green)
mon.write("Программа завершена")
sleep(2)
mon.clear()
print("Конец")
