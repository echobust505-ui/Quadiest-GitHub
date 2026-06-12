-- [MANDATORY] Connected Discord-GitHub
-- This script implements an advanced, OOP-based Grid Placement System.
-- It handles strict spatial queries, normal-based rotation alignment, grid math, and visual interpolation.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local PlaceBlockEvent = ReplicatedStorage:WaitForChild("PlaceBlockEvent")
type PlacementConfig = {
    GridSize: number,
    MaxPlacementRange: number,
    RotationSnapAngle: number,
    GhostOpacity: number,
    ColorValid: Color3,
    ColorInvalid: Color3,
    MaxSlopeAngle: number,
    LerpSmoothing: number,
    CooldownTime: number
}
local Config: PlacementConfig = {
    GridSize = 3,
    MaxPlacementRange = 25,
    RotationSnapAngle = 90,
    GhostOpacity = 0.6,
    ColorValid = Color3.fromRGB(80, 255, 80),
    ColorInvalid = Color3.fromRGB(255, 80, 80),
    MaxSlopeAngle = 50,
    LerpSmoothing = 0.35,
    CooldownTime = 0.15
}
local GridMathUtility = {}
function GridMathUtility.SnapAxis(value: number, step: number): number
    local divided = value / step
    local rounded = math.floor(divided + 0.5)
    return rounded * step
end
function GridMathUtility.SnapPosition(position: Vector3, step: number): Vector3
    local snappedX = GridMathUtility.SnapAxis(position.X, step)
    local snappedY = GridMathUtility.SnapAxis(position.Y, step)
    local snappedZ = GridMathUtility.SnapAxis(position.Z, step)
    return Vector3.new(snappedX, snappedY, snappedZ)
end
function GridMathUtility.GetSurfaceAlignment(surfaceNormal: Vector3): CFrame
    local globalUp = Vector3.new(0, 1, 0)
    local dotProduct = math.abs(surfaceNormal:Dot(globalUp))
    if dotProduct > 0.999 then
        return CFrame.new()
    end
    local rightAxis = globalUp:Cross(surfaceNormal).Unit
    local alignedUp = surfaceNormal:Cross(rightAxis).Unit
    return CFrame.fromMatrix(Vector3.zero, rightAxis, alignedUp, surfaceNormal)
end
local EffectManager = {}
function EffectManager.CreatePlacementSound(parentInstance: Instance): Sound
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://876939830"
    sound.Volume = 0.6
    sound.Pitch = 1.1
    sound.RollOffMaxDistance = 50
    sound.RollOffMinDistance = 10
    sound.Parent = parentInstance
    return sound
end
function EffectManager.CreateErrorSound(parentInstance: Instance): Sound
    local sound = Instance.new("Sound")
    sound.SoundId = "rbxassetid://235040113"
    sound.Volume = 0.4
    sound.Pitch = 0.9
    sound.Parent = parentInstance
    return sound
end
function EffectManager.PlayPopEffect(originCFrame: CFrame, size: Vector3)
    local effectPart = Instance.new("Part")
    effectPart.Anchored = true
    effectPart.CanCollide = false
    effectPart.CanQuery = false
    effectPart.Size = size
    effectPart.CFrame = originCFrame
    effectPart.Material = Enum.Material.ForceField
    effectPart.Color = Color3.new(1, 1, 1)
    effectPart.Parent = workspace
    local tweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
    local properties = {
        Size = size * 1.5,
        Transparency = 1
    }
    local tween = TweenService:Create(effectPart, tweenInfo, properties)
    tween:Play()
    tween.Completed:Connect(function()
        effectPart:Destroy()
    end)
end
local PlacementController = {}
PlacementController.__index = PlacementController
function PlacementController.new(tool: Tool)
    local self = setmetatable({}, PlacementController)
    self.ToolInstance = tool
    self.LocalPlayer = Players.LocalPlayer
    self.MainCamera = workspace.CurrentCamera
    self.Character = self.LocalPlayer.Character or self.LocalPlayer.CharacterAdded:Wait()
    self.RootPart = self.Character:WaitForChild("HumanoidRootPart")
    self.Humanoid = self.Character:WaitForChild("Humanoid")
    self.SpatialRayParams = RaycastParams.new()
    self.SpatialRayParams.FilterType = Enum.RaycastFilterType.Exclude
    self.SpatialRayParams.FilterDescendantsInstances = {self.Character}
    self.SpatialRayParams.IgnoreWater = true
    self.SpatialOverlapParams = OverlapParams.new()
    self.SpatialOverlapParams.FilterType = Enum.RaycastFilterType.Exclude
    self.SpatialOverlapParams.FilterDescendantsInstances = {self.Character}
    self.SpatialOverlapParams.MaxParts = 50
    self.RotationState = 0
    self.SystemActive = false
    self.IsPositionValid = false
    self.CalculatedCFrame = CFrame.new()
    self.LastInteractionTime = 0
    self.EventConnections = {}
    self.PlaceSound = EffectManager.CreatePlacementSound(self.ToolInstance)
    self.ErrorSound = EffectManager.CreateErrorSound(self.ToolInstance)
    self:InitializeGhostBlock()
    return self
