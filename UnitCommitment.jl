cd("C:/Users/Guillermo/OneDrive - uc.cl/Material Universidad/Ramos/2020-II/Optimizacion-Avanzada/Proyecto");

### Load packages ###
using JuMP, GLPK, XLSX, Gurobi

function UnitCommitmentFunctionRenewables(Data) #Función constructura y optimizadora del modelo
    #Se cargan los datos
    BusSet = Data[1]; TimeSet = Data[2]; GeneratorSet = Data[3]; LineSet = Data[4]; Pd = Data[5]; GeneratorBusLocation = Data[6]; GeneratorPminInMW = Data[7]; GeneratorPmaxInMW = Data[8];
    GeneratorRampInMW = Data[9]; GeneratorStartUpShutDownRampInMW = Data[10]; GeneratorMinimumUpTimeInHours = Data[11]; GeneratorMinimumDownTimeInHours = Data[12];
    GeneratorStartUpCostInUSD = Data[13]; GeneratorFixedCostInUSDperHour = Data[14]; GeneratorVariableCostInUSDperMWh = Data[15];
    GeneratorVariableCostInUSDperMWh = Data[16]; LineFromBus = Data[17]; LineToBus = Data[18]; LineReactance = Data[19]; LineMaxFlow = Data[20]; ReservasMax= Data[21]; ReservasMin= Data[22];
    #Horizonte de tiempo
    T = length(TimeSet)

    R_req = 0;
    #Creacion del modelo de JuMP con optimizador GLPK
    #model = Model(with_optimizer(GLPK.Optimizer()))
    model = Model(solver= GurobiSolver(OutputFlag=0))
    #Variables del modelo
    @variable(model, x[GeneratorSet,TimeSet], Bin) #Estado del generador i (ON/OFF) en cada hora t
    @variable(model, u[GeneratorSet,TimeSet], Bin) #Variable de decisión de encendido del generador i en la hora t
    @variable(model, v[GeneratorSet,TimeSet], Bin) #Variable de decisión de apagado del generador i en la hora t
    @variable(model, Pg[GeneratorSet,TimeSet]) #Generación de potencia activa del generador i en la hora t
    @variable(model, r[GeneratorSet,TimeSet]) #reservas potencia activa del generador i en la hora t
    @variable(model, Theta[BusSet,TimeSet]) #Angulo de voltaje en el bus i para la hora t

    @objective(model, Min, sum(GeneratorFixedCostInUSDperHour[i] * x[i,t] #Funcion objetivo, costos fijos/hora,
        + GeneratorStartUpCostInUSD[i] * u[i,t]                           #costos variables/MW y costo de encendido
        + GeneratorVariableCostInUSDperMWh[i] * Pg[i,t] for i in GeneratorSet, t in TimeSet))

    #Restricciones de inicio y de estado de los generadores dependiendo de las variables de decisión para cada hora
    @constraint(model, LogicConstraintBorder[i in GeneratorSet, t in 1:1], x[i,t] - 0 == u[i,t] - v[i,t])
    @constraint(model, LogicConstraint[i in GeneratorSet, t in 2:T], x[i,t] - x[i,t-1] == u[i,t] - v[i,t])
    #Restricciones de potencia maxima y minima para cada generador convencional y renovable en cada hora dependiendo de si esta encendido
    @constraint(model, PConstraint1[i in GeneratorSet, t in 1:T], GeneratorPminInMW[i][t] <= Pg[i,t] + r[i,t])
    @constraint(model, PConstraint2[i in GeneratorSet, t in 1:T],  Pg[i,t] + r[i,t]<= GeneratorPmaxInMW[i][t])

    @constraint(model, PConstraint3[i in GeneratorSet, t in 1:T], GeneratorPminInMW[i][t] * x[i,t] <= Pg[i,t])
    @constraint(model, PConstraint4[i in GeneratorSet, t in 1:T], Pg[i,t] <= GeneratorPmaxInMW[i][t] * x[i,t])
    #@constraint(model, PMaxConstraint[i in GeneratorSet, t in 1:T], Pg[i,t] + r[i,t] <= GeneratorPmaxInMW[i][t] * x[i,t])
    #Restricciones de rampa en operacion y de encendido/apagado
    @constraint(model, RampUp[i in GeneratorSet, t in 2:T], Pg[i,t] - Pg[i,t-1] <= GeneratorRampInMW[i]*(1-u[i,t])+GeneratorStartUpShutDownRampInMW[i]*u[i,t])
    @constraint(model, RampDown[i in GeneratorSet, t in 2:T], Pg[i,t] - Pg[i,t-1] >= -GeneratorRampInMW[i]*(1-v[i,t])-GeneratorStartUpShutDownRampInMW[i]*v[i,t])
    #Restricciones de tiempo minimo de operación y tiempo minimo de no operación
    @constraint(model, MinUpBorder[i in GeneratorSet, t in 1:1],
    sum(x[i,k] for k in TimeSet if t<=k<=t+GeneratorMinimumUpTimeInHours[i]-1) >= GeneratorMinimumUpTimeInHours[i] * (x[i,t]-0))
    @constraint(model, MinUp[i in GeneratorSet, t in 2:T],
    sum(x[i,k] for k in TimeSet if t<=k<=t+GeneratorMinimumUpTimeInHours[i]-1) >= GeneratorMinimumUpTimeInHours[i] * (x[i,t]-x[i,t-1]))
    @constraint(model, MinDown[i in GeneratorSet, t in 2:T],
    sum(1 - x[i,k] for k in TimeSet if t<=k<=t+GeneratorMinimumDownTimeInHours[i]-1) >= GeneratorMinimumDownTimeInHours[i] * (x[i,t-1]-x[i,t]))
    #Fijación del angulo de referencia
    @constraint(model, FixAngleAtReferenceBusConstraint[i in 1:1, t in 1:T], Theta[i,t] == 0)
    #Restricciones de flujo DC
    @constraint(model, DCPowerFlowConstraint[i in BusSet, t in 1:T],
        sum(Pg[k,t] for k in GeneratorSet if GeneratorBusLocation[k] == i)
        - Pd[i][t]
        == sum( (1/LineReactance[l]) * (Theta[LineFromBus[l],t] - Theta[LineToBus[l],t]) for l in LineSet if LineFromBus[l] == i)
        + sum( (1/LineReactance[l]) * (Theta[LineToBus[l],t] - Theta[LineFromBus[l],t]) for l in LineSet if LineToBus[l] == i))
    #Restricciones de limite de lineas
    @constraint(model, LineLimitsOne[i in LineSet, t in 1:T],
        1/LineReactance[i] * (Theta[LineFromBus[i],t] - Theta[LineToBus[i],t]) <= LineMaxFlow[i])
    @constraint(model, LineLimitsTwo[i in LineSet, t in 1:T],
    1/LineReactance[i] * (Theta[LineFromBus[i],t] - Theta[LineToBus[i],t]) >= -LineMaxFlow[i])
    #Restriccion de encendido de renovables
    @constraint(model, Renewables[i in GeneratorSet[6:7], t in TimeSet], x[i,t] == 1)

    #agregar reservas
    @constraint(model, ReservasMax[i in GeneratorSet, t in 1:T], r[i,t] <=  ReservasMax[i])
    @constraint(model, NVReservas[i in GeneratorSet, t in 1:T], r[i,t] >= 0)
    #@constraint(model, Requerimientos[i in GeneratorSet, t in 1:T], sum(r[k,t] for k in GeneratorSet) == R_req);

    #Optimizacion del modelo
    solve(model)

    return [model,x,u,v,Pg,r]
