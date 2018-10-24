---------------------------------------------------------------------------
-- Gear calulation parameters 
---------------------------------------------------------------------------
-- Edit the gear ratios to mathch your car
-- Add another gear row if needed for 6th gear or delete extraneous ones

-- below values are constants for the vehicle
local gear1 = 3.23
local gear2 = 2.045
local gear3 = 1.258
local gear4 = 0.972
local gear5 = 0.731
local FinalDrive = 4.285
--diameter in inches
local TireDia = 25.6  
--allowable error of gear ratio to allow for measurement variation
local gearErr = 0.1
local rpmSpeedRatio = 0
--initialized to 0 so if it doesn't work you know
local gearPos = 0 --this is the gear channel variable

--this part only works for firmware version 2.0 per the RCP page
local gearId = addChannel("Gear",5,0,1,5)
--

---------------------------------------------------------------------------
-- Analog channel map
---------------------------------------------------------------------------
local tpsChannel = 0
local fuelLevelChannel = 2
local oilTempChannel = 3
local coolantChannel = 4
local oilPressureChannel = 5
local fuelPressureChannel = 6
local voltageChannel = 7

---------------------------------------------------------------------------
-- Digital I/O channel map
---------------------------------------------------------------------------
local lowFuelIOChannel = 0


---------------------------------------------------------------------------
-- Fuel totalizer parameters
---------------------------------------------------------------------------
-- Fuel flow meter PWM/RPM channel id
local fuelFlowChannelId = 1
-- Fuel flow meter k factor
local fuelKFactor = 37000
-- Internal variables
local fuelTotal = 0
local fuelLastCount = 0
local fuelTotalChanId = addChannel("FuelTotal",10,2)
local gphChanId = addChannel("GPH",10,2)


---------------------------------------------------------------------------
-- Variable for check engine/warning light
---------------------------------------------------------------------------
local maxOilTemp = 260
local maxCoolantTemp = 215
local minOilPressure = 10
local minVoltage = 12
local warningLightChannel = 0


-----------------------------------------------------------------
-- ShiftX2 Variables
-----------------------------------------------------------------
-- What CAN bus ShiftX2 is connected to. 0=CAN1, 1=CAN2
sxCan = 0

-- 0=first ShiftX2 on bus, 1=second ShiftX2 (if ADR1 jumper is cut)
sxId=0

--how often ShiftX2 is updated
tickRate=10

--Brightness, 0-100. 0=automatic brightness
sxBright=0

-- ShiftX2 CanId
sxCanId = 0xE3600 + (256 * sxId)
println('shiftx2 base id ' ..sxCanId)

---------------------------------------------------------------------------
-- Gear calulation function
---------------------------------------------------------------------------
--Developed by Luther Lloyd III 8/22/14 for use by Autosport Labs Community
function calcGear()
  --assumes Pulse Input channel one is for the RPM signal and speed in MPH
  local speed = getGpsSpeed()
  local rpm = getTimerRpm(0)

  -- Enable logging if the engine is running
  if rpm > 10 then
    startLogging()
  else
    stopLogging()
  end

  -- Calculate the current gear if we're moving
  if speed > 10 then
    --makes sure your rolling so as not to divide by 0 
    
   rpmSpeedRatio = (rpm/speed)/(FinalDrive*1056/(TireDia*3.14159))

    if ((gear1 - rpmSpeedRatio)^2) < (gearErr^2) then gearPos = 1 end
    if ((gear2 - rpmSpeedRatio)^2) < (gearErr^2) then gearPos = 2 end
    if ((gear3 - rpmSpeedRatio)^2) < (gearErr^2) then gearPos = 3 end
    if ((gear4 - rpmSpeedRatio)^2) < (gearErr^2) then gearPos = 4 end
    if ((gear5 - rpmSpeedRatio)^2) < (gearErr^2) then gearPos = 5 end
  else 
    gearPos = 0 
  end

  setChannel(gearId, gearPos) --outputs to virtual channel
end


---------------------------------------------------------------------------
-- Warning/check engine light and low fuel light function
---------------------------------------------------------------------------
function checkErrorConditions()
  local showError = 0
  local oilTemp = getAnalog(oilTempChannel)
  local coolantTemp = getAnalog(coolantChannel)
  local oilPressure = getAnalog(oilPressureChannel)
  local fuelPressure = getAnalog(fuelPressureChannel)
  local voltage = getAnalog(voltageChannel)
  local lowFuel = getGpio(lowFuelIOChannel)

  -- if oilTemp > maxOilTemp then showError = 1 end
  if coolantTemp > maxCoolantTemp then showError = 1 end
  if oilPressure < minOilPressure then showError = 1 end
  if voltage < minVoltage then showError = 1 end

  --update engine alert
  if showError == 1 then
    sxUpdateAlert(0, 100)
  else
    sxUpdateAlert(0, 0)
  end

  -- update fuel alert, inverted logic
  if lowFuel == 0 then
    -- fuel pin low indicates low fuel
    sxUpdateAlert(1, 100)
  else
    sxUpdateAlert(1, 0)
  end
end


