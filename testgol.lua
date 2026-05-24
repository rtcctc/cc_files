-- Система управления голосованием на мониторе 6x3.
-- Автоматически подключается к монитору.
-- Для выхода из программы в любой момент нажмите Ctrl+T.
-- Для досрочного завершения активного голосования нажмите Ctrl+V.

-- Функция для подключения к монитору.
local function connectToMonitor()
    local monitor = peripheral.find("monitor") or peripheral.find("advanced_monitor")
    if not monitor then
        error("Монитор не найден. Пожалуйста, установите монитор рядом с компьютером.")
    end
    return monitor
end

-- Функция для очистки монитора и установки курсора в начало.
local function clearMonitor(monitor)
    monitor.clear()
    monitor.setCursorPos(1, 1)
end

-- Функция для рисования цветной линии на мониторе.
local function drawColoredLine(monitor, startX, y, length, color)
    for i = 1, length do
        monitor.setCursorPos(startX + i - 1, y)
        monitor.setBackgroundColor(color)
        monitor.write(" ")
    end
    monitor.setBackgroundColor(colors.black)
end

-- Функция для отображения интерфейса.
local function updateDisplay(monitor, topic, question, participants, votes, totalVotes, waiting)
    clearMonitor(monitor)
    local width, height = monitor.getSize()
    
    -- Вычисляем среднюю точку для заголовка.
    local totalTopic = topic .. ": " .. question
    local titleX = math.max(1, math.floor((width - #totalTopic) / 2))
    monitor.setCursorPos(titleX, 1)
    monitor.setTextColor(colors.white)
    monitor.write(totalTopic)
    
    -- Отображение участников в левой части.
    local leftX = 2
    local yStart = 3
    monitor.setCursorPos(leftX, yStart)
    monitor.setTextColor(colors.lightGray)
    monitor.write("Участники: " .. participants.count)
    for i = 1, participants.count do
        monitor.setCursorPos(leftX, yStart + i)
        monitor.write("  - " .. participants.list[i])
    end
    
    -- Отображение темы и текущих результатов в правой части.
    local halfWidth = math.floor(width / 2)
    local rightX = halfWidth + 2
    local rightWidth = width - halfWidth - 2
    if rightWidth < 10 then rightWidth = 10 end
    
    monitor.setCursorPos(rightX, yStart - 1)
    monitor.write("Голосование: " .. question)
    
    -- Рисуем цветную линию.
    local lineLength = math.min(rightWidth - 2, 20)
    local startDrawX = rightX + 2
    drawColoredLine(monitor, startDrawX, yStart + 2, lineLength, colors.green)
    drawColoredLine(monitor, startDrawX, yStart + 3, lineLength, colors.red)
    drawColoredLine(monitor, startDrawX, yStart + 4, lineLength, colors.yellow)
    
    if waiting then
        drawColoredLine(monitor, startDrawX, yStart + 5, lineLength, colors.gray)
    end
    
    -- Отображаем результаты.
    monitor.setCursorPos(rightX + 2, yStart + 2)
    monitor.write("За: " .. votes.for .. "   ")
    monitor.setCursorPos(rightX + 2, yStart + 3)
    monitor.write("Против: " .. votes.against)
    monitor.setCursorPos(rightX + 2, yStart + 4)
    monitor.write("Воздержался: " .. votes.abstained)
    
    if waiting then
        monitor.setCursorPos(rightX + 2, yStart + 5)
        monitor.write("Ожидание: " .. waiting)
    end
    
    -- Статистика.
    if totalVotes > 0 then
        monitor.setCursorPos(rightX, height - 3)
        monitor.write("Проголосовало: " .. totalVotes .. "/" .. participants.count)
    end
    
    monitor.setCursorPos(1, height)
    monitor.setTextColor(colors.gray)
    monitor.write("[Ctrl+T] для выхода | [Ctrl+V] для досрочного завершения")
end

-- Функция для получения голоса от участника.
local function getVote(monitor, participants, currentVotes, voted, totalVotes)
    local keys = {
        [string.byte('z')] = "for",
        [string.byte('x')] = "against",
        [string.byte('c')] = "abstained"
    }
    
    while true do
        local event, key = os.pullEvent("key")
        local voteType = keys[key]
        if voteType then
            return voteType
        end
    end
end

-- Запуск программы.
local function main()
    print("Подключение к монитору...")
    local monitor = connectToMonitor()
    
    -- Настройка масштаба для монитора 6x3.
    -- Для Advanced Monitor: monitor.setTextScale(2)
    -- Для обычного: monitor.setTextScale(2)
    -- (Пропускаем, если не поддерживается)
    local ok, err = pcall(function() monitor.setTextScale(2) end)
    if not ok then
        print("Настройка масштаба монитора не поддерживается.")
    end
    
    print("Введите тему собрания:")
    local meetingTopic = read()
    print("Введите номер собрания:")
    local meetingNumber = read()
    
    -- Отображаем тему и номер на весь экран.
    clearMonitor(monitor)
    local width = monitor.getSize()
    local totalTopic = meetingTopic .. " " .. meetingNumber
    local titleX = math.max(1, math.floor((width - #totalTopic) / 2))
    monitor.setCursorPos(titleX, 2)
    monitor.setTextColor(colors.lightBlue)
    monitor.write(totalTopic)
    sleep(3)
    
    print("Введите имена участников. Для завершения введите '0':")
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
        error("Список участников не может быть пустым.")
    end
    
    print("Список участников (" .. participants.count .. "):")
    for i, name in ipairs(participants.list) do
        print(i .. ". " .. name)
    end
    print("Нажмите Enter для продолжения...")
    read()
    
    local voted = {}
    for i = 1, participants.count do voted[i] = false end
    
    while true do
        print("Введите тему для голосования:")
        local question = read()
        if question == "" then
            print("Тема голосования не может быть пустой.")
            return
        end
        
        -- Сброс результатов голосования.
        local votes = { for = 0, against = 0, abstained = 0 }
        local totalVotes = 0
        for i = 1, participants.count do voted[i] = false end
        
        -- Функция для обработки голосования.
        local function runVoting()
            while totalVotes < participants.count do
                updateDisplay(monitor, meetingTopic, question, participants, votes, totalVotes, participants.count - totalVotes)
                
                local vote = getVote(monitor, participants, votes, voted, totalVotes)
                
                -- Обработка голоса.
                if vote == "for" then
                    votes.for = votes.for + 1
                elseif vote == "against" then
                    votes.against = votes.against + 1
                elseif vote == "abstained" then
                    votes.abstained = votes.abstained + 1
                end
                totalVotes = totalVotes + 1
            end
        end
        
        -- Функция для проверки досрочного завершения.
        local function checkEarlyStop()
            while true do
                os.pullEvent("key")
                -- Здесь мы ждем комбинацию клавиш. В Lua сложно отследить Ctrl+V напрямую,
                -- поэтому мы проверим, не пришел ли символ 'v' с нажатым Ctrl.
                -- Однако, более простой способ — использовать отдельный обработчик прерываний.
                -- Для простоты мы будем проверять глобальный флаг terminate.
                if os.pullEvent() == "terminate" then
                    return true
                end
            end
        end
        
        -- Запускаем голосование и обработчик прерываний параллельно.
        local running = true
        local co1 = coroutine.create(function() runVoting() end)
        local co2 = coroutine.create(function() 
            while running do
                local event, p1, p2, p3 = os.pullEvent()
                if event == "key" and p1 == 47 then -- Код клавиши V (47)
                    print("Голосование досрочно завершено.")
                    running = false
                    break
                elseif event == "terminate" then
                    print("Программа прервана.")
                    os.exit()
                end
            end
        end)
        
        local status
        while true do
            if coroutine.status(co1) == "dead" then
                status = "finished"
                break
            elseif coroutine.status(co2) == "dead" then
                status = "stopped"
                break
            end
            coroutine.resume(co1)
            coroutine.resume(co2)
            os.sleep(0.1)
        end
        
        updateDisplay(monitor, meetingTopic, question, participants, votes, totalVotes, 0)
        
        if status == "finished" then
            -- Определяем победителя.
            if votes.for > votes.against then
                monitor.setCursorPos(1, 10)
                monitor.write("РЕЗУЛЬТАТ: ПРИНЯТО!")
            elseif votes.against > votes.for then
                monitor.setCursorPos(1, 10)
                monitor.write("РЕЗУЛЬТАТ: ОТКЛОНЕНО!")
            else
                monitor.setCursorPos(1, 10)
                monitor.write("РЕЗУЛЬТАТ: РАВЕНСТВО!")
            end
            sleep(5)
        else
            monitor.setCursorPos(1, 10)
            monitor.write("ГОЛОСОВАНИЕ ПРЕРВАНО!")
            sleep(5)
        end
        
        print("Продолжить голосование? (y/n):")
        local cont = read()
        if cont ~= "y" then
            break
        end
    end
    
    print("Программа завершена.")
end

-- Запуск основной программы.
local ok, err = pcall(main)
if not ok then
    print("Ошибка: " .. tostring(err))
    print("Нажмите любую клавишу для выхода...")
    os.pullEvent("key")
end
