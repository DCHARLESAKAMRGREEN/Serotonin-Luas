--[[
Highlight Library for Serotonin Lua
====================================

A high-performance library for generating precise 2D outlines from 3D parts.
Uses grid rasterization with marching squares contour tracing for efficiency.

Methods:
--------
Highlight:GetOutline(Parts, Step, Padding)
  - Generates a 2D outline polygon from an array of 3D parts
  - Parts: table - Array of Part instances  
  - Step: number - Grid resolution (lower = more precise, higher = faster) [default: 1]
  - Padding: number - Extra space around bounding box [default: Step * 2]
  - Returns: table - Array of {x, y} points forming the outline polygon
]]

----------------------------------------------------------------------------------------------------------------------------------------

local function IsInPoly(Px, Py, Poly)
    local Inside, J = false, #Poly
    for I = 1, J do
        local Xi, Yi, Xj, Yj = Poly[I][1], Poly[I][2], Poly[J][1], Poly[J][2]
        if (Yi > Py) ~= (Yj > Py) and Px < (Xj - Xi) * (Py - Yi) / (Yj - Yi) + Xi then Inside = not Inside end
        J = I
    end
    return Inside
end

local function GetOutlineFromGrid(Grid, Nx, Ny, MinX, MinY, Step, Out)
    local StartX, StartY
    for Y = 1, Ny do
        local Row = Grid[Y]
        if Row then
            for X = 1, Nx do
                if Row[X] then StartX, StartY = X, Y break end
            end
            if StartX then break end
        end
    end
    if not StartX then return Out end

    local Directions = {{0,-1},{1,0},{0,1},{-1,0}}
    local function InGrid(X, Y)
        return X >= 1 and X <= Nx and Y >= 1 and Y <= Ny and Grid[Y] and Grid[Y][X]
    end
    local function GetCorner(X, Y, Dir)
        local L, T = MinX + (X - 1) * Step, MinY + (Y - 1) * Step
        if Dir == 1 then return {L, T}
        elseif Dir == 2 then return {L + Step, T}
        elseif Dir == 3 then return {L + Step, T + Step}
        else return {L, T + Step} end
    end

    local X, Y, Dir = StartX, StartY, 1
    while not InGrid(X + Directions[Dir][1], Y + Directions[Dir][2]) do Dir = Dir % 4 + 1 end
    local StartDir = Dir
    local Count = 0

    repeat
        local NX, NY = X + Directions[Dir][1], Y + Directions[Dir][2]
        if InGrid(NX, NY) then
            local LDir = Dir == 1 and 4 or Dir - 1
            if InGrid(NX + Directions[LDir][1], NY + Directions[LDir][2]) then Dir = LDir end
            X, Y = NX, NY
        else
            Dir = Dir % 4 + 1
        end
        local Corner = GetCorner(X, Y, Dir)
        local Prev = Out[Count]
        if not Prev or Prev[1] ~= Corner[1] or Prev[2] ~= Corner[2] then
            Count = Count + 1
            Out[Count] = Corner
        end
    until X == StartX and Y == StartY and Dir == StartDir

    for I = Count + 1, #Out do Out[I] = nil end
    return Out
end

local Highlight = {
    PolyBuffer = {},
    GridBuffer = {},
    OutlineBuffer = {},
    ScreenPointBuffer = {}
}

