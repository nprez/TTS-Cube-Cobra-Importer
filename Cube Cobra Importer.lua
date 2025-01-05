local cubeId = ""
local magicBack = "http://cloud-3.steamusercontent.com/ugc/1044218919659567154/72AEBC61B3958199DE4389B0A934D68CE53D030B/"

local delaySeconds = 0.1
local retryDelaySeconds = 1

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
        local openQuotes = 0
        while j <= #temp and not (string.sub(temp, j, j) == "," and openQuotes == 0) do
            if string.sub(temp, j, j) == "\"" then
                if openQuotes == 0 then
                    openQuotes = 1
                else
                    openQuotes = 0
                end
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

function createCard(name, cardFace, cardBack, player, hOffset, cubeIndex)
    local customCardData = {
        face = cardFace,
        back = cardBack
    }

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
    newCard.setName(name)
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
    local url = "https://cubecobra.com/cube/download/csv/"..urlencode(cubeId)
    WebRequest.get(
        url,
        function(data)
            parseCubeCobraData(data, color)
        end
    )
end

function parseCubeCobraData(data, color)
    local rows = split(string.gsub(data.text,"\r",""), "\n")
    local headers = split(rows[1], ",")
    local nameCol = 1
    local setCol = 5
    local collectorCol = 6
    local maybeBoardCol = 11
    for i,columnHeader in ipairs(headers) do
        if columnHeader == "Name" then
            nameCol = i
        elseif columnHeader == "Set" then
            setCol = i
        elseif columnHeader == "Collector Number" then
            collectorCol = i
        elseif columnHeader == "Maybeboard" then
            maybeBoardCol = i
        end
    end
    
    for i, cardLine in ipairs(rows) do
        local card = split(cardLine, ",")
        if i ~= 1 and card[maybeBoardCol] == "false" then
            local url = "https://api.scryfall.com/cards/"..string.gsub(card[setCol],"\"","").."/"..string.gsub(card[collectorCol],"\"","")
            Wait.time(
                function()
                    WebRequest.get(
                        url,
                        function(data)
                            parseCardData(data, color, i, card[nameCol], url)
                        end
                    )
                end,
                delaySeconds
            )
        end
    end
end

function parseCardData(data, color, index, cardName, url)
    local cardData = JSON.decode(data.text)
    local status, err = pcall(function () JSON.decode(data.text) end)
    if data.is_error or not status or cardData["status"] == 429 then
        if cardData["status"] == 429 then
            Wait.time(
                function()
                    WebRequest.get(
                        url,
                        function(data)
                            parseCardData(data, color, index, cardName, url)
                        end
                    )
                end,
                retryDelaySeconds
            )
            return
        else
            printToAll("Card not found: "..cardName, {r=255, g=255, b=255})
            return
        end
    end
    local name = cardData["name"]
    local cardFront
    if cardData["card_faces"] ~= nil and #cardData["card_faces"] > 1 and cardData["card_faces"][1]["image_uris"] ~= nil then
        cardFront = cardData["card_faces"][1]["image_uris"]["normal"]
        local cardBack = cardData["card_faces"][2]["image_uris"]["normal"]
        createCard(name, cardFront, cardBack, Player[color], 0, index)
        createCard(name, cardFront, magicBack, Player[color], -1, index)
    else
        if cardData["image_uris"] == nil then
            printToAll("Can't find images for card: "..cardName, {r=255, g=255, b=255})
        else
            cardFront = cardData["image_uris"]["normal"]
            createCard(name, cardFront, magicBack, Player[color], 0, index)
        end
    end
    
    --get related cards
    if cardData["all_parts"] then
        for _,part in ipairs(cardData["all_parts"]) do
            if part["component"] == "token" or part["component"] == "meld_result" then
                Wait.time(
                    function()
                        WebRequest.get(
                            part["uri"],
                            function(data)
                                parseRelatedCardData(data, color, part["uri"])
                            end
                        )
                    end,
                    delaySeconds
                )
            elseif part["component"] == "combo_piece" and string.find(part["type_line"], "Emblem", 1, true) then
                Wait.time(
                    function()
                        WebRequest.get(
                            part["uri"],
                            function(data)
                                parseRelatedCardData(data, color, part["uri"])
                            end
                        )
                    end,
                    delaySeconds
                )
            end
        end
    end
end

function parseRelatedCardData(data, color, url)
    local cardData = JSON.decode(data.text)
    local status, err = pcall(function () JSON.decode(data.text) end)
    if data.is_error or not status or cardData["status"] == 429 then
        if cardData["status"] == 429 then
            Wait.time(
                function()
                    WebRequest.get(url,
                        function(data)
                            parseRelatedCardData(data, color, url)
                        end
                    )
                end,
                retryDelaySeconds
            )
            return
        else
            printToAll("Related card not found: "..url, {r=255, g=255, b=255})
            return
        end
    end
    local name = cardData["name"]
    if cardData["layout"] == "transform" or cardData["layout"] == "modal_dfc" then
        local cardFront = cardData["card_faces"][1]["image_uris"]["normal"]
        createCard(name, cardFront, magicBack, Player[color], -1, 0)
    elseif cardData["layout"] == "double_faced_token" then
        local cardFront = cardData["card_faces"][1]["image_uris"]["normal"]
        local cardBack = cardData["card_faces"][2]["image_uris"]["normal"]
        createCard(name, cardFront, cardBack, Player[color], -1, 0)
    else
        local cardFront = cardData["image_uris"]["normal"]
        createCard(name, cardFront, magicBack, Player[color], -1, 0)
    end
end