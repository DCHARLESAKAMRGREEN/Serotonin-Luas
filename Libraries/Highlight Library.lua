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

Internal Functions:
------------------
IsInPoly(Px, Py, Poly)
  - Ray casting algorithm for point-in-polygon testing

GetOutlineFromGrid(Grid, Nx, Ny, MinX, MinY, Step)
  - Marching squares contour tracing from binary grid

Performance Notes:
-----------------
- Single-pass polygon rasterization with bounding box culling
- Reuses buffer tables to minimize allocations
- Step controls precision vs performance tradeoff
]]

local function IsInPoly(Px, Py, Poly)
    local Inside, J = false, #Poly
    for I = 1, J do
        local Xi, Yi, Xj, Yj = Poly[I][1], Poly[I][2], Poly[J][1], Poly[J][2]
        if (Yi > Py) ~= (Yj > Py) and Px < (Xj - Xi) * (Py - Yi) / (Yj - Yi) + Xi then
            Inside = not Inside
        end
        J = I
    end
    return Inside
end

local function GetOutlineFromGrid(Grid, Nx, Ny, MinX, MinY, Step, Boundary)
    local StartX, StartY
    for Iy = 1, Ny do
        local Row = Grid[Iy]
        if Row then
            for Ix = 1, Nx do
                if Row[Ix] then StartX, StartY = Ix, Iy break end
            end
            if StartX then break end
        end
    end
    if not StartX then return Boundary end

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
            local LeftDir = Dir == 1 and 4 or Dir - 1
            if InGrid(NX + Directions[LeftDir][1], NY + Directions[LeftDir][2]) then Dir = LeftDir end
            X, Y = NX, NY
        else
            Dir = Dir % 4 + 1
        end
        local Corner = GetCorner(X, Y, Dir)
        local Last = Boundary[Count]
        if not Last or Last[1] ~= Corner[1] or Last[2] ~= Corner[2] then
            Count = Count + 1
            Boundary[Count] = Corner
        end
    until X == StartX and Y == StartY and Dir == StartDir

    for I = Count + 1, #Boundary do Boundary[I] = nil end
    return Boundary
end

local Highlight = {
    PolygonBuffer = {},
    GridBuffer = {},
    BoundaryBuffer = {}
}

function Highlight:GetOutline(Parts, Step, Padding)
    local Polygons, PolyCount = self.PolygonBuffer, 0
    for I = 1, #Parts do
        local Corners = draw.GetPartCorners(Parts[I])
        if Corners then
            local ScreenPoints, Count = {}, 0
            for J = 1, #Corners do
                local SX, SY, OnScreen = utility.WorldToScreen(Corners[J])
                if OnScreen then
                    Count = Count + 1
                    ScreenPoints[Count] = {SX, SY}
                end
            end
            if Count >= 3 then
                local Hull = draw.ComputeConvexHull(ScreenPoints)
                if Hull and #Hull >= 3 then
                    PolyCount = PolyCount + 1
                    Polygons[PolyCount] = Hull
                end
            end
        end
    end
    for I = PolyCount + 1, #Polygons do Polygons[I] = nil end
    if PolyCount == 0 then return {} end

    local MinX, MinY, MaxX, MaxY = math.huge, math.huge, -math.huge, -math.huge
    for I = 1, PolyCount do
        local Poly = Polygons[I]
        for J = 1, #Poly do
            local PX, PY = Poly[J][1], Poly[J][2]
            if PX < MinX then MinX = PX end
            if PY < MinY then MinY = PY end
            if PX > MaxX then MaxX = PX end
            if PY > MaxY then MaxY = PY end
        end
    end
    if MinX == math.huge then return {} end

    Step = Step or 1
    Padding = Padding or Step * 2
    MinX, MinY = math.floor(MinX) - Padding, math.floor(MinY) - Padding
    MaxX, MaxY = math.ceil(MaxX) + Padding, math.ceil(MaxY) + Padding

    local W, H = math.max(1, math.floor((MaxX - MinX) / Step) + 1), math.max(1, math.floor((MaxY - MinY) / Step) + 1)
    local Grid = self.GridBuffer
    for Y = 1, H do
        Grid[Y] = Grid[Y] or {}
        for X = 1, W do Grid[Y][X] = false end
    end
    for Y = H + 1, #Grid do Grid[Y] = nil end

    for I = 1, PolyCount do
        local Poly = Polygons[I]
        local PMinX, PMinY, PMaxX, PMaxY = math.huge, math.huge, -math.huge, -math.huge
        for J = 1, #Poly do
            local PX, PY = Poly[J][1], Poly[J][2]
            if PX < PMinX then PMinX = PX end
            if PY < PMinY then PMinY = PY end
            if PX > PMaxX then PMaxX = PX end
            if PY > PMaxY then PMaxY = PY end
        end
        local SX, SY = math.max(1, math.floor((PMinX - MinX) / Step) - 1), math.max(1, math.floor((PMinY - MinY) / Step) - 1)
        local EX, EY = math.min(W, math.floor((PMaxX - MinX) / Step) + 1), math.min(H, math.floor((PMaxY - MinY) / Step) + 1)
        for Y = SY, EY do
            local Row = Grid[Y]
            for X = SX, EX do
                if IsInPoly(MinX + (X - 0.5) * Step, MinY + (Y - 0.5) * Step, Poly) then Row[X] = true end
            end
        end
    end

    return GetOutlineFromGrid(Grid, W, H, MinX, MinY, Step, self.BoundaryBuffer)
end

return Highlight
