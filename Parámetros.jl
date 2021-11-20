using JuMP, MathProgBase
using CSV, DataFrames
import MathOptInterface

clearconsole()

## 1.0 Constants
BaseMVA = 100;
M       = 10000;

## 1.1 Path


FILE_BASE                = "G:/Unidades compartidas/Optimización avanzada en Ingeniería Eléctrica/Proyecto"

FILE_MODEL               = "\\Data"

FILE_BUSES               = "\\PARAM_BUSES.csv"
FILE_GENERATORS          = "\\PARAM_GENERATORS.csv"
FILE_LINES               = "\\PARAM_LINES.csv"
FILE_DEMAND              = "\\PARAM_DEMAND.csv"
FILE_SYSTEM              = "\\PARAM_SYSTEM.csv"
FILE_HYDRO_NODES         = "\\PARAM_HYDRO_NODES.csv"
FILE_HYDRO_STREAMS       = "\\PARAM_HYDRO_STREAMS.csv"
FILE_BLOCKS              = "\\PARAM_BLOCKS.csv"
FILE_ALPHA               = "\\PARAM_AFFLUENT.csv"
FILE_BETA                = "\\PARAM_BLOCK_SIZE.csv"
FILE_CVAR                = "\\PARAM_CVAR.csv"
FILE_FPLANTA             = "\\PARAM_CHI_GENVAR.csv"
FILE_BUSES_OV_LS         = "\\PARAM_BUSES_OG_LS.csv"

# 1.2 DataFrames
DATA_BUSES               = CSV.File(FILE_BASE*FILE_MODEL*FILE_BUSES);
DATA_BUSES_OV_LS         = CSV.File(FILE_BASE*FILE_MODEL*FILE_BUSES_OV_LS);
DATA_LINES               = CSV.File(FILE_BASE*FILE_MODEL*FILE_LINES);
DATA_GENERATORS          = CSV.File(FILE_BASE*FILE_MODEL*FILE_GENERATORS);
DATA_DEMAND              = CSV.File(FILE_BASE*FILE_MODEL*FILE_DEMAND);
DATA_SYSTEM              = CSV.File(FILE_BASE*FILE_MODEL*FILE_SYSTEM);
DATA_HYDRO_NODES         = CSV.File(FILE_BASE*FILE_MODEL*FILE_HYDRO_NODES);
DATA_HYDRO_STREAMS       = CSV.File(FILE_BASE*FILE_MODEL*FILE_HYDRO_STREAMS);
DATA_BLOCKS              = CSV.File(FILE_BASE*FILE_MODEL*FILE_BLOCKS);
DATA_ALPHA               = CSV.File(FILE_BASE*FILE_MODEL*FILE_ALPHA);
DATA_BETA                = CSV.File(FILE_BASE*FILE_MODEL*FILE_BETA);
DATA_CVAR                = CSV.File(FILE_BASE*FILE_MODEL*FILE_CVAR);
DATA_FPLANTA             = CSV.File(FILE_BASE*FILE_MODEL*FILE_FPLANTA);

## 1.3 Dictionaries
Data = Dict();
Data["Buses"]           = Dict()
Data["Lines"]           = Dict()
Data["Generators"]      = Dict()
Data["HydroNodes"]      = Dict()
Data["HydroStreamsT"]   = Dict()
Data["HydroStreamsNT"]  = Dict()
Data["TimeBlocks"]      = Dict()
Data["System"]          = Dict()

## 1.3.1  bus                                   #b_id::Int            # ID de la barra
Data["Buses"]["Name"]                  = Dict() #b_name::String       # Nombre de la barra
Data["Buses"]["FromLine"]              = Dict() #b_flines             # lista de lineas que tienen el nodo como from
Data["Buses"]["ToLine"]                = Dict() #b_tlines             # lista de lineas que tienen el nodo como to
Data["Buses"]["Gens"]                  = Dict() #b_gens               # lista de generadores ubicados en el nodo
Data["Buses"]["Neighbor"]              = Dict() #b_neighbor           # lista de nodos vecinos
Data["Buses"]["Demand"]                = Dict() #b_demand             # demanda de la barra
Data["Buses"]["HydroGens"]             = Dict() #b_hydro_gens         # lista de ID de nodos hidricos de generadores conectados
Data["Buses"]["OverGenCost"]           = Dict() #b_c_sobregeneracion  # Costo de la barra por bloque de sobregeneracion
Data["Buses"]["LoadSheddingCost"]      = Dict() #b_c_load_shedding    # Costo de la barra por bloque de load shedding
Data["Buses"]["VariableGens"]          = Dict() #b_var_gens           # lista de generadores variables ubicados en el nodo

