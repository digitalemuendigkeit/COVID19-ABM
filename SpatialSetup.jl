using StatsBase, Distributions, Statistics,Distributed, GraphPlot, GraphRecipes, AgentsPlots, StatsPlots, Luxor, LightGraphs, OpenStreetMapX

function create_node_map()
    #get map data and its inbounds
    aachen_map = get_map_data(joinpath("SourceData","aachen_test3.osm"), use_cache=false, only_intersections=true)
    aachen_graph = aachen_map.g
    bounds = aachen_map.bounds

    #use the raw parseOSM function to obtain nodes tagged with "school"
    aachen_schools = OpenStreetMapX.parseOSM(joinpath("SourceData","aachen_test3.osm"))
    aachen_schools_nodes = [key for (key,value) in aachen_schools.features if value[2]=="school"]
    aachen_schools = Dict([key => value for (key,value) in aachen_schools.nodes if in(key,aachen_schools_nodes)])

    #lat long of Aachen as reference frame
    LLA_ref = LLA((bounds.max_y+bounds.min_y)/2, (bounds.max_x+bounds.min_x)/2, 266.0)
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
    #graphplot(aachen_graph, markersize=2, x=LLA_Dict_longs, y=LLA_Dict_lats)
    #show the map to prove how cool and orderly it is
    #gplot(aachen_graph, LLA_Dict_longs, LLA_Dict_lats)
    #savegraph("Graphics\\aachen_graph.lgz", aachen_graph)
    aachen_graph = aachen_graph, LLA_Dict_longs, LLA_Dict_lats, bounds, aachen_schools, aachen_map

    return aachen_graph
end

function create_demography_map()
    rawdata = DataFrame!(CSV.File(joinpath("SourceData","zensus.csv")))
    #make sure properties are symboml
    colsymbols = propertynames(rawdata)
    DataFrames.rename!(rawdata,colsymbols)
    #@time plot(rawdata.X,rawdata.Y)
    return rawdata
end

