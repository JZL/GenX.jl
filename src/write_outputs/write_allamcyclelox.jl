
@doc raw"""
	write_allam_capacity(path::AbstractString, inputs::Dict, setup::Dict, EP::Model)

This function writes the different capacities for the Allam Cycle LOX technologies (starting capacities or, existing capacities, retired capacities, and new-built capacities) to the `capacity_allam_cycle_lox.csv` file.
"""
function write_allam_capacity(path::AbstractString, inputs::Dict, setup::Dict, EP::Model)
	# Capacity decisions
	gen = inputs["RESOURCES"]
	ALLAM_CYCLE_LOX = inputs["ALLAM_CYCLE_LOX"] 
    COMMIT_Allam = setup["UCommit"] > 1 ? ALLAM_CYCLE_LOX : Int[]
	MultiStage = setup["MultiStage"]

    # Allam cycle components
    # by default, i = 1 -> sCO2Turbine; i = 2 -> ASU; i = 3 -> LOX
    sco2turbine, asu, lox = 1, 2, 3
    # get component-wise data
    allam_dict = inputs["allam_dict"]

	G = inputs["G"]
	capAllam_sco2turbine = zeros(G)
	capAllam_asu = zeros(G)
	capAllam_lox = zeros(G)

	# new cap
	for y in ALLAM_CYCLE_LOX
		if y in COMMIT_Allam
			capAllam_sco2turbine[y] = value.(EP[:vCAP_AllamCycleLOX])[y, sco2turbine]* allam_dict[y,"cap_size"][sco2turbine]
			capAllam_asu[y] = value.(EP[:vCAP_AllamCycleLOX])[y, asu]* allam_dict[y,"cap_size"][asu]
			capAllam_lox[y] = value.(EP[:vCAP_AllamCycleLOX])[y, lox]* allam_dict[y,"cap_size"][lox]
		else
			capAllam_sco2turbine[y] = value.(EP[:vCAP_AllamCycleLOX])[y, sco2turbine]
			capAllam_asu[y] = value.(EP[:vCAP_AllamCycleLOX])[y, asu]
			capAllam_lox[y] = value.(EP[:vCAP_AllamCycleLOX])[y, lox]
		end
	end

	# retired cap
	retcapAllam_sco2turbine = zeros(G)
	retcapAllam_asu = zeros(G)
	retcapAllam_lox = zeros(G)

	for y in ALLAM_CYCLE_LOX
		if y in COMMIT_Allam
			retcapAllam_sco2turbine[y] = value.(EP[:vRETCAP_AllamCycleLOX])[y, sco2turbine]* allam_dict[y,"cap_size"][sco2turbine]
			retcapAllam_asu[y] = value.(EP[:vRETCAP_AllamCycleLOX])[y, asu]* allam_dict[y,"cap_size"][asu]
			retcapAllam_lox[y] = value.(EP[:vRETCAP_AllamCycleLOX])[y, lox]* allam_dict[y,"cap_size"][lox]
		else
			retcapAllam_sco2turbine[y] = value.(EP[:vRETCAP_AllamCycleLOX])[y, sco2turbine]
			retcapAllam_asu[y] = value.(EP[:vRETCAP_AllamCycleLOX])[y, asu]
			retcapAllam_lox[y] = value.(EP[:vRETCAP_AllamCycleLOX])[y, lox]
		end
	end


	dfCapAllam = DataFrame(Resource = resource_name.(gen[ALLAM_CYCLE_LOX]),
		Zone = zone_id.(gen[ALLAM_CYCLE_LOX]),
		
		StartCap_sCO2turbine_MW_gross = [allam_dict[y, "existing_cap"][sco2turbine] for y in ALLAM_CYCLE_LOX],
		StartCap_ASU_MW_gross = [allam_dict[y, "existing_cap"][asu] for y in ALLAM_CYCLE_LOX],
		StartCap_LOX_t = [allam_dict[y, "existing_cap"][lox] for y in ALLAM_CYCLE_LOX],
		
		NewCap_sCO2turbine_MW_gross = capAllam_sco2turbine[ALLAM_CYCLE_LOX],
		NewCap_ASU_MW_gross = capAllam_asu[ALLAM_CYCLE_LOX],
		NewCap_LOX_t = capAllam_lox[ALLAM_CYCLE_LOX],

		RetCap_sCO2turbine_MW_gross = retcapAllam_sco2turbine[ALLAM_CYCLE_LOX],
		RetCap_ASU_MW_gross = retcapAllam_asu[ALLAM_CYCLE_LOX],
		RetCap_LOX_t = retcapAllam_lox[ALLAM_CYCLE_LOX],

		EndCap_sCO2turbine_MW_gross = [value.(EP[:eTotalCap_AllamcycleLOX])[y,sco2turbine] for y in ALLAM_CYCLE_LOX],
		EndCap_ASU_MW_gross = [value.(EP[:eTotalCap_AllamcycleLOX])[y,asu] for y in ALLAM_CYCLE_LOX],
		EndCap_LOX_t = [value.(EP[:eTotalCap_AllamcycleLOX])[y,lox] for y in ALLAM_CYCLE_LOX]
	)

	if setup["ParameterScale"] == 1
		columns_to_scale = [
			:StartCap_sCO2turbine_MW_gross,
			:RetCap_sCO2turbine_MW_gross,
			:NewCap_sCO2turbine_MW_gross,
			:EndCap_sCO2turbine_MW_gross,
			
			:StartCap_ASU_MW_gross,
			:RetCap_ASU_MW_gross,
			:NewCap_ASU_MW_gross,
			:EndCap_ASU_MW_gross,

			:StartCap_LOX_t,
			:RetCap_LOX_t,
			:NewCap_LOX_t,
			:EndCap_LOX_t
		]

		scale_columns!(dfCapAllam, columns_to_scale, ModelScalingFactor)
	end

	total_allam = DataFrame(
		Resource = "Total", Zone = "n/a", 
		StartCap_sCO2turbine_MW_gross = sum(dfCapAllam[!,:StartCap_sCO2turbine_MW_gross]), 
		RetCap_sCO2turbine_MW_gross = sum(dfCapAllam[!,:RetCap_sCO2turbine_MW_gross]),
		NewCap_sCO2turbine_MW_gross = sum(dfCapAllam[!,:NewCap_sCO2turbine_MW_gross]), 
		EndCap_sCO2turbine_MW_gross = sum(dfCapAllam[!,:EndCap_sCO2turbine_MW_gross]),

		StartCap_ASU_MW_gross = sum(dfCapAllam[!,:StartCap_ASU_MW_gross]), 
		RetCap_ASU_MW_gross = sum(dfCapAllam[!,:RetCap_ASU_MW_gross]),
		NewCap_ASU_MW_gross = sum(dfCapAllam[!,:NewCap_ASU_MW_gross]), 
		EndCap_ASU_MW_gross = sum(dfCapAllam[!,:EndCap_ASU_MW_gross]),

		StartCap_LOX_t = sum(dfCapAllam[!,:StartCap_LOX_t]), 
		RetCap_LOX_t = sum(dfCapAllam[!,:RetCap_LOX_t]),
		NewCap_LOX_t = sum(dfCapAllam[!,:NewCap_LOX_t]), 
		EndCap_LOX_t = sum(dfCapAllam[!,:EndCap_LOX_t]),
	)

	dfCapAllam = vcat(dfCapAllam, total_allam)
	CSV.write(joinpath(path,"capacity_allam_cycle_lox.csv"), dfCapAllam)

	# also write the vOutput_AllamcycleLOX, vLOX_in, vLOX_out