## 1.3.2  lines                                 #l_id::Int            # ID de la línea
Data["Lines"]["Name"]                  = Dict() #l_name::String       # Nombre de la línea
Data["Lines"]["FromNode"]              = Dict() #l_fnode::Int         # Nodo de destino
Data["Lines"]["ToNode"]                = Dict() #l_tnode::Int         # Nodo de procedencia
Data["Lines"]["MaxFlow"]               = Dict() #l_maxflow::Real      # Flujo máximo por la linea
Data["Lines"]["Reactance"]             = Dict() #l_reactance::Real    # Reactancia de la línea
Data["Lines"]["Resistance"]            = Dict() #l_resistance::Real   # Resistencia de la línea
Data["Lines"]["PairBuses"]             = Dict() #l_pairb              # tupla de nodos (from,to)
Data["Lines"]["G"]                     = Dict() #l_G
Data["Lines"]["B"]                     = Dict() #l_B

## 1.3.3  generators                            #g_id::Int            # ID del generador
Data["Generators"]["Name"]             = Dict() #g_name::String       # Nombre del generador
Data["Generators"]["Bus"]              = Dict() #g_bus::Int           # Bus ID de procedencia
Data["Generators"]["PMax"]             = Dict() #g_pmax::Real         # Potencia Máxima
Data["Generators"]["PMin"]             = Dict() #g_pmin::Real         # Potencia Mínima
Data["Generators"]["Rmax"]             = Dict() #g_rmax::Real         # Reserva hacia arriba
Data["Generators"]["Rmin"]             = Dict() #g_rmin::Real         # Reserva hacia abajo
Data["Generators"]["VariableCost"]     = Dict() #g_cvariable          # Costo variable
Data["Generators"]["Type"]             = Dict() #g_type::String       # Tipo del generador
Data["Generators"]["Agent"]            = Dict() #g_agent::Int         # ID del agente que pertence
Data["Generators"]["Operation"]        = Dict() #g_operation::Int     # binaria de operación
Data["Generators"]["Variable"]         = Dict() #g_var::Bool          # Si es de tipo renovable variable
Data["Generators"]["Fp"]               = Dict() #g_fplanta            # Factor de planta para gen variable, 1 en otro caso
Data["Generators"]["RUP"]              = Dict()                       # Rampa hacia arriba del generador
Data["Generators"]["RDN"]              = Dict()                       # Rampa hacia abajo del generador
Data["Generators"]["SUP"]              = Dict()                       # Costo de encendido del generador
Data["Generators"]["SDN"]              = Dict()                       # Costo de apagado del generador
Data["Generators"]["InitialState"]     = Dict()                       # Costo de apagado del generador
Data["Generators"]["NoLoadCost"]       = Dict()                       # Costo de no tener carga en el generador
Data["Generators"]["UpReserveCost"]    = Dict()                       # Costo de no tener carga en el generador
Data["Generators"]["DownReserveCost"]  = Dict()                       # Costo de no tener carga en el generador
Data["Generators"]["MinUpTime"]        = Dict()                       # Tiempo mínimo de encendido del generador
Data["Generators"]["MinDnTime"]        = Dict()                       # Tiempo mínimo de encendido del generador

