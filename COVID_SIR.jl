using Agents, Random, DataFrames, LightGraphs
using Distributions: Poisson, DiscreteNonParametric
using CSV
using Plots
using LinearAlgebra:diagind
using AgentsPlots
using Images

mutable struct agent <: AbstractAgent
    id::Int
    pos::Tuple{Int,Int}
    days_infected::Int
    status::Symbol #1: S, 2: I, 3:R
end

function translateDensity(x::Int, seed = 0)
    Random.seed!(seed)
    if x == 1
           return(rand(1:250))
       elseif x == 2
           return(rand(250:500))
       elseif x == 3
           return(rand(500:2000))
       elseif x == 4
           return(rand(2000:4000))
       elseif x == 5
           return(rand(5000:8000))
       elseif x == 6
           return(rand(8000:8100))
    end
    return 0
end


function getDensityData()

    rawdata = CSV.read("census.csv")
    #names(rawdata)

    rawdata.x = (rawdata.x_mp_1km .- 500) ./ 1000
    rawdata.y = (rawdata.y_mp_1km .- 500) ./ 1000

    xmin = minimum(rawdata.x)
    xmax = maximum(rawdata.x)
    xsize = Int(xmax - xmin) + 1

    ymin = minimum(rawdata.y)
    ymax = maximum(rawdata.y)
    ysize = Int(ymax - ymin) + 1

    rawdata.x = rawdata.x .- xmin .+1
    rawdata.y = rawdata.y .- ymin .+1

    rawdata
end