end


#Load case 14
Case14 = XLSX.readxlsx("Case014.xlsx")
Buses = Case14["Buses"]
Demand = Case14["Demand"]
Generators = Case14["Generators"]
Lines = Case14["Lines"]
Renewables = Case14["Renewables"]

#Case 14 with renewables
#Sets and parameters
#BusSet
BusSet = Array{Int64,1}(undef,14)
for i = 1:14
    BusSet[i] = i
end
#TimeSet
TimeSet = 1:24
#GeneratorSet
GeneratorSet = Array{Int64,1}(undef,7)
for i = 1:7
    GeneratorSet[i] = i
end
#LineSet
LineSet = Array{Int64,1}(undef,20)
for i=1:20
    LineSet[i] = i
end
#Pd
DemandSet = [Demand["B3:Y3"],Demand["B4:Y4"],Demand["B5:Y5"],Demand["B6:Y6"],Demand["B7:Y7"],Demand["B8:Y8"],Demand["B9:Y9"],Demand["B10:Y10"],Demand["B11:Y11"],Demand["B12:Y12"],Demand["B13:Y13"],Demand["B14:Y14"],Demand["B15:Y15"],Demand["B16:Y16"]]
Pd = Array{Array{Float64,1},1}(undef,maximum(BusSet))
for i=1:maximum(BusSet)
    Pd[i] = Float64[]