## 1.3.4    hydro_nodes                         #hn_id::Int            # ID del nodo hidrico
Data["HydroNodes"]["Name"]             = Dict() #hn_name::String       # Nombre del caudal
Data["HydroNodes"]["Type"]             = Dict() #hn_type::String       # Tipo de nodo hidrico (almacenamiento, bocatoma o generación hidro y riego)
Data["HydroNodes"]["Bus"]              = Dict() #hn_bus::Int           # Barra de conexión del sistema eléctrico
Data["HydroNodes"]["Terminal"]         = Dict() #hn_terminal::String   # Define el nodo como terminal o no
Data["HydroNodes"]["Delta"]            = Dict() #hn_delta              # Conversion de generacion nodo hidro
Data["HydroNodes"]["InitialLevel"]     = Dict() #hn_start_level        # Condición Inicial
Data["HydroNodes"]["FinalLevel"]       = Dict()                        # Nivel final requerido en el embalse
Data["HydroNodes"]["Pmax"]             = Dict() #hn_pmax               # Potencia Máxima
Data["HydroNodes"]["Pmin"]             = Dict() #hn_pmin               # Potencia Máxima
Data["HydroNodes"]["Affluent"]         = Dict() #hn_affluent           # Afluente del nodo hidro
Data["HydroNodes"]["MinStorage"]       = Dict() #hn_min_storage        # Nivel mínimo del embalse (si corresponde)
Data["HydroNodes"]["MaxStorage"]       = Dict() #hn_max_storage        # Nivel máximo del embalse (si corresponde)
Data["HydroNodes"]["MaxStream"]        = Dict() #hn_min_stream         # Mínimo caudal turbinable
Data["HydroNodes"]["MinStream"]        = Dict() #hn_max_stream         # Máximo caudal turbinable
Data["HydroNodes"]["FromStreamTurb"]   = Dict() #hn_fstream_turb       # Set de nodos al cual se les entrega agua turbinable
Data["HydroNodes"]["ToStreamTurb"]     = Dict() #hn_tstream_turb       # Set de nodos al cual de donde ingresa agua turbinable
Data["HydroNodes"]["FromStreamNTurb"]  = Dict() #hn_fstream_nturb      # Set de nodos al cual se les entrega agua no turbinable
Data["HydroNodes"]["ToStreamNTurb"]    = Dict() #hn_tstream_nturb      # Set de nodos al cual de donde ingresa agua no turbinable
Data["HydroNodes"]["Demand"]           = Dict() #hn_demand             # Demanda del nodo hidro

## 1.3.5    hydro_streams                       #hs_id::Int            # ID del canal
Data["HydroStreamsT"]["Name"]            = Dict() #hs_name::String       # Nombre del canal
Data["HydroStreamsT"]["Type"]            = Dict() #hs_type::String       # Tipo del canal
Data["HydroStreamsT"]["MaxStream"]       = Dict() #hs_stream_max         # Limite maximo del caudal del canal
Data["HydroStreamsT"]["MinStream"]       = Dict() #hs_stream_min         # Limite minimo del caudal del canal
Data["HydroStreamsT"]["PairHydroNodes"]  = Dict() #hs_pair_hn            # tupla de nodos hidro (from,to)
Data["HydroStreamsT"]["FromHydroNode"]   = Dict() #hs_fhnode::Int        # Nodo hidro de destino
Data["HydroStreamsT"]["ToHydroNode"]     = Dict() #hs_thnode::Int        # Nodo hidro de procedencia
Data["HydroStreamsNT"]["Name"]           = Dict() #hs_name::String       # Nombre del canal
Data["HydroStreamsNT"]["Type"]           = Dict() #hs_type::String       # Tipo del canal
Data["HydroStreamsNT"]["MaxStream"]      = Dict() #hs_stream_max         # Limite maximo del caudal del canal
Data["HydroStreamsNT"]["MinStream"]      = Dict() #hs_stream_min         # Limite minimo del caudal del canal
Data["HydroStreamsNT"]["PairHydroNodes"] = Dict() #hs_pair_hn            # tupla de nodos hidro (from,to)
Data["HydroStreamsNT"]["FromHydroNode"]  = Dict() #hs_fhnode::Int        # Nodo hidro de destino
Data["HydroStreamsNT"]["ToHydroNode"]    = Dict() #hs_thnode::Int        # Nodo hidro de procedencia

