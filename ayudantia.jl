cd("C:/Users/Guillermo/OneDrive - uc.cl/Material Universidad/Ramos/2020-II/Optimizacion-Avanzada/Proyecto");

using JuMP, Gurobi, Random

## Modularizacion del problema ##
struct ProblemData
    A::Array{Float64,2}
    b::Array{Float64,1}
    c::Array{Float64,1}
end

struct ProblemDefinition
    data::ProblemData
    x::Vector{VariableRef}
    m::Model
end

function test_data()
    A= [[2. 1.];[1. 2.];[3. 1.]];
    b= [2. ; 2. ; 2.];
    c= [1. ; 1.];

    return ProblemData(A,b,c)
end

function BuildProblem(d::ProblemData, m::Model)
    x = @variable(m, )
    @constraint(m, )
    @constraint(m, )

    return ProblemDefinition(d,x,n);
end

function OptimizeProblem(sp::ProblemDefinition)
    @objective()
end

data = test_data();

## guardar datos ##

path = "C:/Users/Guillermo/OneDrive - uc.cl/Material Universidad/Ramos/2020-II/Optimizacion-Avanzada/Proyecto"

save(path * "data_test.jld", "data",data); #crear path

loaded_data = load(path * "data_test.jld", "data"); #cargar datos

loaded_data.A; #recuperar variable


## generar matriz de datos aleatorios ##

filas = 5; columnas = 2;

Random.seed!(1234);

matriz_rdm = rand(0:0.01:1, filas, columnas); #entre 0-1

##

#generate scenarios
filas = 1; scenarios = 24;
Random.seed!(1234);
matriz_rdm_1 = rand(-10:0.01:10, filas, scenarios); #gaussian noise

mhu = 10; sigma = 5;

d = Normal(mhu, sigma); td = truncated(d, 0.0, Inf);



##
Case14 = XLSX.readxlsx("Case14bus.xlsx");
Renewables = Case14["Renewables"];

Wind_Set = Array{Int64,1}(undef,2)

Wind_Available = [Renewables["B3:Y3"],Renewables["B4:Y4"]];
xi = Array{Array{Float64,1},1}(undef,maximum(Wind_Set))

for i=1:maximum(Wind_Set)
    xi[i] = Float64[]
end

for i = 1:maximum(Wind_Set)
    for j =1:maximum(1:24)
        xi[i] = vcat(xi[i],Renewables[i][j])
    end
end


filename = "WindProfile.xlsx"

columns = Vector()

for i in 1:24
    push!(columns, xi[1,i]);
end

labels = [ "1", "2","3","4","5","6", "7", "8","9","10","11","12", "13", "14","15","16","17","18", "19", "20","21","22","23","24"];

#labels = [ "Wind Generator","1", "2","3","4","5","6","7","8","9","10","11","12","13","14","15","16","17","18","19","20","21","22","23","24"]

XLSX.openxlsx(filename, mode="w") do xf
    sheet = xf[1]
    XLSX.writetable!(sheet, columns, labels, anchor_cell=XLSX.CellRef("B2"))
end




for t in 1:24

reservas = 0;

for i in 1:3
   reservas = reservas + getvalue(r[i,t]) +getvalue(w[i,t]);
       end
print(reservas,",");

end

for t in 1:24
    p = 0;
    for i in 1:3
       p = p + getvalue(Pg[i,t]) ;
    end
    print(p,",");
end


for t in 1:24
    w = 0;
    for i in 1:2
       w = w + getvalue(w[i,t]) ;
    end
    print(w,",");
end


##########33

for t in 1:24
    rs = 0;
    for i in 1:3
       rs = rs + getvalue(r[i,t,2]) ;
    end
    print(rs,",");
end

println("Eolica");
for t in 1:24
    eolic = 0;
    for i in 1:2
       eolic = eolic + getvalue(w[i,t,2]) ;
    end
    print(eolic,",");
end
