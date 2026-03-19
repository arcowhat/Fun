local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local TeleportService  = game:GetService("TeleportService")

local stopped = false
local manualStop = false

UserInputService.InputBegan:Connect(function(input, gpe)
    if gpe then return end
    if input.KeyCode == Enum.KeyCode.X and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then
        stopped = true
        manualStop = true
    end
end)

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local humanoid  = character:WaitForChild("Humanoid")
local backpack  = player:WaitForChild("Backpack")
local camera    = workspace.CurrentCamera

local RESPAWN_POS   = Vector3.new(51.032, 341.518, 23.478)
local BIND_NAME     = "PositionLock"
local ABOVE_OFFSET  = 8.4
local APPROACH_TIME = 0.12
local CLOSE_TIME    = 0.03

local HITBOX_SIZE         = Vector3.new(30, 30, 30)
local HITBOX_TRANSPARENCY = 0.4

local function expandHitbox(char)
    local hrp = char:WaitForChild("HumanoidRootPart", 5)
    if not hrp then return end
    hrp.Size         = HITBOX_SIZE
    hrp.Transparency = HITBOX_TRANSPARENCY
    hrp.CanCollide   = false
end

local function hookPlayer(p)
    if p == player then return end
    p.CharacterAdded:Connect(function(char)
        task.spawn(expandHitbox, char)
    end)
    if p.Character then
        task.spawn(expandHitbox, p.Character)
    end
end

for _, p in ipairs(Players:GetPlayers()) do hookPlayer(p) end
Players.PlayerAdded:Connect(hookPlayer)

local function startServerHopCheck()
    task.spawn(function()
        while true do
            if manualStop then return end
            task.wait(5)
            if #Players:GetPlayers() < 5 then
                print("test")
                TeleportService:Teleport(game.PlaceId, player)
                return
            end
        end
    end)
end

local function isAlive()
    return humanoid and humanoid.Health > 0
end

local tookHeavyDamage = false

local function isValidTarget(p)
    local char = p.Character
    if not char then return false end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hrp or not hum or hum.Health <= 0 then return false end

    if (hrp.Position - RESPAWN_POS).Magnitude <= 300 then return false end

    for _, obj in ipairs(char:GetDescendants()) do
        if string.find(obj.Name, "Tank") then return false end
    end
    local bp = p:FindFirstChild("Backpack")
    if bp then
        for _, obj in ipairs(bp:GetChildren()) do
            if string.find(obj.Name, "Tank") then return false end
        end
    end

    return true
end

local function getSortedPlayers()
    local myHRP = character:FindFirstChild("HumanoidRootPart")
    if not myHRP then return {} end

    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p == player then continue end
        if not isValidTarget(p) then continue end

        local hrp = p.Character:FindFirstChild("HumanoidRootPart")
        local dist = (hrp.Position - myHRP.Position).Magnitude
        if dist > 400 then continue end

        table.insert(list, { player = p, dist = dist })
    end

    table.sort(list, function(a, b) return a.dist < b.dist end)
    return list
end

local function getTarget()
    local sorted = getSortedPlayers()
    if #sorted == 0 then return nil end
    if tookHeavyDamage and #sorted >= 2 then
        tookHeavyDamage = false
        return sorted[2].player
    end
    return sorted[1].player
end

local function hasItems()
    for _, t in ipairs(backpack:GetChildren()) do
        if t:IsA("Tool") then return true end
    end
    for _, t in ipairs(character:GetChildren()) do
        if t:IsA("Tool") then return true end
    end
    return false
end

local function buildAboveCF(tHRP)
    local abovePos = tHRP.Position + Vector3.new(0, ABOVE_OFFSET, 0)
    return CFrame.new(abovePos, abovePos + Vector3.new(0, -1, 0))
end

local function startRespawnTPLoop()
    task.spawn(function()
        while true do
            if stopped or not isAlive() then return end
            if not hasItems() then
                local hrp = character:FindFirstChild("HumanoidRootPart")
                if hrp then
                    hrp.CFrame = CFrame.new(RESPAWN_POS)
                end
            end
            task.wait(0.05)
        end
    end)
end

