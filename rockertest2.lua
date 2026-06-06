-- ==================================================
-- Avtopilot ballisticheskoy rakety (CC: Sable API)
-- Upravlenie 4 dvigatelyami cherez redstone.setOutput
-- ==================================================

-- ---------- NASTROYKI ----------
local CRUISE_ALT = 80
local CLIMB_PITCH = math.rad(30)
local DIVE_PITCH = math.rad(-45)
local TURN_THRESHOLD = math.rad(5)
local DIVE_DIST = 200
local IMPACT_DIST = 15

local BASE_THRUST = 8
local MAX_CORR = 5

-- PID koeffitsienty
local PID_YAW   = {Kp=2.0, Ki=0.05, Kd=0.8, int=0, last_err=0}
local PID_PITCH = {Kp=1.5, Ki=0.02, Kd=0.5, int=0, last_err=0}
local PID_ALT   = {Kp=1.2, Ki=0.01, Kd=0.3, int=0, last_err=0}

-- ---------- FUNKTSII ----------
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

-- Poluchenie dannyh ot sublevel API
function getShipData()
    if not sublevel.isInPlotGrid() then
        return nil
    end
    local pose = sublevel.getLogicalPose()
    local pos = pose.position
    local vel = sublevel.getVelocity()
    -- Poluchaem uglы (yaw, pitch, roll) iz kvaternionа
    local orientation = pose.orientation
    local angles = quaternion.toEuler(orientation)
    
    return {
        x = pos.x, y = pos.y, z = pos.z,
        vx = vel.x, vy = vel.y, vz = vel.z,
        yaw = angles.yaw,
        pitch = angles.pitch,
        roll = angles.roll
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

-- ---------- OSNOVNOY CIKL ----------
local target = {x = 1000, z = 0, y = 0}
local state = "CLIMB"
local lastTime = os.clock()

print("Avtopilot zapushen. Tsel: X=" .. target.x .. " Z=" .. target.z)

while true do
    local now = os.clock()
    local dt = now - lastTime
    if dt < 0.01 then sleep(0.01) dt = os.clock() - lastTime end
    lastTime = now

    local data = getShipData()
    if not data then
        print("Oshibka: net dannyh ot CC: Sable. Raketa ne na sub-urovne?")
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

        -- Perekluchenie faz
        if state == "CLIMB" and y >= CRUISE_ALT - 3 then
            state = "TURN"
            print(">>> Nabor vysoty zavershen, razvorot k tseli")
        elseif state == "TURN" and math.abs(yaw_err) < TURN_THRESHOLD then
            state = "CRUISE"
            print(">>> Razvorot zavershen, kreyserskiy polyot")
        elseif state == "CRUISE" and fullDist < DIVE_DIST then
            state = "DIVE"
            print(">>> Perekhod v pikirovanie")
        elseif state == "DIVE" and fullDist < IMPACT_DIST then
            setAllEngines(0, 0, 0, 0)
            print(">>> POPADANIE! Dvigateli otklyucheny.")
            break
        end

        -- Tselevye ugly v zavisimosti ot fazy
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
            print(string.format("[%s] Y:%.1f  Dist:%.0f  OshYaw:%.1f°  OshPitch:%.1f°",
                state, y, fullDist, math.deg(yaw_err_cmd), math.deg(pitch_err_cmd)))
        end
    end
    sleep(0.05)
end