function generateDensity(rawdata, target = 80000000, seed = 0)
    Random.seed!(seed)
    xmin = minimum(rawdata.x)
    xmax = maximum(rawdata.x)
    xsize = Int(xmax - xmin) + 1

    ymin = minimum(rawdata.y)
    ymax = maximum(rawdata.y)
    ysize = Int(ymax - ymin) + 1
    # empty map
    densitymap = zeros(Int64, xsize, ysize)
    println("$(nrow(rawdata)) sets of data.")
    for i in 1:nrow(rawdata)
        value = rawdata[i,:Einwohner]
        x = Int(rawdata.x[i])
        y = Int(rawdata.y[i])
        densitymap[x, y] = translateDensity(value)
    end

    correctionfactor = target / sum(densitymap)
    densitymap = (x->Int.(round(x))).(densitymap' .* correctionfactor)

end

rawdata = getDensityData()
fullmap = generateDensity(rawdata, 80000, 123123123)
sum(fullmap)
gr()
heatmap(fullmap)

function model_initiation(;beta_undet, beta_det, densitymap, infection_period = 8, reinfection_probability = 0.02,
    detection_time = 14, death_rate = 0.02, seed=0)#Is infected per city, starts with 1 infected

    Random.seed!(seed)
    properties = Dict(:beta_det=> beta_det, :beta_undet=>beta_undet,
    :infection_period=>infection_period, :reinfection_probability=>reinfection_probability,
    :detection_time=>detection_time, :death_rate=> death_rate)

    xsize = width(densitymap)
    ysize = height(densitymap)
    space = Space((xsize, ysize), moore = true)
    model = ABM(agent, space; properties=properties)

    #add individuals
    i = 1
    for x in 1:xsize, y in 1:ysize
        if densitymap[y,x] > 0
            for j in 1:densitymap[y,x]
                a = agent(i, (x,y), 0, :S)
                add_agent_pos!(a, model)
                i += 1
            end
        end
    end

    #add random infected individuals close to munich with a low percentage in  the area
    for x in 400:410, y in 100:110
        inds = get_node_contents((x,y), model)
        for n in inds
            if rand()<0.1
                agent = id2agent(n, model)
                agent.status = :I
                agent.days_infected = 1
            end
        end
    end

    return model
end

params = Dict(
:beta_det=> 1,
:beta_undet=> 3,
:infection_period=> 10,
:reinfection_probability=> 0.01,
:detection_time=> 6,
:death_rate=> 0.02)

#=
#old plotting method
plotargs = (node_size	= 0.2, method = :circular, linealpha = 0.4)
plotabm(model; plotargs...)
#modify edges so that the reflect migration rate
g = model.space.graph
edgewidthsdict = Dict()
for node in 1:nv(g)
    nbs = neighbors(g, node)
    for nb in nbs
        edgewidthsdict[(node, nb)] = params[:migration_rates][node,nb]
    end
end

#and show it
edgewidthsf(s,d,w) = edgewidthsdict[(s,d)]*250
plotargs = merge(plotargs, (edgewidth = edgewidthsf,))
plotabm(model; plotargs...)

#color node with ratio of infected
infected_fraction(x) = cgrad(:inferno)[count(a.status == :I for a in x)/length(x)]
plotabm(model, infected_fraction; plotargs...)
=#

function agent_step!(agent, model)
    migrate!(agent, model)
    transmit!(agent,model)
    update!(agent,model)
    recover_or_die!(agent,model)
end

function migrate!(agent, model)
    #if he wants to move
    if rand()<0.005
        #get random coordinates
        dims = model.space.dimensions
        randx = rand(1:1:dims[1])
        randy = rand(1:1:dims[2])
        while length(get_node_contents((randx,randy), model))==0
            randx = rand(1:1:dims[1])
            randy = rand(1:1:dims[2])
        end
        #and move the agent to a none-empty place
        if length(get_node_contents((randx,randy), model))>1
            move_agent!(agent,(randx,randy), model)
        end
    end
end

function transmit!(agent, model)
    #cant transmit if healthy/recovered
    agent.status == :S && return
    agent.status == :R && return
    prop = model.properties

    #set the detected/undetected infection rate, also check if he doesnt show symptoms
    rate = if agent.days_infected >= prop[:detection_time] && rand()<=0.8
            prop[:beta_det]
    else
        prop[:beta_undet]
    end

    d = Poisson(rate)
    n = rand(d) #determine number of people to infect, based on the rate
    n == 0 && return #skip if probability of infection =0
    timeout = n*2
    t = 0
    #infect the number of contacts and then return
    #node_contents = get_node_contents(agent, model)
    neighbors = node_neighbors(agent, model)

    #trying to infect n others from random neighbor node, timeout if in a node without
    while n > 0 && t < timeout
        node = rand(neighbors)
        contents = get_node_contents(node, model)
        if length(contents)>1
            infected = id2agent(rand(contents), model)
            if infected.status == :S || (infected.status == :R && rand() <= prop[:reinfection_probability])
                infected.status = :I
                n -= 1
            end
        end
        t +=1
    end
end

update!(agent, model) = agent.status == :I && (agent.days_infected +=1)

function recover_or_die!(agent, model)
    if agent.days_infected >= model.properties[:infection_period]
        if rand() <= model.properties[:death_rate]
            kill_agent!(agent, model)
        else
            agent.status = :R
            agent.days_infected = 0
        end
    end
end


model = model_initiation(densitymap = fullmap; params...)

#Plot of overall SIR count

infected(x) = count(i == :I for i in x)
recovered(x) = count(i == :R for i in x)
susceptible(x) = count(i == :S for i in x)
data_to_collect = Dict(:status => [infected, recovered, susceptible, length])
data = step!(model, agent_step!, 100, data_to_collect)
N = sum(fullmap) # Total initial population
x = data.step
p = Plots.plot(x, log10.(data[:, Symbol("infected(status)")]), label = "infected")
plot!(p, x, log10.(data[:, Symbol("recovered(status)")]), label = "recovered")
plot!(p, x, log10.(data[:, Symbol("susceptible(status)")]), label = "susceptible")
dead = log10.(N .- data[:, Symbol("length(status)")])
plot!(p, x, dead, label = "dead")
xlabel!(p, "steps")
ylabel!(p, "log( count )")
p

#Animation of spatial spread
properties = [:status, :pos]
#plot the ith step of the simulation
anim = @animate for i ∈ 1:50
    data = step!(model, agent_step!, 1, properties)
    p = plot2D(data, :status, nodesize=3)
    title!(p, "Day $(i)")
end
gif(anim, "covid_evolution.gif", fps = 3);