@doc raw"""
	write_capacity(path::AbstractString, inputs::Dict, setup::Dict, EP::Model))

Function for writing the different capacities for the different generation technologies (starting capacities or, existing capacities, retired capacities, and new-built capacities).
"""
function write_capacity(path::AbstractString, inputs::Dict, setup::Dict, EP::Model)
    gen = inputs["RESOURCES"]

    MultiStage = setup["MultiStage"]

    sco2turbine = 1
    ALLAM_CYCLE_LOX = inputs["ALLAM_CYCLE_LOX"]
    COMMIT_Allam = setup["UCommit"] > 0 ? ALLAM_CYCLE_LOX : Int[]   # If UCommit is 1, then ALL Allam Cycle LOX resources are committed

    # Capacity decisions
    capdischarge = zeros(size(inputs["RESOURCE_NAMES"]))
    for i in inputs["NEW_CAP"]
        if i in inputs["COMMIT"]
            capdischarge[i] = value(EP[:vCAP][i]) * cap_size(gen[i])
        elseif i in COMMIT_Allam
            capdischarge[i] = value(EP[:vCAP_AllamCycleLOX][i, sco2turbine]) * inputs["allam_dict"][i,"cap_size"][sco2turbine]
        elseif i in ALLAM_CYCLE_LOX
            capdischarge[i] = value(EP[:vCAP_AllamCycleLOX][i, sco2turbine])
        else
            capdischarge[i] = value(EP[:vCAP][i])
        end
    end

    retcapdischarge = zeros(size(inputs["RESOURCE_NAMES"]))
    for i in inputs["RET_CAP"]
        if i in inputs["COMMIT"]
            retcapdischarge[i] = first(value.(EP[:vRETCAP][i])) * cap_size(gen[i])
        elseif i in COMMIT_Allam
            retcapdischarge[i] = value(EP[:vRETCAP_AllamCycleLOX][i, sco2turbine]) * inputs["allam_dict"][i,"cap_size"][sco2turbine]
        elseif i in ALLAM_CYCLE_LOX
            retcapdischarge[i] = value(EP[:vRETCAP_AllamCycleLOX][i, sco2turbine])
        else
            retcapdischarge[i] = first(value.(EP[:vRETCAP][i]))
        end
    end

    retrocapdischarge = zeros(size(inputs["RESOURCE_NAMES"]))
    for i in inputs["RETROFIT_CAP"]
        if i in inputs["COMMIT"]
            retrocapdischarge[i] = first(value.(EP[:vRETROFITCAP][i])) * cap_size(gen[i])
        else
            retrocapdischarge[i] = first(value.(EP[:vRETROFITCAP][i]))
        end
    end

    capacity_constraint_dual = zeros(size(inputs["RESOURCE_NAMES"]))
    for y in ids_with_positive(gen, max_cap_mw)
        capacity_constraint_dual[y] = -dual.(EP[:cMaxCap][y])
    end

    capcharge = zeros(size(inputs["RESOURCE_NAMES"]))
    retcapcharge = zeros(size(inputs["RESOURCE_NAMES"]))
    existingcapcharge = zeros(size(inputs["RESOURCE_NAMES"]))
    for i in inputs["STOR_ASYMMETRIC"]
        if i in inputs["NEW_CAP_CHARGE"]
            capcharge[i] = value(EP[:vCAPCHARGE][i])
        end
        if i in inputs["RET_CAP_CHARGE"]
            retcapcharge[i] = value(EP[:vRETCAPCHARGE][i])
        end
        existingcapcharge[i] = MultiStage == 1 ? value(EP[:vEXISTINGCAPCHARGE][i]) :
                               existing_charge_cap_mw(gen[i])
    end

    capenergy = zeros(size(inputs["RESOURCE_NAMES"]))
    retcapenergy = zeros(size(inputs["RESOURCE_NAMES"]))
    existingcapenergy = zeros(size(inputs["RESOURCE_NAMES"]))
    for i in inputs["STOR_ALL"]
        if i in inputs["NEW_CAP_ENERGY"]
            capenergy[i] = value(EP[:vCAPENERGY][i])
        end
        if i in inputs["RET_CAP_ENERGY"]
            retcapenergy[i] = value(EP[:vRETCAPENERGY][i])
        end
        existingcapenergy[i] = MultiStage == 1 ? value(EP[:vEXISTINGCAPENERGY][i]) :
                               existing_cap_mwh(gen[i])
    end
    if !isempty(inputs["VRE_STOR"])
        for i in inputs["VS_STOR"]
            if i in inputs["NEW_CAP_STOR"]
                capenergy[i] = value(EP[:vCAPENERGY_VS][i])
            end
            if i in inputs["RET_CAP_STOR"]
                retcapenergy[i] = value(EP[:vRETCAPENERGY_VS][i])
            end
            existingcapenergy[i] = existing_cap_mwh(gen[i]) # multistage functionality doesn't exist yet for VRE-storage resources
        end
    end

    startcap = MultiStage == 1 ? value.(EP[:vEXISTINGCAP]) : existing_cap_mw.(gen)
    endcap = value.(EP[:eTotalCap])
    
    # for allam cycle lox, we need to use:
    # eExistingCap_AllamCycleLOX instead of eExistingCap
    # eTotalCap_AllamcycleLOX instead of eTotalCap
    for y in ALLAM_CYCLE_LOX
        startcap[y] = value(EP[:eExistingCap_AllamCycleLOX][y, sco2turbine])
        endcap[y] = value(EP[:eTotalCap_AllamcycleLOX][y, sco2turbine])
    end

    dfCap = DataFrame(Resource = inputs["RESOURCE_NAMES"],
        Zone = zone_id.(gen),
        Retrofit_Id = retrofit_id.(gen),
        StartCap = startcap[:],
        RetCap = retcapdischarge[:],
        RetroCap = retrocapdischarge[:], #### Need to change later
        NewCap = capdischarge[:],
        EndCap = endcap[:],
        CapacityConstraintDual = capacity_constraint_dual[:],
        StartEnergyCap = existingcapenergy[:],
        RetEnergyCap = retcapenergy[:],
        NewEnergyCap = capenergy[:],
        EndEnergyCap = existingcapenergy[:] - retcapenergy[:] + capenergy[:],
        StartChargeCap = existingcapcharge[:],
        RetChargeCap = retcapcharge[:],
        NewChargeCap = capcharge[:],
        EndChargeCap = existingcapcharge[:] - retcapcharge[:] + capcharge[:])
    if setup["ParameterScale"] == 1
        dfCap.StartCap = dfCap.StartCap * ModelScalingFactor
        dfCap.RetCap = dfCap.RetCap * ModelScalingFactor
        dfCap.RetroCap = dfCap.RetroCap * ModelScalingFactor
        dfCap.NewCap = dfCap.NewCap * ModelScalingFactor
        dfCap.EndCap = dfCap.EndCap * ModelScalingFactor
        dfCap.CapacityConstraintDual = dfCap.CapacityConstraintDual * ModelScalingFactor
        dfCap.StartEnergyCap = dfCap.StartEnergyCap * ModelScalingFactor
        dfCap.RetEnergyCap = dfCap.RetEnergyCap * ModelScalingFactor
        dfCap.NewEnergyCap = dfCap.NewEnergyCap * ModelScalingFactor
        dfCap.EndEnergyCap = dfCap.EndEnergyCap * ModelScalingFactor
        dfCap.StartChargeCap = dfCap.StartChargeCap * ModelScalingFactor
        dfCap.RetChargeCap = dfCap.RetChargeCap * ModelScalingFactor
        dfCap.NewChargeCap = dfCap.NewChargeCap * ModelScalingFactor
        dfCap.EndChargeCap = dfCap.EndChargeCap * ModelScalingFactor
    end
    total = DataFrame(Resource = "Total", Zone = "n/a", Retrofit_Id = "n/a",
        StartCap = sum(dfCap[!, :StartCap]), RetCap = sum(dfCap[!, :RetCap]),
        NewCap = sum(dfCap[!, :NewCap]), EndCap = sum(dfCap[!, :EndCap]),
        RetroCap = sum(dfCap[!, :RetroCap]),
        CapacityConstraintDual = "n/a",
        StartEnergyCap = sum(dfCap[!, :StartEnergyCap]),
        RetEnergyCap = sum(dfCap[!, :RetEnergyCap]),
        NewEnergyCap = sum(dfCap[!, :NewEnergyCap]),
        EndEnergyCap = sum(dfCap[!, :EndEnergyCap]),
        StartChargeCap = sum(dfCap[!, :StartChargeCap]),
        RetChargeCap = sum(dfCap[!, :RetChargeCap]),
        NewChargeCap = sum(dfCap[!, :NewChargeCap]),
        EndChargeCap = sum(dfCap[!, :EndChargeCap]))

    dfCap = vcat(dfCap, total)
    CSV.write(joinpath(path, "capacity.csv"), dfCap)

    if !isempty(ALLAM_CYCLE_LOX)
        @info "Capacity output for Allam Cycle LOX resources that is included in the capacity.csv file is for the sCO2Turbine in an Allam Cycle LOX resource."
        @info "For the full capacity output, please refer to the capacity_allam_cycle_lox.csv file."
    end
    
    return dfCap
end
