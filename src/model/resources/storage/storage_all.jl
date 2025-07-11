@doc raw"""
	storage_all!(EP::Model, inputs::Dict, setup::Dict)

Sets up variables and constraints common to all storage resources. See [`storage!()`](@ref) in ```storage.jl``` for description of constraints.
"""
function storage_all!(EP::Model, inputs::Dict, setup::Dict)
    # Setup variables, constraints, and expressions common to all storage resources
    println("Storage Core Resources Module")

    gen = inputs["RESOURCES"]
    CapacityReserveMargin = setup["CapacityReserveMargin"] > 0
    HourlyMatching = setup["HourlyMatching"]

    virtual_discharge_cost = inputs["VirtualChargeDischargeCost"]

    T = inputs["T"]     # Number of time steps (hours)
    Z = inputs["Z"]     # Number of zones

    STOR_ALL = inputs["STOR_ALL"]
    STOR_SHORT_DURATION = inputs["STOR_SHORT_DURATION"]
    STOR_LONG_DURATION = inputs["STOR_LONG_DURATION"]
    representative_periods = inputs["REP_PERIOD"]

    START_SUBPERIODS = inputs["START_SUBPERIODS"]
    INTERIOR_SUBPERIODS = inputs["INTERIOR_SUBPERIODS"]
    QUALIFIED_SUPPLY = inputs["QUALIFIED_SUPPLY"]   # Resources that are qualified to contribute to hourly matching constraint

    hours_per_subperiod = inputs["hours_per_subperiod"] #total number of hours per subperiod
    weight = inputs["omega"]

    eTotalCapEnergy = EP[:eTotalCapEnergy]
    vP = EP[:vP]

    ### Variables ###

    # Storage level of resource "y" at hour "t" [MWh] on zone "z" - unbounded
    @variable(EP, vS[y in STOR_ALL, t = 1:T]>=0)

    # Energy withdrawn from grid by resource "y" at hour "t" [MWh] on zone "z"
    @variable(EP, vCHARGE[y in STOR_ALL, t = 1:T]>=0)

    if CapacityReserveMargin
        # Virtual discharge contributing to capacity reserves at timestep t for storage cluster y
        @variable(EP, vCAPRES_discharge[y in STOR_ALL, t = 1:T]>=0)

        # Virtual charge contributing to capacity reserves at timestep t for storage cluster y
        @variable(EP, vCAPRES_charge[y in STOR_ALL, t = 1:T]>=0)

        # Total state of charge being held in reserve at timestep t for storage cluster y
        @variable(EP, vCAPRES_socinreserve[y in STOR_ALL, t = 1:T]>=0)
    end

    ### Expressions ###

    # Energy losses related to technologies (increase in effective demand)
    @expression(EP,
        eELOSS[y in STOR_ALL],
        sum(weight[t] * vCHARGE[y, t]
        for t in 1:T)-sum(weight[t] * vP[y, t]
        for t in 1:T))

    ## Objective Function Expressions ##

    #Variable costs of "charging" for technologies "y" during hour "t" in zone "z"
    @expression(EP,
        eCVar_in[y in STOR_ALL, t = 1:T],
        weight[t]*var_om_cost_per_mwh_in(gen[y])*vCHARGE[y, t])

    # Sum individual resource contributions to variable charging costs to get total variable charging costs
    @expression(EP, eTotalCVarInT[t = 1:T], sum(eCVar_in[y, t] for y in STOR_ALL))
    @expression(EP, eTotalCVarIn, sum(eTotalCVarInT[t] for t in 1:T))
    add_to_expression!(EP[:eObj], eTotalCVarIn)

    if CapacityReserveMargin
        #Variable costs of "virtual charging" for technologies "y" during hour "t" in zone "z"
        @expression(EP,
            eCVar_in_virtual[y in STOR_ALL, t = 1:T],
            weight[t]*virtual_discharge_cost*vCAPRES_charge[y, t])
        @expression(EP,
            eTotalCVarInT_virtual[t = 1:T],
            sum(eCVar_in_virtual[y, t] for y in STOR_ALL))
        @expression(EP, eTotalCVarIn_virtual, sum(eTotalCVarInT_virtual[t] for t in 1:T))
        EP[:eObj] += eTotalCVarIn_virtual

        #Variable costs of "virtual discharging" for technologies "y" during hour "t" in zone "z"
        @expression(EP,
            eCVar_out_virtual[y in STOR_ALL, t = 1:T],
            weight[t]*virtual_discharge_cost*vCAPRES_discharge[y, t])
        @expression(EP,
            eTotalCVarOutT_virtual[t = 1:T],
            sum(eCVar_out_virtual[y, t] for y in STOR_ALL))
        @expression(EP, eTotalCVarOut_virtual, sum(eTotalCVarOutT_virtual[t] for t in 1:T))
        EP[:eObj] += eTotalCVarOut_virtual
    end

    ## Power Balance Expressions ##

    STOR_ALL_BY_ZONE = map(1:Z) do z
        return intersect(STOR_ALL, resources_in_zone_by_rid(gen, z))
    end
    # Term to represent net dispatch from storage in any period
    @expression(EP, ePowerBalanceStor[t = 1:T, z = 1:Z],
        sum(vP[y, t] - vCHARGE[y, t]
        for y in STOR_ALL_BY_ZONE[z]))
    add_similar_to_expression!(EP[:ePowerBalance], ePowerBalanceStor)

    ### Constraints ###

    ## Storage energy capacity and state of charge related constraints:

    # Links state of charge in first time step with decisions in last time step of each subperiod
    # We use a modified formulation of this constraint (cSoCBalLongDurationStorageStart) when operations wrapping and long duration storage are being modeled
    if representative_periods > 1 && !isempty(STOR_LONG_DURATION)
        CONSTRAINTSET = STOR_SHORT_DURATION
    else
        CONSTRAINTSET = STOR_ALL
    end
    @constraint(EP,
        cSoCBalStart[t in START_SUBPERIODS, y in CONSTRAINTSET],
        vS[y, t]==
        vS[y, t + hours_per_subperiod - 1] -
        (1 / efficiency_down(gen[y]) * vP[y, t])
        +
        (efficiency_up(gen[y]) * vCHARGE[y, t]) -
        (self_discharge(gen[y]) * vS[y, t + hours_per_subperiod - 1]))

    @constraints(EP,
        begin
            # Maximum energy stored must be less than energy capacity
            [y in STOR_ALL, t in 1:T], vS[y, t] <= eTotalCapEnergy[y]

            # energy stored for the next hour
            cSoCBalInterior[t in INTERIOR_SUBPERIODS, y in STOR_ALL],
            vS[y, t] ==
            vS[y, t - 1] - (1 / efficiency_down(gen[y]) * vP[y, t]) +
            (efficiency_up(gen[y]) * vCHARGE[y, t]) -
            (self_discharge(gen[y]) * vS[y, t - 1])
        end)

    # Hourly matching constraints
    if HourlyMatching == 1
        QUALIFIED_STOR_ALL_BY_ZONE = map(1:Z) do z
            return intersect(QUALIFIED_SUPPLY, STOR_ALL, resources_in_zone_by_rid(gen, z))
        end
        @expression(EP, eHMCharge[t = 1:T, z = 1:Z],
            -sum(vCHARGE[y, t] for y in QUALIFIED_STOR_ALL_BY_ZONE[z]))
        add_similar_to_expression!(EP[:eHM], eHMCharge)
    end

    # Storage discharge and charge power (and reserve contribution) related constraints:
    storage_all_operation!(EP, inputs, setup)

    # From CO2 Policy module
    expr = @expression(EP,
        [z = 1:Z],
        sum(eELOSS[y] for y in intersect(STOR_ALL, resources_in_zone_by_rid(gen, z))))
    add_similar_to_expression!(EP[:eELOSSByZone], expr)

    # Capacity Reserve Margin policy
    if CapacityReserveMargin
        # Constraints governing energy held in reserve when storage makes virtual capacity reserve margin contributions:

        # Links energy held in reserve in first time step with decisions in last time step of each subperiod
        # We use a modified formulation of this constraint (cVSoCBalLongDurationStorageStart) when operations wrapping and long duration storage are being modeled
        @constraint(EP,
            cVSoCBalStart[t in START_SUBPERIODS, y in CONSTRAINTSET],
            vCAPRES_socinreserve[y,
                t]==
            vCAPRES_socinreserve[y, t + hours_per_subperiod - 1] +
            (1 / efficiency_down(gen[y]) * vCAPRES_discharge[y, t])
            -
            (efficiency_up(gen[y]) * vCAPRES_charge[y, t]) - (self_discharge(gen[y]) *
             vCAPRES_socinreserve[y, t + hours_per_subperiod - 1]))

        # energy held in reserve for the next hour
        @constraint(EP,
            cVSoCBalInterior[t in INTERIOR_SUBPERIODS, y in STOR_ALL],
            vCAPRES_socinreserve[y, t]== vCAPRES_socinreserve[y, t - 1] +
            (1 / efficiency_down(gen[y]) * vCAPRES_discharge[y, t]) -
            (efficiency_up(gen[y]) * vCAPRES_charge[y, t]) -
            (self_discharge(gen[y]) * vCAPRES_socinreserve[y, t - 1]))

        # energy held in reserve acts as a lower bound on the total energy held in storage
        @constraint(EP,
            cSOCMinCapRes[t in 1:T, y in STOR_ALL],
            vS[y, t] >= vCAPRES_socinreserve[y, t])
    end