## 1.3.6    system
Data["System"]["Name"]                 = [] #sys_name::String     # Nombre del sistema
Data["System"]["ConvCoef"]             = [] #sys_conv_coef::Real  # Factor de conversion de m3/s a m3/etapa (fijo de momento).
Data["System"]["SetBuses"]             = [] #set_buses            # Set de barras ID
Data["System"]["SetDemandBuses"]       = []                       # Set de barras ID con demanda
Data["System"]["SetLines"]             = [] #set_lines            # Set de lineas (tupla de nodos ID)
Data["System"]["SetGens"]              = [] #set_gens             # Set de generadores ID
Data["System"]["SetGensVar"]           = [] #set_gens_var         # Set de generadores variables ID
Data["System"]["SetHydroNodes"]        = [] #set_hydro_nodes      # Set de nodos hidricos ID
Data["System"]["SetHydroStreams"]      = []                       # Set de caudales hidricos
Data["System"]["SetHydroNodesLeaf"]    = [] #set_hydro_nodes_leaf # Set de nodos hidricos terminales ID
Data["System"]["SetHydroStreamsTurb"]  = [] #set_hydro_stream_t   # Set de caudales turbinables
Data["System"]["SetHydroStreamsNTurb"] = [] #set_hydro_stream_nt  # Set de caudales no turbinables
Data["System"]["SetHydroNodeGen"]      = [] #set_hydro_nodes_gen  # Set de nodos hidricos de generación
Data["System"]["SetHydroNodesSto"]     = [] #set_hydro_nodes_sto  # Set de nodos hidricos de embalse
Data["System"]["SetHydroNodesBoc"]     = [] #set_hydro_nodes_boc  # Set de nodos hidricos de bocatoma
Data["System"]["SetTimeHorizon"]       = [] #set_time_horizon     # Horizonte temporal del modelo (número de etapas)
Data["System"]["SetTimeBlocks"]        = [] #bt_stage::Int        # Número de etapa

## 1.3.7    block_time                          #bt_stage::Int    # Número de etapa
Data["TimeBlocks"]["Size"]             = Dict() #bt_size::Int     # Cantidad de bloques de la etapa t
Data["TimeBlocks"]["beta"]             = Dict() #bt_beta          # Tamaño del bloque de la etapa

## 1.3.8    First Stage Solutions
Data["FirstStage"]                     = Dict()
Data["FirstStage"]["e"]                = Dict()
Data["FirstStage"]["rU"]               = Dict()
Data["FirstStage"]["rD"]               = Dict()
Data["FirstStage"]["y"]                = Dict()
Data["FirstStage"]["yh"]               = Dict()

## 1.4.1 Procedures for buses, lines, generators and blocks
for row in DATA_BUSES
    append!(Data["System"]["SetBuses"], row.bus_id);
    Data["Buses"]["Name"][row.bus_id] = row.bus_name;
end

for row in DATA_LINES
    #append!(Data["System"]["SetLines"], row.line_id);

    bus_from_index = 0; bus_to_index = 0;
    for bus in Data["System"]["SetBuses"]
        bus_from_index = (row.line_from_bus == Data["Buses"]["Name"][bus] ? bus : bus_from_index);
        bus_to_index   = (row.line_to_bus   == Data["Buses"]["Name"][bus] ? bus : bus_to_index);
    end
    line_pair = (bus_from_index,bus_to_index)
    append!(Data["System"]["SetLines"], [(bus_from_index,bus_to_index)])

    Data["Lines"]["PairBuses"][line_pair]  = (bus_from_index,bus_to_index);
    Data["Lines"]["Name"][line_pair]       = row.line_name;
    Data["Lines"]["FromNode"][line_pair]   = bus_from_index;
    Data["Lines"]["ToNode"][line_pair]     = bus_to_index;
    Data["Lines"]["MaxFlow"][line_pair]    = row.line_flow_capacity;
    Data["Lines"]["Reactance"][line_pair]  = row.line_reactance;
    Data["Lines"]["Resistance"][line_pair] = row.line_resistance;
    Data["Lines"]["G"][line_pair]          = round(row.line_resistance/(row.line_resistance^2 + row.line_reactance^2), digits = 3);
    Data["Lines"]["B"][line_pair]          = round(-row.line_reactance/(row.line_resistance^2 + row.line_reactance^2), digits = 3);
end

