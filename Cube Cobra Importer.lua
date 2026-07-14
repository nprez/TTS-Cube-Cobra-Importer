local cubeId = ""
local magicBack = "https://steamusercontent-a.akamaihd.net/ugc/16484457864693312264/CEB9227AD5C35A1561B0F3F8AE6975656A0B066E/"

local cubeCobraURL = "https://cubecobra.com/cube/api/cubeJSON/";
local cubeCobraTokenURL = "https://assets.cubecobra.com/cardimages/";

local delaySeconds = 0.1

local headers = {
    Accept = "*/*",
    ["User-Agent"] = "MTGReprintScript/1.0"
}

function urlencode (str)
    str = string.gsub (
        str,
        "([^0-9a-zA-Z !'()*._~-])",
        function (c) return string.format ("%%%02X", string.byte(c)) end
    )
    str = string.gsub (str, " ", "+")
    return str
end

function urldecode (str)
    str = string.gsub (str, "+", " ")
    str = string.gsub (str, "%%(%x%x)", function(h) return string.char(tonumber(h,16)) end)
    return str
end

function split(str, delim)
    if delim == "," then
        --need to account for entries that have commas in them
        return csvSplit(str)
    else
        local t = {}
        local temp = str
        local index = string.find(temp, delim)
        while(index ~= nil) do
            table.insert(t, string.sub(temp, 1, index-1))
            temp = string.sub(temp, index+1)
            index = string.find(temp, delim)
        end
        table.insert(t, temp)
        return t
    end
end

function csvSplit(str)
    local t = {}
    local temp = str
    local i = 1
    while i <= #temp do
        local j = i
        local quotes = 0
        while j <= #temp and not (string.sub(temp, j, j) == "," and quotes % 2 == 0) do
            if string.sub(temp, j, j) == "\"" then
                quotes = quotes + 1
            end
            
            j = j + 1
        end
        
        if j > #temp then
            table.insert(t, string.sub(temp, i, #temp))
            i = j
        else
            table.insert(t, string.sub(temp, i, j-1))
            i = j + 1
        end
    end
    return t
end

function createCard(name, cardFace, cardBack, player, hOffset, cubeIndex, customImg, customBackImg)
    local customCardData = {
        face = cardFace,
        back = cardBack
    }
    if customImg ~= nil and #customImg > 0 then
        customImg = string.sub(customImg, 2, #customImg-1)
        customCardData.face = customImg
    end
    if customBackImg ~= nil and #customBackImg > 0 then
        customBackImg = string.sub(customBackImg, 2, #customBackImg-1)
        customCardData.back = customBackImg
    end

    local playerSeat = player.getHandTransform()
    local shiftForward = 1
    if hOffset >= 0 then
        shiftForward = 1 + math.floor(hOffset / 3)
    end
    local shiftRight = hOffset
    if hOffset >=0 then
        shiftRight = hOffset % 3
    end
    local spawnData = {
        type = "CardCustom",
        position = playerSeat.position + (playerSeat.forward * 5 * shiftForward) + (playerSeat.right * 4 * shiftRight) + (playerSeat.up * 0.05 * cubeIndex),
        rotation = vector(playerSeat.rotation.x, (playerSeat.rotation.y + 180) % 360, playerSeat.rotation.z),
        scale = vector(1.5, 1, 1.5)
    }

    local newCard = spawnObject(spawnData)
    if name ~= nil then
        newCard.setName(name)
    end
    newCard.setCustomObject(customCardData)
end

function cubeIdInput(obj, color, input, stillEditing)
    if not stillEditing then
        cubeId = input
    end
end

self.createInput({
    input_function="cubeIdInput", function_owner=self, tooltip="Cube ID",
    alignment=3, position={0,0.5,-0.25}, height=100, width=400,
    font_size=52, alignment=3, validation=1, label="Cube ID", value=cubeId
})

self.createButton({
    click_function = "import",
    function_owner = self,
    label          = "Import",
    position       = {0, .5, .25},
    rotation       = {0, 0, 0},
    width          = 400,
    height         = 200,
    font_size      = 78,
    color          = {0, .5, 0},
    font_color     = {1, 1, 1},
    tooltip        = "Import Cube",
})

function import(obj, color, alt_click)
    local url = cubeCobraURL..urlencode(cubeId)
    printToAll("Importing from "..url, {r=255, g=255, b=255})
    WebRequest.custom(
        url,
        "GET",
        true,
        nil,
        headers,
        function(data)
            if data.is_error then
                printToAll(data.error, {r=255, g=0, b=0})
            else
               parseCubeCobraData(JSON.decode(data.text), color) 
            end
        end
    )
end

function parseCubeCobraData(data, color)
    for i, card in ipairs(data["cards"]["mainboard"]) do
        local cardName = card["details"]["name"]
        local cardFront = card["details"]["image_normal"]
        local cardBack = card["details"]["image_flip"]
        local isDFC = cardBack ~= nil
        if not isDFC then
            cardBack = magicBack
        end
        local customImg = card["imgUrl"]
        local customBackImg = card["imgBackUrl"]
        
        Wait.time(
            function()
                createCard(cardName, cardFront, cardBack, Player[color], 0, i, customImg, customBackImg)
                if isDFC then
                    Wait.time(
                        function()
                            createCard(cardName, cardFront, magicBack, Player[color], -1, i, customImg, customBackImg)
                        end,
                        delaySeconds
                    )
                end
                
                local tokens = card["details"]["tokens"]
                if tokens ~= nil then
                    for j, token in ipairs(tokens) do
                        Wait.time(
                            function()
                                local tokenUrl = cubeCobraTokenURL..token.."/normal.webp"
                                createCard(nil, tokenUrl, magicBack, Player[color], -1, j, nil, nil)
                            end,
                            delaySeconds
                        )
                    end
                end
            end,
            delaySeconds
        )
    end
end