end
for i = 1:maximum(BusSet)
    for j =1:maximum(TimeSet)
        Pd[i] = vcat(Pd[i],DemandSet[i][j])
    end
end
#GeneratorBusLocation
Location = Generators["B2:B8"]
for i=1:length(Location)
    Location[i] = parse(Int64, Location[i][4:end])
end
GeneratorBusLocation = Array{Int64,1}(undef,length(Location))
for i=1:length(Location)
    GeneratorBusLocation[i] = Location[i]
end
#GeneratorPminInMW
ReneMin = [zeros(24,1),zeros(24,1)]
Min = Generators["D2:D8"]
GeneratorPminauxiliar = Array{Float64,1}(undef,length(Min))
for i = 1:length(Min)
    GeneratorPminauxiliar[i] = Min[i]
end

GeneratorPminInMW = Array{Array{Float64,1},1}(undef,length(Min))
for i=1:length(GeneratorPminInMW)
    GeneratorPminInMW[i] = Float64[]
end


for i = 1:5
    for j = 1:24
        GeneratorPminInMW[i] = vcat(GeneratorPminInMW[i],GeneratorPminauxiliar[i])
    end
end

for i=6:7
    for j = 1:24
        GeneratorPminInMW[i] = vcat(GeneratorPminInMW[i],ReneMin[i-5][j])
    end
end

#GeneratorPmaxInMW
Rene =  [Renewables["B3:Y3"],Renewables["B4:Y4"]]
Max =  Generators["C2:C8"]
GeneratorPmaxauxiliar = Array{Float64,1}(undef,length(Max))
for i = 1:length(Max)
    GeneratorPmaxauxiliar[i] = Max[i]
end

GeneratorPmaxInMW = Array{Array{Float64,1},1}(undef,length(Max))
for i=1:length(GeneratorPmaxInMW)
    GeneratorPmaxInMW[i] = Float64[]
end

for i = 1:5
    for j = 1:24
        GeneratorPmaxInMW[i] = vcat(GeneratorPmaxInMW[i],GeneratorPmaxauxiliar[i])
    end
end
for i=6:7
    for j = 1:24
        GeneratorPmaxInMW[i] = vcat(GeneratorPmaxInMW[i],Rene[i-5][j])
    end
end


#Reservas min
ReservasMin = Generators["U2:U8"]
Generator_Rmin = Array{Float64,1}(undef,length(ReservasMin))
for i = 1:length(ReservasMin)
    Generator_Rmin[i] = ReservasMin[i]
end

#Reservas max
ReservasMax = Generators["V2:V8"]
Generator_Rmax = Array{Float64,1}(undef,length(ReservasMax))
for i = 1:length(ReservasMax)
    Generator_Rmax[i] = ReservasMax[i]
end

#GeneratorRampInMW
Rampa = Generators["G2:G8"]
GeneratorRampInMW = Array{Float64,1}(undef,length(Rampa))
for i = 1:length(Rampa)
    GeneratorRampInMW[i] = Rampa[i]
end
#GeneratorStartUpShutDownRampInMW
RampaStart = Generators["H2:H8"]
GeneratorStartUpShutDownRampInMW = Array{Float64,1}(undef,length(RampaStart))
for i = 1:length(RampaStart)
    GeneratorStartUpShutDownRampInMW[i] = RampaStart[i]
end
#GeneratorMinimumUpTimeInHours
UpTime = Generators["I2:I8"]
GeneratorMinimumUpTimeInHours = Array{Int64,1}(undef,length(UpTime))
for i = 1:length(UpTime)
    GeneratorMinimumUpTimeInHours[i] = UpTime[i]
end
#GeneratorMinimumDownTimeInHours
DownTime = Generators["J2:J8"]
GeneratorMinimumDownTimeInHours = Array{Int64,1}(undef,length(DownTime))
for i=1:length(DownTime)
    GeneratorMinimumDownTimeInHours[i] = DownTime[i]
end
#GeneratorStartUpCostInUSD
SCost = Generators["M2:M8"]
GeneratorStartUpCostInUSD = Array{Float64,1}(undef,length(SCost))
for i=1:length(SCost)
    GeneratorStartUpCostInUSD[i] = SCost[i]
end
#GeneratorFixedCostInUSDperHour
FCost = Generators["N2:N8"]
GeneratorFixedCostInUSDperHour = Array{Float64,1}(undef,length(FCost))
for i = 1:length(FCost)
    GeneratorFixedCostInUSDperHour[i] = FCost[i]
