function draw_initial_map(model,lat,long)
    N = Agents.nodes(model)
    ncolor = Vector(undef, length(N))
    nodesizevec = Vector(undef, length(N))
    #color and size the nodes according to the population
    #could set size to population and color to other attributes (sickness, belief,...)
    for (i, n) in enumerate(N)
        a = get_node_agents(n, model)
        #set color for empty nodes and populated nodes
        b = [agent.workplace for agent in a]
        b = mean(b)

        #ncolor[i]=cgrad(:]inferno)[mean(b)/10]
        b==0 ? ncolor[i]=RGBA(1.0, 1.0, 1.0, 0.6) : ncolor[i]=RGBA(0.0, 0.6, 0.6, 0.8)
        length(a)==0 ? nodesizevec[i] = 2 : nodesizevec[i] = 3
    end
    p = gplot(model.space.graph, long, lat, nodefillc=ncolor, nodesize=nodesizevec)
    return p
end

function draw_map(model,lat,long)
    N = Agents.nodes(model)
    ncolor = Vector(undef, length(N))
    nodesizevec = Vector(undef, length(N))
    for i in N
        a = get_node_agents(i, model)
        #set color for empty nodes and populated nodes
        b = [agent.behavior for agent in a]
        b = mean(b)
        #catch empty nodes, scale others up to 256 colors and set the cgrad
        isnan(b) && (b = 1)
        b = scale(0,158,0,256,b)
        #finding out that the input has to be an int or else it will turn mad took only like, 4 hours?
        b = round(b)
        b = Int16(b)
        b == 0 && (b = 1)
        b > 256 && (b = 256)
        ncolor[i]=cgrad(:inferno)[b]
        #get infected agents#
        c = count(agent -> in(agent.health_status,(:E,:IwS,:Q,:NQ,:HS)),a)
        #set nodesize according to number of infected agents
        length(a)==0 ? nodesizevec[i] = 0.5 : nodesizevec[i] = c
        #b > 20 && println("for node $i color is $(ncolor[i]) while cgrad is $(cgrad(:inferno)[b]) with mean b $b and infected $(c)")
    end
    p = gplot(model.space.graph, long, lat, nodefillc=ncolor, nodesize=nodesizevec)
    return p
end

#paint the edges of edgecolor red for all edges in the route
function generate_edgecolors(route, edgecolors)
    for i in route
        start =  src(i)
        fin = dst(i)
        if has_edge(model.space.graph,start,fin) || has_edge(model.space.graph,fin,start)
            edge1 = LightGraphs.SimpleEdge(start, fin)
            edge2 = LightGraphs.SimpleEdge(fin, start)
            #check for all edges if its equal (forward and backward) to the route edge, if so set color to yellow
            for (index,value) in enumerate(edges(model.space.graph))
                if(value == edge1 || value == edge2 )
                    edgecolors[index] = colorant"red"
                    continue
                end
            end
        end
    end
    return edgecolors
end

function draw_route(model,lat,long)
    #draw random agent and get the route
    agent = random_agent(model)
    workplaceroute = agent.workplaceroute
    socialroute = agent.socialroute
    distantroute = agent.distantroute
    while(length(workplaceroute)<10)
        agent = random_agent(model)
        thisroute = agent.workplaceroute
    end
    #make array of normal edge colors
    edgecolors = [colorant"lightgray" for i in  1:ne(model.space.graph)]
    #and add all routes to edgecolors
    edgecolors = generate_edgecolors(workplaceroute, edgecolors)
    edgecolors = generate_edgecolors(socialroute, edgecolors)
    edgecolors = generate_edgecolors(distantroute, edgecolors)
    #set the home as yellow point in the map
    nodecolors = [colorant"turquoise" for i in  1:ne(model.space.graph)]
    nodecolors[agent.household] = colorant"yellow"
    gplot(model.space.graph, long, lat, edgestrokec=edgecolors, nodefillc=nodecolors)
end

function create_chart(steps)
    #one step is a week!
    b = agent_week!(model, social_groups, distant_groups,steps,false)
    p = Plots.plot(b.infected,label="infected")
    plot!(p,b.susceptible,label="susceptible")
    plot!(p,b.recovered,label="recovered")
    plot!(p,b.mean_fear.*100,label="fear")
    plot!(p,b.mean_behavior.*100,label="behavior")
    plot!(p,b.daily_cases,label="daily cases")
end

function create_gif(steps)
    #call agent week with paint_mode on
    plot_vector = agent_week!(model, social_groups, distant_groups,steps,true)
    #and create an interactive chart that allows you to check the different stages.
    @manipulate throttle = 0.5 for i in 1:length(plot_vector)
            compose(plot_vector[i],(context(),Compose.text(0, -1, "Day $i", hcenter, vcenter)),(context(), rectangle(), fill("turquoise")))
    end
end

export draw_map,draw_route,create_chart, create_gif

#=savefig examples
savefig(a,"Graphics\\example_route.png")
using Compose
draw(PNG("Graphics\\example_route.png",16cm,16cm),a)
=#
set_default_graphic_size(30Plots.cm, 30Plots.cm)
