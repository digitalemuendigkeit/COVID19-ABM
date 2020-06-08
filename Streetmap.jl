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
    select!(rawdata,Not(3:14))
    colsymbols = propertynames(rawdata)
    rename!(rawdata,colsymbols)
    rawdata = rawdata[rawdata.distance.!=0,:]
    return rawdata
end

function get_amount(inhabitants,input)
    return round(mean((inhabitants*input)/100))
end

isbetween(a, x, b) = a <= x <= b || b <= x <= a

function fill_map()
    #create the nodemap and rawdata demography map and set the bounds for it
    @time nodes,lat,long=create_node_map()
    topleft = (maximum(lat),minimum(long))
    bottomright = (minimum(lat),maximum(long))
    @time rawdata = create_demography_map()

    #get the grid data within the boundaries of the node map
    working_grid = rawdata[(rawdata.X .> topleft[2]) .& (rawdata.X .< bottomright[2]) .& (rawdata.Y .< topleft[1]) .& (rawdata.Y .> bottomright[1]),:]
    #TODO improve this so we also get edge cases, leads to some empty grid cells
    working_grid = groupby(working_grid,:DE_Gitter_ETRS89_LAEA_1km_ID_1k; sort=true)

    #divide the population by this to avoid computing me to death
    #should scale nicely with graph size to keep agent number in check
    correction_factor = nv(nodes)

    #set up the variables and iterate over the groups to fill the node map
    inhabitants = women = age = below18 = over65 = 0
    agent_struct = Vector{DemoAgent}

    agent_tuple = [(Bool, 0)]
    agent_properties = []
    testfact = 50

    mutable struct agent_tuple1
        women::Bool
        age::Int16
    end

    space = GraphSpace(nodes)
    model = ABM(DemoAgent,space)

    for group in working_grid

        #get the bounds and skip if the cell is empty
        top = maximum(group[:Y])
        bottom = minimum(group[:Y])
        left = minimum(group[:X])
        right = maximum(group[:X])
        top-bottom == 0 && right-left == 0 && continue

        #get the number of inhabitants, women, old people etc for the current grid
        inhabitants = Int(round(mean(group.Einwohner)/correction_factor))
        women = get_amount(inhabitants,group.Frauen_A)
        age = Int(round(mean(group.Alter_D)))
        below18 = get_amount(inhabitants,group.unter18_A)
        over65 = get_amount(inhabitants,group.ab65_A)
        #print("We have $(inhabitants) inhabitants with $(women) women, $(age) mean age and $(over65) old people \n")

        possible_nodes_long = findall(y -> isbetween(left,y,right), long)
        possible_nodes_lat = findall(x -> isbetween(bottom, x, top), lat)
        #get index of nodes to create a base of nodes we can later add our agents to
        possible_modes =
        #print(intersect(possible_nodes_lat,possible_nodes_long))


        #fill array with default agents of respective amount of agents with young/old age and gender
        agent_properties = Vector{agent_tuple1}(undef,inhabitants)
        for x in 1:inhabitants
            agent_properties[Int(x)] = agent_tuple1(false,age)
        end
        for w in women
            agent_properties[rand(1:inhabitants)].women = true
        end
        for y in below18
            agent_properties[rand(1:inhabitants)].age = rand(1:17)
        end
        for o in over65
            temp_arr = findall(x -> x.age == age, agent_properties)
            agent_properties[rand(temp_arr)].age = rand(66:100)
        end
        #for agent in agent_properties
        #    add_agent!(agent,model,)
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


mutable struct DemoAgent <: AbstractAgent
    id::Int # The identifier number of the agent
    pos::Int # The nodenumber
    women::Bool
    age::Int8
end


agent_number(x) = cgrad(:inferno)[length(x)]
agent_size(x) = length(x)/10

plotabm(model; ac = agent_number, as=agent_size, plotargs...)