function fill_map(model,group,long, lat, correction_factor,schools,schoolrange, workplacedict, social_groups,distant_groups)
    nrow(group) < 4 && return
    #get the bounds and skip if the cell is empty
    top = maximum(group[:Y])
    bottom = minimum(group[:Y])
    left = minimum(group[:X])
    right = maximum(group[:X])
    top-bottom == 0 && right-left == 0 && return

    possible_nodes_long = findall(y -> isbetween(left,y,right), long)
    possible_nodes_lat = findall(x -> isbetween(bottom, x, top), lat)
    #get index of nodes to create a base of nodes we can later add our agents to
    #and skip if there are no nodes within this space
    possible_nodes = (intersect(possible_nodes_lat,possible_nodes_long))
    length(possible_nodes) == 0 && return

    #get the number of inhabitants, women, old people etc for the current grid
    inhabitants = Int(round(mean(group.Einwohner)/(correction_factor/1000)))
    inhabitants < 2 && return
    println("working at next group with $inhabitants inhabitants")
    women = get_amount(inhabitants,group.Frauen_A)
    age = Int(round(mean(group.Alter_D)))
    below18 = get_amount(inhabitants,group.unter18_A)
    over65 = get_amount(inhabitants,group.ab65_A)
    kaufkraft = mean(group.kaufkraft)

    #println("We have $(inhabitants) inhabitants with $(women) women, $(age) mean age, $(over65) old people and $rich rich, $poor poor persons \n")

    #fill array with default agents of respective amount of agents with young/old age and gender
    agent_properties = Vector{agent_tuple}(undef,inhabitants)
    undef_vector = LightGraphs.SimpleGraphs.SimpleEdge{Int64}[]
    undef_history = Vector{Float32}(undef,0)
    for x in 1:inhabitants
        agent_properties[Int(x)] = agent_tuple(:S,0,0,0,0,0,0,false,age,0,0,0,0,0,undef_vector,undef_vector,undef_vector,undef_history)
    end

    #randomly set women and young/old inhabitants
    [agent.women = true for agent in agent_properties[1:women]]
    shuffle!(agent_properties)
    [agent.age = rand(1:17) for agent in agent_properties[1:below18]]
    #check if there are enough agents before setting the share to old age
    if (below18+1+over65)<=length(agent_properties)
        [agent.age = rand(66:110) for agent in agent_properties[below18+1:(below18+1+over65)]]
    else
        [agent.age = rand(66:110) for agent in agent_properties[below18:(below18+over65)]]
    end
    shuffle!(agent_properties)

    #shuffle the agent_properties, sample #inhabitants, map it to the desired range and assign those to the agent properties
    wealth_distribution = BetaPrime(2.29201,108.029)
    sample = rand(wealth_distribution,inhabitants)
    #modify and round the sample so that its mean equals kaufkraft
    multiplier = kaufkraft/mean(sample)
    sample = sample .* multiplier
    sample = round.(sample)
    #and assign the wealth to inhabitants
    for (index,value) in enumerate(sample)
        agent_properties[index].wealth = value
    end

    #Adding households to the map
    #get inhabitants/2 random nodes
    nodecount = Int(round(inhabitants/2))
    nodes = rand(possible_nodes,nodecount)
    noderange = [nv(model.space)+1:nv(model.space)+length(nodes);]
    #add them to the map
    add_households(nodes,model,lat,long)
    #now pair agents and households within newly added nodes
    #hh distribution from paper, fitted Categorical to it
    household_distribution = Categorical([0.41889017788089716, 0.337949535962877, 0.11898201856148492, 0.09058391337973705, 0.03359435421500387])
    #redraw the sample so that it fits to the number of inhabitants
    #okay performance for 5 digits, for 6 performance starts to tank but highest nodesize is 23379 so its probably okay
    sample = rand(household_distribution,nodecount)
    n = 1
    while sum(sample) != inhabitants
        sample = rand(household_distribution,nodecount)
        n+=1
        n == 1000 && (sample = [inhabitants])
    end
    #for all newly added nodes, set the household of #sample[i] agents to it.
    #we thereby generate sampled households
    agent_index = 0
    #fill the social groups up
    #sanity check if groups are too small, then make only one group
    for (index,value) in enumerate(noderange)
          hhhere = sample[index]
          for i in 1:hhhere
              #set #hhere agents to this node and increment the agent_index counter
              agent_properties[agent_index+i].household = value
          end
          agent_index = agent_index+hhhere
      end


    #adding friendgroup, same behavior, select random nodes
    nodecount = Int(round(inhabitants/11))
    nodes = rand(possible_nodes,nodecount)
    length(nodes) == 0 && (nodes = [rand(possible_nodes)])
    #from sinus institut, get friend size groups
    friend_distribution = Normal(11,3)
    sample = Int.(round.(rand(friend_distribution,nodecount)))
    n = 1
    while sum(sample) != inhabitants
        sample = Int.(round.(rand(friend_distribution,nodecount)))
        n+=1
        n == 1000 && (sample = [inhabitants])
    end
    agent_index = 0
    #fill the social groups up
    #sanity check if groups are too small, then make only one group
    if length(sample) == 1
        hhhere = sample[1]
        value = rand(nodes)
        push!(social_groups,value)
        for i in 1:hhhere
            agent_properties[agent_index+i].socialgroup = value
        end
    else
        for (index,value) in enumerate(nodes)
            hhhere = sample[index]
            push!(social_groups,value)
            for i in 1:hhhere
                agent_properties[agent_index+i].socialgroup = value
            end
            agent_index = agent_index+hhhere
        end
    end

    #adding distnant groups, representing sport and shopping behavior
    nodecount = Int(round(inhabitants/20))
    nodes = rand(possible_nodes,nodecount)
    length(nodes) == 0 && (nodes = [rand(possible_nodes)])
    #from sinus institut, get friend size groups
    distant_distribution = Normal(20,5)
    sample = Int.(round.(rand(distant_distribution,nodecount)))
    n = 1
    while sum(sample) != inhabitants
        sample = Int.(round.(rand(distant_distribution,nodecount)))
        n+=1
        n == 1000 && (sample = [inhabitants])
    end
    agent_index = 0

    #fill the distant groups
    if length(sample) == 1
        hhhere = sample[1]
        value = rand(possible_nodes)
        push!(distant_groups,value)
        for i in 1:hhhere
            agent_properties[agent_index+i].distantgroup = value
        end
    else
        for (index,value) in enumerate(nodes)
            hhhere = sample[index]
            push!(distant_groups,value)
            for i in 1:hhhere
                agent_properties[agent_index+i].distantgroup = value
            end
            agent_index = agent_index+hhhere
        end
    end

    #get people in school age
    young_people = filter(x -> isbetween(5,x.age,18), agent_properties)
    #search the closest school and set it as their workplace
    for agent in young_people
        search_dist = 0.005
        school_nodes = findall(x -> abs(x.lat-lat[agent.household])<search_dist && abs(x.lon-long[agent.household])<search_dist,[values(schools)...])
        #if no nodes are within range, expand it step by step
        while length(school_nodes) == 0
            search_dist*=2
            school_nodes = findall(x -> abs(x.lat-lat[agent.household])<search_dist && abs(x.lon-long[agent.household])<search_dist,[values(schools)...])
        end
        agent.workplace = schoolrange[rand(school_nodes)]
    end

    #and distribute the agents to the workspaces
    middle_people = filter(x -> isbetween(18,x.age,65), agent_properties)
    for agent in middle_people
        search_dist = 0.005
        workplace_keys = collect(Base.keys(workplacedict))
        workplace_values = collect(values(workplacedict))
        #deduce the workplace size preference of this agent
        max_workplace_size = round(exp_workplace(agent.wealth))
        #check if the workplace is within range and not yet filled beyond individual preference
        workplace_nodes = findall(x -> abs(x[3]-lat[agent.household])<search_dist && abs(x[4]-long[agent.household])<search_dist && x[2]<max_workplace_size,[workplace_values...] )
        #if no nodes are within range, expand it step by step
        while length(workplace_nodes) == 0
            search_dist*=2
            workplace_nodes = findall(x -> abs(x[3]-lat[agent.household])<search_dist && abs(x[4]-long[agent.household])<search_dist && x[2]<max_workplace_size,[workplace_values...] )
            #if range gets to big, add agent against his preferences to node
            if search_dist > 0.1
                workplace_nodes = findall(x -> abs(x[3]-lat[agent.household])<search_dist && abs(x[4]-long[agent.household])<search_dist,[workplace_values...] )
            end
        end
        #set one of the possible nodes as workplace for this agent
        selected_workspace = workplace_keys[rand(workplace_nodes)]
        agent.workplace = selected_workspace
        #and increment the counter for this workplace
        workplacedict[selected_workspace][2]+= 1
    end

    compute_attitudes(agent_properties)

    #and, finally, compute add all agent properties to the model
    for agent in agent_properties
        #only compute route if agent has a workplace
        if agent.workplace != 0
            agent_workplace_route = a_star(model.space.graph,agent.household,agent.workplace)
        else
            agent_workplace_route = Vector{LightGraphs.SimpleGraphs.SimpleEdge{Int64}}[]
        end
        agent_social_route = a_star(model.space.graph,agent.household,agent.socialgroup)
        agent_distant_route = a_star(model.space.graph,agent.household,agent.distantgroup)
        add_agent!(agent.household, model, agent.health_status, agent.days_infected, agent.attitude, agent.original_attitude, agent.fear, agent.behavior, agent.acquaintances_growth, agent.women, agent.age, agent.wealth, agent.household, agent.workplace, agent.socialgroup, agent.distantgroup, agent_workplace_route, agent_social_route, agent_distant_route, agent.fear_history)
    end
    return
