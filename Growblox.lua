-- Jalankan di terminal VS Code dengan: lua Growblox.lua
local size = 5
local blocks = 3
local tiles = {}
local drops = {}
local selected
local selectedX, selectedY

local function showGrid()
    print("\nGrowblox   . kosong   B blok   o hasil")
    print("  1 2 3 4 5")
    for y = 1, size do
        local row = {}
        for x = 1, size do
            local index = (y - 1) * size + x
            row[x] = tiles[index] and "B" or drops[index] and "o" or "."
        end
        print(y .. " " .. table.concat(row, " "))
    end
    local selection = selected and ("Petak (%d, %d)"):format(selectedX, selectedY)
        or "Belum ada petak dipilih"
    print(("%s | Blok: %d"):format(selection, blocks))
end

local function isCoordinate(value)
    return value and value >= 1 and value <= size and value % 1 == 0
end

local function showHelp()
    print("Perintah: pilih X Y, pasang, hancurkan, ambil, bantuan, keluar")
end

showHelp()
while true do
    showGrid()
    io.write("> ")
    io.flush()
    local input = io.read("*l")
    if not input then
        break
    end

    local command, args = input:match("^%s*(%S+)%s*(.-)%s*$")
    if command == "keluar" and args == "" then
        break
    elseif command == "bantuan" and args == "" then
        showHelp()
    elseif command == "pilih" then
        local xText, yText = args:match("^(%S+)%s+(%S+)$")
        local x, y = tonumber(xText), tonumber(yText)
        if isCoordinate(x) and isCoordinate(y) then
            selectedX, selectedY = x, y
            selected = (y - 1) * size + x
        else
            print(("Koordinat harus bilangan bulat 1-%d."):format(size))
        end
    elseif args == "" and (command == "pasang" or command == "hancurkan" or command == "ambil") then
        if not selected then
            print("Pilih petak dulu.")
        elseif command == "pasang" then
            if tiles[selected] then
                print("Petak sudah berisi blok.")
            elseif blocks == 0 then
                print("Blok habis.")
            else
                tiles[selected] = true
                blocks = blocks - 1
                print("Blok dipasang.")
            end
        elseif command == "hancurkan" then
            if tiles[selected] then
                tiles[selected] = nil
                drops[selected] = (drops[selected] or 0) + 1
                print("Blok hancur. Ada hasil untuk diambil.")
            else
                print("Petak kosong.")
            end
        elseif drops[selected] then
            local amount = drops[selected]
            blocks = blocks + amount
            drops[selected] = nil
            print(("Blok diambil: %d."):format(amount))
        else
            print("Tidak ada hasil di petak ini.")
        end
    elseif command then
        print("Perintah tidak dikenal. Ketik bantuan.")
    end
end
