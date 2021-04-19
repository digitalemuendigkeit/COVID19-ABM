using Distributed
using Agents, Random, DataFrames, LightGraphs, CSV, Plots, HypothesisTests, Distances
using Gadfly, Interact, Compose, Printf, Reactive, ColorSchemes

include("SpatialSetup.jl") #exports setup
include("Visualization.jl")# exports draw_route(model,lat,long) and draw_map(model,lat,long), create_chart(steps), create_gif(steps)
include("UtilityFunctions.jl")# exports add_infected(number),reset_infected(model),restart_model(agents,steps) and scale(min_m,max_m,min_t,max_t,m)
include("Validation.jl")#provides validation with parallel runs and plotting
include("SteppingFunction.jl")#exports agent_week!

#agent and params setup
@everywhere mutable struct DemoAgent <: AbstractAgent
    id::Int
    pos::Int
    health_status::Symbol #reflects the SIR extended states (Susceptible, Exposed, Infected, InfectedWitoutSymptpms, NotQuarantined, Quarantined, Dead, Immune)
    days_infected::Int16
    attitude::Int16
    original_attitude::Int16
    fear::Float32
    behavior::Int16
    acquaintances_growth::Int32
    women::Bool
    age::Int8
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
parameters = Dict(
            :infection_period=> 10,
            :exposed_period=>5,
            :infected_now=> 0,
            :infected_reported=>0,
            :norms_message=>0,
            :daily_cases=>0,
            :daily_mobility=>0,
            :daily_contact=>0,
            :work_closes=>21,
            :work_opens=>70,
            :days_passed => 0)

#initialize the model and generate the map - takes about 115s for 13.000 agents
model,lat,long,social_groups, distant_groups = setup(parameters)

#if I want to load or save workspaces
#using JLD2
#@save "workspacefile_aachen.jl" model social_groups distant_groups lat long
#@load "workspacefile.jl" model social_groups distant_groups lat long

#add workers and make the packages, functions etc. available for all of them
addprocs(7)
@everywhere using Agents, Random, DataFrames, LightGraphs, CSV, Plots, Bootstrap
@everywhere using StatsBase, Distributions, Statistics,Distributed, GraphPlot, GraphRecipes, AgentsPlots, StatsPlots, Luxor, LightGraphs, OpenStreetMapX
include("UtilityFunctions.jl")# exports add_infected(number),reset_infected(model)
include("SteppingFunction.jl")#exports agent_week!
include("Validation.jl")#provides validation with parallel runs and plotting

#make important data available as well - eval evaluates expression on global scope, everywhere makes it available for all workers, what does $do?
@everywhere mutable struct DemoAgent <: AbstractAgent
    id::Int
    pos::Int
    health_status::Symbol
    days_infected::Int16
    attitude::Int16
    original_attitude::Int16
    fear::Float32
    behavior::Int16
    acquaintances_growth::Int32
    women::Bool
    age::Int8
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
@eval @everywhere model = $model
@eval @everywhere social_groups = $social_groups
@eval @everywhere distant_groups = $distant_groups

@time test = run_parallel(model,social_groups,distant_groups,16,7)
