-- ============================================================================
-- AVTOPILOT RAKETY S LOKALNOY SISTEMOY KOORDINAT
-- Fazy: CLIMB -> TURN -> CRUISE -> DIVE
-- ============================================================================

-- ------------------------- NACHTROYKI --------------------------------------
local CRUISE_ALT = 80
local CLIMB_PITCH = 30      -- v gradusah
local DIVE_PITCH = -45
local TURN_THRESHOLD_DEG = 5
local DIVE_DIST = 200
local IMPACT_DIST = 15

local BASE_THRUST_CLIMB = 8
local BASE_THRUST_CRUISE = 6
local MAX_CORR = 3.0

-- PID dlya ryoskaniya (yaw) i tangaja (pitch), rabotayut v lokalnykh oshibkakh
local PID_YAW_TURN = {Kp=0.4, Ki=0, Kd=0.5, int=0, last_err=0}
local PID_YAW_CRUISE = {Kp=0.8, Ki=0.02, Kd=0.8, int=0, last_err=0}
local PID_PITCH_CRUISE = {Kp=0.5, Ki=0.01, Kd=0.4, int=0, last_err=0}
local PID_PITCH_DIVE = {Kp=0.6, Ki=0, Kd=0.5, int=0, last_err=0}
local PID_ALT = {Kp=0.8, Ki=0.01, Kd=0.3, int=0, last_err=0}

-- Dampirovanie
local YAW_DAMPING = 0.3
local ROLL_DAMPING = 0.5
local MAX_ROLL_DAMP = 1.5
local CORR_RATE_LIMIT = 1.5
local MIN_VY_FOR_TURN = 15

-- ------------------------- FUNKCII DLYA RABOTY S VEKTORAMI I UGLAMI --------
function math.sign(x) return x>0 and 1 or x<0 and -1 or 0 end
function degToRad(deg) return deg * math.pi / 180 end
function radToDeg(rad) return rad * 180 / math.pi end

function rotateVectorByQuaternion(v, q)
    -- Vrashchaet vektor v s pomoshchyu kvaterniona q
    local qx, qy, qz, qw = q.x, q.y, q.z, q.w
    local vx, vy, vz = v.x, v.y, v.z
    local ix =  (qw * vx + qy * vz - qz * vy) * 2
    local iy =  (qw * vy + qz * vx - qx * vz) * 2
    local iz =  (qw * vz + qx * vy - qy * vx) * 2
    return {
        x = vx + ix * qw + (qy * iz - qz * iy),
        y = vy + iy * qw + (qz * ix - qx * iz),
        z = vz + iz * qw + (qx * iy - qy * ix)
    }
end

function getAnglesFromOrientation(orientation)
    if orientation.toEuler then return orientation:toEuler() end
    if orientation.x and orientation.y and orientation.z and orientation.w then
        local x, y, z, w = orientation.x, orientation.y, orientation.z, orientation.w
        local roll = math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y))
        local sinp = 2 * (w * y - z * x)
        local pitch = math.abs(sinp) >= 1 and math.pi/2 * math.sign(sinp) or math.asin(sinp)
        local yaw = math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z))
        return pitch, yaw, roll
    end
    print("Ne udałos' poluchit' ugly iz orientation.")
    return 0, 0, 0
end

function getShipData()
    if not sublevel.isInPlotGrid() then return nil end
    local pose = sublevel.getLogicalPose()
    local pos = pose.position
    local vel = sublevel.getVelocity()
    local angVel = sublevel.getAngularVelocity()
    local pitch, yaw, roll = getAnglesFromOrientation(pose.orientation)
    return {
        x = pos.x, y = pos.y, z = pos.z,
        vx = vel.x, vy = vel.y, vz = vel.z,
        yaw = yaw, pitch = pitch, roll = roll,
        yaw_rate = angVel.y, roll_rate = angVel.z,
        orientation = pose.orientation
    }
end

function pidUpdate(pid, error, dt)
    pid.int = pid.int + error * dt
    pid.int = math.max(-5, math.min(5, pid.int))
    local derivative = (error - pid.last_err) / dt
    pid.last_err = error
    return pid.Kp * error + pid.Ki * pid.int + pid.Kd * derivative
end

function setEngine(side, value)
    value = math.floor(math.max(0, math.min(15, value)))
    redstone.setAnalogOutput(side, value)
end
function setAllEngines(L, R, F, B)
    setEngine("left", L); setEngine("right", R)
    setEngine("front", F); setEngine("back", B)
end

-- ------------------------- OSNOVNOY CIKL -----------------------------------
local target = {x = 1000, z = 0, y = 0}
local state = "CLIMB"
local lastTime = os.clock()
local last_yaw_corr, last_pitch_corr = 0, 0

print("Avtopilot zapushen. Cel: X=" .. target.x .. " Z=" .. target.z)

