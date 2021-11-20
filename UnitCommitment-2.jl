cd("C:/Users/Guillermo/OneDrive - uc.cl/Material Universidad/Ramos/2020-II/Optimizacion-Avanzada/Proyecto");

using JuMP, Gurobi, Random, Distributions

## two nodes ## ##

function RO()
    TimeSet = 1:24;
    GeneratorSet = 1:3;
    WindSet = 1:2;

    UncertainSet = 1:10; #numero de escenarios
    T = length(TimeSet);
    Random.seed!(1234);
    d = Normal(0, 1);

    FluxMaxLine = 60;
    reactance = 0.13;

    Pd= [[110, 90, 76, 67, 60.52, 58.19, 69.84, 81.47, 90.78, 95.44, 102.42, 103.58, 97.76, 93.81, 88.45, 102.42, 104.75, 109.3, 110, 100.8, 95, 80, 73.5, 69.9],
    3*[30,24.06,21.14,18.95,18.22,21.87,25.51,28.43,29.89,32.07,33.01,30.62,29.16,27.7,32.06,32.8,30.98,32.44,34.26,35.72,36.45,32.8,31.7,29.89]];
    Pmax = [120,80,70];
    Pmin =[36,8,7];

    StartUpCost = [3600,2400,2100];  #costo encendido
    FixCost = [720,480,420];         #costo fijo
    VariableCost = [60,40,20];       #costo variable
    PenalizationFactor = 0.01;        #curtailment

    RampUp = (1/3)*[21,24,15];
    RampDown = (1/3)*[21,24,15];
    StartRamp = [21,24,36];

    MinUp = [6,4,4];
    MinDW = [6,4,4];

    filas = 1; scenarios = length(UncertainSet);     #numero de escenarios

    ForecastWind_1 = [31.17,29.43,27.67,28.63,28.75,29.22,28.64,29.74,30.42,31.77,33.13,36.41,38.46,40.53,41.39,42.52,45.5,42.61,32.75,30.49,25.98,25.47,22.5,18.21];
    ForecastWind_2 = [26.17,24.43, 22.67, 23.63, 23.75,	24.22,23.64, 24.74,	25.42,	26.77,	28.13,	31.41,	33.46,	35.53,	36.39,	37.52,	40.50,	33.61,	35.75,	25.49,	25.98,	30.47,	27.50,	26.21];

    for i in 1:24
        ForecastWind_1[i] =  ForecastWind_1[i]-5;
        ForecastWind_2[i] =  ForecastWind_2[i]-5;
    end

    chi_1 = []; #parametro incierto: disponibilidad eolica Wind farm 1
    chi_2 = []; #parametro incierto: disponibilidad eolica Wind farm 2

    for i in 1:24
        box_1 = [];
        box_2 = [];
        for s in 1:length(UncertainSet)
            push!(box_1, ForecastWind_1[i] + rand(-5:0.01:2)); #max delta = +-5;
            push!(box_2, ForecastWind_2[i] + rand(-5:0.01:2));
        end
        push!(chi_1, box_1);
        push!(chi_2, box_2);
    end

    #******************** **************************** ***************

    model = Model(solver= GurobiSolver(TimeLimit=100));


    #Variables primera etapa
    @variable(model, x[GeneratorSet,TimeSet], Bin);  #on/off
    @variable(model, u[GeneratorSet,TimeSet], Bin);  #decision de encendido
    @variable(model, v[GeneratorSet,TimeSet], Bin); #decision apagado

    #variables segunda etapa
    @variable(model, Pg[GeneratorSet,TimeSet,UncertainSet]);              #generador convencional
    @variable(model, r[GeneratorSet,TimeSet,UncertainSet]);               #reservas
    @variable(model, Theta[GeneratorSet,TimeSet,UncertainSet]);           #angulo
    @variable(model, w[WindSet,TimeSet,UncertainSet]);                    #produccion eolica
    @variable(model, aux);



    #function objetive
    @objective(model, Min, sum(FixCost[i]*x[i,t]
        + StartUpCost[i]*u[i,t] for i in GeneratorSet, t in TimeSet) + aux);

    #### ### constraint first stage ### #### ###
    @constraint(model, LogicConstraintBorder[i in GeneratorSet, t in 1:1], x[i,t] - 0 == u[i,t] - v[i,t]);
    @constraint(model, LogicConstraint[i in GeneratorSet, t in 2:T], x[i,t] - x[i,t-1] == u[i,t] - v[i,t]);

    @constraint(model, MinUpBorder[i in GeneratorSet, t in 1:1],
    sum(x[i,k] for k in TimeSet if t<=k<=t+MinUp[i]-1) >= MinUp[i] * (x[i,t]-0));
    @constraint(model, MinUp[i in GeneratorSet, t in 2:T],
    sum(x[i,k] for k in TimeSet if t<=k<=MinUp[i]-1) >= MinUp[i] * (x[i,t]-x[i,t-1]))
    @constraint(model, MinDown[i in GeneratorSet, t in 2:T],
    sum(1 - x[i,k] for k in TimeSet if t<=k<=t+MinDW[i]-1) >= MinDW[i] * (x[i,t-1]-x[i,t]));

    #### ### constraint two stage ### ### #### ###

    #limites de potencia
    @constraint(model, PConstraint3[i in GeneratorSet, t in 1:T, s in UncertainSet],
     Pmin[i]* x[i,t] <= Pg[i,t,s] + r[i,t,s]);
    @constraint(model, PConstraint4[i in GeneratorSet, t in 1:T, s in UncertainSet],
    Pg[i,t,s] + r[i,t,s] <= Pmax[i]*x[i,t])

    #requerimientos de reserva
    #@constraint(model, ReservasMax[i in GeneratorSet, t in 1:T, s in UncertainSet],
    #sum(r[k,t,s] for k in GeneratorSet) >= Req);

    #rampas generador
    @constraint(model, RampUp[i in GeneratorSet, t in 2:T, s in UncertainSet],
    Pg[i,t,s] - Pg[i,t-1,s] + r[i,t,s] <= RampUp[i]*(1-u[i,t]) + StartRamp[i]*u[i,t]);
    @constraint(model, RampDown[i in GeneratorSet, t in 2:T, s in UncertainSet],
    Pg[i,t,s] - Pg[i,t-1,s] >= -RampDown[i]*(1-v[i,t])- StartRamp[i]*v[i,t]);

    #angulo slack
    @constraint(model, FixAngleAtReferenceBusConstraint[i in 1:1, t in 1:T, s in UncertainSet], Theta[i,t,s] == 0);

    #limite lineas de transmision
    @constraint(model, LineLimitsOne[t in 1:T, s in UncertainSet], (1/reactance)*(Theta[1,t,s] - Theta[2,t,s]) <= FluxMaxLine);
    @constraint(model, LineLimitsTwo[t in 1:T,  s in UncertainSet], (1/reactance)*(Theta[1,t,s] - Theta[2,t,s]) >= -FluxMaxLine);

    #flujo de potencia
    @constraint(model,PowerFlow1[t in 1:T,  s in UncertainSet],  Pg[1,t,s] + Pg[2,t,s] + w[1,t,s] == Pd[1][t] + (1/reactance)*(Theta[1,t,s] - Theta[2,t,s]));
    @constraint(model,PowerFlow2[t in 1:T,  s in UncertainSet],  Pg[3,t,s] + w[2,t,s] == Pd[2][t] + (1/reactance)*(Theta[2,t,s] - Theta[1,t,s]));

    #variable auxiliar: costos segunda etapa
    @constraint(model, ConstraintAux[i in GeneratorSet, t in 1:T, s in UncertainSet] ,
    aux >= sum(VariableCost[i]*Pg[i,t,s]
    for i in GeneratorSet, t in TimeSet for s in UncertainSet));

    #produccion eolica
    @constraint(model, Wind1[t in 1:T, s in UncertainSet], w[1,t,s] <= chi_1[t][s]);
    @constraint(model, Wind2[t in 1:T, s in UncertainSet], w[2,t,s] <= chi_2[t][s]);

    #naturaleza de las variables
    @constraint(model, Wind3[i in WindSet, t in 1:T, s in UncertainSet], w[i,t,s] >= 0);
    @constraint(model, NVReservas[i in GeneratorSet, t in 1:T, s in UncertainSet], r[i,t,s] >= 0);

    solve(model)

    return[model, x,u,v,Pg,r,w,Theta,aux, chi_1, chi_2];

end

TimeSet = 1:24;
GeneratorSet = 1:3;
GeneratorBusLocation = [1,1,2];
WindSet = 1:2;
UncertainSet = 1:5; #numero de escenarios

Sol = RO(); modelo = Sol[1]; X= [Sol[2],Sol[3],Sol[4]]; Pg = Sol[5]; r = Sol[6]; w =Sol[7]; theta=Sol[8], aux = Sol[9];

chi_1 = Sol[10]; chi_2 = Sol[11];

println("Valor F.O = ", getObjectiveValue(modelo));

for t in 1:24
    eolic = 0;
    for i in 1:2
       eolic = eolic + getvalue(w[i,t,10]) ;
    end
    print(eolic,",");
end

for t in 1:24
    rs = 0;
    for i in 1:3
       rs = rs + getvalue(r[i,t,10]) ;
    end
    print(rs,",");
end
