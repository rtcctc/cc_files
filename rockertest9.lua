-- ============================================================================
-- AVTOPILOT BALLISTICHESKOY RAKETY (CC: Sable + Create)
-- S stabilizatsiey na vzlyote i myagkim razvorotom
-- ============================================================================

-- ------------------------- NACHTROYKI --------------------------------------
local CRUISE_ALT = 80
local CLIMB_PITCH = math.rad(30)
local DIVE_PITCH = math.rad(-45)
local TURN_THRESHOLD = math.rad(5)    -- 5 gradusov
local DIVE_DIST = 200
local IMPACT_DIST = 15

local BASE_THRUST_CLIMB = 8
local BASE_THRUST_CRUISE = 6
local MAX_CORR = 3.0

-- PID dlya stabilizatsii kursa na vzlyote (slabyy, tolko chtoby ne uhodil)
local PID_YAW_CLIMB = {Kp=0.2, Ki=0, Kd=0.3, int=0, last_err=0}
-- PID dlya plavnogo razvorota
local PID_YAW_TURN = {Kp=0.3, Ki=0,   Kd=0.6, int=0, last_err=0}
local PID_YAW_CRUISE = {Kp=0.8, Ki=0.02, Kd=0.8, int=0, last_err=0}
local PID_PITCH_CRUISE = {Kp=0.5, Ki=0.01, Kd=0.4, int=0, last_err=0}
local PID_PITCH_DIVE = {Kp=0.6, Ki=0, Kd=0.5, int=0, last_err=0}
local PID_ALT = {Kp=0.8, Ki=0.01, Kd=0.3, int=0, last_err=0}

-- Dampirovanie po ryoskaniyu i krenu
local YAW_DAMPING = 0.3    -- chem vyshe, tem sil'nee tormozhenie vrascheniya
local ROLL_DAMPING = 0.5
local MAX_ROLL_DAMP = 1.5

local CORR_RATE_LIMIT = 1.5   -- plavnost povorota

-- Minimalnaya vertikalnaya skorost dlya nachala razvorota (m/s)
local MIN_VY_FOR_TURN = 15

-- ------------------------- FUNKCII -----------------------------------------
function setEngine(side, value)
    value = math.floor(math.max(0, math.min(15, value)))
    redstone.setAnalogOutput(side, value)
end

function setAllEngines(L, R, F, B)
    setEngine("left", L)
    setEngine("right", R)
    setEngine("front", F)
    setEngine("back", B)
end

function math.sign(x)
    return x>0 and 1 or x<0 and -1 or 0
end

-- Konversiya kvaterniona v ugly (podderzhka raznyh formatov)
function getAnglesFromOrientation(orientation)
    if orientation.toEuler then
        return orientation:toEuler()
    end
    if orientation.x and orientation.y and orientation.z and orientation.w then
        local x, y, z, w = orientation.x, orientation.y, orientation.z, orientation.w
        local sinr_cosp = 2 * (w * x + y * z)
        local cosr_cosp = 1 - 2 * (x * x + y * y)
        local roll = math.atan2(sinr_cosp, cosr_cosp)
        local sinp = 2 * (w * y - z * x)
        local pitch = (math.abs(sinp) >= 1) and (math.pi/2 * math.sign(sinp)) or math.asin(sinp)
        local siny_cosp = 2 * (w * z + x * y)
        local cosy_cosp = 1 - 2 * (y * y + z * z)
        local yaw = math.atan2(siny_cosp, cosy_cosp)
        return pitch, yaw, roll
    end
    if orientation[1] and orientation[2] and orientation[3] and orientation[4] then
        local x, y, z, w = orientation[1], orientation[2], orientation[3], orientation[4]
        local sinr_cosp = 2 * (w * x + y * z)
        local cosr_cosp = 1 - 2 * (x * x + y * y)
        local roll = math.atan2(sinr_cosp, cosr_cosp)
        local sinp = 2 * (w * y - z * x)
        local pitch = (math.abs(sinp) >= 1) and (math.pi/2 * math.sign(sinp)) or math.asin(sinp)
        local siny_cosp = 2 * (w * z + x * y)
        local cosy_cosp = 1 - 2 * (y * y + z * z)
        local yaw = math.atan2(siny_cosp, cosy_cosp)
        return pitch, yaw, roll
    end
    print("Ne udałos' poluchit' ugly. Tip: " .. type(orientation))
    return 0, 0, 0