while true do
    local now = os.clock()
    local dt = now - lastTime
    if dt < 0.01 then sleep(0.01) dt = os.clock() - lastTime end
    lastTime = now
    
    local data = getShipData()
    if not data then print("Net dannyh ot sublevel"); sleep(1) 
    else
        local x, y, z = data.x, data.y, data.z
        local cur_pitch_deg = radToDeg(data.pitch)
        local cur_yaw_deg = radToDeg(data.yaw)
        local vy = data.vy
        local yaw_rate, roll_rate = data.yaw_rate, data.roll_rate
        
        -- Vektor do celi v mirovykh koordinatakh
        local dx, dz, dy = target.x - x, target.z - z, target.y - y
        local horDist = math.sqrt(dx*dx + dz*dz)
        local fullDist = math.sqrt(horDist*horDist + dy*dy)
        
        -- 1. Poluchaem vektor do celi v LOKALNYKH koordinatakh rakety
        local worldVec = {x=dx, y=dy, z=dz}
        local localVec = rotateVectorByQuaternion(worldVec, data.orientation)
        localVec = {x=localVec.x, y=localVec.y, z=localVec.z}
        
        -- 2. Vychislyaem lokalnye ugly do celi
        local local_yaw_rad = math.atan2(localVec.x, localVec.z)
        local horLen = math.sqrt(localVec.x*localVec.x + localVec.z*localVec.z)
        local local_pitch_rad = math.atan2(-localVec.y, horLen)
        local local_yaw_deg = radToDeg(local_yaw_rad)
        local local_pitch_deg = radToDeg(local_pitch_rad)
        
        -- Dlya perekhoda v fazu TURN ispolzuem absolyutnuyu oshibku yaw v gradusah
        local yaw_err_deg = (math.deg(math.atan2(dx, dz)) - cur_yaw_deg + 180) % 360 - 180
        
        -- 3. Fazy poleta (logika bez izmeneniy)
        if state == "CLIMB" then
            if y >= CRUISE_ALT - 10 and vy >= MIN_VY_FOR_TURN then
                state = "TURN"; print(">>> Perehod k razvorotu")
                PID_YAW_TURN.int, PID_YAW_TURN.last_err = 0, 0
            end
        elseif state == "TURN" then
            if math.abs(yaw_err_deg) < TURN_THRESHOLD_DEG then
                state = "CRUISE"; print(">>> Razvorot zavershen")
            end
        elseif state == "CRUISE" and fullDist < DIVE_DIST then
            state = "DIVE"; print(">>> Pikirovanie")
        elseif state == "DIVE" and fullDist < IMPACT_DIST then
            setAllEngines(0, 0, 0, 0); print(">>> POPADANIE!"); break
        end
        
        -- 4. Vybor tselevogo uglya (teper v LOKALNYKH koordinatakh) i raschet korrektsii
        local target_local_yaw, target_local_pitch = 0, 0
        local yaw_corr, pitch_corr = 0, 0
        if state == "CLIMB" then
            target_local_pitch = degToRad(CLIMB_PITCH)
            pitch_corr = (target_local_pitch - data.pitch) * 0.5
            yaw_corr = -yaw_rate * YAW_DAMPING
        elseif state == "TURN" then
            target_local_yaw = 0
            local pid_error_yaw = target_local_yaw - local_yaw_rad
            yaw_corr = pidUpdate(PID_YAW_TURN, pid_error_yaw, dt)
            pitch_corr = 0
        elseif state == "CRUISE" then
            target_local_yaw, target_local_pitch = 0, 0
            local alt_err = CRUISE_ALT - y
            local alt_corr = pidUpdate(PID_ALT, alt_err, dt)
            target_local_pitch = math.max(-0.3, math.min(0.3, alt_corr))
            local yaw_pid_error = target_local_yaw - local_yaw_rad
            local pitch_pid_error = target_local_pitch - local_pitch_rad
            yaw_corr = pidUpdate(PID_YAW_CRUISE, yaw_pid_error, dt)
            pitch_corr = pidUpdate(PID_PITCH_CRUISE, pitch_pid_error, dt)
        else -- DIVE
            target_local_pitch = degToRad(DIVE_PITCH)
            local pitch_pid_error = target_local_pitch - local_pitch_rad
            pitch_corr = pidUpdate(PID_PITCH_DIVE, pitch_pid_error, dt)
            local yaw_pid_error = target_local_yaw - local_yaw_rad
            yaw_corr = pidUpdate(PID_YAW_CRUISE, yaw_pid_error, dt)
        end
        
        yaw_corr = math.max(-MAX_CORR, math.min(MAX_CORR, yaw_corr + (-yaw_rate * YAW_DAMPING)))
        pitch_corr = math.max(-MAX_CORR, math.min(MAX_CORR, pitch_corr))
        local roll_corr = math.max(-MAX_ROLL_DAMP, math.min(MAX_ROLL_DAMP, -roll_rate * ROLL_DAMPING))
        
        local max_change = CORR_RATE_LIMIT * dt
        if math.abs(yaw_corr - last_yaw_corr) > max_change then yaw_corr = last_yaw_corr + math.sign(yaw_corr - last_yaw_corr) * max_change end
        if math.abs(pitch_corr - last_pitch_corr) > max_change then pitch_corr = last_pitch_corr + math.sign(pitch_corr - last_pitch_corr) * max_change end
        last_yaw_corr, last_pitch_corr = yaw_corr, pitch_corr
        
        local base = state == "CLIMB" and BASE_THRUST_CLIMB or BASE_THRUST_CRUISE
        local L = base - yaw_corr - roll_corr
        local R = base + yaw_corr + roll_corr
        local F = base - pitch_corr
        local B = base + pitch_corr
        setAllEngines(L, R, F, B)
        
        if math.floor(now) % 2 == 0 then
            print(string.format("[%s] H:%.0f D:%.0f V:%.1f Ly:%.1f° Lp:%.1f°",
                state, y, fullDist, vy, local_yaw_deg, local_pitch_deg))
        end
    end
    sleep(0.05)
end
