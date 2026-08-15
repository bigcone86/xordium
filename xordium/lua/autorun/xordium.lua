-- Создаем папку addons/creepy_npc/lua/autorun/
-- и сохраняем этот файл как creepy_npc.lua

AddCSLuaFile()

if SERVER then
    -- Таблица для хранения созданных NPC
    local creepyNPCs = {}
    local taxCollectors = {}
    local shadowEntities = {}
    
    -- Таблица для Монстра Annihilation
    local annihilationMonsters = {}

    -- ======================================================================
    -- 1. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ (Объявлены в самом начале)
    -- ======================================================================

    -- Функция генерации несуразного текста для кика (200 символов)
    local function GenerateKickReason()
        local chars = "AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz"
        local result = ""
        for i = 1, 200 do
            result = result .. chars[math.random(1, #chars)]
        end
        return result
    end

    -- Функции включения/отключения затемнения
    local function ActivateGlobalEffects()
        for _, ply in pairs(player.GetAll()) do
            if IsValid(ply) then
                ply:SendLua("annihilationActive = true; targetShadowAlphaAnn = 64")
            end
        end
    end

    local function DeactivateGlobalEffects()
        for _, ply in pairs(player.GetAll()) do
            if IsValid(ply) then
                ply:SendLua("annihilationActive = false; targetShadowAlphaAnn = 0")
            end
        end
    end

    -- ======================================================================
    -- 2. ФУНКЦИЯ СПАВНА ANNIHILATION
    -- ======================================================================

    local function SpawnAnnihilationMonster(spawnPos)
        local monster = ents.Create("npc_citizen")
        if not IsValid(monster) then return nil end
        
        monster:SetPos(spawnPos + Vector(0,0,20))
        monster:SetModel("models/humans/group01/male_06.mdl")
        monster:SetKeyValue("spawnflags", "1") 
        monster:Spawn()
        
        monster:SetHealth(99999)
        monster:SetMaxHealth(99999)
        monster:SetColor(Color(0, 0, 0, 255))
        monster:SetMaterial("") 
        monster:SetModelScale(2.5, 0)
        monster:SetRenderMode(RENDERMODE_NORMAL)
        monster:SetMoveType(MOVETYPE_STEP) 
        monster:SetSolid(SOLID_BBOX)
        monster:DrawShadow(true)
        monster:SetSequence(monster:LookupSequence("walk_all")) 
        monster:SetPlaybackRate(1.5)

        monster:EmitSound("ambient/levels/labs/teleport_mechanism.wav", 80, 50, 1, CHAN_AUTO)
        PrintMessage(HUD_PRINTTALK, "Annihilation.")
        
        ActivateGlobalEffects()

        local chaseStartTime = CurTime() + 2 -- Фора 2 секунды

        timer.Create("AnnihilationChase_" .. monster:EntIndex(), 0.1, 0, function()
            if not IsValid(monster) then 
                timer.Remove("AnnihilationChase_" .. monster:EntIndex())
                DeactivateGlobalEffects()
                return 
            end

            if CurTime() < chaseStartTime then return end

            local monsterPos = monster:GetPos()
            
            local alivePlayers = {}
            for _, ply in pairs(player.GetAll()) do
                if IsValid(ply) and ply:Alive() then
                    table.insert(alivePlayers, ply)
                end
            end

            if #alivePlayers == 0 then
                if IsValid(monster) then
                    timer.Remove("AnnihilationChase_" .. monster:EntIndex())
                    monster:Remove()
                    annihilationMonsters[monster:EntIndex()] = nil
                end
                DeactivateGlobalEffects()
                return
            end

            local nearestDist = 99999
            local nearestPlayer = nil

            for _, ply in pairs(alivePlayers) do
                local dist = monsterPos:Distance(ply:GetPos())
                if dist < nearestDist then
                    nearestDist = dist
                    nearestPlayer = ply
                end
            end

            if nearestPlayer then
                local targetPos = nearestPlayer:GetPos()
                local direction = (targetPos - monsterPos):GetNormalized()
                local speed = 200
                
                local newPos = monsterPos + direction * speed
                monster:SetPos(newPos)
                local ang = (targetPos - newPos):Angle()
                monster:SetAngles(Angle(0, ang.yaw, 0))

                if nearestDist < 100 then
                    local reason = GenerateKickReason()
                    nearestPlayer:Kick(reason)
                    nearestPlayer = nil 
                end
            end
        end)

        annihilationMonsters[monster:EntIndex()] = monster
        return monster
    end

    local function TriggerAnnihilationSpawn()
        local players = player.GetAll()
        if #players == 0 then return end
        
        local targetPlayer = players[math.random(#players)]
        if not IsValid(targetPlayer) then return end
        
        local forward = targetPlayer:GetForward()
        local randomAngle = math.random(-45, 45)
        local dir = Vector(forward.x, forward.y, 0):GetNormalized()
        dir:Rotate(Angle(0, randomAngle, 0))
        
        local distance = math.random(250, 400)
        local spawnPos = targetPlayer:GetPos() + (dir * distance)
        
        local trace = util.TraceLine({
            start = spawnPos + Vector(0, 0, 100),
            endpos = spawnPos - Vector(0, 0, 1000),
            filter = targetPlayer
        })
        
        if trace.Hit then
            spawnPos = trace.HitPos + Vector(0, 0, 5)
        else
            spawnPos.z = targetPlayer:GetPos().z + 5
        end
        
        SpawnAnnihilationMonster(spawnPos)
    end

    -- ======================================================================
    -- 3. ФУНКЦИИ СТАРЫХ NPC (Красные, Тени, Коллекторы) - ОБЪЯВЛЕНЫ ДО КОМАНД
    -- ======================================================================

    local function CheckPlayerDeaths()
        for _, npc in pairs(creepyNPCs) do
            if not IsValid(npc) then continue end
            for _, ply in pairs(player.GetAll()) do
                if not IsValid(ply) or not ply:Alive() then continue end
                local distance = ply:GetPos():Distance(npc:GetPos())
                if distance <= 100 then
                    ply:Kill()
                    local effectData = EffectData()
                    effectData:SetOrigin(ply:GetPos())
                    effectData:SetStart(ply:GetPos())
                    util.Effect("Explosion", effectData, true, true)
                    PrintMessage(HUD_PRINTTALK, ply:Nick() .. " killed by Red Phosphorus")
                end
            end
        end
    end
    
    local function CheckShadows()
        for _, data in pairs(shadowEntities) do
            local shadow = data.shadow
            if not IsValid(shadow) then continue end
            local targetPlayer = data.target
            if not IsValid(targetPlayer) or not targetPlayer:Alive() then
                if IsValid(shadow) then shadow:Remove() end
                shadowEntities[shadow:EntIndex()] = nil
                continue
            end
            if data.lastSoundTime == nil or CurTime() - data.lastSoundTime > 2 then
                shadow:EmitSound("my_sounds/shadow_chase.wav", 75, math.random(90, 110), 1, CHAN_AUTO)
                data.lastSoundTime = CurTime()
            end
            if data.lastPos then
                local currentPos = shadow:GetPos()
                local targetPos = data.lastPos
                local direction = (targetPos - currentPos):GetNormalized()
                local speed = 100 
                local newPos = currentPos + direction * speed
                if currentPos:Distance(targetPos) < 20 then
                    data.lastPos = targetPlayer:GetPos()
                    data.lastAngles = targetPlayer:EyeAngles()
                end
                shadow:SetPos(newPos)
                local lookAngle = (targetPlayer:GetPos() - newPos):Angle()
                shadow:SetAngles(Angle(0, lookAngle.yaw, 0))
            end
            local distance = shadow:GetPos():Distance(targetPlayer:GetPos())
            if distance < 50 then
                local skull = ents.Create("prop_physics")
                skull:SetModel("models/gibs/hgibs.mdl")
                skull:SetPos(targetPlayer:GetPos())
                skull:Spawn()
                targetPlayer:Kill()
                shadow:Remove()
                shadowEntities[shadow:EntIndex()] = nil
                timer.Simple(30, function() if IsValid(skull) then skull:Remove() end end)
            end
        end
    end
    
    local function SpawnShadow(ply)
        if not IsValid(ply) or not ply:Alive() then return end
        local shadow = ents.Create("npc_citizen")
        if not IsValid(shadow) then return end
        local spawnPos = ply:GetPos() + Vector(math.random(-200, 200), math.random(-200, 200), 0)
        shadow:SetPos(spawnPos)
        shadow:Spawn()
        shadow:SetHealth(99999)
        shadow:SetMaxHealth(99999)
        shadow:SetColor(Color(0, 0, 0, 255))
        shadow:SetMaterial("models/props_combine/portalball")
        shadow:SetRenderMode(RENDERMODE_TRANSALPHA)
        shadow:SetMoveType(MOVETYPE_NOCLIP)
        shadow:SetSolid(SOLID_BBOX)
        shadow:SetNoDraw(false)
        shadow:DrawShadow(false)
        shadow:SetSequence(0)
        shadow:ResetSequence(0)
        shadow:SetCycle(0)
        shadow:SetPlaybackRate(0)
        shadow:EmitSound("my_sounds/shadow_chase.wav", 80, 100, 1, CHAN_AUTO)
        shadowEntities[shadow:EntIndex()] = {
            shadow = shadow,
            target = ply,
            lastPos = ply:GetPos(),
            lastAngles = ply:EyeAngles(),
            lastSoundTime = CurTime()
        }
        timer.Create("ShadowUpdate_" .. shadow:EntIndex(), 0.5, 0, function()
            if IsValid(shadow) and IsValid(ply) then
                shadowEntities[shadow:EntIndex()].lastPos = ply:GetPos()
                shadowEntities[shadow:EntIndex()].lastAngles = ply:EyeAngles()
            end
        end)
        timer.Simple(120, function()
            if IsValid(shadow) then
                shadow:Remove()
                timer.Remove("ShadowUpdate_" .. shadow:EntIndex())
                shadowEntities[shadow:EntIndex()] = nil
            end
        end)
    end
    
    local function CheckTaxCollectors()
        for _, data in pairs(taxCollectors) do
            local npc = data.npc
            if not IsValid(npc) then continue end
            local targetPlayer = data.target
            if not IsValid(targetPlayer) or not targetPlayer:Alive() then
                if IsValid(npc) then npc:Remove() end
                taxCollectors[npc:EntIndex()] = nil
                continue
            end
            if data.waitingForProp and CurTime() - data.spawnTime > 5 then
                data.waitingForProp = false
                data.chasing = true
                npc:SetColor(Color(0, 0, 0, 255))
                npc:SetMaterial("")
                npc:SetSequence(0)
                npc:ResetSequence(0)
                npc:SetCycle(0)
                npc:SetPlaybackRate(0)
                npc:SetMoveType(MOVETYPE_NOCLIP)
                npc:SetSolid(SOLID_BBOX)
                PrintMessage(HUD_PRINTTALK, "[Tax Collector] you can't escape me now, " .. targetPlayer:Nick())
            end
            if data.chasing then
                local npcPos = npc:GetPos()
                local playerPos = targetPlayer:GetPos()
                local targetPos = Vector(playerPos.x, playerPos.y, playerPos.z)
                local direction = (targetPos - npcPos):GetNormalized()
                local speed = 80
                local newPos = npcPos + direction * speed
                newPos.z = targetPos.z
                local angle = (targetPos - npcPos):Angle()
                npc:SetAngles(Angle(0, angle.yaw, 0))
                npc:SetPos(newPos)
                local distance = npcPos:Distance(playerPos)
                if distance < 50 then
                    targetPlayer:Kick("...---...")
                    if IsValid(npc) then npc:Remove() end
                    taxCollectors[npc:EntIndex()] = nil
                end
            end
            if data.waitingForProp then
                for _, prop in pairs(ents.FindByClass("prop_physics")) do
                    if IsValid(prop) then
                        local distance = npc:GetPos():Distance(prop:GetPos())
                        if distance < 100 then
                            PrintMessage(HUD_PRINTTALK, "[Tax Collector] oh yeea props")
                            npc:EmitSound("items/suitchargeok1.wav", 75, 100, 1, CHAN_AUTO)
                            npc:SetColor(Color(0, 255, 0, 255))
                            timer.Simple(1, function()
                                if IsValid(npc) then npc:Remove() end
                                taxCollectors[npc:EntIndex()] = nil
                            end)
                            data.waitingForProp = false
                            break
                        end
                    end
                end
            end
        end
    end
    
    local function SpawnTaxCollector()
        local players = player.GetAll()
        if #players == 0 then return end
        local targetPlayer = players[math.random(#players)]
        local playerPos = targetPlayer:GetPos()
        local behindPos = playerPos - (targetPlayer:GetForward() * 200) + Vector(0, 0, 70)
        local npc = ents.Create("npc_citizen")
        if not IsValid(npc) then return end
        npc:SetModel("models/humans/group01/male_09.mdl")
        npc:SetPos(behindPos)
        npc:Spawn()
        npc:SetHealth(99999)
        npc:SetMaxHealth(99999)
        npc:SetColor(Color(255, 255, 255, 255))
        npc:SetMoveType(MOVETYPE_NOCLIP)
        npc:SetSolid(SOLID_BBOX)
        local lookAngle = (playerPos - behindPos):Angle()
        npc:SetAngles(Angle(0, lookAngle.yaw, 0))
        timer.Simple(0.5, function()
            if IsValid(npc) and IsValid(targetPlayer) then PrintMessage(HUD_PRINTTALK, "[Tax Collector] Hello") end
        end)
        timer.Simple(1.5, function()
            if IsValid(npc) and IsValid(targetPlayer) then PrintMessage(HUD_PRINTTALK, "[Tax Collector] I need props. Right now.") end
        end)
        taxCollectors[npc:EntIndex()] = {
            npc = npc,
            target = targetPlayer,
            spawnTime = CurTime(),
            waitingForProp = true,
            chasing = false
        }
        timer.Simple(600, function()
            if IsValid(npc) then
                PrintMessage(HUD_PRINTTALK, "[Tax Collector] we going meet again, " .. targetPlayer:Nick() .. ".")
                npc:Remove()
                taxCollectors[npc:EntIndex()] = nil
            end
        end)
    end

    local function PlayCustomSound(npc, distance)
        if not IsValid(npc) then return end
        local soundPath = "my_sounds/close_scary_1.wav"
        local volume = 100
        if distance < 200 then volume = 85
        elseif distance < 400 then volume = 65
        elseif distance < 700 then volume = 45
        else volume = 30 end
        npc:EmitSound(soundPath, volume, math.random(90, 110), 1, CHAN_AUTO)
    end
    
    local function SpawnCreepyNPC()
        local npc = ents.Create("npc_citizen")
        if not IsValid(npc) then return end
        local players = player.GetAll()
        if #players == 0 then return end
        local targetPlayer = players[math.random(#players)]
        local pos = targetPlayer:GetPos()
        local angle = math.random() * math.pi * 2
        local distance = math.random(500, 1000)
        local height = math.random(500, 1000)
        local spawnPos = pos + Vector(math.cos(angle) * distance, math.sin(angle) * distance, height)
        local trace = util.TraceHull({
            start = spawnPos,
            endpos = spawnPos,
            mins = Vector(-16, -16, 0),
            maxs = Vector(16, 16, 72),
            filter = targetPlayer
        })
        if trace.Hit then spawnPos = trace.HitPos + Vector(0, 0, 500) end
        npc:SetPos(spawnPos)
        npc:Spawn()
        npc:SetHealth(99999)
        npc:SetMaxHealth(99999)
        npc:SetColor(Color(255, 0, 0, 255))
        npc:SetRenderMode(RENDERMODE_TRANSALPHA)
        npc:SetMoveType(MOVETYPE_NOCLIP)
        npc:SetSolid(SOLID_BBOX)
        npc:SetNoDraw(false)
        npc:DrawShadow(false)
        timer.Simple(0.1, function()
            if IsValid(npc) then
                npc:SetSequence(0)
                npc:ResetSequence(0)
                npc:SetCycle(0)
                npc:SetPlaybackRate(0)
                npc:SetColor(Color(255, 0, 0, 200))
                npc:SetMaterial("models/props_combine/portalball")
                local light = ents.Create("light_dynamic")
                light:SetPos(npc:GetPos())
                light:SetKeyValue("_light", "255 0 0 200")
                light:SetKeyValue("style", "5")
                light:SetKeyValue("distance", "200")
                light:Spawn()
                light:SetParent(npc)
                local descendPhase = true
                local circlePhase = false
                local attackPhase = false
                local lastSoundTime = 0
                local function MovementBehavior()
                    if not IsValid(npc) then return end
                    local nearestPlayer = nil
                    local nearestDist = 99999
                    for _, ply in pairs(player.GetAll()) do
                        if IsValid(ply) and ply:Alive() then
                            local dist = npc:GetPos():Distance(ply:GetPos())
                            if dist < nearestDist then nearestDist = dist; nearestPlayer = ply end
                        end
                    end
                    if nearestPlayer then
                        local npcPos = npc:GetPos()
                        local playerPos = nearestPlayer:GetPos()
                        local distanceToPlayer = npcPos:Distance(playerPos)
                        local heightDiff = npcPos.z - playerPos.z
                        if CurTime() - lastSoundTime > 2 then
                            PlayCustomSound(npc, distanceToPlayer); lastSoundTime = CurTime()
                        end
                        if heightDiff > 200 then descendPhase = true; circlePhase = false; attackPhase = false
                        elseif distanceToPlayer < 300 then descendPhase = false; circlePhase = false; attackPhase = true
                        else descendPhase = false; circlePhase = true; attackPhase = false end
                        local newPos = npcPos
                        if descendPhase then
                            local direction = (playerPos - npcPos):GetNormalized()
                            local speed = math.random(100, 200)
                            newPos = npcPos + direction * speed
                            newPos.z = npcPos.z - math.random(10, 30)
                            newPos = newPos + Vector(math.sin(CurTime() * 2) * 20, math.cos(CurTime() * 2) * 20, 0)
                        elseif circlePhase then
                            local circleRadius = 300
                            local circleSpeed = 1
                            local circleAngle = CurTime() * circleSpeed
                            local circlePos = playerPos + Vector(math.cos(circleAngle) * circleRadius, math.sin(circleAngle) * circleRadius, 200)
                            newPos = npcPos + (circlePos - npcPos) * 0.1
                            newPos.z = npcPos.z - 2
                        elseif attackPhase then
                            local direction = (playerPos - npcPos):GetNormalized()
                            local speed = math.random(150, 250)
                            newPos = npcPos + direction * speed
                            if math.random(1, 3) == 1 then newPos = newPos + direction * 100 end
                        end
                        if newPos.z < playerPos.z - 100 then newPos.z = playerPos.z + 50 end
                        if newPos.z > playerPos.z + 1000 then newPos.z = playerPos.z + 500 end
                        npc:SetPos(newPos)
                    end
                end
                timer.Create("NPC_Move_" .. npc:EntIndex(), 0.3, 0, MovementBehavior)
            end
        end)
        table.insert(creepyNPCs, npc)
        if #creepyNPCs > 7 then
            local oldNPC = table.remove(creepyNPCs, 1)
            if IsValid(oldNPC) then timer.Remove("NPC_Move_" .. oldNPC:EntIndex()); oldNPC:Remove() end
        end
        timer.Simple(300, function()
            if IsValid(npc) then
                for k, v in pairs(creepyNPCs) do if v == npc then table.remove(creepyNPCs, k); break end end
                timer.Remove("NPC_Move_" .. npc:EntIndex()); npc:Remove()
            end
        end)
    end

    -- ======================================================================
    -- 4. ТАЙМЕРЫ (Спавн по времени)
    -- ======================================================================

    -- Annihilation: 15 минут (900 секунд). Без тестового спавна!
    timer.Create("AnnihilationSpawner", 900, 0, TriggerAnnihilationSpawn)

    -- Красные NPC (150 секунд)
    timer.Create("CreepyNPC_Spawner", 150, 0, SpawnCreepyNPC)
    timer.Create("CheckPlayerDeaths", 0.2, 0, CheckPlayerDeaths)
    timer.Create("CheckTaxCollectors", 0.2, 0, CheckTaxCollectors)
    timer.Create("CheckShadows", 0.2, 0, CheckShadows)
    timer.Create("TaxCollectorSpawner", 300, 0, SpawnTaxCollector)
    timer.Simple(5, SpawnTaxCollector) -- Коллектор через 5 сек

    hook.Add("PlayerSpawn", "CheckShadowSpawn", function(ply)
        timer.Simple(5, function()
            if IsValid(ply) and ply:Alive() then
                if math.random(1, 100) <= 20 then
                    SpawnShadow(ply)
                end
            end
        end)
    end)

    -- ======================================================================
    -- 5. КОНСОЛЬНЫЕ КОМАНДЫ (ОБЪЯВЛЕНЫ В САМОМ КОНЦЕ)
    -- ======================================================================
    
    concommand.Add("xor_create", function(ply, cmd, args)
        -- Защита: команду могут использовать только админы (чтобы избежать хаоса на сервере)
        if not IsValid(ply) or not ply:IsAdmin() then return end

        if args[1] == "tax" and args[2] == "collector" then 
            SpawnTaxCollector() 
        end
        
        if args[1] == "sigma" then
            local target = ply
            if IsValid(target) and target:Alive() then 
                SpawnShadow(target) 
            end
        end
        
        if args[1] == "annihilation" then
            local forward = ply:GetForward()
            local spawnPos = ply:GetPos() + (forward * 200) + Vector(0, 0, 10)
            SpawnAnnihilationMonster(spawnPos)
            print("Annihilation spawned!")
        end
    end)

    -- ======================================================================
    -- 6. ОЧИСТКА КАРТЫ
    -- ======================================================================
    
    hook.Add("PostCleanupMap", "RemoveCreepyNPCs", function()
        for _, npc in pairs(creepyNPCs) do
            if IsValid(npc) then timer.Remove("NPC_Move_" .. npc:EntIndex()); npc:Remove() end
        end
        creepyNPCs = {}
        for _, data in pairs(taxCollectors) do if IsValid(data.npc) then data.npc:Remove() end end
        taxCollectors = {}
        for _, data in pairs(shadowEntities) do
            if IsValid(data.shadow) then timer.Remove("ShadowUpdate_" .. data.shadow:EntIndex()); data.shadow:Remove() end
        end
        shadowEntities = {}
        for _, monster in pairs(annihilationMonsters) do
             if IsValid(monster) then timer.Remove("AnnihilationChase_" .. monster:EntIndex()); monster:Remove() end
        end
        annihilationMonsters = {}
    end)
end

if CLIENT then
    -- Переменные для эффекта Annihilation
    local annihilationActive = false
    local targetShadowAlphaAnn = 0
    local shadowScreenAlphaAnn = 0
    
    -- Переменные для старых эффектов
    local redScreen = false
    local alpha = 0
    local targetAlpha = 0
    local isChasedByShadow = false
    local shadowScreenAlphaOld = 0
    local targetShadowAlphaOld = 0
    local showSumSymbol = false
    local sumAlpha = 0
    
    hook.Add("Think", "CheckCreepyNPCDistance", function()
        local ply = LocalPlayer()
        if not IsValid(ply) or not ply:Alive() then 
            redScreen = false
            targetAlpha = 0
            isChasedByShadow = false
            targetShadowAlphaOld = 0
            showSumSymbol = false
            return 
        end
        
        redScreen = false
        isChasedByShadow = false
        
        for _, npc in pairs(ents.FindByClass("npc_citizen")) do
            if IsValid(npc) and npc:GetMaterial() == "models/props_combine/portalball" and npc:GetColor() == Color(255, 0, 0, 200) then
                local distance = ply:GetPos():Distance(npc:GetPos())
                if distance < 500 then
                    redScreen = true
                    targetAlpha = math.max(0, 255 - (distance / 500) * 255)
                    break
                end
            end
        end
        
        for _, npc in pairs(ents.FindByClass("npc_citizen")) do
            if IsValid(npc) and npc:GetColor() == Color(0, 0, 0, 255) and npc:GetMaterial() == "models/props_combine/portalball" then
                isChasedByShadow = true
                targetShadowAlphaOld = 192 
                break
            end
        end
        
        if not redScreen then targetAlpha = 0 end
        if not isChasedByShadow then targetShadowAlphaOld = 0 end
        
        alpha = math.Approach(alpha, targetAlpha, FrameTime() * 300)
        shadowScreenAlphaOld = math.Approach(shadowScreenAlphaOld, targetShadowAlphaOld, FrameTime() * 200)
        shadowScreenAlphaAnn = math.Approach(shadowScreenAlphaAnn, targetShadowAlphaAnn, FrameTime() * 300)
    end)
    
    hook.Add("HUDPaint", "DrawShadowEffects", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        
        if not ply:Alive() and showSumSymbol then
            sumAlpha = math.Approach(sumAlpha, 255, FrameTime() * 500)
            surface.SetDrawColor(Color(0, 0, 0, sumAlpha))
            surface.DrawRect(0, 0, ScrW(), ScrH())
            draw.SimpleTextOutlined(
                "∑", "DermaLarge", ScrW() / 2, ScrH() / 2,
                Color(255, 255, 255, sumAlpha),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 3, Color(0, 0, 0, 0)
            )
        else
            sumAlpha = math.Approach(sumAlpha, 0, FrameTime() * 200)
        end
        
        if shadowScreenAlphaOld > 0 then
            surface.SetDrawColor(Color(0, 0, 0, shadowScreenAlphaOld))
            surface.DrawRect(0, 0, ScrW(), ScrH())
        end
        
        if alpha > 0 then
            surface.SetDrawColor(Color(255, 0, 0, alpha))
            surface.DrawRect(0, 0, ScrW(), ScrH())
            
            if alpha > 150 then
                surface.SetDrawColor(Color(0, 0, 0, math.random(0, 30)))
                for i = 1, 10 do
                    local x = math.random(0, ScrW())
                    local y = math.random(0, ScrH())
                    local w = math.random(50, 200)
                    local h = math.random(50, 200)
                    surface.DrawRect(x, y, w, h)
                end
            end
            
            if alpha > 200 then
                local pulse = math.sin(CurTime() * 5) * 0.3 + 0.7
                surface.SetDrawColor(Color(0, 0, 0, 200 * pulse))
                local centerX, centerY = ScrW() / 2, ScrH() / 2
                for i = 0, 360, 10 do
                    local angle = math.rad(i)
                    local radius = 250
                    local x1 = centerX + math.cos(angle) * radius
                    local y1 = centerY + math.sin(angle) * radius
                    local x2 = centerX + math.cos(angle) * (radius + 300)
                    local y2 = centerY + math.sin(angle) * (radius + 300)
                    surface.DrawPoly({
                        {x = centerX, y = centerY},
                        {x = x1, y = y1},
                        {x = x2, y = y2}
                    })
                end
            end
        end

        -- ЭФФЕКТ ANNIHILATION (Черно-белый экран + 64)
        if annihilationActive or shadowScreenAlphaAnn > 0 then
            render.SetColorModulation(1, 1, 1)
            render.SetBlend(1)
            surface.SetDrawColor(Color(0, 0, 0, shadowScreenAlphaAnn))
            surface.DrawRect(0, 0, ScrW(), ScrH())
        end
    end)
    
    hook.Add("Think", "CheckPlayerDeath", function()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        if not ply:Alive() and isChasedByShadow then showSumSymbol = true end
        if ply:Alive() then showSumSymbol = false end
    end)
    
    hook.Add("PostDrawOpaqueRenderables", "HighlightShadow", function()
        for _, npc in pairs(ents.FindByClass("npc_citizen")) do
            if IsValid(npc) and npc:GetColor() == Color(0, 0, 0, 255) and npc:GetMaterial() == "models/props_combine/portalball" then
                render.SetColorModulation(1, 1, 1)
                render.SuppressEngineLighting(true)
                halo.Add({npc}, Color(255, 255, 255, 200), 2, 2, 1, true, false)
                render.SuppressEngineLighting(false)
            end
        end
    end)
    
    hook.Add("ShutDown", "CleanRedScreen", function()
        redScreen = false
        alpha = 0
        targetAlpha = 0
        isChasedByShadow = false
        shadowScreenAlphaOld = 0
        targetShadowAlphaOld = 0
        showSumSymbol = false
        sumAlpha = 0
        annihilationActive = false
        targetShadowAlphaAnn = 0
        shadowScreenAlphaAnn = 0
    end)
end