for row in DATA_GENERATORS
    if row.gen_var == 0
        append!(Data["System"]["SetGens"], row.gen_id);
    else
        append!(Data["System"]["SetGensVar"], row.gen_id);
    end

    bus_index = 0;
    for bus in Data["System"]["SetBuses"]
        bus_index = (row.gen_bus ==  Data["Buses"]["Name"][bus] ? bus : bus_index);
    end

    Data["Generators"]["Name"][row.gen_id]              = row.gen_name;
    Data["Generators"]["Bus"][row.gen_id]               = bus_index;
    Data["Generators"]["PMax"][row.gen_id]              = row.gen_p_max;
    Data["Generators"]["PMin"][row.gen_id]              = row.gen_p_min;
    Data["Generators"]["Rmax"][row.gen_id]              = row.gen_r_max;
    Data["Generators"]["Rmin"][row.gen_id]              = row.gen_r_min;
    Data["Generators"]["Type"][row.gen_id]              = row.gen_technology;
    Data["Generators"]["Agent"][row.gen_id]             = row.gen_agent;
    Data["Generators"]["Operation"][row.gen_id]         = row.gen_operation_bin;
    Data["Generators"]["Variable"][row.gen_id]          = row.gen_var;
    Data["Generators"]["RUP"][row.gen_id]               = row.RUP;
    Data["Generators"]["RDN"][row.gen_id]               = row.RDN;
    Data["Generators"]["SUP"][row.gen_id]               = row.SUP;
    Data["Generators"]["SDN"][row.gen_id]               = row.SDN;
    Data["Generators"]["InitialState"][row.gen_id]      = row.initial_state;
    Data["Generators"]["NoLoadCost"][row.gen_id]        = row.no_load_cost;
    Data["Generators"]["UpReserveCost"][row.gen_id]     = row.up_reserve_cost;
    Data["Generators"]["DownReserveCost"][row.gen_id]   = row.down_reserve_cost;
    Data["Generators"]["MinUpTime"][row.gen_id]         = row.min_up_time
    Data["Generators"]["MinDnTime"][row.gen_id]         = row.min_dn_time
end

for bus in Data["System"]["SetBuses"]
    Data["Buses"]["FromLine"][bus]      = [Data["Lines"]["PairBuses"][line] for line in Data["System"]["SetLines"] if Data["Lines"]["ToNode"][line] == bus];
    Data["Buses"]["ToLine"][bus]        = [Data["Lines"]["PairBuses"][line] for line in Data["System"]["SetLines"] if Data["Lines"]["FromNode"][line] == bus];
    Data["Buses"]["Gens"][bus]          = [gen for gen in Data["System"]["SetGens"] if Data["Generators"]["Bus"][gen] == bus && Data["Generators"]["Variable"][gen] == 0];
    Data["Buses"]["VariableGens"][bus]  = [gen for gen in Data["System"]["SetGensVar"] if Data["Generators"]["Bus"][gen] == bus && Data["Generators"]["Variable"][gen] == 1];
    Data["Buses"]["Neighbor"][bus]      = union([Data["Lines"]["FromNode"][line] for line in Data["System"]["SetLines"] if Data["Lines"]["ToNode"][line] == bus],[Data["Lines"]["ToNode"][line] for line in Data["System"]["SetLines"] if Data["Lines"]["FromNode"][line] == bus]);
end

for row in DATA_BLOCKS
    append!(Data["System"]["SetTimeBlocks"], row.time)
    Data["TimeBlocks"]["Size"][row.time] = row.blocks_number;
end

for row in DATA_BETA  ## Revisar
    for t in Data["System"]["SetTimeBlocks"]
        Data["TimeBlocks"]["beta"][row.beta_bloque, t] = row[t+1]
    end
end

## 1.4.2 Procedures for hydro nodes and water flows
for row in DATA_HYDRO_NODES
    append!(Data["System"]["SetHydroNodes"], row.hydro_node_id);

    bus_index = 0;
    for bus in Data["System"]["SetBuses"]
        bus_index = (row.hydro_node_bus ==  Data["Buses"]["Name"][bus] ? bus : bus_index);
    end

    Data["HydroNodes"]["Name"][row.hydro_node_id]            = row.hydro_node_name;
    Data["HydroNodes"]["Type"][row.hydro_node_id]            = row.hydro_node_type;
    Data["HydroNodes"]["Bus"][row.hydro_node_id]             = bus_index;
    Data["HydroNodes"]["Terminal"][row.hydro_node_id]        = row.hydro_node_terminal;
    Data["HydroNodes"]["Delta"][row.hydro_node_id]           = row.hydro_delta;
    Data["HydroNodes"]["InitialLevel"][row.hydro_node_id]    = row.hydro_initial_condition;
    Data["HydroNodes"]["Pmax"][row.hydro_node_id]            = row.hydro_genmax;
    Data["HydroNodes"]["Pmin"][row.hydro_node_id]            = row.hydro_genmin;
    Data["HydroNodes"]["Affluent"][row.hydro_node_id]        = [0 for i=1:length(Data["TimeBlocks"]["Size"])] # Revisar
    Data["HydroNodes"]["MinStorage"][row.hydro_node_id]      = row.hydro_min_storage;
    Data["HydroNodes"]["MaxStorage"][row.hydro_node_id]      = row.hydro_max_storage;
    Data["HydroNodes"]["MaxStream"][row.hydro_node_id]       = row.hydro_max_stream;
    Data["HydroNodes"]["MinStream"][row.hydro_node_id]       = row.hydro_min_stream;
    Data["HydroNodes"]["FinalLevel"][row.hydro_node_id]      = row.hydro_final_condition;
