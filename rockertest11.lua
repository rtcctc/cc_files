-- ============================================================================
-- AVTOPILOT RAKETY (CC: Sable) - UPRAVLENIE PO LOKALNYM UGLAM
-- Ispol'zuet tol'ko ugly yaw, pitch (bez kvaternionov)
-- ============================================================================

-- ------------------------- NACHTROYKI --------------------------------------
local CRUISE_ALT = 120
local CLIMB_PITCH_DEG = 30
local DIVE_PITCH_DEG = -45
local TURN_THRESHOLD_DEG = 5
local DIVE_DIST = 200
local IMPACT_DIST = 15

local BASE_THRUST_CLIMB = 8
local BASE_THRUST_CRUISE = 6
local MAX_CORR = 3.0

local PID_YAW_TURN = {Kp=0.3, Ki=0, Kd=0.4, int=0, last_err=0}
local PID_YAW_CRUISE = {Kp=0.7, Ki=0.01, Kd=0.6, int=0, last_err=0}
local PID_PITCH_CRUISE = {Kp=0.4, Ki=0.01, Kd=0.4, int=0, last_err=0}
local PID_PITCH_DIVE = {Kp=0.5, Ki=0, Kd=0.4, int=0, last_err=0}
local PID_ALT = {Kp=0.6, Ki=0.01, Kd=0.3, int=0, last_err=0}

local YAW_DAMPING = 0.4
local ROLL_DAMPING = 0.5
local MAX_ROLL_DAMP = 1.5
local CORR_RATE_LIMIT = 1.5
local MIN_VY_FOR_TURN = 15

-- ------------------------- FUNKCII -----------------------------------------
function math.sign(x) return x>0 and 1 or x<0 and -1 or 0 end
function degToRad(d) return d * math.pi / 180 end
function radToDeg(r) return r * 180 / math.pi end

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

function getShipData()
    if not sublevel.isInPlotGrid() then return nil end
    local pose = sublevel.getLogicalPose()
    local pos = pose.position
    local vel = sublevel.getVelocity()
    local angVel = sublevel.getAngularVelocity()
    
    -- Poluchaem ugly raznymi sposobami
    local pitch, yaw, roll
    local orientation = pose.orientation
    if orientation.toEuler then
        pitch, yaw, roll = orientation:toEuler()
    elseif orientation.getPitch and orientation.getYaw then
        pitch = orientation:getPitch()
        yaw = orientation:getYaw()
        roll = orientation:getRoll()
    else
        -- Zapasnoy variant: esli vse ostal'noe ne rabotaet
        local angles = orientation:getAngles() -- method, esli est'
        if angles then
            pitch, yaw, roll = angles.pitch, angles.yaw, angles.roll
        else
            print("Ne udalos' poluchit' ugly")
            return nil
        end
    end
    
    return {
        x = pos.x, y = pos.y, z = pos.z,
        vx = vel.x, vy = vel.y, vz = vel.z,
        yaw = yaw, pitch = pitch, roll = roll,
        yaw_rate = angVel.y, roll_rate = angVel.z
    }
end

function pidUpdate(pid, error, dt)
    pid.int = pid.int + error * dt
    pid.int = math.max(-5, math.min(5, pid.int))
    local derivative = (error - pid.last_err) / dt
    pid.last_err = error
    return pid.Kp * error + pid.Ki * pid.int + pid.Kd * derivative
end

function normalizeAngleDeg(angle)
    angle = angle % 360
    if angle > 180 then angle = angle - 360 end
    return angle
end

-- ------------------------- OSNOVNOY CIKL -----------------------------------
local target = {x = 1000, z = 0, y = 0}
local state = "CLIMB"
local lastTime = os.clock()
local last_yaw_corr = 0
local last_pitch_corr = 0
local start_yaw = nil

print("Avtopilot zapushen. Cel: X=" .. target.x .. " Z=" .. target.z)

