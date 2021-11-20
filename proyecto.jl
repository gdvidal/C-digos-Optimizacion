cd("C:/Users/Guillermo/OneDrive - uc.cl/Material Universidad/Ramos/2020-II/Optimizacion-Avanzada");

using JuMP, JuMPeR, LinearAlgebra, Random, Gurobi

function ro()

    m = RobustModel(solver= GurobiSolver(OutputFlag=0));

    TimeSet = 1:1; T = length(TimeSet);

    Nodos [1,2];
    Pd = [110, 30]; #demanda por nodo

    #Información técnica
    LineCapacity = 60;
    Reactance = 0.13;

    #3 Generadores Termicos
    GeneratorSet = [1,2,3];
    GeneratorPmax = [120,80,70];
    GeneratorPmin =[0,0,0];

    GeneratorCost = [32,20,12];
    ReserveCostUp =[7, 11, 15];
    ReserveCostDown = [5, 6, 14];

    #Wind data
    ForecastWind = [20, 25];
    DeltaWindMax = [15, 20];


    @variable(m, Pg[GeneratorSet]);        #Generacion Termica
    @variable(m, r_up[GeneratorSet]);      #Reserva Up
    @variable(m, r_down[GeneratorSet]);    #Reserva Down
    @variable(m, angle[Nodos]);

    @objective(m, Min, sum(
    GeneratorCost[i] * Pg[i]
    + ReserveCostUp[i]*r_up[i] + ReserveCostDown[i]*r_down[i] for i in GeneratorSet))

    #angulo slack
    @constraint(m, SlackFix, angle[1] == 0);

    #Limites de Potencia
    @constraint(m, PMinConstraint[i in GeneratorSet], GeneratorPmin[i] <= Pg[i] - r_down[i]);
    @constraint(m, PMaxConstraint[i in GeneratorSet], Pg[i] + r_up[i] <= GeneratorPmax[i]);

    #Demanda
    @constraint(m,PowerFlow12[i in GeneratorSet], Pg[1] + Pg[2] + ForecastWind[1] == Pd[1] + (angle[1] -angle[2])/Reactance);
    @constraint(m,PowerFlow21[i in GeneratorSet], Pg[3] + ForecastWind[2] == Pd[2] + (angle[2] - angle[1])/Reactance);

    #Capacidad de linea
    @constraint(m, LineFlow, angle[2]/Reactance >= -60); @constraint(m, LineFlow2, angle/Reactance <= 60);

    #Naturaleza de las Variables
    @constraint(m, NaturalezaVars[i in GeneratorSet, t in 1:T], r_up[i,t]>= 0);
    @constraint(m, NaturalezaVars2[i in GeneratorSet, t in 1:T], r_down[i,t]>= 0);

    ##########################

    ###max min problem##
    @variable(m, Pg_Up[GeneratorSet]);
    @variable(m, Pg_Down[GeneratorSet]);

    @uncertain(m, dW[Nodos]);        #desviacion respecto a la generacion promedio
    @uncertain(m, dW_Up[Nodos]);     #parte positiva de la desviacion
    @uncertain(m, dW_Down[Nodos]);   #parte negativa de la desviacion

    @variable(m, delta[Nodos]); #angulo de la red actual
    @variable(m, l_sh[Nodos]);  #derrame de carga
    @variable(m, w_sp[Nodos]);  #derrame eolico




end

resultados = ro();