end



#helper functions

#generates a distribution of base attitudes towards protective behavior
function compute_attitudes(agent_properties)
    #assign random attitude values to the agent attributes
    trust_distribution = Normal(55.53191489361702,16.542467674404413)
    [agent.attitude = Int.(round.(rand(trust_distribution))) for agent in agent_properties]
    #manipulate the attitude according to demographic factors
    for agent in agent_properties
        #women have more trust than men
        if !agent.women
            agent.attitude = agent.attitude+rand(1:1:10)
        else
            agent.attitude = agent.attitude-rand(1:1:10)
        end
        #change attitude according to age
        if agent.age>20
            #set the baseline at average age 40, older people get a penalty on attitude, younger a bonus
            agent.attitude = agent.attitude + Int(round(10-(agent.age/4)))
        end
        #prevent attitude from getting negative
        agent.attitude<=0 && (agent.attitude = 1)

    end
end

#counts the number of inhabitants so its available externally
function count_inhabitants(working_grid,lat, long, correction_factor)
    inhabitants = 0
    for group in working_grid
        nrow(group) < 4 && continue
        #add the number of people eligibile for work to the inhabitants
        inhabitants_here = Int(round(mean(group.Einwohner)/(correction_factor/1000)))
        below18 = get_amount(inhabitants_here,group.unter18_A)
        over65 = get_amount(inhabitants_here,group.ab65_A)
        inhabitants+= (inhabitants_here-below18)-over65
    end
    return inhabitants