end

for row in DATA_HYDRO_STREAMS # Cambio del index de par de nodos hidro a id (ya que exiten par turbinado y no turbinado)
    append!(Data["System"]["SetHydroStreams"], row.hydro_stream_id)

    hydro_node_from_index = 0; hydro_node_to_index = 0;
    for hydro_node in Data["System"]["SetHydroNodes"]
        hydro_node_from_index = (row.hydro_stream_from_node == Data["HydroNodes"]["Name"][hydro_node] ? hydro_node : hydro_node_from_index);
        hydro_node_to_index   = (row.hydro_stream_to_node   == Data["HydroNodes"]["Name"][hydro_node] ? hydro_node : hydro_node_to_index);
    end

    stream_pair = (hydro_node_from_index,hydro_node_to_index)
    if row.hydro_stream_type == "Turbinable"
        append!(Data["System"]["SetHydroStreamsTurb"], [stream_pair])
        Data["HydroStreamsT"]["Name"][stream_pair]           = row.hydro_stream_name;
        Data["HydroStreamsT"]["Type"][stream_pair]           = row.hydro_stream_type;
        Data["HydroStreamsT"]["MaxStream"][stream_pair]      = row.hydro_stream_max_flow;
        Data["HydroStreamsT"]["MinStream"][stream_pair]      = row.hydro_stream_min_flow;
        Data["HydroStreamsT"]["PairHydroNodes"][stream_pair] = (hydro_node_from_index,hydro_node_to_index);
        Data["HydroStreamsT"]["FromHydroNode"][stream_pair]  = hydro_node_from_index;
        Data["HydroStreamsT"]["ToHydroNode"][stream_pair]    = hydro_node_to_index;
    elseif row.hydro_stream_type == "Not turbinable"
        append!(Data["System"]["SetHydroStreamsNTurb"], [stream_pair])
        Data["HydroStreamsNT"]["Name"][stream_pair]           = row.hydro_stream_name;
        Data["HydroStreamsNT"]["Type"][stream_pair]           = row.hydro_stream_type;
        Data["HydroStreamsNT"]["MaxStream"][stream_pair]      = row.hydro_stream_max_flow;
        Data["HydroStreamsNT"]["MinStream"][stream_pair]      = row.hydro_stream_min_flow;
        Data["HydroStreamsNT"]["PairHydroNodes"][stream_pair] = (hydro_node_from_index,hydro_node_to_index);
        Data["HydroStreamsNT"]["FromHydroNode"][stream_pair]  = hydro_node_from_index;
        Data["HydroStreamsNT"]["ToHydroNode"][stream_pair]    = hydro_node_to_index;
    end
end

for hydro_node in Data["System"]["SetHydroNodes"]
    Data["HydroNodes"]["FromStreamTurb"][hydro_node]  = [Data["HydroStreamsT"]["PairHydroNodes"][hydro_stream] for hydro_stream in Data["System"]["SetHydroStreamsTurb"]  if Data["HydroStreamsT"]["FromHydroNode"][hydro_stream] == hydro_node];
    Data["HydroNodes"]["ToStreamTurb"][hydro_node]    = [Data["HydroStreamsT"]["PairHydroNodes"][hydro_stream] for hydro_stream in Data["System"]["SetHydroStreamsTurb"]  if Data["HydroStreamsT"]["ToHydroNode"][hydro_stream]   == hydro_node];
    Data["HydroNodes"]["FromStreamNTurb"][hydro_node] = [Data["HydroStreamsNT"]["PairHydroNodes"][hydro_stream] for hydro_stream in Data["System"]["SetHydroStreamsNTurb"] if Data["HydroStreamsNT"]["FromHydroNode"][hydro_stream] == hydro_node];
    Data["HydroNodes"]["ToStreamNTurb"][hydro_node]   = [Data["HydroStreamsNT"]["PairHydroNodes"][hydro_stream] for hydro_stream in Data["System"]["SetHydroStreamsNTurb"] if Data["HydroStreamsNT"]["ToHydroNode"][hydro_stream]   == hydro_node];
    Data["HydroNodes"]["Affluent"][hydro_node]        = Dict();
