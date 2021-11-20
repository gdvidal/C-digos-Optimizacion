cd("C:/Users/Guillermo/OneDrive - uc.cl/Material Universidad/Ramos/2020-II/Topicos Avanzados Potencia/Tareas/Tarea_3");

using JuMP, Gurobi

function p2()

    model = Model(solver= GurobiSolver(OutputFlag=0))

    TimeSet = 1:12; T = length(TimeSet)
    GeneratorSet = [1,2,3,4,5];
    VariableGeneratorCost= [10,20,30,40,50];
    FixedGeneratorCost = [1000, 300, 100, 50, 0];

    Pd = [40, 20, 30, 40, 50, 60, 65, 60, 50, 30, 25, 21];
    #Pd = [40, 30, 40, 60, 50, 70, 60, 60, 40, 30, 40, 25];

    GeneratorPmax= [25, 15, 10, 10, 10];
    GeneratorPmin= [0, 0, 0, 0, 0];

    #modificaciones caso B
    RampUp = [6, 6, 3, 3, 3];   #rampas
    RampDown=  [6, 6, 3, 3, 3]; #rampas

    PgInitial = [2, 2, 2, 2, 2]; #caso base para rampas
    x = [[1,1,1,1,1,1,1,1,1,1,1,1],[1,1,1,1,1,1,1,1,1,1,1,0],
    [1,1,1,1,1,1,1,1,1,1,1,0],[1,1,0,1,1,1,1,1,1,1,0,0],[1,1,1,1,1,1,1,1,1,1,1,1]]; #fijar variables binarias

    @variable(model, Pg[GeneratorSet,TimeSet]);     #nivel de generacion
    #@variable(model, x[GeneratorSet,TimeSet], Bin); #estado del gen

    @objective(model, Min, sum(
    FixedGeneratorCost[i]*x[i][t] +
    VariableGeneratorCost[i] * Pg[i,t] for i in GeneratorSet, t in TimeSet))

    #@objective(model, Min, sum(
    #FixedGeneratorCost[i]*x[i,t] +
    #VariableGeneratorCost[i] * Pg[i,t] for i in GeneratorSet, t in TimeSet))

    #Limites de Potencia
    @constraint(model, PMinConstraint[i in GeneratorSet, t in 1:T], GeneratorPmin[i] * x[i][t]  <= Pg[i,t]);
    @constraint(model, PMaxConstraint[i in GeneratorSet, t in 1:T], Pg[i,t] <= GeneratorPmax[i]* x[i][t]);

    #Demanda
    @constraint(model,PowerFlow[i in GeneratorSet, t in 1:T], sum(Pg[k,t] for k in GeneratorSet)  == Pd[t]);

    #Reestricciones de Rampa
    #@constraint(model, RampConstraintInitial[i in GeneratorSet, t in 1:1], Pg[i,t] - PgInitial[i] <= RampUp[i]);
    @constraint(model, RampConstraintUp[i in GeneratorSet, t in 2:T], Pg[i,t] - Pg[i,t-1] <= RampUp[i]*x[i][t-1]);
    @constraint(model, RampConstraintDown[i in GeneratorSet, t in 2:T], Pg[i,t] - Pg[i,t-1] >= -RampUp[i]*x[i][t]);

    solve(model)

    return [model, x, Pg]
end

Results = p2();
model = Results[1]; x= Results[2]; Pg= Results[3];

println("Costos Totales: ", getObjectiveValue(model));
println("Costo Marginal :",  getObjectiveValue(model) - 25640);