end

function exp_workplace(x)
    return (2990.168x^-0.7758731)-x/10+rand(0:(2*x/10))
end

function add_workplaces(model,lat,long,working_population)
    workplacesize_distribution = Rayleigh(96.31905979491185)
    #draw (#inhabitants/avg number of workplaces) workplaces from the distribution
    workplacesizes = Int.(round.(rand(workplacesize_distribution,Int(round(working_population/mean(workplacesize_distribution))))))
    sum_wp_size = sum(workplacesizes)
    #remove too big draws from workplacesizes
    while sum(workplacesizes) >= working_population
        pop!(workplacesizes)
    end
    #and fill the last slow with a workplace in the fitting size
    push!(workplacesizes,(working_population-sum(workplacesizes)))
    workplacerange = [nv(model.space)+1:nv(model.space)+length(workplacesizes);]
    random_nodes = rand(vertices(model.space.graph),length(workplacesizes))
    #add workplaces to the graph
    add_nodes_to_model(model,workplacesizes)
    #initialize a dict of node => (max workplaces, currently used workplaces)
    workplacedict = Dict(0 => [0,0,0.0,0.0])
    index = 1
    for i in 1:length(workplacesizes)
        #set the coordinate of the school at a random point in the map, connect to it
        adjacent_node = random_nodes[i]
        add_edge!(model.space.graph, adjacent_node, workplacerange[i])
        #and set the lat,longs with a little offset to that node
        push!(lat,lat[adjacent_node]+0.0002)
        push!(long,long[adjacent_node]+0.0002)
        workplacedict[workplacerange[i]] = [workplacesizes[i],0,lat[adjacent_node]+0.0002,long[adjacent_node]+0.0002]
    end
    return workplacedict
end


function add_schools(schools,schoolrange,model,lat,long)
    add_nodes_to_model(model,schools)
    index = 1
    for value in values(schools)
        #find nodes that are close to the school
        search_dist = 0.001
        school_nodes = intersect(findall(x -> abs(x-value.lat)<search_dist,lat),findall(x -> abs(x-value.lon)<search_dist,long))
        #if no nodes are within range, expand it step by step
        while length(school_nodes) == 0
            search_dist*=2
            school_nodes = intersect(findall(x -> abs(x-value.lat)<search_dist,lat),findall(x -> abs(x-value.lon)<search_dist,long))
        end
        #add an edge between one of the random nodes and the school to the map
        add_edge!(model.space.graph, rand(school_nodes), schoolrange[index])
        index+=1
        #and append the coordinates of the school to the lats and longs for plotting
        push!(lat,value.lat)
        push!(long,value.lon)
    end