local function startEquipLoop()
    task.spawn(function()
        local direction = 1
        while true do
            if stopped or not isAlive() then return end
            while #backpack:GetChildren() == 0 do
                if stopped or not isAlive() then return end
                task.wait(0.2)
            end
            local tools = {}
            for _, t in ipairs(backpack:GetChildren()) do
                if t:IsA("Tool") then table.insert(tools, t) end
            end
            if #tools == 0 then task.wait(0.2) continue end
            if direction == -1 then
                local rev = {}
                for i = #tools, 1, -1 do table.insert(rev, tools[i]) end
                tools = rev
            end
            for _, tool in ipairs(tools) do
                if stopped or not isAlive() then return end
                if not tool or not tool.Parent then continue end
                humanoid:EquipTool(tool)
                task.wait(0.15)
            end
            direction = direction * -1
        end
    end)
end

local approachingTarget = nil
local hardLockedTarget  = nil
local activeTween       = nil

local function stopMoveTween()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    approachingTarget = nil
end

local function tweenToTarget(hrp, tHRP, duration, onDone)
    stopMoveTween()
    approachingTarget = tHRP
    local tween = TweenService:Create(
        hrp,
        TweenInfo.new(duration, Enum.EasingStyle.Linear),
        { CFrame = buildAboveCF(tHRP) }
    )
    activeTween = tween
    tween.Completed:Connect(function(state)
        if approachingTarget == tHRP then
            approachingTarget = nil
        end
        if state == Enum.PlaybackState.Completed and onDone then
            onDone()
        end
    end)
    tween:Play()
end

local function startPositionLock()
    RunService:UnbindFromRenderStep(BIND_NAME)
    RunService:BindToRenderStep(BIND_NAME, Enum.RenderPriority.First.Value, function()
        if stopped or not isAlive() then
            stopMoveTween()
            hardLockedTarget = nil
            RunService:UnbindFromRenderStep(BIND_NAME)
            return
        end

        local hrp = character:FindFirstChild("HumanoidRootPart")
        if not hrp then return end

        if not hasItems() then
            stopMoveTween()
            hardLockedTarget = nil
            return
        end

        if hardLockedTarget and not isValidTarget(hardLockedTarget) then
            hardLockedTarget = nil
            stopMoveTween()
        end

        local target = getTarget()

        if not target then
            stopMoveTween()
            hardLockedTarget = nil
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            return
        end

        local tHRP = target.Character and target.Character:FindFirstChild("HumanoidRootPart")
        if not tHRP then return end

        if hardLockedTarget == target then
            hrp.CFrame = buildAboveCF(tHRP)
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            return
        end

        if approachingTarget == tHRP then
            hrp.AssemblyLinearVelocity = Vector3.zero
            hrp.AssemblyAngularVelocity = Vector3.zero
            return
        end

        local dist = (hrp.Position - tHRP.Position).Magnitude
        local duration = dist <= 50 and CLOSE_TIME or APPROACH_TIME

        tweenToTarget(hrp, tHRP, duration, function()
            if not stopped and getTarget() == target then
                hardLockedTarget = target
            end
        end)

        hrp.AssemblyLinearVelocity = Vector3.zero
        hrp.AssemblyAngularVelocity = Vector3.zero
    end)
end

local function startClickLoop()
    task.spawn(function()
        while true do
            if stopped or not isAlive() then return end
            local tool = character:FindFirstChildOfClass("Tool")
            if tool then
                local re = tool:FindFirstChildOfClass("RemoteEvent")
                if re then re:FireServer() end
                tool:Activate()
            end
            task.wait(0.05)
        end
    end)
end

local function setupCharacter(newChar)
    character       = newChar
    humanoid        = newChar:WaitForChild("Humanoid")
    backpack        = player:WaitForChild("Backpack")
    tookHeavyDamage = false

    stopMoveTween()
    hardLockedTarget = nil

    local lastHealth = humanoid.Health
    humanoid.HealthChanged:Connect(function(newHealth)
        local dmg = lastHealth - newHealth
        if dmg >= 30 then tookHeavyDamage = true end
        lastHealth = newHealth
    end)

    humanoid.Died:Connect(function()
        stopped = true
    end)

    if not stopped then
        startRespawnTPLoop()
        startEquipLoop()
        startPositionLock()
        startClickLoop()
    end
end

setupCharacter(character)
startServerHopCheck()

player.CharacterAdded:Connect(function(newChar)
    task.spawn(function()
        newChar:WaitForChild("HumanoidRootPart", 10)
        newChar:WaitForChild("Humanoid", 10)
        task.wait(0.5)
        if manualStop then return end
        stopped = false
        setupCharacter(newChar)
        startServerHopCheck()
    end)
end)