end

for row in DATA_ALPHA ## Revisar
    hydro_node_index = 0;
    for hydro_node in Data["System"]["SetHydroNodes"]
        hydro_node_index = (row.hydro_node_name == Data["HydroNodes"]["Name"][hydro_node] ? hydro_node : hydro_node_index);
    end

    for t in  Data["System"]["SetTimeBlocks"]
        Data["HydroNodes"]["Affluent"][hydro_node_index][t] = row[t+1]
    end
end

for bus in Data["System"]["SetBuses"]
    Data["Buses"]["HydroGens"][bus] = [hydro_node for hydro_node in Data["System"]["SetHydroNodes"] if Data["HydroNodes"]["Type"][hydro_node] == "generation" && Data["HydroNodes"]["Bus"][hydro_node] == bus]
end

## 1.4.3 Procedures for demand, variable cost, plant factor and LS & OG cost

for bus in Data["System"]["SetBuses"]
    Data["Buses"]["Demand"][bus] = Dict()
end

for row in DATA_DEMAND
    bus_index = 0;
    for bus in Data["System"]["SetBuses"]
        bus_index = (row.bus_name ==  Data["Buses"]["Name"][bus] ? bus : bus_index);
    end

    if ~(bus_index in Data["System"]["SetDemandBuses"])
        append!(Data["System"]["SetDemandBuses"], bus_index)
    end

    for t in  Data["System"]["SetTimeBlocks"]
         Data["Buses"]["Demand"][bus_index][row.bus_bloque, t] = row[t+2]
    end
end

for gen in Data["System"]["SetGens"]
    Data["Generators"]["VariableCost"][gen] = Dict(); #zeros(Data["System"]["SetTimeBlocks"], Data["TimeBlocks"]["Size"][t])
end

for gen in Data["System"]["SetGensVar"]
    Data["Generators"]["Fp"][gen]           = Dict(); #zeros(Data["System"]["SetTimeBlocks"], Data["TimeBlocks"]["Size"][t])
end

for bus in Data["System"]["SetBuses"]
    Data["Buses"]["OverGenCost"][bus]       = Dict()
    Data["Buses"]["LoadSheddingCost"][bus]  = Dict()
end

for row in DATA_CVAR
    gen_index = 0;
    for gen in Data["System"]["SetGens"]
        gen_index = (row.gen_name == Data["Generators"]["Name"][gen] ? gen : gen_index);
    end

    for t in  Data["System"]["SetTimeBlocks"]
        Data["Generators"]["VariableCost"][gen_index][row.gen_bloque, t] = row[t+2]
    end
end

for row in DATA_FPLANTA
    gen_index = 0;
    for gen in Data["System"]["SetGensVar"]
        gen_index = (row.gen_name == Data["Generators"]["Name"][gen] ? gen : gen_index);
    end

    for t in Data["System"]["SetTimeBlocks"]
        Data["Generators"]["Fp"][gen_index][row.gen_bloque, t] = row[t+2]
    end
end

for row in DATA_BUSES_OV_LS # Revisar archivo (se edito el archivo csv)
    bus_index = 0;
    for bus in Data["System"]["SetBuses"]
        bus_index = (row.bus_name == Data["Buses"]["Name"][bus] ? bus : bus_index);
    end

    Data["Buses"]["OverGenCost"][bus_index][row.bus_bloque]       = row.bus_og
    Data["Buses"]["LoadSheddingCost"][bus_index][row.bus_bloque]  = row.bus_ls
end

## 1.4.4 Procedures for system parameters
for row in DATA_SYSTEM
    Data["System"]["Name"]                 = row.system_name
    Data["System"]["ConvCoef"]             = row.system_conv_coef
end

Data["System"]["SetHydroNodesLeaf"]    = [hydro_node for hydro_node in Data["System"]["SetHydroNodes"] if Data["HydroNodes"]["Terminal"][hydro_node] == "terminal"]
Data["System"]["SetHydroNodeGen"]      = [hydro_node for hydro_node in Data["System"]["SetHydroNodes"] if Data["HydroNodes"]["Type"][hydro_node] == "generation"]
Data["System"]["SetHydroNodesSto"]     = [hydro_node for hydro_node in Data["System"]["SetHydroNodes"] if Data["HydroNodes"]["Type"][hydro_node] == "storage"]
Data["System"]["SetHydroNodesBoc"]     = [hydro_node for hydro_node in Data["System"]["SetHydroNodes"] if Data["HydroNodes"]["Type"][hydro_node] == "intake"]


