using JuMP, MathProgBase
using Gurobi
using CSV, DataFrames, DelimitedFiles
import MathOptInterface
using Plots

clearconsole()
gr()

# 1.0 Include files
include("Parámetros.jl")

# 2.0 Optimizer function

function PrimeraEtapa(Data)

    # 2.1 Problem definition
    model = Model(Gurobi.Optimizer)
    set_optimizer_attribute(model, "NumericFocus", 3)
    #set_optimizer_attribute(model, "OutputFlag", 1) 
    #set_optimizer_attribute(model, "MIPGap", 0.01)

    # 2.2 Variable Definition
    @variable(model,                   gen_state[Data["System"]["SetGens"],             t in Data["System"]["SetTimeBlocks"]], binary = true);
    @variable(model,                   hydro_state[Data["System"]["SetHydroNodeGen"],   t in Data["System"]["SetTimeBlocks"]], binary = true);
    @variable(model,                   startup[Data["System"]["SetGens"],               t in Data["System"]["SetTimeBlocks"]], binary = true);
    @variable(model,                   shutdown[Data["System"]["SetGens"],              t in Data["System"]["SetTimeBlocks"]], binary = true);
    @variable(model,                   expected_generation[Data["System"]["SetGens"],   t in Data["System"]["SetTimeBlocks"]], lower_bound = 0);
    @variable(model,                   up_reserve[Data["System"]["SetGens"],            t in Data["System"]["SetTimeBlocks"]], lower_bound = 0);
    @variable(model,                   down_reserve[Data["System"]["SetGens"],          t in Data["System"]["SetTimeBlocks"]], lower_bound = 0);

    # 2.3 Objective Function
    @objective(model, Min, sum( sum(Data["Generators"]["SUP"][g]*startup[g,t] + Data["Generators"]["SDN"][g]*shutdown[g,t] + Data["Generators"]["NoLoadCost"][g] * gen_state[g,t]
                                  + Data["Generators"]["UpReserveCost"][g] * up_reserve[g,t] + Data["Generators"]["DownReserveCost"][g] * down_reserve[g,t]
                         for t in Data["System"]["SetTimeBlocks"]) for g in Data["System"]["SetGens"]))

    # 2.4 Constraints

    # 2.4.1 (Restricción 1.b)
    for g in Data["System"]["SetGens"]
        for t =2:maximum(Data["System"]["SetTimeBlocks"])
            @constraint(model, gen_state[g,t-1] - gen_state[g,t] + startup[g,t]  >= 0)
        end
        @constraint(model, Data["Generators"]["InitialState"][g] - gen_state[g,1] + startup[g,1]  >= 0)
    end

    # 2.4.2 (Restricción 1.c)
    for g in Data["System"]["SetGens"]
        for t =2:maximum(Data["System"]["SetTimeBlocks"])
            @constraint(model, shutdown[g,t] == gen_state[g,t-1] - gen_state[g,t] + startup[g,t] )
        end
        @constraint(model, shutdown[g,1] == Data["Generators"]["InitialState"][g] - gen_state[g,1] + startup[g,1])
    end

    # 2.4.3 (Restricción 1.d)
    for g in Data["System"]["SetGens"]
        for t =2:(maximum(Data["System"]["SetTimeBlocks"])-1)
            for tau=t+1:maximum([t+Data["Generators"]["MinUpTime"][g]-1, maximum(Data["System"]["SetTimeBlocks"])])
                @constraint(model, gen_state[g,t] - gen_state[g,t-1] <= gen_state[g,tau])
            end
        end
        @constraint(model, gen_state[g,1] - Data["Generators"]["InitialState"][g] <= gen_state[g,Data["Generators"]["MinUpTime"][g]])
    end

    # 2.4.4 (Restricción 1.e)
    for g in Data["System"]["SetGens"]
        for t =2:(maximum(Data["System"]["SetTimeBlocks"])-1)
            for tau=t+1:maximum([t+Data["Generators"]["MinDnTime"][g]-1, maximum(Data["System"]["SetTimeBlocks"])])
                @constraint(model, gen_state[g,t-1] - gen_state[g,t] <= 1-gen_state[g,tau])
            end
        end
        @constraint(model, Data["Generators"]["InitialState"][g] - gen_state[g,1] <= 1-gen_state[g,Data["Generators"]["MinDnTime"][g]])
    end

    # 2.4.5 (Restricción 1.f)
    for g in Data["System"]["SetGens"]
        for t =1:(maximum(Data["System"]["SetTimeBlocks"]))
            @constraint(model, expected_generation[g,t] + up_reserve[g,t] <= Data["Generators"]["PMax"][g]*gen_state[g,t])
        end
    end

    # 2.4.4 (Restricción 1.g)
    for g in Data["System"]["SetGens"]
        for t =1:(maximum(Data["System"]["SetTimeBlocks"]))
            @constraint(model, expected_generation[g,t] - down_reserve[g,t] >= Data["Generators"]["PMin"][g]*gen_state[g,t])
        end
    end


    #print(model)
    optimize!(model)

    #Guardamos las decisiones
    Solution = Dict();
    Solution["hydro_generation"]    = [JuMP.value.(hydro_generation)];
    Solution["thermal_generation"]  = [JuMP.value.(thermal_generation)];
    Solution["reservoir_level"]     = [JuMP.value.(reservoir_level)];
    Solution["power_flow"]          = [JuMP.value.(power_flow)];
    Solution["stream_turb"]         = [JuMP.value.(stream_turb)];
    Solution["stream_no_turb"]      = [JuMP.value.(stream_no_turb)];
    Solution["variable_generation"] = [JuMP.value.(variable_generation)];
    Solution["over_generation"]     = [JuMP.value.(over_generation)];
    Solution["load_shedding"]       = [JuMP.value.(load_shedding)];
    Solution["objetive_value"]      = JuMP.objective_value(model)

    return Solution
