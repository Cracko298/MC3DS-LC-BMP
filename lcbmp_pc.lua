local function read_uint16_le(data, offset)
    local b1, b2 = data:byte(offset, offset+1)
    return b1 + b2*256
end

local function read_uint32_le(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset+3)
    return b1 + b2*256 + b3*65536 + b4*16777216
end

local function morton_interleave(x, y)
    local function part1by1(n)
        n = n & 0xFFFF
        n = (n | (n << 8)) & 0x00FF00FF
        n = (n | (n << 4)) & 0x0F0F0F0F
        n = (n | (n << 2)) & 0x33333333
        n = (n | (n << 1)) & 0x55555555
        return n
    end
    return part1by1(x) | (part1by1(y) << 1)
end

local function extract_channel(value, mask)
    if mask == 0 then return 0 end
    local shift = 0
    local tmp_mask = mask
    while tmp_mask % 2 == 0 do
        tmp_mask = tmp_mask / 2
        shift = shift + 1
    end
    local bits = 0
    tmp_mask = mask
    while tmp_mask > 0 do
        if tmp_mask % 2 == 1 then bits = bits + 1 end
        tmp_mask = math.floor(tmp_mask / 2)
    end
    return math.floor(((value & mask) >> shift) * 255 / ((1 << bits)-1))
end

local function load_bmp(path)
    local f = assert(io.open(path, "rb"))
    local data = f:read("*all")
    f:close()

    local signature = data:sub(1,2)
    assert(signature == "BM", "Not a BMP file")

    local header_size = read_uint32_le(data, 15) 
    local pixel_offset = read_uint32_le(data, 11)

    local width  = read_uint32_le(data, 19)
    local height = read_uint32_le(data, 23)
    local bpp    = read_uint16_le(data, 29)

    print("BMP info:", width, height, bpp)

    if bpp ~= 32 then
        print("Warning: bpp ~= 32, forcing alpha=255")
    end

    local pixels = {}
    for y = height-1, 0, -1 do
        for x = 0, width-1 do
            local offset = pixel_offset + (y*width + x)*(bpp/8)
            local b,g,r,a
            if bpp == 32 then
                b,g,r,a = data:byte(offset+1, offset+4)
            elseif bpp == 24 then
                b,g,r = data:byte(offset+1, offset+3)
                a = 255
            else
                error("Unsupported BMP bpp: "..bpp)
            end
            pixels[y*width + x] = {r,g,b,a}
        end
    end
    return pixels, width, height
end

local function swizzle_3ds(pixels, width, height)
    local swizzled = {}
    local function tile_index(x, y)
        local tile_x = math.floor(x / 8)
        local tile_y = math.floor(y / 8)
        local morton = morton_interleave(x % 8, y % 8)
        return ((tile_y * math.ceil(width/8) + tile_x) * 64) + morton + 1
    end
    
    for y = 0, height-1 do
        for x = 0, width-1 do
            local idx = tile_index(x, y)
            local px = pixels[y*width + x]
            swizzled[idx] = string.char(px[4], px[3], px[2], px[1])
        end
    end
    return table.concat(swizzled)
end

local function save_raw(path, data)
    local f = assert(io.open(path, "wb"))
    f:write(data)
    f:close()
end

-- Main
local input_file = "input.bmp"
local output_file = "output.3dst"

local pixels, width, height = load_bmp(input_file)
local swizzled_data = swizzle_3ds(pixels, width, height)
save_raw(output_file, swizzled_data)

print("Conversion complete: "..output_file)
