using OpenStreetMapX, LightGraphs, GraphPlot
using CSV, DataFrames
using Agents, AgentsPlots
using Statistics

function create_node_map()
    #get map data and intersections
    aachen_map = get_map_data("SourceData\\map.osm", use_cache=false, only_intersections=true)
    aachen_graph = aachen_map.g

    #lat long of Aachen as reference frame
    LLA_ref = LLA(50.77664, 6.08342, 0.0)
    #conversion to lat long coordinates
    LLA_Dict = OpenStreetMapX.LLA(aachen_map.nodes, LLA_ref)
    #filter the LLA_Dict so we have only the nodes we have in the graph
    LLA_Dict = filter(key -> haskey(aachen_map.v, key.first), LLA_Dict)

    #sort the LLA_dict_values as in aachen_map.v so the graph has the right ordering of the nodes
    LLA_Dict_values = Vector{LLA}(undef,length(LLA_Dict))
    for (key,value) in aachen_map.v
        LLA_Dict_values[value] = LLA_Dict[key]
    end

    #and parse the lats longs into separate vectors
    LLA_Dict_lats = zeros(Float64,0)
    LLA_Dict_longs = zeros(Float64,0)
    for (value) in LLA_Dict_values
        append!(LLA_Dict_lats, value.lat)
        append!(LLA_Dict_longs, value.lon)
    end

    aachen_graph = SimpleGraph(aachen_graph)
    aachen_graph = aachen_graph,LLA_Dict_lats,LLA_Dict_longs

    #show the map to prove how cool and orderly it is
    #gplot(aachen_graph, LLA_Dict_lats, LLA_Dict_longs)
    return aachen_graph
end

function create_demography_map()
    #read the data
    rawdata = CSV.read("SourceData\\zensus3.csv")
    #drop irrelevant columns and redundant rows
    deletecols!(rawdata,3:14)
    colsymbols = propertynames(rawdata)
    rename!(rawdata,colsymbols)
    rawdata = rawdata[rawdata.distance.!=0,:]
    return rawdata
end

function fill_map()
    #create the nodemap and rawdata demography map and set the bounds for it
    nodes,lat,long=create_node_map()
    topleft = (maximum(lat),minimum(long))
    bottomright = (minimum(lat),maximum(long))
    rawdata = create_demography_map()

    #get the grid data from the boundaries of the node
    working_grid = rawdata[(rawdata.X .> topleft[2]) .& (rawdata.X .< bottomright[2]) .& (rawdata.Y .< topleft[1]) .& (rawdata.Y .> bottomright[1]),:]
    working_grid = groupby(working_grid,:DE_Gitter_ETRS89_LAEA_1km_ID_1k)

    #divide the population by this to avoid computating me to death
    correction_factor = 1000

    #set up the variables and iterate over the groups to fill the node map
    inhabitants = women = age = below18 = over65 = 0
    agents = Array{AbstractAgent}
    for group in working_grid
        einwohner = round(mean(group.Einwohner)/correction_factor)
        for
        agent = SchellingAgents
        women =
        print("einwohner:",einwohner)
    end

end

function create_abm()

    space = GraphSpace(nodes)
    model = ABM(SchellingAgents,space)

    for x in 1:100
        agent = SchellingAgents(x+200, x, false, 1)
        add_agent!(agent, model)
    end

    plotargs = (node_size = 0.001, method = :spring, linealpha = 0.1)




mutable struct SchellingAgents <: AbstractAgent
    id::Int # The identifier number of the agent
    pos::Int # The x, y location of the agent on a 2D grid
    mood::Bool # whether the agent is happy in its node. (true = happy)
    group::Int # The group of the agent,  determines mood as it interacts with neighbors
end

mutable struct DemoAgent <: AbstractAgent
    id::Int64 # The identifier number of the agent
    pos::Int32 # The nodenumber
    women::Bool
    age::Int8
end


agent_number(x) = cgrad(:inferno)[length(x)]
agent_size(x) = length(x)/10

plotabm(model; ac = agent_number, as=agent_size, plotargs...)