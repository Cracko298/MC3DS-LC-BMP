-- Compatible with LunaCore >0.19.0
-- Uses math instead of bitwise operators for compatibility with Lua 5.1

local function read_uint16_le(data, offset)
    local b1, b2 = data:byte(offset, offset+1)
    return b1 + b2 * 256
end

local function read_uint32_le(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset+3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function morton_interleave(x, y)
    local res = 0
    for i = 0, 2 do
        local bit_x = math.floor(x / (2^i)) % 2
        local bit_y = math.floor(y / (2^i)) % 2
        res = res + (bit_x * (2^(2*i))) + (bit_y * (2^(2*i + 1)))
    end
    return res
end

local function load_bmp(path)
    local file, err = Core.Filesystem.open(path, "rb")
    if not file then 
        Core.Debug.logerror("BMP Open Fail: " .. (err or "??"))
        return nil 
    end
    
    local data = file:read("*all")
    file:close()

    if not data or data:sub(1,2) ~= "BM" then return nil end

    local pixel_offset = read_uint32_le(data, 11)
    local width  = read_uint32_le(data, 19)
    local height = read_uint32_le(data, 23)
    local bpp    = read_uint16_le(data, 29)

    local pixels = {}
    for y = height-1, 0, -1 do
        for x = 0, width-1 do
            local offset = pixel_offset + (y * width + x) * (bpp / 8) + 1
            local b, g, r, a = data:byte(offset, offset + 3)
            a = a or 255
            pixels[((height - 1 - y) * width) + x] = {r, g, b, a}
        end
    end
    return pixels, width, height
end

local function swizzle_3ds(pixels, width, height)
    local swizzled = {}
    local tiles_x = math.ceil(width / 8)
    local tiles_y = math.ceil(height / 8)
    
    for ty = 0, tiles_y - 1 do
        for tx = 0, tiles_x - 1 do
            for py = 0, 7 do
                for px = 0, 7 do
                    local gx, gy = tx * 8 + px, ty * 8 + py
                    local r, g, b, a = 0, 0, 0, 0
                    if gx < width and gy < height then
                        local p = pixels[gy * width + gx]
                        r, g, b, a = p[1], p[2], p[3], p[4]
                    end
                    
                    local m_idx = morton_interleave(px, py)
                    local target_idx = ((ty * tiles_x + tx) * 64) + m_idx + 1
                    swizzled[target_idx] = string.char(a, b, g, r)
                end
            end
        end
    end
    return table.concat(swizzled)
end

Async.run(function()
    local input = "sdmc:/input.bmp"
    local output = "sdmc:/output.3dst"

    if Core.Filesystem.fileExists(input) then
        Core.Debug.log("Loaded 32-Bit BMP...")
        local px, w, h = load_bmp(input)
        if px then
            local data = swizzle_3ds(px, w, h)
            local out_file = Core.Filesystem.open(output, "wb")
            if out_file then
                out_file:write(data)
                out_file:close()
                Core.Debug.log("Converted " .. w .. "x" .. h, true)
            end
        end
    else
        Core.Debug.logerror("Input missing at " .. input)
    end
end)
