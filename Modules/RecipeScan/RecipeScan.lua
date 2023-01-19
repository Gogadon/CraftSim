_, CraftSim = ...

CraftSim.RECIPE_SCAN = {}

CraftSim.RECIPE_SCAN.scanInterval = 0.01

CraftSim.RECIPE_SCAN.SCAN_MODES = {
    Q1 = "Materials Quality 1", 
    Q2 = "Materials Quality 2", 
    Q3 = "Materials Quality 3", 
    OPTIMIZE_G = "Optimize for Guaranteed", 
    OPTIMIZE_I = "Optimize for Inspiration"}

local function print(text, recursive, l) -- override
	CraftSim_DEBUG:print(text, CraftSim.CONST.DEBUG_IDS.MAIN, recursive, l)
end

function CraftSim.RECIPE_SCAN:GetScanMode()
    local RecipeScanFrame = CraftSim.FRAME:GetFrame(CraftSim.CONST.FRAMES.RECIPE_SCAN)
    return RecipeScanFrame.content.scanMode.currentMode
end

function CraftSim.RECIPE_SCAN:SetReagentAllocationByScanMode(recipeData, priceData)
    local scanMode = CraftSim.RECIPE_SCAN:GetScanMode()

    if scanMode == CraftSim.RECIPE_SCAN.SCAN_MODES.Q1 then
        for _, reagent in pairs(recipeData.reagents) do
            reagent.itemsInfo[1].allocations = reagent.requiredQuantity
        end
    elseif scanMode == CraftSim.RECIPE_SCAN.SCAN_MODES.Q2 then
        for _, reagent in pairs(recipeData.reagents) do
            if reagent.differentQualities then
                reagent.itemsInfo[2].allocations = reagent.requiredQuantity
            else
                reagent.itemsInfo[1].allocations = reagent.requiredQuantity
            end 
        end
    elseif scanMode == CraftSim.RECIPE_SCAN.SCAN_MODES.Q3 then
        for _, reagent in pairs(recipeData.reagents) do
            if reagent.differentQualities then
                reagent.itemsInfo[3].allocations = reagent.requiredQuantity
            else
                reagent.itemsInfo[1].allocations = reagent.requiredQuantity
            end 
        end
    elseif scanMode == CraftSim.RECIPE_SCAN.SCAN_MODES.OPTIMIZE_G or scanMode == CraftSim.RECIPE_SCAN.SCAN_MODES.OPTIMIZE_I then
        if not recipeData.hasQualityReagents then
            return recipeData.reagents -- e.g: Primal Convergence
        end
        local bestAllocation = CraftSim.REAGENT_OPTIMIZATION:OptimizeReagentAllocation(recipeData, recipeData.recipeType, priceData, CraftSim.CONST.EXPORT_MODE.SCAN)
        if bestAllocation then
            -- set reagents by best allocation
            -- print("Optimized Allocation: ")
            -- print(bestAllocation, true)
            for _, reagent in pairs(recipeData.reagents) do
                if reagent.differentQualities then
                    for _, itemInfo in pairs(reagent.itemsInfo) do
                        for _, allocation in pairs(bestAllocation.allocations) do
                            for _, subAllocation in pairs(allocation) do
                                if itemInfo.itemID == allocation.itemID then
                                    itemInfo.allocations = subAllocation.allocations
                                end
                            end
                        end
                    end
                    reagent.itemsInfo[3].allocations = reagent.requiredQuantity
                else
                    reagent.itemsInfo[1].allocations = reagent.requiredQuantity
                end 
            end
        else
            print("No best allocation found (should not be possible)")
        end
    end

    return CopyTable(recipeData.reagents)
end

function CraftSim.RECIPE_SCAN:ToggleScanButton(value)
    local frame = CraftSim.FRAME:GetFrame(CraftSim.CONST.FRAMES.RECIPE_SCAN)
    frame.content.scanButton:SetEnabled(value)
    if not value then
        frame.content.scanButton:SetText("Scanning 0%")
    else
        frame.content.scanButton:SetText("Scan Recipes")
    end
end

function CraftSim.RECIPE_SCAN:UpdateScanPercent(currentProgress, maxProgress)
    local currentPercentage = CraftSim.UTIL:round(currentProgress / (maxProgress / 100))

    if currentPercentage % 1 == 0 then
        local frame = CraftSim.FRAME:GetFrame(CraftSim.CONST.FRAMES.RECIPE_SCAN)
        frame.content.scanButton:SetText("Scanning " .. currentPercentage .. "%")
    end
end

function CraftSim.RECIPE_SCAN:EndScan()
    print("scan finished")
    collectgarbage("collect") -- By Option?
    CraftSim.RECIPE_SCAN:ToggleScanButton(true)
end