## 1.4.5 Procedures for system-dependent parameters


## 1.4.6 New Terminal Hydro nodes
max_node_id = maximum(Data["System"]["SetHydroNodes"])
append!(Data["System"]["SetHydroNodes"], max_node_id+1)
Data["HydroNodes"]["MaxStream"][max_node_id+1]              = 0
Data["HydroNodes"]["FromStreamNTurb"][max_node_id+1]        = []
Data["HydroNodes"]["MaxStorage"][max_node_id+1]             = 0
Data["HydroNodes"]["InitialLevel"][max_node_id+1]           = 0
Data["HydroNodes"]["Delta"][max_node_id+1]                  = 0
Data["HydroNodes"]["Name"][max_node_id+1]                   = "Nodo_Terminal"
Data["HydroNodes"]["Pmax"][max_node_id+1]                   = 0
Data["HydroNodes"]["MinStorage"][max_node_id+1]             = 0
Data["HydroNodes"]["Bus"][max_node_id+1]                    = 0
Data["HydroNodes"]["MinStream"][max_node_id+1]              = 0
Data["HydroNodes"]["ToStreamTurb"][max_node_id+1]            = []
Data["HydroNodes"]["Pmin"][max_node_id+1]                   = 0
Data["HydroNodes"]["Terminal"][max_node_id+1]               = "Created"
Data["HydroNodes"]["Affluent"][max_node_id+1]               = 0
Data["HydroNodes"]["Type"][max_node_id+1]                   = "Created"
Data["HydroNodes"]["FromStreamTurb"][max_node_id+1]         = []
Data["HydroNodes"]["ToStreamNTurb"][max_node_id+1]          = []

for i in Data["System"]["SetHydroNodes"]
    if Data["HydroNodes"]["Terminal"][i] == "terminal"
        #Canal Turbinable
        Data["HydroStreamsT"]["Name"][(i,max_node_id+1)]           = "Terminal T $(i) to $(max_node_id+1)";
        Data["HydroStreamsT"]["Type"][(i,max_node_id+1)]           = "turbinable";
        Data["HydroStreamsT"]["MaxStream"][(i,max_node_id+1)]      = 1000;
        Data["HydroStreamsT"]["MinStream"][(i,max_node_id+1)]      = 0;
        Data["HydroStreamsT"]["PairHydroNodes"][(i,max_node_id+1)] = (i,max_node_id+1);
        Data["HydroStreamsT"]["FromHydroNode"][(i,max_node_id+1)]  = i;
        Data["HydroStreamsT"]["ToHydroNode"][(i,max_node_id+1)]    = max_node_id+1;
        #Canal No turbinable
        Data["HydroStreamsNT"]["Name"][(i,max_node_id+1)]           = "Terminal NT $(i) to $(max_node_id+1)";
        Data["HydroStreamsNT"]["Type"][(i,max_node_id+1)]           = "no_turbinable";
        Data["HydroStreamsNT"]["MaxStream"][(i,max_node_id+1)]      = 2000;
        Data["HydroStreamsNT"]["MinStream"][(i,max_node_id+1)]      = 0;
        Data["HydroStreamsNT"]["PairHydroNodes"][(i,max_node_id+1)] = (i,max_node_id+1);
        Data["HydroStreamsNT"]["FromHydroNode"][(i,max_node_id+1)]  = i;
        Data["HydroStreamsNT"]["ToHydroNode"][(i,max_node_id+1)]    = max_node_id+1;
        #Agregar al sistema los streams
        append!(Data["System"]["SetHydroStreamsTurb"], [(i,max_node_id+1)] )
        append!(Data["System"]["SetHydroStreamsNTurb"],  [(i,max_node_id+1)] )
        append!(Data["HydroNodes"]["FromStreamTurb"][i], [(i,max_node_id+1)])
        append!(Data["HydroNodes"]["FromStreamNTurb"][i], [(i,max_node_id+1)])
        append!(Data["HydroNodes"]["ToStreamTurb"][max_node_id+1], [(i,max_node_id+1)])
        append!(Data["HydroNodes"]["ToStreamNTurb"][max_node_id+1], [(i,max_node_id+1)])
    end
end
