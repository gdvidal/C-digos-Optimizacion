cd("C:/Users/Guillermo/OneDrive - uc.cl/Material Universidad/Ramos/2020-II/Optimizacion-Avanzada/Proyecto");

using JuMP, Gurobi, Random, Distributions

## two nodes ## ##

function Deterministic()
    TimeSet = 1:24;
    GeneratorSet = 1:3;
    WindSet = 1:2;
    T = length(TimeSet);

    ForecastWind_1 = [31.17,29.43,27.67,28.63,28.75,29.22,28.64,29.74,30.42,31.77,33.13,36.41,38.46,40.53,41.39,42.52,45.5,42.61,37.75,34.49,35.98,35.47,32.5,31.21];
    ForecastWind_2 = [26.17,24.43, 22.67, 23.63, 23.75,	24.22,23.64, 24.74,	25.42,	26.77,	28.13,	31.41,	33.46,	35.53,	36.39,	37.52,	40.50,	37.61,	32.75,	29.49,	30.98,	30.47,	27.50,	26.21];

    FluxMaxLine = 60;
    reactance = 0.13;

    Pd= [[110, 90, 76, 67, 60.52, 58.19, 69.84, 81.47, 90.78, 95.44, 102.42, 103.58, 97.76, 93.81, 88.45, 102.42, 104.75, 109.3, 110, 100.8, 95, 80, 73.5, 69.9],
    3*[30,24.06,21.14,18.95,18.22,21.87,25.51,28.43,29.89,32.07,33.01,30.62,29.16,27.7,32.06,32.8,30.98,32.44,34.26,35.72,36.45,32.8,31.7,29.89]];
    Pmax = [120,80,70];
    Pmin =[36,8,7];
    Rmax = [30,27,23];

    StartUpCost = [3600,2400,2100];  #costo encendido
    FixCost = [720,480,420];         #costo fijo
    VariableCost = [60,40,20];       #costo variable
    PenalizationFactor = 0.1;        #curtailment

    RampUp = (1/3)*[21,24,24];
    RampDown = (1/3)*[21,24,24];
    StartRamp = [21,24,36];

    MinUp = [6,4,4];
    MinDW = [6,4,4];

    model = Model(solver= GurobiSolver());

    #Variables primera etapa
    @variable(model, x[GeneratorSet,TimeSet], Bin);  #on/off
    @variable(model, u[GeneratorSet,TimeSet], Bin);  #decision de encendido
    @variable(model, v[GeneratorSet,TimeSet], Bin); #decision apagado

    #variables segunda etapa
    @variable(model, Pg[GeneratorSet,TimeSet]);              #generador convencional
    @variable(model, r[GeneratorSet,TimeSet]);               #reservas
    @variable(model, Theta[GeneratorSet,TimeSet]);           #angulo
    @variable(model, w[WindSet,TimeSet]);                    #produccion eolica


    #function objetive
    @objective(model, Min, sum(FixCost[i]*x[i,t]
        + StartUpCost[i]*u[i,t] + VariableCost[i]*Pg[i,t] for i in GeneratorSet, t in TimeSet));

    @constraint(model, LogicConstraintBorder[i in GeneratorSet, t in 1:1], x[i,t] - 0 == u[i,t] - v[i,t]);
    @constraint(model, LogicConstraint[i in GeneratorSet, t in 2:T], x[i,t] - x[i,t-1] == u[i,t] - v[i,t]);

    @constraint(model, MinUpBorder[i in GeneratorSet, t in 1:1],
    sum(x[i,k] for k in TimeSet if t<=k<=t+MinUp[i]-1) >= MinUp[i] * (x[i,t]-0));
    @constraint(model, MinUp[i in GeneratorSet, t in 2:T],
    sum(x[i,k] for k in TimeSet if t<=k<=MinUp[i]-1) >= MinUp[i] * (x[i,t]-x[i,t-1]))
    @constraint(model, MinDown[i in GeneratorSet, t in 2:T],
    sum(1 - x[i,k] for k in TimeSet if t<=k<=t+MinDW[i]-1) >= MinDW[i] * (x[i,t-1]-x[i,t]));

    #limites de potencia
    @constraint(model, PConstraint3[i in GeneratorSet, t in 1:T],
     Pmin[i]* x[i,t] <= Pg[i,t] +r[i,t])
    @constraint(model, PConstraint4[i in GeneratorSet, t in 1:T],
    Pg[i,t] + r[i,t] <= Pmax[i]*x[i,t])


    #rampas generador
    @constraint(model, RampUp[i in GeneratorSet, t in 2:T],
    Pg[i,t] - Pg[i,t-1] + r[i,t] <= RampUp[i]*(1-u[i,t]) + StartRamp[i]*u[i,t]);
    @constraint(model, RampDown[i in GeneratorSet, t in 2:T],
    Pg[i,t] - Pg[i,t-1] >= -RampDown[i]*(1-v[i,t])- StartRamp[i]*v[i,t]);

    #angulo slack
    @constraint(model, FixAngleAtReferenceBusConstraint[i in 1:1, t in 1:T], Theta[i,t] == 0);

    #limite lineas de transmision
    @constraint(model, LineLimitsOne[t in 1:T], (1/reactance)*(Theta[1,t] - Theta[2,t]) <= FluxMaxLine);
    @constraint(model, LineLimitsTwo[t in 1:T], (1/reactance)*(Theta[1,t] - Theta[2,t]) >= -FluxMaxLine);

    #flujo de potencia
    @constraint(model,PowerFlow1[t in 1:T],  Pg[1,t] + Pg[2,t] + w[1,t] == Pd[1][t] + (1/reactance)*(Theta[1,t] - Theta[2,t]));
    @constraint(model,PowerFlow2[t in 1:T],  Pg[3,t] + w[2,t] == Pd[2][t] + (1/reactance)*(Theta[2,t] - Theta[1,t]));

    #produccion eolica
    @constraint(model, Wind1[t in 1:T], w[1,t] <= ForecastWind_1[t]);
    @constraint(model, Wind2[t in 1:T], w[2,t] <= ForecastWind_2[t]);

    #naturaleza de las variables
    @constraint(model, Wind3[i in WindSet, t in 1:T], w[i,t] >= 0);
    @constraint(model, NVReservas[i in GeneratorSet, t in 1:T], r[i,t] >= 0);

    solve(model)

    return[model, x,u,v,Pg,r,w,Theta];

end

TimeSet = 1:24;
GeneratorSet = 1:3;
WindSet = 1:2;

Sol = Deterministic(); modelo = Sol[1]; X= [Sol[2],Sol[3],Sol[4]]; Pg = Sol[5]; r = Sol[6]; w =Sol[7]; theta=Sol[8];

println("Valor F.O = ", getObjectiveValue(modelo));

for i in 1:3
    for t in 1:24
       println("Pg[",i,",",t,"]",getvalue(Pg[i,t]));
    end
end