function CraftSim.RECIPE_SCAN:StartScan()
    
    local scanMode = CraftSim.RECIPE_SCAN:GetScanMode()
    print("Scan Mode: " .. tostring(scanMode))
    local isQualityScan = scanMode == CraftSim.RECIPE_SCAN.SCAN_MODES.OPTIMIZE_G or scanMode == CraftSim.RECIPE_SCAN.SCAN_MODES.OPTIMIZE_I
    local recipeIDs = C_TradeSkillUI.GetAllRecipeIDs()
    local recipeInfos = CraftSim.UTIL:Map(recipeIDs, function(recipeID) 
        return C_TradeSkillUI.GetRecipeInfo(recipeID)
    end)
    -- filter relevant dragon isles recipes
    print("start filter")
    recipeInfos = CraftSim.UTIL:FilterTable(recipeInfos, function(recipeInfo) 
        if not CraftSimOptions.recipeScanIncludeNotLearned and not recipeInfo.learned then
            return false
        end
        ---@diagnostic disable-next-line: missing-parameter
        local recipeCategoryInfo = C_TradeSkillUI.GetCategoryInfo(recipeInfo.categoryID)
        
        if tContains(CraftSim.CONST.DRAGON_ISLES_CATEGORY_IDS, recipeCategoryInfo.parentCategoryID) and (recipeInfo.itemLevel > 1 or recipeInfo.isEnchantingRecipe) then
            if recipeInfo and recipeInfo.supportsCraftingStats and ((isQualityScan and recipeInfo.supportsQualities) or not isQualityScan) then
                local recipeType = CraftSim.UTIL:GetRecipeType(recipeInfo)

                if 
                    recipeType ~= CraftSim.CONST.RECIPE_TYPES.NO_ITEM and
                    recipeType ~= CraftSim.CONST.RECIPE_TYPES.NO_CRAFT_OPERATION and
                    recipeType ~= CraftSim.CONST.RECIPE_TYPES.GATHERING
                then
                    if not CraftSimOptions.recipeScanIncludeSoulbound then
                        if (recipeType == CraftSim.CONST.RECIPE_TYPES.SOULBOUND_GEAR) then
                            return false
                        end
                        if not CraftSimOptions.recipeScanIncludeGear and (recipeType == CraftSim.CONST.RECIPE_TYPES.GEAR) then
                            return false
                        end
                        local itemID = CraftSim.UTIL:GetItemIDByLink(recipeInfo.hyperlink)
                        local isSoulboundNonGear = CraftSim.UTIL:isItemSoulbound(itemID)

                        if isSoulboundNonGear then
                            return false
                        end
                    end

                    if not CraftSimOptions.recipeScanIncludeGear and (recipeType == CraftSim.CONST.RECIPE_TYPES.GEAR or recipeType == CraftSim.CONST.RECIPE_TYPES.SOULBOUND_GEAR) then
                        return false
                    end
                    
                    if not recipeInfo.isRecraft and not recipeInfo.isSalvageRecipe and not recipeInfo.isGatheringRecipe then
                        return true
                    end
                end
                return false
            end
        end
        return false
    end)
    print("end filter")
    local currentIndex = 1
    local function scanRecipesByInterval()
        local recipeInfo = recipeInfos[currentIndex]
        if not recipeInfo then
            CraftSim.RECIPE_SCAN:EndScan()
            return
        end

        CraftSim.RECIPE_SCAN:UpdateScanPercent(currentIndex, #recipeInfos)

        print("recipeID: " .. tostring(recipeInfo.recipeID), false, true)
        print("recipeName: " .. tostring(recipeInfo.name))
        print("isEnchant: " .. tostring(recipeInfo.isEnchantingRecipe))

        local recipeData = CraftSim.DATAEXPORT:exportRecipeData(recipeInfo.recipeID, CraftSim.CONST.EXPORT_MODE.SCAN);
        if not recipeData then
            CraftSim.RECIPE_SCAN:EndScan()
            return
        end
        local priceData = CraftSim.PRICEDATA:GetPriceData(recipeData, recipeData.recipeType)
        local scanReagents = CraftSim.RECIPE_SCAN:SetReagentAllocationByScanMode(recipeData, priceData)

        -- reexport the recipeData, now with the new reagents
        recipeData = CraftSim.DATAEXPORT:exportRecipeData(recipeInfo.recipeID, CraftSim.CONST.EXPORT_MODE.SCAN, {scanReagents=scanReagents})
        if not recipeData then
            -- finishedScan
            print("scan finished, no recipe data after recalculation")
            CraftSim.RECIPE_SCAN:EndScan()
            return
        end
        -- refetch price data
        priceData = CraftSim.PRICEDATA:GetPriceData(recipeData, recipeData.recipeType)
        local meanProfit = CraftSim.CALC:getMeanProfit(recipeData, priceData)
        local bestSimulation = nil

        if CraftSimOptions.recipeScanOptimizeProfessionTools then
            print("Optimize Gear")
            bestSimulation = CraftSim.TOPGEAR:SimulateBestProfessionGearCombination(recipeData, recipeData.recipeType, priceData, CraftSim.CONST.EXPORT_MODE.SCAN)
            print("- Profit old: " .. CraftSim.UTIL:FormatMoney(meanProfit))
            if bestSimulation then
                print("- Found Top Gear")
                -- use the modified recipe data
                recipeData = bestSimulation.modifiedRecipeData
                priceData = CraftSim.PRICEDATA:GetPriceData(recipeData, recipeData.recipeType) -- necessary?
                -- recalculate profit based on recipeData with best gear
                meanProfit = CraftSim.CALC:getMeanProfit(recipeData, priceData)
                print("- Profit Top Gear: " .. CraftSim.UTIL:FormatMoney(meanProfit))
            else
                print("- No Better Gear Found")
            end
        end


        local function continueScan()
            CraftSim.RECIPE_SCAN:AddRecipeToRecipeRow(recipeData, priceData, meanProfit, bestSimulation) 

            currentIndex = currentIndex + 1
            C_Timer.After(CraftSim.RECIPE_SCAN.scanInterval, scanRecipesByInterval)
        end

        if recipeData then
            recipeData.ContinueOnResultItemsLoaded(continueScan)
        end
    end

    CraftSim.RECIPE_SCAN:ToggleScanButton(false)
    CraftSim.RECIPE_SCAN:ResetResults()
    scanRecipesByInterval()
end