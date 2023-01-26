local BANK = {
    Data = {}
}

local activeBlips, atmPoints, markerPoints = {}, {}, {}, {}
local uiActive, inMenu = false, false, false

--Functions
    -- General data collecting thread
    function BANK:Thread()
        self:CreateBlips()
        local data = self.Data

        CreateThread(function()
            while ESX.PlayerLoaded do
                data.ped = ESX.PlayerData.ped
                data.coord = GetEntityCoords(data.ped)
                atmPoints = {}

                if (IsPedOnFoot(data.ped) and not ESX.PlayerData.dead) and not inMenu then
                    for i = 1, #Config.AtmModels do
                        local atm = GetClosestObjectOfType(data.coord.x, data.coord.y, data.coord.z, 0.7, Config.AtmModels[i], false, false, false)
                        if atm ~= 0 then
                            atmPoints[#atmPoints+1] = GetEntityCoords(atm)
                        end
                    end
                end

                if next(atmPoints) and not uiActive then
                    self:TextUi(true, true)
                end
        
                if not next(atmPoints) and uiActive then
                    self:TextUi(false)
                end
                                
                Wait(1000)
            end
        end)

        CreateThread(function()
            for i = 1, #Config.Banks do
                ESX.CreateMarker("bank"..i, Config.Banks[i].Position.xyz, Config.DrawMarker, TranslateCap("press_e_banking"), {
                drawMarker = Config.ShowMarker,
                key = 38,
                scale = {x = 0.5, y = 0.5, z = 0.5}, -- Scale of the marker
                sprite = 20, -- type of the marker
                colour = {r = 50, g = 200, b = 50, a = 200} -- R, G, B, A, colour system
                }, function()
                    if not uiActive then
                        self:HandleUi(true)
                        ESX.HideUI()
                    end
                end)
            end
        end)
    end

    -- Create Blips
    function BANK:CreateBlips()
        local tmpActiveBlips = {}
        for i = 1, #Config.Banks do
            if type(Config.Banks[i].Blip) == 'table' and Config.Banks[i].Blip.Enabled then
                local position = Config.Banks[i].Position
                local bInfo = Config.Banks[i].Blip
                local blip = AddBlipForCoord(position.x, position.y, position.z)
                SetBlipSprite(blip, bInfo.Sprite)
                SetBlipScale(blip, bInfo.Scale)
                SetBlipColour(blip, bInfo.Color)
                SetBlipAsShortRange(blip, true)
                BeginTextCommandSetBlipName('STRING')
                AddTextComponentSubstringPlayerName(bInfo.Label)
                EndTextCommandSetBlipName(blip)
                tmpActiveBlips[#tmpActiveBlips + 1] = blip
            end
        end

        activeBlips = tmpActiveBlips
    end

    function BANK:TextUi(state, atm)
        uiActive = state
        if not state then
            return ESX.HideUI()
        end
        ESX.TextUI(TranslateCap('press_e_banking'))
        CreateThread(function()
            while uiActive do
                if IsControlJustReleased(0, 38) then
                    self:HandleUi(true, atm)
                    self:TextUi(false)
                end
            Wait(0)
            end
        end)
    end

    -- Remove blips
    function BANK:RemoveBlips()
        for i = 1, #activeBlips do
            if DoesBlipExist(activeBlips[i]) then
                RemoveBlip(activeBlips[i])
            end
        end
        activeBlips = {}
    end

    -- Open / Close ui
    function BANK:HandleUi(state, atm)
        atm = atm or false
        SetNuiFocus(state, state)
        inMenu = state
        if not state then
            SendNUIMessage({
                showMenu = false
            })
            return
        end
        ESX.TriggerServerCallback('esx_banking:getPlayerData', function(data)
            SendNUIMessage({
                showMenu = true,
                openATM = atm,
                datas = {
                    your_money_panel = {
                        accountsData = {{
                            name = "cash",
                            amount = data.money
                        }, {
                            name = "bank",
                            amount = data.bankMoney
                        }}
                    },
                    bankCardData = {
                        bankName = TranslateCap('bank_name'),
                        cardNumber = "2232 2222 2222 2222",
                        createdDate = "08/08",
                        name = data.playerName
                    },
                    transactionsData = data.transactionHistory
                }
            })
        end)
    end

    function BANK:LoadNpc(index, netID)
        CreateThread(function()
            while not NetworkDoesEntityExistWithNetworkId(netID) do
                Wait(200)
            end
            local npc = NetworkGetEntityFromNetworkId(netID)
            TaskStartScenarioInPlace(npc, Config.Peds[index].Scenario, 0, true)
            SetEntityProofs(npc, true, true, true, true, true, true, true, true)
            SetBlockingOfNonTemporaryEvents(npc, true)
            FreezeEntityPosition(npc, true)
            SetPedCanRagdollFromPlayerImpact(npc, false)
            SetPedCanRagdoll(npc, false)
            SetEntityAsMissionEntity(npc, true, true)
            SetEntityDynamic(npc, false)
        end)
    end

-- Events
RegisterNetEvent('esx_banking:closebanking', function()
    BANK:HandleUi(false)
end)

RegisterNetEvent('esx_banking:pedHandler', function(netIdTable)
    for i = 1, #netIdTable do
        BANK:LoadNpc(i, netIdTable[i])
    end
end)

RegisterNetEvent('esx_banking:updateMoneyInUI', function(doingType, bankMoney, money)
    SendNUIMessage({
        updateData = true,
        data = {
            type = doingType,
            bankMoney = bankMoney,
            money = money
        }
    })
end)

-- Handlers
    -- Resource starting
    AddEventHandler('onResourceStart', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        BANK:Thread()
    end)

    -- Enable the script on player loaded 
    RegisterNetEvent('esx:playerLoaded', function()
        BANK:Thread()
    end)

    -- Resource stopping
    AddEventHandler('onResourceStop', function(resource)
        if resource ~= GetCurrentResourceName() then return end
        BANK:RemoveBlips()
    end)

-- Nui Callbacks
RegisterNUICallback('close', function(data, cb)
    BANK:HandleUi(false)
    cb('ok')
end)

RegisterNUICallback('clickButton', function(data, cb)
    if not data or not inMenu then
        return cb('ok')
    end

    TriggerServerEvent("esx_banking:doingType", data)
    cb('ok')
end)

RegisterNUICallback('checkPincode', function(data, cb)
    if not data or not inMenu then
        return cb('ok')
    end

    ESX.TriggerServerCallback("esx_banking:checkPincode", function(pincode)
        if pincode then
            cb({
                success = true
            })
            ESX.ShowNotification(TranslateCap('pincode_found'), "success")

        else
            cb({
                error = true
            })
            ESX.ShowNotification(TranslateCap('pincode_not_found'), "error")
        end
    end, data)
end)