end

function add_households(nodes,model,lat,long)
    nodecount=nv(model.space)
    add_nodes_to_model(model, nodes)
    #then generate an edge and locate them close to their parent node
    for (index,value) in enumerate(nodes)
        neighbors = node_neighbors(value,model)
        coordinates = (lat[value]-0.0002,long[value]-0.0002)
        #superhacky stuff that works like 1000%
        add_edge!(model.space.graph, value, (nodecount+index))
        push!(lat,coordinates[1])
        push!(long,coordinates[2])
    end
end

function add_nodes_to_model(model,nodes)
    #first add the vertices to the graph
    add_vertices!(model.space.graph,length(nodes))
    #Agents.jl doesnt support the addition of nodes post-initalization
    #so I changed the agent_positions struct to mutable and concatenate an empty array of
    #the length of our new nodes to it
    new_nodes = [Int[] for i in 1:length(nodes)]
    model.space.agent_positions = vcat(model.space.agent_positions,new_nodes)
end

function get_amount(inhabitants,input)
    result = Int(round((inhabitants*(mean(input)/100))))
    result < 0 && (result = 0)
    return result
end

isbetween(a, x, b) = a <= x <= b || b <= x <= a

mutable struct agent_tuple
    health_status::Symbol
    days_infected::Int8
    attitude::Int16
    original_attitude::Int16
    fear::Float32
    behavior::Int16
    acquaintances_growth::Int32
    women::Bool
    age::Int16
    wealth::Int16
    household::Int32
    workplace::Int32
    socialgroup::Int32
    distantgroup::Int32
    workplaceroute::Vector{LightGraphs.SimpleGraphs.SimpleEdge{Int64}}
    socialroute::Vector{LightGraphs.SimpleGraphs.SimpleEdge{Int64}}
    distantroute::Vector{LightGraphs.SimpleGraphs.SimpleEdge{Int64}}
    fear_history::Vector{Float32}
end

function setup(params)

    #create the nodemap and rawdata demography map and set the bounds for it
    nodes,long,lat,bounds,schools,map_data = create_node_map()
    rawdata = create_demography_map()
    println("loaded raw data")
    #get the grid data within the boundaries of the node map
    working_grid = rawdata[(rawdata.X .> bounds.min_x) .& (rawdata.X .< bounds.max_x) .& (rawdata.Y .> bounds.min_y).& (rawdata.Y .< bounds.max_y),:]

    #divide the population by this to avoid computing me to death
    #should scale nicely with graph size to keep agent number in check
    correction_factor = nv(nodes)

    #set up the variables, structs etc.
    space = GraphSpace(nodes)
    model = ABM(DemoAgent,space; properties=params)
    social_groups = Vector{Int32}(undef,0)
    distant_groups = Vector{Int32}(undef,0)

    #the nodeindices of the schools we add to the model
    schoolrange = [nv(model.space)+1:nv(model.space)+length(schools);]
    add_schools(schools,schoolrange,model,lat,long)

    #divide the grid into groups so we can iterate over it and fill the map with agents
    working_grid = groupby(working_grid,:DE_Gitter_ETRS89_LAEA_1km_ID_1k; sort=false)
    #add workspaces to the map
    working_population = count_inhabitants(working_grid, lat, long, correction_factor)
    workplacedict = add_workplaces(model, lat, long, working_population)
    println("finished additional setup and beginning with agent generation")

    @inbounds for group in working_grid
        fill_map(model,group,long,lat,correction_factor,schools,schoolrange, workplacedict, social_groups, distant_groups)
    end

    return model,lat,long,social_groups,distant_groups
end

export setup
