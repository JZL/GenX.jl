@doc raw"""
	long_duration_storage!(EP::Model, inputs::Dict, setup::Dict)
This function creates variables and constraints enabling modeling of long duration storage resources when modeling representative time periods.\

**Storage inventory balance at beginning of each representative period**
The constraints in this section are used to approximate the behavior of long-duration energy storage technologies when approximating annual grid operations by modeling operations over representative periods. Previously, the state of charge balance for storage (as defined in [`storage_all!()`](@ref)) assumed that state of charge at the beginning and end of each representative period has to be the same. In other words, the amount of energy built up or consumed by storage technology $o$ in zone $z$ over the representative period $m$, $\Delta Q_{o,z,m} = 0$. This assumption implicitly excludes the possibility of transferring energy from one representative period to the other which could be cost-optimal when the capital cost of energy storage capacity is relatively small. To model long-duration energy storage using representative periods, we replace the state of charge equation, such that the first term on the right hand side accounts for change in storage inventory associated with representative period $m$ ($\Delta Q_{o,z,m}$), which could be positive (net accumulation) or negative (net reduction).

```math
\begin{aligned}
& \Gamma_{o,z,(m-1)\times \tau^{period}+1 } =\left(1-\eta_{o,z}^{loss}\right)\times \left(\Gamma_{o,z,m\times \tau^{period}} -\Delta Q_{o,z,m}\right) -  \\
& \frac{1}{\eta_{o,z}^{discharge}}\Theta_{o,z,(m-1)\times \tau^{period}+1} + \eta_{o,z}^{charge}\Pi_{o,z,(m-1)\times \tau^{period}+1} \quad \forall o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, m \in \mathcal{M}
\end{aligned}
```
By definition $\mathcal{T}^{start}=\{\left(m-1\right) \times \tau^{period}+1 | m \in \mathcal{M}\}$, which implies that this constraint is defined for all values of $t \in T^{start}$. \
**Storage inventory change input periods**
We need additional variables and constraints to approximate energy exchange between representative periods, while accounting for their chronological occurrence in the original input time series data and the possibility that two representative periods may not be adjacent to each other (see Figure below). To implement this, we introduce a new variable $Q_{o,z, n}$ that models inventory of storage technology $o \in O$ in zone $z$ in each input period $n \in \mathcal{N}$. Additionally we define a function mapping, $f: n \rightarrow m$, that uniquely maps each input period $n$ to its corresponding representative period $m$. This mapping is available as an output of the process used to identify representative periods (E.g. k-means clustering [Mallapragada et al., 2018](https://www.sciencedirect.com/science/article/pii/S0360544218315238?casa_token=I-6GVNMtAVIAAAAA:G8LFXFqXxRGrXHtrzmiIGm02BusIUmm83zKh8xf1BXY81-dTnA9p2YI1NnGuzlYBXsxK12by)).

![Modeling inter-period energy exchange via long-duration storage when using representative period temporal resolution to approximate annual grid operations](../../assets/LDES_approach.png)
*Figure. Modeling inter-period energy exchange via long-duration storage when using representative period temporal resolution to approximate annual grid operations*

The following two equations define the storage inventory at the beginning of each input period $n+1$ as
the sum of storage inventory at beginning of previous input period $n$ plus change in storage inventory for that period.
The latter is approximated by the change in storage inventory in the corresponding representative period,
identified per the mapping $f(n)$.
If the input period is also a representative period,
then a second constraint enforces that initial storage level estimated by the intra-period storage balance constraint should equal the initial storage level estimated from the inter-period storage balance constraints.

```math
\begin{aligned}
& Q_{o,z,n+1} = Q_{o,z,n} + \Delta Q_{o,z,f(n)}
\quad \forall  o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, n \in \mathcal{N}
\end{aligned}
```

```math
\begin{aligned}
& Q_{o,z,n} =\Gamma_{o,z,f(n)\times \tau^{period}} - \Delta Q_{o,z,m}
\quad \forall  o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, n \in   \mathcal{N}^{rep},
\end{aligned}
```

Finally, the next constraint enforces that the initial storage level for each input period $n$ must be less than the installed energy capacity limit. This constraint ensures that installed energy storage capacity is consistent with the state of charge during both the operational time periods $t$ during each sample period $m$ as well as at the start of each chronologically ordered input period $n$ in the full annual time series.

```math
\begin{aligned}
    Q_{o,z,n} \leq \Delta^{total, energy}_{o,z}
\quad \forall n \in \mathcal{N}, o \in \mathcal{O}^{LDES}
\end{aligned}
```

If the capacity reserve margin constraint is enabled, a similar set of constraints is used to track the evolution of the energy held in reserve across representative periods. The main linking constraint is as follows:
```math
\begin{aligned}
& \Gamma^{CRM}_{o,z,(m-1)\times \tau^{period}+1 } =\left(1-\eta_{o,z}^{loss}\right)\times \left(\Gamma^{CRM}_{o,z,m\times \tau^{period}} -\Delta Q_{o,z,m}\right) +  \\
& \frac{1}{\eta_{o,z}^{discharge}}\Theta^{CRM}_{o,z,(m-1)\times \tau^{period}+1} - \eta_{o,z}^{charge}\Pi^{CRM}_{o,z,(m-1)\times \tau^{period}+1} \quad \forall o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, m \in \mathcal{M}
\end{aligned}
```
All other constraints are identical to those used to track the actual state of charge, except with the new variables $Q^{CRM}_{o,z,n}$ and $\Delta Q^{CRM}_{o,z,n}$ used in place of $Q_{o,z,n}$ and $\Delta Q_{o,z,n}$, respectively. \

**Bound storage inventory in non-representative periods**
We need additional variables and constraints to ensure that the storage content is within zero and the installed energy capacity in non-representative periods. We introduce
the variables $\Delta Q^{max,pos}_{o,z,m}$ and $\Delta Q^{max,neg}_{o,z,m}$ that represent the maximum positive and negative storage content variations within the representative
period $m$, respectively, extracted as:

```math
\begin{aligned}
& \Delta Q^{max,pos}_{o,z,m} \geq \Gamma_{o,z,(m-1)\times \tau^{period}+t } - \Gamma_{o,z,(m-1)\times \tau^{period}+1 } \quad \forall o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, m \in \mathcal{M}, t \in \mathcal{T}
& \end{aligned}
```

```math
\begin{aligned}
& \Delta Q^{max,neg}_{o,z,m} \leq \Gamma_{o,z,(m-1)\times \tau^{period}+t } - \Gamma_{o,z,(m-1)\times \tau^{period}+1 } \quad \forall o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, m \in \mathcal{M}, t \in \mathcal{T}
& \end{aligned}
```

For every input period $n \in \mathcal{N}$, the maximum storage is computed and constrained to be less than or equal to the installed energy capacity as:

```math
\begin{aligned}
&  Q_{o,z,n} \times \left(1-\eta_{o,z}^{loss}\right) - \frac{1}{\eta_{o,z}^{discharge}}\Theta_{o,z,(m-1)\times \tau^{period}+1} + \eta_{o,z}^{charge}\Pi_{o,z,(m-1)\times \tau^{period}+1} + \Delta Q^{max,pos}_{o,z,f(n)} \leq \Delta^{total, energy}_{o,z} \\
& \forall o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, n \in \mathcal{N}
& \end{aligned}
```

Similarly, the minimum storage content is imposed to be positive in every period of the time horizon:

```math
\begin{aligned}
&  Q_{o,z,n} \times \left(1-\eta_{o,z}^{loss}\right) - \frac{1}{\eta_{o,z}^{discharge}}\Theta_{o,z,(m-1)\times \tau^{period}+1} + \eta_{o,z}^{charge}\Pi_{o,z,(m-1)\times \tau^{period}+1} + \Delta Q^{max,neg}_{o,z,f(n)} \geq 0 \\
& \forall o \in \mathcal{O}^{LDES}, z \in \mathcal{Z}, n \in \mathcal{N}
& \end{aligned}
```

Additional details on this approach are available in [Parolin et al., 2024](https://doi.org/10.48550/arXiv.2409.19079).
"""
function long_duration_storage!(EP::Model, inputs::Dict, setup::Dict)
    println("Long Duration Storage Module")

    gen = inputs["RESOURCES"]

    CapacityReserveMargin = setup["CapacityReserveMargin"]

    REP_PERIOD = inputs["REP_PERIOD"]     # Number of representative periods

    STOR_LONG_DURATION = inputs["STOR_LONG_DURATION"]

    hours_per_subperiod = inputs["hours_per_subperiod"] #total number of hours per subperiod

    dfPeriodMap = inputs["Period_Map"] # Dataframe that maps modeled periods to representative periods
    NPeriods = size(inputs["Period_Map"])[1] # Number of modeled periods

    MODELED_PERIODS_INDEX = 1:NPeriods
    REP_PERIODS_INDEX = MODELED_PERIODS_INDEX[dfPeriodMap[!, :Rep_Period] .== MODELED_PERIODS_INDEX]
    NON_REP_PERIODS_INDEX = setdiff(MODELED_PERIODS_INDEX, REP_PERIODS_INDEX)

    eTotalCapEnergy = EP[:eTotalCapEnergy]
    vCHARGE = EP[:vCHARGE]
    vS = EP[:vS]
    vP = EP[:vP]

    ### Variables ###

    # Variables to define inter-period energy transferred between modeled periods

    # State of charge of storage at beginning of each modeled period n
    @variable(EP, vSOCw[y in STOR_LONG_DURATION, n in MODELED_PERIODS_INDEX]>=0)

    # Build up in storage inventory over each representative period w
    # Build up inventory can be positive or negative
    @variable(EP, vdSOC[y in STOR_LONG_DURATION, w = 1:REP_PERIOD])

    if CapacityReserveMargin > 0
        # State of charge held in reserve for storage at beginning of each modeled period n
        @variable(EP, vCAPRES_socw[y in STOR_LONG_DURATION, n in MODELED_PERIODS_INDEX]>=0)

        # Build up in storage inventory held in reserve over each representative period w
        # Build up inventory can be positive or negative
        @variable(EP, vCAPRES_dsoc[y in STOR_LONG_DURATION, w = 1:REP_PERIOD])
    end

    # Additional constraints to prevent violation of SoC limits in non-representative periods
    if setup["LDSAdditionalConstraints"] == 1 && !isempty(NON_REP_PERIODS_INDEX)
        # Maximum positive storage inventory change within subperiod
        @variable(EP, vdSOC_maxPos[y in STOR_LONG_DURATION, w=1:REP_PERIOD] >= 0)

        # Maximum negative storage inventory change within subperiod
        @variable(EP, vdSOC_maxNeg[y in STOR_LONG_DURATION, w=1:REP_PERIOD] <= 0)
    end

    ### Constraints ###

    # Links last time step with first time step, ensuring position in hour 1 is within eligible change from final hour position
    # Modified initial state of storage for long-duration storage - initialize wth value carried over from last period
    # Alternative to cSoCBalStart constraint which is included when not modeling operations wrapping and long duration storage
    # Note: tw_min = hours_per_subperiod*(w-1)+1; tw_max = hours_per_subperiod*w
    @constraint(EP,
        cSoCBalLongDurationStorageStart[w = 1:REP_PERIOD, y in STOR_LONG_DURATION],
        vS[y, hours_per_subperiod * (w - 1) + 1]==(1 - self_discharge(gen[y])) *
                                                (vS[y, hours_per_subperiod * w] -
                                                 vdSOC[y, w])
                                                -
                                                (1 / efficiency_down(gen[y]) * vP[
            y, hours_per_subperiod * (w - 1) + 1]) +
                                                (efficiency_up(gen[y]) * vCHARGE[
            y, hours_per_subperiod * (w - 1) + 1]))

    # Storage at beginning of period w = storage at beginning of period w-1 + storage built up in period w (after n representative periods)
    ## Multiply storage build up term from prior period with corresponding weight
    @constraint(EP,
        cSoCBalLongDurationStorage[y in STOR_LONG_DURATION, r in MODELED_PERIODS_INDEX],
        vSOCw[y,
            mod1(r + 1, NPeriods)]==vSOCw[y, r] +
                                    vdSOC[y, dfPeriodMap[r, :Rep_Period_Index]])

    # Storage at beginning of each modeled period cannot exceed installed energy capacity
    @constraint(EP,
        cSoCBalLongDurationStorageUpper[y in STOR_LONG_DURATION,
            r in MODELED_PERIODS_INDEX],
        vSOCw[y, r]<=eTotalCapEnergy[y])

    # Initial storage level for representative periods must also adhere to sub-period storage inventory balance
    # Initial storage = Final storage - change in storage inventory across representative period
    @constraint(EP,
        cSoCBalLongDurationStorageSub[y in STOR_LONG_DURATION, r in REP_PERIODS_INDEX],
        vSOCw[y,
            r]==vS[y, hours_per_subperiod * dfPeriodMap[r, :Rep_Period_Index]] -
                vdSOC[y, dfPeriodMap[r, :Rep_Period_Index]])

    # Capacity Reserve Margin policy
    if CapacityReserveMargin > 0
        vCAPRES_charge = EP[:vCAPRES_charge]
        vCAPRES_discharge = EP[:vCAPRES_discharge]
        vCAPRES_socinreserve = EP[:vCAPRES_socinreserve]
        # LDES Constraints for storage held in reserve

        # Links last time step with first time step, ensuring position in hour 1 is within eligible change from final hour position
        # Modified initial virtual state of storage for long-duration storage - initialize wth value carried over from last period
        # Alternative to cVSoCBalStart constraint which is included when not modeling operations wrapping and long duration storage
        # Note: tw_min = hours_per_subperiod*(w-1)+1; tw_max = hours_per_subperiod*w
        @constraint(EP,
            cVSoCBalLongDurationStorageStart[w = 1:REP_PERIOD, y in STOR_LONG_DURATION],
            vCAPRES_socinreserve[y,
                hours_per_subperiod * (w - 1) + 1]==(1 - self_discharge(gen[y])) *
                                                    (vCAPRES_socinreserve[
                y, hours_per_subperiod * w] - vCAPRES_dsoc[y, w])
                                                    +
                                                    (1 / efficiency_down(gen[y]) *
                                                     vCAPRES_discharge[
                y, hours_per_subperiod * (w - 1) + 1]) -
                                                    (efficiency_up(gen[y]) *
                                                     vCAPRES_charge[
                y, hours_per_subperiod * (w - 1) + 1]))

        # Storage held in reserve at beginning of period w = storage at beginning of period w-1 + storage built up in period w (after n representative periods)
        ## Multiply storage build up term from prior period with corresponding weight
        @constraint(EP,
            cVSoCBalLongDurationStorage[y in STOR_LONG_DURATION,
                r in MODELED_PERIODS_INDEX],
            vCAPRES_socw[y,
                mod1(r + 1, NPeriods)]==vCAPRES_socw[y, r] +
                                        vCAPRES_dsoc[y, dfPeriodMap[r, :Rep_Period_Index]])

        # Initial reserve storage level for representative periods must also adhere to sub-period storage inventory balance
        # Initial storage = Final storage - change in storage inventory across representative period
        @constraint(EP,
            cVSoCBalLongDurationStorageSub[y in STOR_LONG_DURATION, r in REP_PERIODS_INDEX],
            vCAPRES_socw[y,r]==vCAPRES_socinreserve[y,
                hours_per_subperiod * dfPeriodMap[r, :Rep_Period_Index]] -
                    vCAPRES_dsoc[y, dfPeriodMap[r, :Rep_Period_Index]])

        # energy held in reserve at the beginning of each modeled period acts as a lower bound on the total energy held in storage
        @constraint(EP,
            cSOCMinCapResLongDurationStorage[y in STOR_LONG_DURATION,
                r in MODELED_PERIODS_INDEX],
            vSOCw[y, r]>=vCAPRES_socw[y, r])
    end

    if setup["LDSAdditionalConstraints"] == 1 && !isempty(NON_REP_PERIODS_INDEX)
        # Extract maximum storage level variation (positive) within subperiod
        @constraint(EP, cMaxSoCVarPos[y in STOR_LONG_DURATION, w=1:REP_PERIOD, t=2:hours_per_subperiod],
                    vdSOC_maxPos[y,w] >= vS[y,hours_per_subperiod*(w-1)+t] - vS[y,hours_per_subperiod*(w-1)+1])

        # Extract maximum storage level variation (negative) within subperiod
        @constraint(EP, cMaxSoCVarNeg[y in STOR_LONG_DURATION, w=1:REP_PERIOD, t=2:hours_per_subperiod],
                    vdSOC_maxNeg[y,w] <= vS[y,hours_per_subperiod*(w-1)+t] - vS[y,hours_per_subperiod*(w-1)+1])

        # Max storage content within each modeled period cannot exceed installed energy capacity
        @constraint(EP, cSoCLongDurationStorageMaxInt[y in STOR_LONG_DURATION, r in NON_REP_PERIODS_INDEX],
                (1-self_discharge(gen[y]))*vSOCw[y,r]-(1/efficiency_down(gen[y])*vP[y,hours_per_subperiod*(dfPeriodMap[r,:Rep_Period_Index]-1)+1])
                +(efficiency_up(gen[y])*vCHARGE[y,hours_per_subperiod*(dfPeriodMap[r,:Rep_Period_Index]-1)+1])
                +vdSOC_maxPos[y,dfPeriodMap[r,:Rep_Period_Index]] <= eTotalCapEnergy[y])

        # Min storage content within each modeled period cannot be negative
        @constraint(EP, cSoCLongDurationStorageMinInt[y in STOR_LONG_DURATION, r in NON_REP_PERIODS_INDEX],
                (1-self_discharge(gen[y]))*vSOCw[y,r]-(1/efficiency_down(gen[y])*vP[y,hours_per_subperiod*(dfPeriodMap[r,:Rep_Period_Index]-1)+1])
                +(efficiency_up(gen[y])*vCHARGE[y,hours_per_subperiod*(dfPeriodMap[r,:Rep_Period_Index]-1)+1])
                +vdSOC_maxNeg[y,dfPeriodMap[r,:Rep_Period_Index]] >= 0)
    end
end

