cd("C:/Users/Guillermo/OneDrive - uc.cl/Material Universidad/Ramos/2020-II/Topicos Avanzados Potencia/Tareas");

using JuMP, GLPK, Ipopt

function p3()

    model = Model(with_optimizer(GLPK.Optimizer));

    TimeSet = 1:4; T = length(TimeSet)
    GeneratorSet = [1,2,3,4,5];
    GeneratorCost= [10,20,30,40,50];
    Pd = [40, 20, 40, 60];
    GeneratorPmax= [25, 20, 17, 17, 15];
    GeneratorPmin= [0, 0, 0, 0, 0];

    #modificaciones caso B
    #RampUp = [6, 6, 3, 3, 3];   #rampas
    #RampDown=  [6, 6, 3, 3, 3]; #rampas
    RampUp = [5, 5, 3, 3, 3];   #rampas
    RampDown=  [5, 5, 3, 3, 3]; #rampas

    PgInitial = [3, 3, 3, 3, 3];
    GeneratorPmin_2= [3, 3, 3, 3, 3];

    @variable(model, Pg[GeneratorSet,TimeSet]);

    @objective(model, Min, sum(
    GeneratorCost[i] * Pg[i,t] for i in GeneratorSet, t in TimeSet))


    #Limites de Potencia
    @constraint(model, PMinConstraint[i in GeneratorSet, t in 1:T], GeneratorPmin_2[i] <= Pg[i,t]);
    @constraint(model, PMaxConstraint[i in GeneratorSet, t in 1:T], Pg[i,t] <= GeneratorPmax[i]);

    #Demanda
    @constraint(model,PowerFlow[i in GeneratorSet, t in 1:T], sum(Pg[k,t] for k in GeneratorSet)  == Pd[t]);

    #Reestricciones de Rampa
    @constraint(model, RampConstraintInitial[i in GeneratorSet, t in 1:1], Pg[i,t] - PgInitial[i] <= RampUp[i]);
    @constraint(model, RampConstraintUp[i in GeneratorSet, t in 2:T], Pg[i,t] - Pg[i,t-1] <= RampUp[i]);
    @constraint(model, RampConstraintDown[i in GeneratorSet, t in 2:T], Pg[i,t] - Pg[i,t-1] >= -RampUp[i]);

    JuMP.optimize!(model);

    return [model,Pg]
end

Results = p3();
model = Results[1]; Pg= Results[2];

println("Costos Totales: ", JuMP.objective_value(model));

for i in 1:5
    for t in 1:4
        println("i, t, Pg[i,t] ", i, ", ", t, ", ", JuMP.value(Pg[i,t]), " MW");
    end
end

t=2;
Pd=  JuMP.value(Pg[1,t]) +  JuMP.value(Pg[2,t]) +  JuMP.value(Pg[3,t]) +  JuMP.value(Pg[4,t]) +  JuMP.value(Pg[5,t]);