end
function PlacementController:InitializeGhostBlock()
    self.GhostBlock = Instance.new("Part")
    self.GhostBlock.Name = "PlacementPreview"
    self.GhostBlock.Anchored = true
    self.GhostBlock.CanCollide = false
    self.GhostBlock.CanQuery = false
    self.GhostBlock.CanTouch = false
    self.GhostBlock.CastShadow = false
    self.GhostBlock.Size = Vector3.new(Config.GridSize, Config.GridSize, Config.GridSize)
    self.GhostBlock.Transparency = Config.GhostOpacity
    self.GhostBlock.Material = Enum.Material.SmoothPlastic
    self.GhostBox = Instance.new("SelectionBox")
    self.GhostBox.Adornee = self.GhostBlock
    self.GhostBox.LineThickness = 0.03
    self.GhostBox.Color3 = Color3.new(1, 1, 1)
    self.GhostBox.Parent = self.GhostBlock
end
function PlacementController:CastScreenRay()
    local mouseLocation = UserInputService:GetMouseLocation()
    local screenRay = self.MainCamera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
    local rootDistance = (self.RootPart.Position - screenRay.Origin).Magnitude
    local maximumRayLength = rootDistance + Config.MaxPlacementRange
    local rayDirection = screenRay.Direction * maximumRayLength
    local rayResult = workspace:Raycast(screenRay.Origin, rayDirection, self.SpatialRayParams)
    return rayResult, screenRay
end
function PlacementController:CheckBoundingIntersections(targetCFrame: CFrame): boolean
    local sizeReduction = 0.15
    local boundsVector = Vector3.new(
        Config.GridSize - sizeReduction,
        Config.GridSize - sizeReduction,
        Config.GridSize - sizeReduction
    )
    local intersectingParts = workspace:GetPartBoundsInBox(targetCFrame, boundsVector, self.SpatialOverlapParams)
    local intersectionCount = #intersectingParts
    if intersectionCount > 0 then
        return false
    end
    return true
end
function PlacementController:EvaluateSurfaceSlope(surfaceNormal: Vector3): boolean
    local globalUpVector = Vector3.new(0, 1, 0)
    local dotProductValue = surfaceNormal:Dot(globalUpVector)
    local clampedDot = math.clamp(dotProductValue, -1, 1)
    local angleInDegrees = math.deg(math.acos(clampedDot))
    local isValidSlope = angleInDegrees <= Config.MaxSlopeAngle
    local isValidCeiling = angleInDegrees >= (180 - Config.MaxSlopeAngle)
    return isValidSlope or isValidCeiling
end
function PlacementController:DeterminePlacementCFrame(raycastResult: RaycastResult?, fallbackScreenRay: Ray)
    local originPosition = Vector3.zero
    local finalSurfaceNormal = Vector3.new(0, 1, 0)
    if raycastResult then
        local gridHalfOffset = Config.GridSize * 0.5
        local positionalOffset = raycastResult.Normal * gridHalfOffset
        originPosition = raycastResult.Position + positionalOffset
        finalSurfaceNormal = raycastResult.Normal
    else
        local horizontalDirection = fallbackScreenRay.Direction * Vector3.new(1, 0, 1)
        local horizontalMagnitude = horizontalDirection.Magnitude
        if horizontalMagnitude < 0.001 then
            local characterLook = self.RootPart.CFrame.LookVector
            horizontalDirection = characterLook * Vector3.new(1, 0, 1)
        end
        local normalizedHorizontal = horizontalDirection.Unit
        originPosition = self.RootPart.Position + (normalizedHorizontal * Config.MaxPlacementRange)
    end
    local snappedCoordinates = GridMathUtility.SnapPosition(originPosition, Config.GridSize)
    local orientationCFrame = GridMathUtility.GetSurfaceAlignment(finalSurfaceNormal)
    local rotationRadians = math.rad(self.RotationState)
    local userRotationCFrame = CFrame.Angles(0, rotationRadians, 0)
    local finalPositionCFrame = CFrame.new(snappedCoordinates)
    return finalPositionCFrame * orientationCFrame * userRotationCFrame, finalSurfaceNormal