while true do
    local now = os.clock()
    local dt = now - lastTime
    if dt < 0.01 then sleep(0.01) dt = os.clock() - lastTime end
    lastTime = now
    
    local data = getShipData()
    if not data then
        print("Net dannyh ot sublevel")
        sleep(1)
    else
        local x, y, z = data.x, data.y, data.z
        local cur_yaw_deg = radToDeg(data.yaw)
        local cur_pitch_deg = radToDeg(data.pitch)
        local vy = data.vy
        local yaw_rate = data.yaw_rate
        local roll_rate = data.roll_rate
        
        if start_yaw == nil then
            start_yaw = cur_yaw_deg
            print("Startovyy kurs: " .. start_yaw .. "°")
        end
        
        -- Vektor do celi
        local dx = target.x - x
        local dz = target.z - z
        local dy = target.y - y
        local horDist = math.sqrt(dx*dx + dz*dz)
        local fullDist = math.sqrt(horDist*horDist + dy*dy)
        
        -- Zhelaemyy yaw v globalnykh koordinatakh (azimut na cel')
        local des_yaw_deg = radToDeg(math.atan2(dx, dz))
        -- Oshibka po kursu (absolyutnaya, dlya perekhoda TURN)
        local yaw_err_abs = normalizeAngleDeg(des_yaw_deg - cur_yaw_deg)
        
        -- LOKAL'NAYa oshibka: otklonenie celi ot nosa rakety
        -- V mire: cel' imeet azimut des_yaw_deg, nos rakety smotrit na cur_yaw_deg.
        -- Lokal'naya oshibka = des_yaw_deg - cur_yaw_deg, normalizovannaya.
        local local_yaw_error = normalizeAngleDeg(des_yaw_deg - cur_yaw_deg)
        
        -- Lokal'naya oshibka po pitch: nuzhno popravit' na tekushchiy pitch rakety,
        -- no dlya prostoty budem ispol'zovat' absolyutnyy pitch do celi.
        local des_pitch_deg = radToDeg(math.atan2(dy, horDist))
        local local_pitch_error = des_pitch_deg - cur_pitch_deg
        
        -- ------------------------- FAZOVYE PEREXODY ---------------------------
        if state == "CLIMB" then
            if y >= CRUISE_ALT - 10 and vy >= MIN_VY_FOR_TURN then
                state = "TURN"
                print(">>> Perehod k razvorotu")
                PID_YAW_TURN.int = 0; PID_YAW_TURN.last_err = 0
            end
        elseif state == "TURN" then
            if math.abs(yaw_err_abs) < TURN_THRESHOLD_DEG then
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
        
        -- ------------------------- VYChISLENIE KORREKCIY ---------------------
        local yaw_corr, pitch_corr
        
        if state == "CLIMB" then
            -- Stabiliziruemsya po kursu: derzhim startovyy yaw
            local yaw_err_climb = normalizeAngleDeg(start_yaw - cur_yaw_deg)
            yaw_corr = yaw_err_climb * 0.1   -- prostoy P-regulyator
            -- Pitch derzhim zadannyy
            local pitch_err_climb = CLIMB_PITCH_DEG - cur_pitch_deg
            pitch_corr = pitch_err_climb * 0.1
        elseif state == "TURN" then
            -- Ispol'zuem PID dlya lokal'noy oshibki
            local err_rad = degToRad(local_yaw_error)
            yaw_corr = pidUpdate(PID_YAW_TURN, err_rad, dt)
            pitch_corr = 0
        elseif state == "CRUISE" then
            -- PID po yaw (lokal'naya oshibka)
            local err_yaw_rad = degToRad(local_yaw_error)
            yaw_corr = pidUpdate(PID_YAW_CRUISE, err_yaw_rad, dt)
            -- PID po pitch + korrekciya vysoty
            local alt_err = CRUISE_ALT - y
            local alt_corr = pidUpdate(PID_ALT, alt_err, dt)
            alt_corr = math.max(-0.3, math.min(0.3, alt_corr))
            local desired_pitch_deg = alt_corr * 20   -- pereschet v gradusy
            local pitch_err_deg = desired_pitch_deg - cur_pitch_deg
            pitch_corr = pidUpdate(PID_PITCH_CRUISE, degToRad(pitch_err_deg), dt)
        else -- DIVE
            local err_yaw_rad = degToRad(local_yaw_error)
            yaw_corr = pidUpdate(PID_YAW_CRUISE, err_yaw_rad, dt)
            local pitch_err_deg = DIVE_PITCH_DEG - cur_pitch_deg
            pitch_corr = pidUpdate(PID_PITCH_DIVE, degToRad(pitch_err_deg), dt)
        end
        
        -- Dampirovanie po ryoskaniyu i krenu
        yaw_corr = yaw_corr + (-yaw_rate * YAW_DAMPING)
        pitch_corr = pitch_corr
        local roll_corr = -roll_rate * ROLL_DAMPING
        roll_corr = math.max(-MAX_ROLL_DAMP, math.min(MAX_ROLL_DAMP, roll_corr))
        
        -- Ogranichenie
        yaw_corr = math.max(-MAX_CORR, math.min(MAX_CORR, yaw_corr))
        pitch_corr = math.max(-MAX_CORR, math.min(MAX_CORR, pitch_corr))
        
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
            print(string.format("[%s] Y:%.1f D:%.0f LyErr:%.1f° LPitch:%.1f°",
                state, y, fullDist, local_yaw_error, local_pitch_error))
        end
    end
    sleep(0.05)
end