---------------------------------------------------------------------------
-- Fuel totalizer function
---------------------------------------------------------------------------
-- Calculate the amount of fuel used since the last call.
function updateFuelTotal()
  -- Get the current pulse count from the PWM channel
  local timerCount = getTimerCount(fuelFlowChannelId)

  -- Determine if the pulse count was reset back to 0 since the last time
  -- we checked and calculate the number of pulses since last update
  if fuelLastCount < timerCount then
    local countSinceLast = timerCount - fuelLastCount
    -- Update the current fuel total
    fuelTotal = fuelTotal + (countSinceLast / fuelKFactor)
    -- Set the virtual channel with the updated value
    setChannel(fuelTotalChanId, fuelTotal)
  end

  -- Update the last count value for the next tick
  fuelLastCount = timerCount
end


---------------------------------------------------------------------------
-- Gallons Per Hour calculation
---------------------------------------------------------------------------
function updateGPH()
  -- Get the fuel flow sensor pulse frequency
  local fuelFlowFreq = getTimerFreq(fuelFlowChannelId)
  -- set the gph to the frequency times the number of seconds in an hour
  -- divide by the k factor of the sensor
  setChannel(gphChanId, fuelFlowFreq * 3600 / fuelKFactor)
end


----------------------------------------------------------------
--  ShiftX2 Initialization and update functions
----------------------------------------------------------------
function sxOnUpdate()
  --add your code to update ShiftX2 alerts or linear graph during run time.
  --Runs continuously based on tickRate.
  
  --uncomment the below for OBDII RPM PID
  --sxUpdateLinearGraph(readOBD2(12))

  --uncomment the below for Direct RPM on input 0
  sxUpdateLinearGraph(getTimerRpm(0))
end

function sxOnInit()
  --config shift light
  sxCfgLinearGraph(0,0,0,7000) --left to right graph, linear style, 0 - 7000 RPM range

  sxSetLinearThresh(0,0,3000,0,255,0,0) --green at 3000 RPM
  sxSetLinearThresh(1,0,5800,255,255,0,0) --yellow at 5000 RPM
  sxSetLinearThresh(2,0,6800,255,0,0,10) --red+flash at 6800 RPM

  --configure first alert (right LED) as engine temperature (F)
  sxSetAlertThresh(0,0,100,255,0,0,10) -- red flash at 225F

  --configure second alert (left LED) as oil pressure (PSI)
  sxSetAlertThresh(1,0,100,255,0,0,0) --red flash below 15 psi
end

-- Clear fuel total on ShiftX2 button press
function sxOnBut(b)
  -- button is pressed when b == 1
  if b == 1 then
    -- reset fuel total
    resetTimerCount(fuelFlowChannelId)
    fuelTotal = 0
    fuelLastCount = 0
    setChannel(fuelTotalChanId, fuelTotal)
  end
end

-----------------------------------------------------------------
-- ShiftX2 API functions - provided by Autosport labs
-----------------------------------------------------------------
function sxSetLed(i,l,r,g,b,f)
  sxTx(10,{i,l,r,g,b,f})
end

function sxSetLinearThresh(id,s,th,r,g,b,f)
  sxTx(41,{id,s,spl(th),sph(th),r,g,b,f})
end

function sxSetAlertThresh(id,tid,th,r,g,b,f)
  sxTx(21,{id,tid,spl(th),sph(th),r,g,b,f})
end

function setBaseConfig(bright)
  sxTx(3,{bright})
end

function sxSetAlert(id,r,g,b,f)
  sxTx(20,{id,r,g,b,f})
end

function sxUpdateAlert(id,v)
  if v~=nil then sxTx(22,{id,spl(v),sph(v)}) end
end

function sxCfgLinearGraph(rs,ls,lr,hr) 
  sxTx(40,{rs,ls,spl(lr),sph(lr),spl(hr),sph(hr)})
end

function sxUpdateLinearGraph(v)
  if v ~= nil then sxTx(42,{spl(v),sph(v)}) end
end

function sxInit()
  println('config shiftX2')
  setBaseConfig(sxBright)
  if sxOnInit~=nil then sxOnInit() end
end

function sxChkCan()
  id,ext,data=rxCAN(sxCan,0)
  if id==sxCanId then sxInit() end
  if id==sxCanId+60 and sxOnBut~=nil then sxOnBut(data[1]) end
end

function sxProcess()
  sxChkCan()
  if sxOnUpdate~=nil then sxOnUpdate() end
end

function sxTx(offset, data)
  txCAN(sxCan, sxCanId + offset, 1, data)
  sleep(10)
end

function spl(v) return bit.band(v,0xFF) end
function sph(v) return bit.rshift(bit.band(v,0xFF00),8) end


---------------------------------------------------------------------------
-- Main onTick function that calls the above functions to update values
-- and the ShiftX2
---------------------------------------------------------------------------
--update gear position, fuel total, GPH, error conditions and update shiftx2
function onTick() 
  updateFuelTotal()
  updateGPH()
  checkErrorConditions()
  calcGear()
  sxProcess()
end


setTickRate(tickRate)
sxInit()

