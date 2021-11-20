cd("C:/Users/Guillermo/OneDrive - uc.cl/Material Universidad/Ramos/2020-II/Topicos Avanzados Potencia/Tareas/Tarea_4");

using JuMP, Gurobi

function LMP()

    model = Model(solver= GurobiSolver(OutputFlag=0))

    LineSet = 1:4;
    GeneratorSet = 1:4;

    VariableGeneratorCost = [40, 20, 50, 0];

    Reactance_21 = 0.001;
    Reactance_23 = 0.002;
    Reactance_34 = 0.001;
    Reactance_14 = 0.001;

    LineCapacity_21 = 600;
    LineCapacity_23 = 300;
    LineCapacity_34 = 3000;
    LineCapacity_14 = 3000;

    #LineCapacity_21 = 3000;

    #LineCapacity_21 = 10_000;
    #LineCapacity_23 = 10_000;
    #LineCapacity_34 = 10_000;
    #LineCapacity_14 = 10_000;

    #Pmax = [1500,1000,1500,0];
    Pmax = [1500,1000,1200,0];
    Pmin = [0,0,0,0];

    #Demand = [0, 0, 0, 1500];
    Demand = [0, 0, 0, 3000];


    @variable(model, Pg[1:4]);
    @variable(model, theta[1:4]);

    @objective(model, Min, sum(VariableGeneratorCost[i]*Pg[i] for i in GeneratorSet))

    @constraint(model, theta[3] == 0); #slack

    #BALANCE DE POTENCIA
    @constraint(model, PowerFlowLine1, (1/Reactance_21)*(theta[1] - theta[2]) +
    (1/Reactance_14)*(theta[1] - theta[4]) == Pg[1] - Demand[1]);
    @constraint(model, PowerFlowLine2,  (1/Reactance_21)*(theta[2] - theta[1]) +
    (1/Reactance_23)*(theta[2] - theta[3]) == Pg[2] - Demand[2]);
    @constraint(model, PowerFlowLine3, (1/Reactance_23)*(theta[3] - theta[2]) +
    (1/Reactance_34)*(theta[3] - theta[4]) == Pg[3] - Demand[3]);
    @constraint(model, PowerFlowLine0, (1/Reactance_14)*(theta[4] - theta[1]) +
    (1/Reactance_34)*(theta[4] - theta[3]) == Pg[4] - Demand[4]);

    #FLUJO POR LAS LINEAS
    @constraint(model, FluxMaxLine_2_1, (1/Reactance_21)*(theta[2] - theta[1]) <= LineCapacity_21);
    @constraint(model, FluxMaxLine_2_3, (1/Reactance_23)*(theta[2] - theta[3]) <= LineCapacity_23);
    @constraint(model, FluxMaxLine3_4, (1/Reactance_34)*(theta[3] - theta[4]) <= LineCapacity_34);
    @constraint(model, FluxMaxLine1_4, (1/Reactance_14)*(theta[1] - theta[4]) <= LineCapacity_14);

    @constraint(model, FluxMinLine_2_1, (1/Reactance_21)*(theta[2] - theta[1]) >= -LineCapacity_21);
    @constraint(model, FluxMinLine_2_3, (1/Reactance_23)*(theta[2] - theta[3]) >= -LineCapacity_23);
    @constraint(model, FluxMinLine3_4, (1/Reactance_34)*(theta[3] - theta[4]) >= -LineCapacity_34);
    @constraint(model, FluxMinLine1_4, (1/Reactance_14)*(theta[1] - theta[4]) >= -LineCapacity_14);

    #LIMITES DE POTENCIA
    @constraint(model, Powermax1, Pg[1] <= Pmax[1]);
    @constraint(model, Powermax2, Pg[2] <= Pmax[2]);
    @constraint(model, Powermax3, Pg[3] <= Pmax[3]);
    @constraint(model, Powermax4, Pg[4] <= Pmax[4]);

    @constraint(model, Powermin1, Pg[1] >= Pmin[1]);
    @constraint(model, Powermin2, Pg[2] >= Pmin[2]);
    @constraint(model, Powermin3, Pg[3] >= Pmin[3]);
    @constraint(model, Powermin4, Pg[4] >= Pmax[4]);


    solve(model)

    println("");

    println("LMP1 = ", getdual(PowerFlowLine1)/-1, " (Variable Dual Balance Potencia 1)");
    println("LMP2 = ", getdual(PowerFlowLine2)/-1, " (Variable Dual  Balance Potencia 2)");
    println("LMP3 = ", getdual(PowerFlowLine3)/-1, "(Variable Dual  Balance Potencia 3)");
    println("LMP4 = ", getdual(PowerFlowLine0)/-1, "(Variable Dual  Balance Potencia 0)");

    return [model, Pg, theta]
end

Resultados = LMP();
modelo = Resultados[1]; Pg = Resultados[2]; theta = Resultados[3];

println("costos totales: ", getObjectiveValue(modelo));

for i in 1:4
    println("Pg", i,": ", getvalue(Pg[i]), " MW");
end

for i in 1:4
    println("Angle", i,": ", getvalue(theta[i]));
end