end

function getShipData()
    if not sublevel.isInPlotGrid() then
        return nil
    end
    local pose = sublevel.getLogicalPose()
    local pos = pose.position
    local vel = sublevel.getVelocity()
    local angVel = sublevel.getAngularVelocity()
    local pitch, yaw, roll = getAnglesFromOrientation(pose.orientation)
    return {
        x = pos.x, y = pos.y, z = pos.z,
        vx = vel.x, vy = vel.y, vz = vel.z,
        yaw = yaw, pitch = pitch, roll = roll,
        yaw_rate = angVel.y,
        roll_rate = angVel.z
    }
end

function pidUpdate(pid, error, dt)
    pid.int = pid.int + error * dt
    local i_max = 5
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

-- ------------------------- OSNOVNOJ CIKL -----------------------------------
local target = {x = 1000, z = 0, y = 0}
local state = "CLIMB"
local lastTime = os.clock()
local last_yaw_corr = 0
local last_pitch_corr = 0
local start_yaw = nil   -- zapomnim kurs pri starte

print("Avtopilot zapushen. Cel: X=" .. target.x .. " Z=" .. target.z)

while true do
    local now = os.clock()
    local dt = now - lastTime
    if dt < 0.01 then
        sleep(0.01)
        dt = os.clock() - lastTime
    end
    lastTime = now
    
    local data = getShipData()
    if not data then
        print("Net dannyh ot sublevel")
        sleep(1)
    else
        local x, y, z = data.x, data.y, data.z
        local cur_yaw = data.yaw
        local cur_pitch = data.pitch
        local vy = data.vy
        local yaw_rate = data.yaw_rate
        local roll_rate = data.roll_rate
        
        -- Zafiksirovat' startovyy kurs pri pervom shage
        if start_yaw == nil then
            start_yaw = cur_yaw
            print("Startovyy kurs: " .. math.deg(start_yaw) .. "°")
        end
        
        local dx = target.x - x
        local dz = target.z - z
        local dy = target.y - y
        local horDist = math.sqrt(dx*dx + dz*dz)
        local fullDist = math.sqrt(horDist*horDist + dy*dy)
        
        local des_yaw = math.atan2(dx, dz)
        local des_pitch = math.atan2(dy, horDist)
        
        local yaw_err = normalizeAngle(des_yaw - cur_yaw)
        
        -- ------------------------- FAZY -----------------------------------
        if state == "CLIMB" then
            -- Uslovie perekhoda: dostignuta vysota I dostatochna vertikalnaya skorost'
            if y >= CRUISE_ALT - 10 and vy >= MIN_VY_FOR_TURN then
                state = "TURN"
                print(">>> Perehod k razvorotu (vysota " .. y .. ", vy=" .. vy .. ")")
                -- Sbros integralov PID
                PID_YAW_TURN.int = 0; PID_YAW_TURN.last_err = 0
            end
        elseif state == "TURN" then
            if math.abs(yaw_err) < TURN_THRESHOLD then
                state = "CRUISE"
                print(">>> Razvorot zavershen")
            end
        elseif state == "CRUISE" then
            if fullDist < DIVE_DIST then
                state = "DIVE"
                print(">>> Pikirovanie")
            end
        elseif state == "DIVE" then
            if fullDist < IMPACT_DIST then
                setAllEngines(0, 0, 0, 0)
                print(">>> POPADANIE!")
                break
            end
        end
        
        -- ------------------------- VYChISLENIE KORREKCIY -------------------
        local target_yaw, target_pitch
        local yaw_corr, pitch_corr
        
        if state == "CLIMB" then
            -- Stabiliziruem startovyy kurs, ne pozvolyaya ukhodit'
            target_yaw = start_yaw
            target_pitch = CLIMB_PITCH
            local yaw_err_cmd = normalizeAngle(target_yaw - cur_yaw)
            yaw_corr = pidUpdate(PID_YAW_CLIMB, yaw_err_cmd, dt)
            pitch_corr = 0   -- tank podderzhivaet zadannyy pitch avtomaticheski
        elseif state == "TURN" then
            target_yaw = des_yaw
            target_pitch = 0
            local yaw_err_cmd = normalizeAngle(target_yaw - cur_yaw)
            yaw_corr = pidUpdate(PID_YAW_TURN, yaw_err_cmd, dt)
            pitch_corr = 0
        elseif state == "CRUISE" then
            target_yaw = des_yaw
            local alt_err = CRUISE_ALT - y
            local alt_corr = pidUpdate(PID_ALT, alt_err, dt)
            alt_corr = math.max(-0.3, math.min(0.3, alt_corr))
            target_pitch = alt_corr
            local yaw_err_cmd = normalizeAngle(target_yaw - cur_yaw)
            local pitch_err_cmd = target_pitch - cur_pitch
            yaw_corr = pidUpdate(PID_YAW_CRUISE, yaw_err_cmd, dt)
            pitch_corr = pidUpdate(PID_PITCH_CRUISE, pitch_err_cmd, dt)
        else -- DIVE
            target_yaw = des_yaw
            target_pitch = DIVE_PITCH
            local yaw_err_cmd = normalizeAngle(target_yaw - cur_yaw)
            local pitch_err_cmd = target_pitch - cur_pitch
            yaw_corr = pidUpdate(PID_YAW_CRUISE, yaw_err_cmd, dt)
            pitch_corr = pidUpdate(PID_PITCH_DIVE, pitch_err_cmd, dt)
        end
        
        -- Dampirovanie po ryoskaniyu (protivodeystvie vrascheniyu)
        local yaw_damping = -yaw_rate * YAW_DAMPING
        yaw_corr = yaw_corr + yaw_damping
        
        -- Ogranichenie korrekcii
        yaw_corr = math.max(-MAX_CORR, math.min(MAX_CORR, yaw_corr))
        pitch_corr = math.max(-MAX_CORR, math.min(MAX_CORR, pitch_corr))
        
        -- Dampirovanie krena
        local roll_corr = -roll_rate * ROLL_DAMPING
        roll_corr = math.max(-MAX_ROLL_DAMP, math.min(MAX_ROLL_DAMP, roll_corr))
        
        -- Rate limiting
        local max_change = CORR_RATE_LIMIT * dt
        if math.abs(yaw_corr - last_yaw_corr) > max_change then
            yaw_corr = last_yaw_corr + math.sign(yaw_corr - last_yaw_corr) * max_change
        end
        if math.abs(pitch_corr - last_pitch_corr) > max_change then
            pitch_corr = last_pitch_corr + math.sign(pitch_corr - last_pitch_corr) * max_change
        end
        last_yaw_corr = yaw_corr
        last_pitch_corr = pitch_corr
        
        local base = (state == "CLIMB") and BASE_THRUST_CLIMB or BASE_THRUST_CRUISE
        local L = base - yaw_corr - roll_corr
        local R = base + yaw_corr + roll_corr
        local F = base - pitch_corr
        local B = base + pitch_corr
        
        setAllEngines(L, R, F, B)
        
        if math.floor(now) % 2 == 0 then
            print(string.format("[%s] Y:%.1f D:%.0f Yerr:%.1f° Vy:%.1f Yrate:%.2f",
                state, y, fullDist, math.deg(yaw_err), vy, yaw_rate))
        end
    end
    sleep(0.05)
end