end
function PlacementController:UpdateRenderCycle()
    if not self.SystemActive then
        return
    end
    if self.Humanoid.Health <= 0 then
        self:DeactivateSystem()
        return
    end
    local castResult, viewportRay = self:CastScreenRay()
    local targetCFrame, hitNormal = self:DeterminePlacementCFrame(castResult, viewportRay)
    self.CalculatedCFrame = targetCFrame
    local clearanceCheck = self:CheckBoundingIntersections(self.CalculatedCFrame)
    local slopeCheck = self:EvaluateSurfaceSlope(hitNormal)
    local distanceMagnitude = (self.CalculatedCFrame.Position - self.RootPart.Position).Magnitude
    local distanceCheck = distanceMagnitude <= Config.MaxPlacementRange
    self.IsPositionValid = clearanceCheck and slopeCheck and distanceCheck
    local isGhostParented = self.GhostBlock.Parent ~= nil
    if not isGhostParented then
        self.GhostBlock.Parent = workspace
    end
    self.GhostBlock.CFrame = self.GhostBlock.CFrame:Lerp(self.CalculatedCFrame, Config.LerpSmoothing)
    if self.IsPositionValid then
        self.GhostBlock.Color = Config.ColorValid
    else
        self.GhostBlock.Color = Config.ColorInvalid
    end
end
function PlacementController:ProcessServerPlacement()
    if not self.SystemActive then
        return
    end
    if not self.IsPositionValid then
        self.ErrorSound:Play()
        return
    end
    local currentTime = os.clock()
    local timeDifference = currentTime - self.LastInteractionTime
    if timeDifference < Config.CooldownTime then
        return
    end
    self.LastInteractionTime = currentTime
    self.PlaceSound:Play()
    EffectManager.PlayPopEffect(self.CalculatedCFrame, self.GhostBlock.Size)
    PlaceBlockEvent:InvokeServer(self.CalculatedCFrame)
end
function PlacementController:ParseKeyboardInputs(inputObject: InputObject, eventProcessed: boolean)
    if eventProcessed then
        return
    end
    if not self.SystemActive then
        return
    end
    local inputState = inputObject.UserInputState
    if inputState ~= Enum.UserInputState.Begin then
        return
    end
    local inputKey = inputObject.KeyCode
    if inputKey == Enum.KeyCode.R then
        self.RotationState = (self.RotationState + Config.RotationSnapAngle) % 360
    elseif inputKey == Enum.KeyCode.F then
        self.RotationState = (self.RotationState - Config.RotationSnapAngle) % 360
    end
end
function PlacementController:ParseMouseInputs(inputObject: InputObject, eventProcessed: boolean)
    if eventProcessed then
        return
    end
    if not self.SystemActive then
        return
    end
    local inputType = inputObject.UserInputType
    local isMouseClick = inputType == Enum.UserInputType.MouseButton1
    local isScreenTouch = inputType == Enum.UserInputType.Touch
    if not (isMouseClick or isScreenTouch) then
        return
    end
    local inputState = inputObject.UserInputState
    if inputState == Enum.UserInputState.Begin then
        self:ProcessServerPlacement()
    end
end
function PlacementController:ActivateSystem()
    self.SystemActive = true
    self.RotationState = 0
    local renderConnection = RunService.RenderStepped:Connect(function()
        self:UpdateRenderCycle()
    end)
    self.EventConnections["RenderStep"] = renderConnection
    local keyboardConnection = UserInputService.InputBegan:Connect(function(input, processed)
        self:ParseKeyboardInputs(input, processed)
    end)
    self.EventConnections["KeyboardBegan"] = keyboardConnection
    local mouseConnection = UserInputService.InputBegan:Connect(function(input, processed)
        self:ParseMouseInputs(input, processed)
    end)
    self.EventConnections["MouseBegan"] = mouseConnection
end
function PlacementController:DeactivateSystem()
    self.SystemActive = false
    for connectionName, activeConnection in pairs(self.EventConnections) do
        if activeConnection.Connected then
            activeConnection:Disconnect()
        end
    end
    table.clear(self.EventConnections)
    self.IsPositionValid = false
    self.RotationState = 0
    if self.GhostBlock and self.GhostBlock.Parent then
        self.GhostBlock.Parent = nil
    end
end
local PrimaryTool = script.Parent
local MasterController = PlacementController.new(PrimaryTool)
PrimaryTool.Equipped:Connect(function()
    MasterController:ActivateSystem()
end)
PrimaryTool.Unequipped:Connect(function()
    MasterController:DeactivateSystem()
end)