function Highlight:GetOutline(Parts, Step, Padding)
    local Polygons, Grid, ScreenPoints = self.PolyBuffer, self.GridBuffer, self.ScreenPointBuffer
    for I = 1, #Polygons do Polygons[I] = nil end
    for Y = 1, #Grid do Grid[Y] = nil end

    local Count, HasValidPoint = 0, false
    for I = 1, #Parts do
        local Corners = draw.GetPartCorners(Parts[I])
        if Corners then
            local PCount = 0
            for J = 1, #Corners do
                local SX, SY, On = utility.WorldToScreen(Corners[J])
                if On then 
                    PCount = PCount + 1 
                    ScreenPoints[PCount] = {SX, SY}
                    HasValidPoint = true
                end
            end
            if PCount >= 3 then
                local Hull = draw.ComputeConvexHull(ScreenPoints)
                if Hull and #Hull >= 3 then 
                    Count = Count + 1 
                    Polygons[Count] = Hull 
                end
            end
            for K = PCount + 1, #ScreenPoints do ScreenPoints[K] = nil end
        end
    end
    
    if Count == 0 or not HasValidPoint then 
        for I = 1, #self.OutlineBuffer do self.OutlineBuffer[I] = nil end
        return self.OutlineBuffer 
    end

    local MinX, MinY, MaxX, MaxY = math.huge, math.huge, -math.huge, -math.huge
    for I = 1, Count do
        local Poly = Polygons[I]
        for J = 1, #Poly do
            local PX, PY = Poly[J][1], Poly[J][2]
            MinX = PX < MinX and PX or MinX
            MinY = PY < MinY and PY or MinY
            MaxX = PX > MaxX and PX or MaxX
            MaxY = PY > MaxY and PY or MaxY
        end
    end
    
    if MinX == math.huge then 
        for I = 1, #self.OutlineBuffer do self.OutlineBuffer[I] = nil end
        return self.OutlineBuffer 
    end

    Step = Step or 1
    Padding = Padding or Step * 2
    MinX, MinY = math.floor(MinX) - Padding, math.floor(MinY) - Padding
    MaxX, MaxY = math.ceil(MaxX) + Padding, math.ceil(MaxY) + Padding

    local W, H = math.max(1, math.floor((MaxX - MinX) / Step) + 1), math.max(1, math.floor((MaxY - MinY) / Step) + 1)
    
    for Y = 1, H do
        local Row = Grid[Y]
        if not Row then Row = {} Grid[Y] = Row end
        for X = 1, W do Row[X] = false end
    end

    for I = 1, Count do
        local Poly = Polygons[I]
        local PMinX, PMinY, PMaxX, PMaxY = math.huge, math.huge, -math.huge, -math.huge
        for J = 1, #Poly do
            local PX, PY = Poly[J][1], Poly[J][2]
            PMinX = PX < PMinX and PX or PMinX
            PMinY = PY < PMinY and PY or PMinY
            PMaxX = PX > PMaxX and PX or PMaxX
            PMaxY = PY > PMaxY and PY or PMaxY
        end
        local SX = math.max(1, math.floor((PMinX - MinX) / Step) - 1)
        local SY = math.max(1, math.floor((PMinY - MinY) / Step) - 1)
        local EX = math.min(W, math.floor((PMaxX - MinX) / Step) + 1)
        local EY = math.min(H, math.floor((PMaxY - MinY) / Step) + 1)
        
        for Y = SY, EY do
            local Row = Grid[Y]
            for X = SX, EX do
                if IsInPoly(MinX + (X - 0.5) * Step, MinY + (Y - 0.5) * Step, Poly) then Row[X] = true end
            end
        end
    end
    return GetOutlineFromGrid(Grid, W, H, MinX, MinY, Step, self.OutlineBuffer)
end

local Bones = {"Head","UpperTorso","LowerTorso","LeftUpperArm","LeftLowerArm","LeftHand","RightUpperArm","RightLowerArm","RightHand","LeftUpperLeg","LeftLowerLeg","LeftFoot","RightUpperLeg","RightLowerLeg","RightFoot","Torso","Left Arm","Right Arm","Left Leg","Right Leg"}

local function Render()
    local Player = game.LocalPlayer
    if not Player then return end
    local Char = Player.Character
    if not Char then return end

    local Parts, Count, OnScreen = {}, 0, false
    for I = 1, #Bones do
        local Part = Char:FindFirstChild(Bones[I])
        if Part then
            local Pos = Part.Position
            local _, _, On = utility.WorldToScreen(Pos)
            if On then OnScreen = true end
            Count = Count + 1
            Parts[Count] = Part
        end
    end
    
    if not OnScreen or Count == 0 then return end

    local Outline = Highlight:GetOutline(Parts, 1)
    if #Outline >= 3 then
        draw.Polyline(Outline, Color3.new(1,1,1), true, 1.5, 255)
    end
end

cheat.register("onPaint", Render)

return Highlight