end

function storage_all_operation!(EP::Model, inputs::Dict, setup::Dict)
    gen = inputs["RESOURCES"]
    T = inputs["T"]
    p = inputs["hours_per_subperiod"]
    CapacityReserveMargin = setup["CapacityReserveMargin"] > 0
    OperationalReserves = setup["OperationalReserves"] == 1

    STOR_ALL = inputs["STOR_ALL"]

    eTotalCap = EP[:eTotalCap]
    eTotalCapEnergy = EP[:eTotalCapEnergy]

    vP = EP[:vP]
    vS = EP[:vS]
    vCHARGE = EP[:vCHARGE]

    if OperationalReserves
        STOR_REG = intersect(STOR_ALL, inputs["REG"]) # Set of storage resources with REG reserves
        STOR_RSV = intersect(STOR_ALL, inputs["RSV"]) # Set of storage resources with RSV reserves

        vREG = EP[:vREG]
        vRSV = EP[:vRSV]
        vREG_charge = EP[:vREG_charge]
        vRSV_charge = EP[:vRSV_charge]
        vREG_discharge = EP[:vREG_discharge]
        vRSV_discharge = EP[:vRSV_discharge]

        # Maximum storage contribution to reserves is a specified fraction of installed capacity
        @constraint(EP, [y in STOR_REG, t in 1:T], vREG[y, t]<=reg_max(gen[y]) * eTotalCap[y])
        @constraint(EP, [y in STOR_RSV, t in 1:T], vRSV[y, t]<=rsv_max(gen[y]) * eTotalCap[y])

        # Actual contribution to regulation and reserves is sum of auxilary variables for portions contributed during charging and discharging
        @constraint(EP,
            [y in STOR_REG, t in 1:T],
            vREG[y, t]==vREG_charge[y, t] + vREG_discharge[y, t])
        @constraint(EP,
            [y in STOR_RSV, t in 1:T],
            vRSV[y, t]==vRSV_charge[y, t] + vRSV_discharge[y, t])

        # Maximum discharging rate and contribution to reserves down must be greater than zero
        # Note: when discharging, reducing discharge rate is contributing to downwards regulation as it drops net supply
        @constraint(EP, [y in STOR_REG, t in 1:T], vP[y, t] - vREG_discharge[y, t]>=0)

        # Maximum charging rate plus contribution to reserves up must be greater than zero
        # Note: when charging, reducing charge rate is contributing to upwards reserve & regulation as it drops net demand
        expr = extract_time_series_to_expression(vCHARGE, STOR_ALL)
        add_similar_to_expression!(expr[STOR_REG, :], -vREG_charge[STOR_REG, :])
        add_similar_to_expression!(expr[STOR_RSV, :], -vRSV_charge[STOR_RSV, :])
        @constraint(EP, [y in STOR_ALL, t in 1:T], expr[y, t]>=0)

        # Maximum charging rate plus contribution to regulation down must be less than available storage capacity
        @constraint(EP,
            [y in STOR_REG, t in 1:T],
            efficiency_up(gen[y]) *
            (vCHARGE[y, t] +
             vREG_charge[y, t])<=eTotalCapEnergy[y] - vS[y, hoursbefore(p, t, 1)])
        # Note: maximum charge rate is also constrained by maximum charge power capacity, but as this differs by storage type,
        # this constraint is set in functions below for each storage type
    end

    # Maximum discharging rate (and contribution to reserves up) must be less than power rating
    expr = extract_time_series_to_expression(vP, STOR_ALL)
    if OperationalReserves
        add_similar_to_expression!(expr[STOR_REG, :], vREG_discharge[STOR_REG, :])
        add_similar_to_expression!(expr[STOR_RSV, :], vRSV_discharge[STOR_RSV, :])
    end
    if CapacityReserveMargin
        vCAPRES_discharge = EP[:vCAPRES_discharge]
        add_similar_to_expression!(expr[STOR_ALL, :], vCAPRES_discharge[STOR_ALL, :])
    end
    @constraint(EP, [y in STOR_ALL, t in 1:T], expr[y, t]<=eTotalCap[y])
    # Maximum discharging rate (and contribution to reserves up) must be less than available stored energy in prior period
    @constraint(EP,
        [y in STOR_ALL, t in 1:T],
        expr[y, t]<=vS[y, hoursbefore(p, t, 1)] * efficiency_down(gen[y]))
end
