@everywhere function add_infected(x,model)
    for i in 1:x
        agent = random_agent(model)
        #have at least two other contacts so we dont initialize in some underpopulated position
        while length(get_node_contents(agent.pos, model)) < 3
            agent = random_agent(model)
        end
        agent.health_status = :E
    end
end

function reset_infected(model)
    all_agents = collect(allagents(model))
    for agent in all_agents
        agent.health_status = :S
        agent.fear = 0
        agent.behavior = 0
        agent.days_infected = 0
    end
    model.properties[:days_passed] = 0
end

function reset_model_parallel(agents)
    reset_infected(model)
    #add_infected(agents)
    @eval @everywhere model = $model
end

function restart_model(agents,steps)
    reset_infected(model)
    add_infected(agents)
    create_chart(steps)
end

function get_validation_data()
    #get the case data from germany
    csv_raw = CSV.read("SourceData\\Fear_Data.csv", DataFrame;delim=";")
    DataFrames.rename!(csv_raw,[:x,:y])
    csv_raw.x = [round(parse(Float16,replace(x,","=>"."))) for x in csv_raw.x]
    csv_raw.y = [round(parse(Float16,replace(x,","=>"."))) for x in csv_raw.y]
    sort(csv_raw,:x)
    #prepend some data as guess for the trend
    fear_yougov_prepend = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,2,3,6,9,14,18,21,25,28,31]
    #try to delete row 3, doesnt work so far.
    csv_raw = csv_raw[setdiff(1:end, 3), :]
    #parse the strings to Float16s
    #starting at the 16.03.
    #adding the missing month, since the graph only starts from the 16.03. and not as the model the 14.02.
    fear_yougov = vcat(fear_yougov_prepend,csv_raw.y)
    #scale it to 125
    fear_real = fear_yougov.*2.7

    #get behavior data
    csv_raw = CSV.read("SourceData\\Mobility_Behavior_Data.csv",DataFrame)
    behavior_real = csv_raw.Value
    behavior_real = behavior_real.*1.4

    #get infection data
    csv_infections = CSV.read("SourceData\\Infection_Data.csv",DataFrame)
    csv_infections = filter(x -> x[Symbol("Country/Region")] == "Germany",csv_infections)
    #get cases from the 14.02., the start date of the model and five more months
    csv_infections = csv_infections.infections[46:200]
    #both start with 1 infection
    infections_real = csv_infections ./ 25

    return fear_real, behavior_real, infections_real
end

function plot_model_demographics(infected,known_infected,mobility_cases,contact_cases)
    #remove first bogus column and average
    known_infected = known_infected[1:end, 2:end]
    known_inf = mean(known_infected, dims=2)
    IwS = IwS[1:end, 2:end]
    IwS = mean(IwS, dims=2)
    infected = infected[1:end, 2:end]
    inf = mean(infected,dims=2)
    println("known_infected $known_inf")
    println("infected $(inf)")
    println("last percentage $(known_inf[end]/inf[end])")
    Plots.plot(inf,label="infected")
    display(Plots.plot!(IwS, label="known_infected"))

    #same with mobility contact cases
    mobility_cases = mobility_cases[1:end, 2:end]
    contact_cases = contact_cases[1:end, 2:end]
    mobility_cases = mean(mobility_cases, dims=2)
    contact_cases = mean(contact_cases, dims=2)
    println("mobility $(mobility_cases[end]), contact $(contact_cases[end]))")
    Plots.plot(mobility_cases, label="mobility_cases")
    display(Plots.plot!(contact_cases,label="contact_cases"))
    return
end

#a nice function that scales input
@everywhere function scale(min_m,max_m,min_t,max_t,m)
    return (m-min_m)/(max_m-min_m)*(max_t-min_t)+min_t
end

export add_infected,reset_infected,restart_model, scale, reset_model_parallel, get_validation_data, plot_model_demographics