end
#GeneratorVariableCostInUSDperMWh
VCost= Generators["O2:O8"]
GeneratorVariableCostInUSDperMWh = Array{Float64,1}(undef,length(VCost))
for i = 1:length(VCost)
    GeneratorVariableCostInUSDperMWh[i] = VCost[i]
end
#LineFromBus
From = Lines["B2:B21"]
for i=1:length(From)
    From[i] = parse(Int64, From[i][4:end])
end
LineFromBus = Array{Int64,1}(undef,length(From))
for i = 1:length(From)
    LineFromBus[i] = From[i]
end

#LineToBus
To = Lines["C2:C21"]
for i=1:length(To)
    To[i] = parse(Int64, To[i][4:end])
end
LineToBus = Array{Int64,1}(undef,length(To))
for i=1:length(To)
    LineToBus[i] = To[i]
end
#LineReactance
Reactance = Lines["E2:E21"]
LineReactance = Array{Float64,1}(undef,length(Reactance))
for i = 1:length(Reactance)
    LineReactance[i] = Reactance[i]
end
#LineMaxFlow
MaxFlow = Lines["G2:G21"]
LineMaxFlow = Array{Float64,1}(undef,length(MaxFlow))
for i =1:length(MaxFlow)
    LineMaxFlow[i] = MaxFlow[i]
end


Pd = Pd.*0.01
GeneratorPminInpu = GeneratorPminInMW.*0.01
GeneratorPmaxInpu = GeneratorPmaxInMW.*0.01
GeneratorRampInpu = GeneratorRampInMW.*0.01
GeneratorStartUpShutDownRampInpu = GeneratorStartUpShutDownRampInMW.*0.01
GeneratorVariableCostInUSDperpu = GeneratorVariableCostInUSDperMWh.*100
LineMaxFlowpu = LineMaxFlow.*0.01

ReservasMinInpu = Generator_Rmin*0.01
ReservasMaxInpu= Generator_Rmax* 0.01


Data = [BusSet,TimeSet,GeneratorSet,LineSet,Pd,GeneratorBusLocation,GeneratorPminInpu,
GeneratorPmaxInpu,GeneratorRampInpu,GeneratorStartUpShutDownRampInpu,GeneratorMinimumUpTimeInHours,
GeneratorMinimumDownTimeInHours,GeneratorStartUpCostInUSD,GeneratorFixedCostInUSDperHour,
GeneratorVariableCostInUSDperpu,GeneratorVariableCostInUSDperpu,LineFromBus,LineToBus,
LineReactance,LineMaxFlowpu, ReservasMaxInpu, ReservasMinInpu]


Results = UnitCommitmentFunctionRenewables(Data)
model = Results[1]; x = Results[2]; u = Results[3]; v = Results[4]; Pg = Results[5]; r= Results[6];
println("Case with renewables")
println("Total cost: ", getObjectiveValue(model))
println("Total start up costs: ",sum(getvalue(u[i,t])*GeneratorStartUpCostInUSD[i] for i in GeneratorSet for t in TimeSet))
println("Total fixed costs: ",sum(getvalue(x[i,t])*GeneratorFixedCostInUSDperHour[i] for i in GeneratorSet for t in TimeSet))
println("Total variable costs: ",sum(getvalue(Pg[i,t])*GeneratorVariableCostInUSDperpu[i] for i in GeneratorSet for t in TimeSet))
println("Total reserve cost: ",sum(getvalue(r[i,t])*GeneratorVariableCostInUSDperpu[i] for i in GeneratorSet for t in TimeSet) )




for t in 1:24
    hora_1 = 0;
    for i in 1:7
        #println("Reservas: ", " Hora: ",t, " Nivel: ", sum(getvalue(r[i,t])))
        hora_1 = hora_1 + getvalue(r[i,t]);
    end

    println("Reservas hora ",t, ": ",hora_1)
end




filename = "Sol_145.xlsx"

columns = Vector()

P = Array{Array{Float64,1},1}(undef,24)
for i in 1:length(P)
    P[i] = Float64[]
end

for i in TimeSet
    for t in GeneratorSet
        P[i] = vcat(P[i],getvalue(Pg[t,i])*100)
    end
end

push!(columns, [1,2,3,4,5,"Eolica1","Eolica2"])
for t in TimeSet
    push!(columns, P[t])
end
labels = [ "Generator","1", "2","3","4","5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24"]

XLSX.openxlsx(filename, mode="w") do xf
    sheet = xf[1]
    XLSX.writetable!(sheet, columns, labels, anchor_cell=XLSX.CellRef("B2"))
end
