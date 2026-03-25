-- LunaCore 0.1X.X BMP to 3DST Converter

-- GLOBAL VARS
local SKIN_DIR = "sdmc:/Minecraft 3DS/skins/"
local OUT_DIR  = "sdmc:/Minecraft 3DS/output/"


-- HELPER FUNCTION(S)
local function read_uint16_le(data, offset)
    local b1, b2 = data:byte(offset, offset+1)
    return b1 + b2 * 256
end

local function read_uint32_le(data, offset)
    local b1, b2, b3, b4 = data:byte(offset, offset+3)
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function write_u32_le(val)
    local b1 = val % 256
    local b2 = math.floor(val / 256) % 256
    local b3 = math.floor(val / 65536) % 256
    local b4 = math.floor(val / 16777216) % 256
    return string.char(b1, b2, b3, b4)
end

-- REPLAICATE 3DS MORTON TEXTURE INTERLEAVE
local function morton_interleave(x, y)
    local res = 0
    for i = 0, 2 do
        local bit_x = math.floor(x / (2^i)) % 2
        local bit_y = math.floor(y / (2^i)) % 2
        res = res + (bit_x * (2^(2*i))) + (bit_y * (2^(2*i + 1)))
    end
    return res
end


-- BMP LOADER
local function load_bmp(path)
    local file = Core.Filesystem.open(path, "rb")
    if not file then return nil end

    local data = file:read("*all")
    file:close()

    if not data or data:sub(1,2) ~= "BM" then return nil end

    local pixel_offset = read_uint32_le(data, 11)
    local width  = read_uint32_le(data, 19)
    local height = read_uint32_le(data, 23)
    local bpp    = read_uint16_le(data, 29)

    if bpp ~= 32 then
        Core.Debug.logerror("Only 32-bit BMP supported")
        return nil
    end

    local pixels = {}

    for y = height-1, 0, -1 do
        for x = 0, width-1 do
            local offset = pixel_offset + (y * width + x) * 4 + 1
            local b, g, r, a = data:byte(offset, offset+3)
            pixels[((height-1-y)*width)+x] = {r, g, b, a or 255}
        end
    end

    return pixels, width, height
end

-- REPLICATE 3DS TILING SWIZZLE
local function swizzle_3ds(pixels, width, height)
    local swizzled = {}
    local tiles_x = math.ceil(width / 8)
    local tiles_y = math.ceil(height / 8)

    for ty = 0, tiles_y - 1 do
        for tx = 0, tiles_x - 1 do
            for py = 0, 7 do
                for px = 0, 7 do
                    local gx, gy = tx*8 + px, ty*8 + py

                    local r,g,b,a = 0,0,0,0
                    if gx < width and gy < height then
                        local p = pixels[gy*width + gx]
                        r,g,b,a = p[1],p[2],p[3],p[4]
                    end

                    local m = morton_interleave(px, py)
                    local idx = ((ty * tiles_x + tx) * 64) + m + 1
                    swizzled[idx] = string.char(a, b, g, r)
                end
            end
        end
    end

    return table.concat(swizzled)
end

-- HEADER BUILDER
local function build_header(w, h)
    local header = {}
    header[#header+1] = string.char(
        0x33,0x44,0x53,0x54,
        0x03,0x00,0x00,0x00,
        0x00,0x00,0x00,0x00
    )

    header[#header+1] = write_u32_le(w)
    header[#header+1] = write_u32_le(h)
    header[#header+1] = write_u32_le(w)
    header[#header+1] = write_u32_le(h)

    header[#header+1] = string.char(0x01,0x00,0x00,0x00)

    return table.concat(header)
end

-- BASICALLY THE MAIN FUNCTIONS LOL
local function convert_file(path)
    local px, w, h = load_bmp(path)
    if not px then return end

    local data = swizzle_3ds(px, w, h)
    local header = build_header(w, h)

    local final = header .. data

    -- pad to 0x4020
    if #final < 0x4020 then
        final = final .. string.rep("\0", 0x4020 - #final)
    end

    Core.Filesystem.createDirectory(OUT_DIR)

    local name = path:match("([^/]+)%.bmp$")
    local out_path = OUT_DIR .. name .. ".3dst"

    local f = Core.Filesystem.open(out_path, "wb")
    if f then
        f:write(final)
        f:close()
        Core.Debug.log("Converted: "..name, true)
    end
end

-- MENU SETUP
local root = Core.Menu.getMenuFolder()
local folder = root:newFolder("BMP Skin Converter")

local function populate_menu()
    if not Core.Filesystem.directoryExists(SKIN_DIR) then
        Core.Debug.logerror("Skin dir missing")
        return
    end

    local files = Core.Filesystem.getDirectoryElements(SKIN_DIR)

    for i=1,#files do
        local file = files[i]

        if file:lower():match("%.bmp$") then
            folder:newEntry(file, function()
                convert_file(SKIN_DIR .. file)
            end)
        end
    end
end

populate_menu()