end

@doc raw"""
	write_allam_output(path::AbstractString, inputs::Dict, setup::Dict, EP::Model)

This function writes the power output from each component of an Allam Cycle LOX resource to the `output_allam_cycle_lox.csv` file.
"""
function write_allam_output(path::AbstractString, inputs::Dict, setup::Dict, EP::Model)
	ALLAM_CYCLE_LOX = inputs["ALLAM_CYCLE_LOX"] 
	T = inputs["T"]
    # Allam cycle components
    # by default, i = 1 -> sCO2Turbine; i = 2 -> ASU; i = 3 -> LOX
    sco2turbine, asu, lox = 1, 2, 3

	@expression(EP, eNetPowerAllam[y in ALLAM_CYCLE_LOX, t = 1:T],
        EP[:eP_Allam][y,t] - EP[:vCHARGE_ALLAM][y,t])

    # Power injected by each resource in each time step
	allam_resources = inputs["RESOURCE_NAMES"][ALLAM_CYCLE_LOX]
    dfAllam_output = DataFrame(Resource = 
		[allam_resources .*"_sco2turbine_gross_power_mw";
		allam_resources .*"_sco2turbine_commit";
		allam_resources .*"_asu_gross_power_mw";
		allam_resources .*"_asu_commit";
		allam_resources .*"_net_power_output_mw";
		allam_resources .*"_storage_lox_t";
		allam_resources .*"_lox_in_t";
		allam_resources .*"_lox_out_t";
		allam_resources .*"_gox_t"])

	gross_power_sco2turbine = value.(EP[:vOutput_AllamcycleLOX])[:,sco2turbine,:]
	if setup["UCommit"] > 0
		sco2turbine_commit = value.(EP[:vCOMMIT_Allam])[:, sco2turbine, :]
		asu_commit = value.(EP[:vCOMMIT_Allam])[:, asu, :]
	else
		sco2turbine_commit = zeros(1,T)
		asu_commit = zeros(1,T)
	end
	gross_power_asu = value.(EP[:vOutput_AllamcycleLOX])[:,asu,:]
	net_power_out = value.(EP[:eNetPowerAllam])[:,:]
	lox_storage = value.(EP[:vOutput_AllamcycleLOX])[:,lox,:]
	lox_in = value.(EP[:vLOX_in])
	lox_out = value.(EP[:eLOX_out])
	gox = value.(EP[:vGOX])

    if setup["ParameterScale"] == 1
        gross_power_sco2turbine *= ModelScalingFactor
		gross_power_asu *= ModelScalingFactor
		net_power_out *= ModelScalingFactor
		lox_storage *= ModelScalingFactor
		lox_in *= ModelScalingFactor
		lox_out *= ModelScalingFactor
		gox *= ModelScalingFactor
    end

    allamoutput = [Array(gross_power_sco2turbine);
                   Array(sco2turbine_commit);
                   Array(gross_power_asu);
                   Array(asu_commit);
                   Array(net_power_out);
                   Array(lox_storage);
                   Array(lox_in);
                   Array(lox_out);
                   Array(gox)]

	final_allam = permutedims(DataFrame(hcat(Array(dfAllam_output), allamoutput), :auto))
    CSV.write(joinpath(path,"output_allam_cycle_lox.csv"), final_allam, writeheader = false)
end