end

function SegundaEtapa(Data)

    # 2.1 Problem definition
    model = Model(Gurobi.Optimizer)
    set_optimizer_attribute(model, "NumericFocus", 3)
    #set_optimizer_attribute(model, "OutputFlag", 1)
    #set_optimizer_attribute(model, "MIPGap", 0.01)

    # 2.2 Variable Definition
    @variable(model,                   θ[Data["System"]["SetBuses"],             t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]]);
    @variable(model,          power_flow[Data["System"]["SetLines"],             t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]],                  start = 0);
    @variable(model,  thermal_generation[Data["System"]["SetGens"],              t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model, variable_generation[Data["System"]["SetGensVar"],           t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,    hydro_generation[Data["System"]["SetHydroNodes"],        t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,       load_shedding[Data["System"]["SetBuses"],             t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,     over_generation[Data["System"]["SetBuses"],             t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,         stream_turb[Data["System"]["SetHydroStreamsTurb"],  t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,      stream_no_turb[Data["System"]["SetHydroStreamsNTurb"], t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,     reservoir_level[Data["System"]["SetHydroNodesSto"],     t in Data["System"]["SetTimeBlocks"]],                                  lower_bound = 0, start = 1000);

    # 2.3 Objective Function
    @objective(model, Min, sum(
                          (sum(thermal_generation[g,t,1]*Data["Generators"]["VariableCost"][g][1,t] for g in Data["System"]["SetGens"])
                         + sum(Data["Buses"]["LoadSheddingCost"][i][1]*load_shedding[i,t,1] + Data["Buses"]["OverGenCost"][i][1]*over_generation[i,t,1] for i in Data["System"]["SetBuses"]))
                         for t in Data["System"]["SetTimeBlocks"]))


    # 2.4 Constraints

    # 2.4.1 (Restricción 2.b) Generación máxima y mínima convencional
    for g in Data["System"]["SetGens"]
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
            @constraint(model, Data["FirstStage"]["e"][(g,t)] - Data["FirstStage"]["RD"][(g,t)]  <= thermal_generation[g,t,b] <= Data["FirstStage"]["e"][(g,t)] + Data["FirstStage"]["RU"][(g,t)])
        end
    end

    # 2.4.2 (Restricción 2.c) Rampa hacia arriba
    for g in Data["System"]["SetGens"]
        for t in 1:maximum(Data["System"]["SetTimeBlocks"])-1, b in 1:Data["TimeBlocks"]["Size"][t]
            @constraint(model, thermal_generation[g,t+1] - thermal_generation[g,t,b]  <= minimum([Data["Generators"]["RUP"][g], Data["Generators"]["PMax"][g]]))
        end
    end

    # 2.4.3 (Restricción 2.d) Rampa hacia abajo
    for g in Data["System"]["SetGens"]
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
            @constraint(model, thermal_generation[g,t] - thermal_generation[g,t+1]  <= minimum([Data["Generators"]["RDN"][g], Data["Generators"]["PMax"][g]]))
        end
    end

    # 2.4.4 (Restriccion 2.e) Cumplimiento de la demanda
    for i in Data["System"]["SetBuses"]
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
            @constraint(model, sum(thermal_generation[gen,t,b] for gen in Data["Buses"]["Gens"][i])
                             + sum(variable_generation[gen,t,b] for gen in Data["Buses"]["VariableGens"][i])
                             + sum(hydro_generation[j,t,b] for j in Data["Buses"]["HydroGens"][i])
                             + sum(power_flow[l,t,b] for l in Data["Buses"]["FromLine"][i])
                             - sum(power_flow[l,t,b] for l in Data["Buses"]["ToLine"][i])
                             + load_shedding[i,t,b] + over_generation[i,t,b]
                             ==
                             Data["Buses"]["Demand"][i][b,t]
                             )
        end
    end

    # 2.4.5 (Restricción 2.f, 2.i) Balance de masa en EMBALSES y condición inicial
    for e in Data["System"]["SetHydroNodesSto"]
        for t in Data["System"]["SetTimeBlocks"]
            if t == 1       # Condicion inicial
                @constraint(model,
                  reservoir_level[e,t] == Data["HydroNodes"]["InitialLevel"][e]
                                        + sum( Data["TimeBlocks"]["beta"][b,t]*(Data["HydroNodes"]["Affluent"][e][t]
                                        + reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["ToStreamTurb"][e]    init = 1)
                                        + reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["ToStreamNTurb"][e]   init = 1)
                                        - reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["FromStreamTurb"][e]  init = 1)
                                        - reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["FromStreamNTurb"][e] init = 1))
                                        for b in 1:Data["TimeBlocks"]["Size"][t] ))
            elseif t == maximum(Data["System"]["SetTimeBlocks"])       # Condicion final
                @constraint(model,
                  Data["HydroNodes"]["FinalLevel"][e] == reservoir_level[e,t-1]
                                        + sum( Data["TimeBlocks"]["beta"][b,t]*(Data["HydroNodes"]["Affluent"][e][t]
                                        + reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["ToStreamTurb"][e]    init = 1)
                                        + reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["ToStreamNTurb"][e]   init = 1)
                                        - reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["FromStreamTurb"][e]  init = 1)
                                        - reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["FromStreamNTurb"][e] init = 1))
                                        for b in 1:Data["TimeBlocks"]["Size"][t] ))
            else
                @constraint(model,
                  reservoir_level[e,t] == reservoir_level[e,t-1]
                                        + sum( Data["TimeBlocks"]["beta"][b,t]*(Data["HydroNodes"]["Affluent"][e][t]
                                        + reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["ToStreamTurb"][e]    init = 1)
                                        + reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["ToStreamNTurb"][e]   init = 1)
                                        - reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["FromStreamTurb"][e]  init = 1)
                                        - reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["FromStreamNTurb"][e] init = 1))
                                        for b in 1:Data["TimeBlocks"]["Size"][t] ))
            end
        end
    end

    # 2.4.6 (Restricción 2.g) Balance de masa en nodos de paso
    for n in union(Data["System"]["SetHydroNodeGen"], Data["System"]["SetHydroNodesBoc"])
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
            @constraint(model, Data["HydroNodes"]["Affluent"][n][t]
                             + reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["ToStreamTurb"][n]  init = 0)
                             + reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["ToStreamNTurb"][n] init = 0)
                            == reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["FromStreamTurb"][n]  init = 0)
                             + reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["FromStreamNTurb"][n] init = 0))
        end
    end

    # 2.4.7 (Restricción 2.h) Generación de energía en nodos
    for j in Data["System"]["SetHydroNodeGen"]
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
                @constraint(model, hydro_generation[j,t,b] == Data["HydroNodes"]["Delta"][j]
                                   * (reduce(+, stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"] if pair_stream in Data["HydroNodes"]["FromStreamTurb"][j] init = 0)))
        end
    end

    # 2.4.8 (Restricción 2.j) Niveles mínimos y máximos de embalses
    for n in Data["System"]["SetHydroNodesSto"]
        for t in Data["System"]["SetTimeBlocks"]
            @constraint(model, Data["HydroNodes"]["MinStorage"][n] <= reservoir_level[n,t] <= Data["HydroNodes"]["MaxStorage"][n])
        end
    end

    # 2.4.9 (Restricción 2.k) Caudal turbinable máximo por central
    for n in Data["System"]["SetHydroNodeGen"] #union(Data["System"]["SetHydroNodeGen"], Data["System"]["SetHydroNodesBoc"])
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
                @constraint(model, Data["HydroNodes"]["MinStream"][n]*Data["FirstStage"]["yh"][n]
                                <= reduce(+, stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"] if pair_stream in Data["HydroNodes"]["FromStreamTurb"][n] init = 0)
                                <= Data["HydroNodes"]["MaxStream"][n]*Data["FirstStage"]["yh"][n]
                )
        end
    end

    # 2.4.10 (Restricción 2.l) Flujo DC
    for line in Data["System"]["SetLines"]
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
            @constraint(model, power_flow[line,t,b] == (θ[Data["Lines"]["FromNode"][line],t,b] - θ[Data["Lines"]["ToNode"][line],t,b])*Data["Lines"]["B"][line])
        end
    end

    # 2.4.11 (Restricción 2.m) Flujo máximo
    for line in Data["System"]["SetLines"]
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
            @constraint(model, -Data["Lines"]["MaxFlow"][line] <= power_flow[line,t,b] <= Data["Lines"]["MaxFlow"][line])
        end
    end

    # 2.4.12 (Restricción 2.n) Generación máxima y mínima de la central hidráulica
    for n in Data["System"]["SetHydroNodeGen"]
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
                @constraint(model, Data["HydroNodes"]["Pmin"][n]*Data["FirstStage"]["yh"][n] <= hydro_generation[n,t,b] <= Data["HydroNodes"]["Pmax"][n]*Data["FirstStage"]["yh"][n])
        end
    end

    # 2.4.13 (Restricción 2.o) Generación renovable
    for g in Data["System"]["SetGensVar"]
        for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
            @constraint(model, 0 <= variable_generation[g,t,b] <= Data["Generators"]["PMax"][g]*Data["Generators"]["Fp"][g][b,t])
        end
    end

    #print(model)
    optimize!(model)

    #Guardamos las decisiones
    Solution = Dict();
    Solution["hydro_generation"]    = [JuMP.value.(hydro_generation)];
    Solution["thermal_generation"]  = [JuMP.value.(thermal_generation)];
    Solution["reservoir_level"]     = [JuMP.value.(reservoir_level)];
    Solution["power_flow"]          = [JuMP.value.(power_flow)];
    Solution["stream_turb"]         = [JuMP.value.(stream_turb)];
    Solution["stream_no_turb"]      = [JuMP.value.(stream_no_turb)];
    Solution["variable_generation"] = [JuMP.value.(variable_generation)];
    Solution["over_generation"]     = [JuMP.value.(over_generation)];
    Solution["load_shedding"]       = [JuMP.value.(load_shedding)];
    Solution["objetive_value"]      = JuMP.objective_value(model)

    return Solution
end

function Deterministico(Data)
    # 2.1 Problem definition
    model = Model(Gurobi.Optimizer)
    set_optimizer_attribute(model, "NumericFocus", 3)
    #set_optimizer_attribute(model, "OutputFlag", 1)
    #set_optimizer_attribute(model, "MIPGap", 0.01)

    # 2.2 Variable Definition
    @variable(model,                   gen_state[Data["System"]["SetGens"],                      t in Data["System"]["SetTimeBlocks"]], binary = true);
    @variable(model,                   hydro_state[Data["System"]["SetHydroNodeGen"],            t in Data["System"]["SetTimeBlocks"]], binary = true);
    @variable(model,                   startup[Data["System"]["SetGens"],                        t in Data["System"]["SetTimeBlocks"]], binary = true);
    @variable(model,                   shutdown[Data["System"]["SetGens"],                       t in Data["System"]["SetTimeBlocks"]], binary = true);
    @variable(model,                   expected_generation[Data["System"]["SetGens"],            t in Data["System"]["SetTimeBlocks"]], lower_bound = 0);
    @variable(model,                   up_reserve[Data["System"]["SetGens"],                     t in Data["System"]["SetTimeBlocks"]], lower_bound = 0);
    @variable(model,                   down_reserve[Data["System"]["SetGens"],                   t in Data["System"]["SetTimeBlocks"]], lower_bound = 0);
    @variable(model,                   θ[Data["System"]["SetBuses"],                             t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]]);
    @variable(model,                   power_flow[Data["System"]["SetLines"],                    t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]],                  start = 0);
    @variable(model,                   thermal_generation[Data["System"]["SetGens"],             t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,                   variable_generation[Data["System"]["SetGensVar"],         t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,                   hydro_generation[Data["System"]["SetHydroNodes"],         t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,                   load_shedding[Data["System"]["SetBuses"],                 t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,                   over_generation[Data["System"]["SetBuses"],               t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,                   stream_turb[Data["System"]["SetHydroStreamsTurb"],        t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,                   stream_no_turb[Data["System"]["SetHydroStreamsNTurb"],    t in Data["System"]["SetTimeBlocks"], 1:Data["TimeBlocks"]["Size"][t]], lower_bound = 0, start = 0);
    @variable(model,                   reservoir_level[Data["System"]["SetHydroNodesSto"],       t in Data["System"]["SetTimeBlocks"]],                                  lower_bound = 0, start = 1000);


    # 2.3 Objective Function
    @objective(model, Min, sum( sum(Data["Generators"]["SUP"][g]*startup[g,t] + Data["Generators"]["SDN"][g]*shutdown[g,t] + Data["Generators"]["NoLoadCost"][g] * gen_state[g,t]
                                  + Data["Generators"]["UpReserveCost"][g] * up_reserve[g,t] + Data["Generators"]["DownReserveCost"][g] * down_reserve[g,t]
                                    for t in Data["System"]["SetTimeBlocks"]) for g in Data["System"]["SetGens"]) +
                                    sum(
                                       (sum(thermal_generation[g,t,1]*Data["Generators"]["VariableCost"][g][1,t] for g in Data["System"]["SetGens"])
                                       + sum(Data["Buses"]["LoadSheddingCost"][i][1]*load_shedding[i,t,1] + Data["Buses"]["OverGenCost"][i][1]*over_generation[i,t,1] for i in Data["System"]["SetBuses"]))
                                       for t in Data["System"]["SetTimeBlocks"])
             )

     # 2.4.1 (Restricción 2.b) Generación máxima y mínima convencional
     for g in Data["System"]["SetGens"]
         for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
             @constraint(model, expected_generation[g,t] - down_reserve[g,t]  <= thermal_generation[g,t,b])
             @constraint(model, thermal_generation[g,t,b] <= expected_generation[g,t]+ up_reserve[g,t])
         end
     end

     # 2.4.2 (Restricción 2.c) Rampa hacia arriba
     for g in Data["System"]["SetGens"]
         for t=1:maximum(Data["System"]["SetTimeBlocks"])-1, b in 1:Data["TimeBlocks"]["Size"][t]
             @constraint(model, thermal_generation[g,t+1,b] - thermal_generation[g,t,b]  <= minimum([Data["Generators"]["RUP"][g], Data["Generators"]["PMax"][g]]))
         end
     end

     # 2.4.3 (Restricción 2.d) Rampa hacia abajo
     for g in Data["System"]["SetGens"]
         for t=1:maximum(Data["System"]["SetTimeBlocks"])-1, b in 1:Data["TimeBlocks"]["Size"][t]
             @constraint(model, thermal_generation[g,t,b] - thermal_generation[g,t+1,b]  <= minimum([Data["Generators"]["RDN"][g], Data["Generators"]["PMax"][g]]))
         end
     end

     # 2.4.4 (Restriccion 2.e) Cumplimiento de la demanda
     for i in Data["System"]["SetBuses"]
         for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
             @constraint(model, sum(thermal_generation[gen,t,b] for gen in Data["Buses"]["Gens"][i])
                              + sum(variable_generation[gen,t,b] for gen in Data["Buses"]["VariableGens"][i])
                              + sum(hydro_generation[j,t,b] for j in Data["Buses"]["HydroGens"][i])
                              + sum(power_flow[l,t,b] for l in Data["Buses"]["FromLine"][i])
                              - sum(power_flow[l,t,b] for l in Data["Buses"]["ToLine"][i])
                              + load_shedding[i,t,b] + over_generation[i,t,b]
                              ==
                              Data["Buses"]["Demand"][i][b,t]
                              )
         end
     end

     # 2.4.5 (Restricción 2.f, 2.i) Balance de masa en EMBALSES y condición inicial y final
     for e in Data["System"]["SetHydroNodesSto"]
        for t in Data["System"]["SetTimeBlocks"]
            if t == 1       # Condicion inicial
                @constraint(model,
                  reservoir_level[e,t] == Data["HydroNodes"]["InitialLevel"][e]
                                        + sum( Data["TimeBlocks"]["beta"][b,t]*(Data["HydroNodes"]["Affluent"][e][t]
                                        + reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["ToStreamTurb"][e]    init = 1)
                                        + reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["ToStreamNTurb"][e]   init = 1)
                                        - reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["FromStreamTurb"][e]  init = 1)
                                        - reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["FromStreamNTurb"][e] init = 1))
                                        for b in 1:Data["TimeBlocks"]["Size"][t] ))
            else
                @constraint(model,
                  reservoir_level[e,t] == reservoir_level[e,t-1]
                                        + sum( Data["TimeBlocks"]["beta"][b,t]*(Data["HydroNodes"]["Affluent"][e][t]
                                        + reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["ToStreamTurb"][e]    init = 1)
                                        + reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["ToStreamNTurb"][e]   init = 1)
                                        - reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["FromStreamTurb"][e]  init = 1)
                                        - reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["FromStreamNTurb"][e] init = 1))
                                        for b in 1:Data["TimeBlocks"]["Size"][t] ))
            end
            if t == maximum(Data["System"]["SetTimeBlocks"])       # Condicion final
                 @constraint(model,
                   Data["HydroNodes"]["FinalLevel"][e] == reservoir_level[e,t])
            end
        end
    end

     # 2.4.6 (Restricción 2.g) Balance de masa en nodos de paso
     for n in union(Data["System"]["SetHydroNodeGen"], Data["System"]["SetHydroNodesBoc"])
         for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
             @constraint(model, Data["HydroNodes"]["Affluent"][n][t]
                              + reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["ToStreamTurb"][n]  init = 0)
                              + reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["ToStreamNTurb"][n] init = 0)
                             == reduce(+,     stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"]  if pair_stream in Data["HydroNodes"]["FromStreamTurb"][n]  init = 0)
                              + reduce(+,  stream_no_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsNTurb"] if pair_stream in Data["HydroNodes"]["FromStreamNTurb"][n] init = 0))
         end
     end

     # 2.4.7 (Restricción 2.h) Generación de energía en nodos
     for j in Data["System"]["SetHydroNodeGen"]
         for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
                 @constraint(model, hydro_generation[j,t,b] == Data["HydroNodes"]["Delta"][j]
                                    * (reduce(+, stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"] if pair_stream in Data["HydroNodes"]["FromStreamTurb"][j] init = 0)))
         end
     end

     # 2.4.8 (Restricción 2.j) Niveles mínimos y máximos de embalses
     for n in Data["System"]["SetHydroNodesSto"]
         for t in Data["System"]["SetTimeBlocks"]
             @constraint(model, Data["HydroNodes"]["MinStorage"][n] <= reservoir_level[n,t] <= Data["HydroNodes"]["MaxStorage"][n])
         end
     end

     # 2.4.9 (Restricción 2.k) Caudal turbinable máximo por central
     for n in Data["System"]["SetHydroNodeGen"] #union(Data["System"]["SetHydroNodeGen"], Data["System"]["SetHydroNodesBoc"])
         for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
                 @constraint(model, Data["HydroNodes"]["MinStream"][n]*hydro_state[n,t]
                                 <= reduce(+, stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"] if pair_stream in Data["HydroNodes"]["FromStreamTurb"][n] init = 0)                 )
                 @constraint(model, reduce(+, stream_turb[pair_stream,t,b] for pair_stream in Data["System"]["SetHydroStreamsTurb"] if pair_stream in Data["HydroNodes"]["FromStreamTurb"][n] init = 0)
                                 <= Data["HydroNodes"]["MaxStream"][n]*hydro_state[n,t])
         end
     end

     # 2.4.10 (Restricción 2.l) Flujo DC
     for line in Data["System"]["SetLines"]
         for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
             @constraint(model, power_flow[line,t,b] == (θ[Data["Lines"]["FromNode"][line],t,b] - θ[Data["Lines"]["ToNode"][line],t,b])*Data["Lines"]["B"][line])
         end
     end

     # 2.4.11 (Restricción 2.m) Flujo máximo
     for line in Data["System"]["SetLines"]
         for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
             @constraint(model, -Data["Lines"]["MaxFlow"][line] <= power_flow[line,t,b] <= Data["Lines"]["MaxFlow"][line])
         end
     end

     # 2.4.12 (Restricción 2.n) Generación máxima y mínima de la central hidráulica
     for n in Data["System"]["SetHydroNodeGen"]
         for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
                 @constraint(model, Data["HydroNodes"]["Pmin"][n]*hydro_state[n,t] <= hydro_generation[n,t,b])
                 @constraint(model, hydro_generation[n,t,b] <= Data["HydroNodes"]["Pmax"][n]*hydro_state[n,t])
         end
     end

     # 2.4.13 (Restricción 2.o) Generación renovable
     for g in Data["System"]["SetGensVar"]
         for t in Data["System"]["SetTimeBlocks"], b in 1:Data["TimeBlocks"]["Size"][t]
             @constraint(model, variable_generation[g,t,b] <= Data["Generators"]["PMax"][g]*Data["Generators"]["Fp"][g][b,t])
         end
     end

     # 2.4.1 (Restricción 1.b)
     for g in Data["System"]["SetGens"]
         for t =2:maximum(Data["System"]["SetTimeBlocks"])
             @constraint(model, gen_state[g,t-1] - gen_state[g,t] + startup[g,t]  >= 0)
         end
         @constraint(model, Data["Generators"]["InitialState"][g] - gen_state[g,1] + startup[g,1]  >= 0)
     end

     # 2.4.2 (Restricción 1.c)
     for g in Data["System"]["SetGens"]
         for t =2:maximum(Data["System"]["SetTimeBlocks"])
             @constraint(model, shutdown[g,t] == gen_state[g,t-1] - gen_state[g,t] + startup[g,t] )
         end
         @constraint(model, shutdown[g,1] == Data["Generators"]["InitialState"][g] - gen_state[g,1] + startup[g,1])
     end

     # 2.4.3 (Restricción 1.d)
     for g in Data["System"]["SetGens"]
         for t =2:(maximum(Data["System"]["SetTimeBlocks"])-1)
             for tau=t+1:minimum([t+Data["Generators"]["MinUpTime"][g]-1, maximum(Data["System"]["SetTimeBlocks"])])
                 @constraint(model, gen_state[g,t] - gen_state[g,t-1] <= gen_state[g,tau])
             end
         end
         @constraint(model, gen_state[g,1] - Data["Generators"]["InitialState"][g] <= gen_state[g,Data["Generators"]["MinUpTime"][g]])
     end

     # 2.4.4 (Restricción 1.e)
     for g in Data["System"]["SetGens"]
         for t =2:(maximum(Data["System"]["SetTimeBlocks"])-1)
             for tau=t+1:minimum([t+Data["Generators"]["MinDnTime"][g]-1, maximum(Data["System"]["SetTimeBlocks"])])
                 @constraint(model, gen_state[g,t-1] - gen_state[g,t] <= 1-gen_state[g,tau])
             end
         end
         @constraint(model, Data["Generators"]["InitialState"][g] - gen_state[g,1] <= 1-gen_state[g,Data["Generators"]["MinDnTime"][g]])
     end

     # 2.4.5 (Restricción 1.f)
     for g in Data["System"]["SetGens"]
         for t =1:(maximum(Data["System"]["SetTimeBlocks"]))
             @constraint(model, expected_generation[g,t] + up_reserve[g,t] <= Data["Generators"]["PMax"][g]*gen_state[g,t])
         end
     end

     # 2.4.4 (Restricción 1.g)
     for g in Data["System"]["SetGens"]
         for t =1:(maximum(Data["System"]["SetTimeBlocks"]))
             @constraint(model, expected_generation[g,t] - down_reserve[g,t] >= Data["Generators"]["PMin"][g]*gen_state[g,t])
         end
     end


     #print(model)
     optimize!(model)

     #Guardamos las decisiones
     Solution = Dict();
     Solution["hydro_generation"]    = [JuMP.value.(hydro_generation)];
     Solution["thermal_generation"]  = [JuMP.value.(thermal_generation)];
     Solution["reservoir_level"]     = [JuMP.value.(reservoir_level)];
     Solution["power_flow"]          = [JuMP.value.(power_flow)];
     Solution["stream_turb"]         = [JuMP.value.(stream_turb)];
     Solution["stream_no_turb"]      = [JuMP.value.(stream_no_turb)];
     Solution["variable_generation"] = [JuMP.value.(variable_generation)];
     Solution["over_generation"]     = [JuMP.value.(over_generation)];
     Solution["load_shedding"]       = [JuMP.value.(load_shedding)];
     Solution["objetive_value"]      = JuMP.objective_value(model)


     return Solution
end

sol = Deterministico(Data)

## Plot de resultados

etapas  = maximum(Data["System"]["SetTimeBlocks"])
print("Nivel de embalses:\n")
print([sol["reservoir_level"][1][1,i] for i =1:etapas])
print("\n")

print("Generación Hídrica:\n")
for j in Data["System"].set_hydro_nodes_gen
    print("$(j) -> $(sol["hydro_generation"][1][j,1,1]) ")
end
print("\n")

print("Generación Térmica:\n")
for g in Data["System"].set_gens
    print("$(g) -> $(sol["thermal_generation"][1][g,1,1]) ")
end
print("\n")

print("Generación Variable:\n")
for g in Data["System"].set_gens_var
    print("$(g) -> $(sol["variable_generation"][1][g,1,1]) ")
end
print("\n")

print("Load Shedding:\n")
for x in Data["System"].set_buses
    print("$(x) -> $(sol["load_shedding"][1][x,1,1])  ")
end
print("\n")

print("Caudal Turbinable:\n")
for x in Data["System"]["SetHydroStreamsTurb"]
    print("$(x) -> $(sol["stream_turb"][1][x,1,1])  ")
end
print("\n")


print("Caudal NO Turbinable:\n")
for x in Data["System"]["SetHydroStreamsNTurb"]
    print("$(x) -> $(sol["stream_no_turb"][1][x,1,1])  ")
end

print("\n")

writedlm("GeneraciónHídrica.csv",  [[x,t,b,sol["hydro_generation"][1][x,t,b]]    for t in Data["System"]["SetTimeBlocks"] for x in Data["System"]["SetHydroNodeGen"]      for b=1:Data["TimeBlocks"]["Size"][t]], ',')
writedlm("GeneraciónTérmica.csv",  [[x,t,b,sol["thermal_generation"][1][x,t,b]]  for t in Data["System"]["SetTimeBlocks"] for x in Data["System"]["SetGens"]              for b=1:Data["TimeBlocks"]["Size"][t]], ',')

# Reservoir level plot
plot(LinRange(1,etapas,etapas),[sol["reservoir_level"][1][1,i] for i=1:etapas]/1e6,
xlabel="Stages", ylabel="Reservoir level [Mm3]", label="Colbún", lw=2,margin=12Plots.mm)
#plot!(LinRange(1,etapas,etapas),[sol["reservoir_level"][1][3,i] for i=1:etapas]/1e6, label="Machicura",lw=2)
p=twinx()
plot!(p,[Data["HydroNodes"]["Affluent"][1][i] for i=1:etapas], label="Colbún", line=:dash,
ylabel="Monthly Mean Inflow [m3/s]", legend=:topleft,background_color_legend = nothing)
savefig("Data\\Plots\\nivelEmbalses.png")

# Generation plot
hydroGen,carbonGen,dieselGen,gasGen,variableGen,xlabel = [],[],[],[],[],[]
for t=1:maximum(Data["System"]["SetTimeBlocks"])
    for b in 1:Data["TimeBlocks"]["Size"][t]
        append!(hydroGen, reduce(+,sol["hydro_generation"][1][gen,t,b] for gen in Data["System"]["SetHydroNodeGen"]))
        append!(carbonGen, reduce(+,sol["thermal_generation"][1][gen,t,b] for gen in Data["System"]["SetGens"] if Data["Generators"]["Type"][gen] == "Carbon")) #Carbon
        append!(dieselGen, reduce(+,sol["thermal_generation"][1][gen,t,b] for gen in Data["System"]["SetGens"] if Data["Generators"]["Type"][gen] == "Diesel"))
        append!(gasGen, reduce(+,sol["thermal_generation"][1][gen,t,b] for gen in Data["System"]["SetGens"] if Data["Generators"]["Type"][gen] == "Gas"))
        append!(variableGen, reduce(+,sol["variable_generation"][1][gen,t,b] for gen in Data["System"]["SetGensVar"]))
        push!(xlabel, string("$t"))
    end
end

genType = ["Hydro" "Carbon" "Diesel" "Gas" "Variable"]
# df = DataFrame(StagesBlocks=xLabel, Hydro=hydroGen, Thermal=thermalGen, Variable=variableGen)

areaplot(1:size(xlabel)[1], [hydroGen carbonGen dieselGen gasGen variableGen], #[hydroGen carbonGen dieselGen gasGen variableGen],
    xticks=(1:size(xlabel)[1],xlabel), label=genType,xlabel="Stage",
    seriescolor=[:dodgerblue :gray :red :black :gold], fillalpha=0.6,
    ylabel="Generation [MW]", legend=:topright, size=(1200,600),margin=8Plots.mm)
##plot!(p,[sum(Data["Buses"]["Demand"][i][(b,t)] for i in Data["System"]["SetBuses"]) for t in Data["System"]["SetTimeBlocks"] for b=1:Data["TimeBlocks"]["Size"][t]], label="Demanda", line=:dash,
#    ylabel="Demanda total", legend=:topleft,background_color_legend = nothing)
savefig("Data\\Plots\\genMatrix.png")
