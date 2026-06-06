-- ==================================================
-- Автопилот баллистической ракеты
-- Управление 4 двигателями через redstone.setOutput
-- Требуется CC: Sable на борту
-- ==================================================

-- ---------- НАСТРОЙКИ ----------
local CRUISE_ALT = 80          -- высота крейсерского полёта
local CLIMB_PITCH = math.rad(30)   -- угол набора высоты
local DIVE_PITCH = math.rad(-45)   -- угол пикирования
local TURN_THRESHOLD = math.rad(5) -- порог завершения разворота
local DIVE_DIST = 200          -- дистанция до цели для начала пикирования
local IMPACT_DIST = 15         -- дистанция для отключения двигателей

local BASE_THRUST = 8
local MAX_CORR = 5

-- ПИД-коэффициенты
local PID_YAW   = {Kp=2.0, Ki=0.05, Kd=0.8, int=0, last_err=0}
local PID_PITCH = {Kp=1.5, Ki=0.02, Kd=0.5, int=0, last_err=0}
local PID_ALT   = {Kp=1.2, Ki=0.01, Kd=0.3, int=0, last_err=0}

-- ---------- ФУНКЦИИ ----------
function setEngine(side, value)
    value = math.floor(math.max(0, math.min(15, value)))
    redstone.setOutput(side, value)
end

function setAllEngines(L, R, F, B)
    setEngine("left", L)
    setEngine("right", R)
    setEngine("front", F)
    setEngine("back", B)
end

function getShipData()
    local ship = sable.getShipController()
    if not ship then return nil end
    -- Проверяем наличие методов (на случай отличий в API)
    if not ship.getPosition or not ship.getYaw then return nil end
    local pos = ship.getPosition()
    local vel = ship.getVelocity()
    return {
        x = pos.x, y = pos.y, z = pos.z,
        vx = vel.x, vy = vel.y, vz = vel.z,
        yaw = ship.getYaw(),
        pitch = ship.getPitch(),
        roll = ship.getRoll()
    }
end

function pidUpdate(pid, error, dt)
    pid.int = pid.int + error * dt
    local i_max = 10
    pid.int = math.max(-i_max, math.min(i_max, pid.int))
    local derivative = (error - pid.last_err) / dt
    pid.last_err = error
    return pid.Kp * error + pid.Ki * pid.int + pid.Kd * derivative
end

function normalizeAngle(angle)
    angle = angle % (2 * math.pi)
    if angle > math.pi then angle = angle - 2 * math.pi end
    return angle
end

-- ---------- ОСНОВНОЙ ЦИКЛ ----------
local target = {x = 1000, z = 0, y = 0}
local state = "CLIMB"
local lastTime = os.clock()

print("Автопилот запущен. Цель: X=" .. target.x .. " Z=" .. target.z)

while true do
    local now = os.clock()
    local dt = now - lastTime
    if dt < 0.01 then
        sleep(0.01)
        now = os.clock()
        dt = now - lastTime
    end
    lastTime = now

    local data = getShipData()
    if not data then
        print("Ошибка: нет данных от CC: Sable")
        sleep(1)
    else
        local x, y, z = data.x, data.y, data.z
        local cur_yaw = data.yaw
        local cur_pitch = data.pitch

        local dx = target.x - x
        local dz = target.z - z
        local dy = target.y - y
        local horDist = math.sqrt(dx*dx + dz*dz)
        local fullDist = math.sqrt(horDist*horDist + dy*dy)

        local des_yaw = math.atan2(dx, dz)
        local des_pitch = math.atan2(dy, horDist)

        local yaw_err = normalizeAngle(des_yaw - cur_yaw)
        local pitch_err = des_pitch - cur_pitch

        -- Фазовые переходы
        if state == "CLIMB" then
            if y >= CRUISE_ALT - 3 then
                state = "TURN"
                print(">>> Набор высоты завершён, разворот к цели")
            end
        elseif state == "TURN" then
            if math.abs(yaw_err) < TURN_THRESHOLD then
                state = "CRUISE"
                print(">>> Разворот завершён, крейсерский полёт")
            end
        elseif state == "CRUISE" then
            if fullDist < DIVE_DIST then
                state = "DIVE"
                print(">>> Переход в пикирование")
            end
        elseif state == "DIVE" then
            if fullDist < IMPACT_DIST then
                setAllEngines(0, 0, 0, 0)
                print(">>> ПОПАДАНИЕ! Двигатели отключены.")
                break
            end
        end

        -- Целевые углы в зависимости от фазы
        local target_yaw, target_pitch
        if state == "CLIMB" then
            target_yaw = cur_yaw
            target_pitch = CLIMB_PITCH
        elseif state == "TURN" then
            target_yaw = des_yaw
            target_pitch = 0
        elseif state == "CRUISE" then
            target_yaw = des_yaw
            local alt_err = CRUISE_ALT - y
            local alt_corr = pidUpdate(PID_ALT, alt_err, dt)
            alt_corr = math.max(-0.3, math.min(0.3, alt_corr))
            target_pitch = alt_corr
        else -- DIVE
            target_yaw = des_yaw
            target_pitch = DIVE_PITCH
        end

        local yaw_err_cmd = normalizeAngle(target_yaw - cur_yaw)
        local pitch_err_cmd = target_pitch - cur_pitch

        local yaw_corr = pidUpdate(PID_YAW, yaw_err_cmd, dt)
        local pitch_corr = pidUpdate(PID_PITCH, pitch_err_cmd, dt)

        yaw_corr = math.max(-MAX_CORR, math.min(MAX_CORR, yaw_corr))
        pitch_corr = math.max(-MAX_CORR, math.min(MAX_CORR, pitch_corr))

        local L = BASE_THRUST - yaw_corr
        local R = BASE_THRUST + yaw_corr
        local F = BASE_THRUST - pitch_corr
        local B = BASE_THRUST + pitch_corr

        setAllEngines(L, R, F, B)

        if math.floor(now) % 2 == 0 then
            print(string.format("[%s] Y:%.1f  Дист:%.0f  ОшYaw:%.1f°  ОшPitch:%.1f°",
                state, y, fullDist, math.deg(yaw_err_cmd), math.deg(pitch_err_cmd)))
        end
    end -- if data
    sleep(0.05)
end
