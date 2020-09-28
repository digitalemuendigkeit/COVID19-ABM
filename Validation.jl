@everywhere function validate_infected(steps)
    reset_infected(model)
    add_infected(1)
    b = agent_week!(model, social_groups, distant_groups,steps,false)
    csv_raw = CSV.read("SourceData\\covid19_ECDC.csv")
    csv_germany = filter(x -> x[Symbol("Country/Region")] == "Germany",csv_raw)
    #get cases from the 14.02., the start date of the model and five more months
    cases_germany = csv_germany.infections[46:200]
    cases_germany = cases_germany ./ 20
    cases_model = b.infected_adjusted
    Plots.plot(b.infected_adjusted,label="infected")
    Plots.plot!(b.daily_mobility,label="inf mobility")
    Plots.plot!(b.daily_contact,label="inf contact")
    result = rmse(cases_germany,cases_model)
end

function validate_fear(steps)
    reset_infected(model)
    add_infected(1)
    b = agent_week!(model, social_groups, distant_groups,steps,false)
    csv_raw = CSV.read("SourceData\\fear_real.csv";delim=";")
    DataFrames.rename!(csv_raw,[:x,:y])
    csv_raw.x = [round(parse(Float16,replace(x,","=>"."))) for x in csv_raw.x]
    csv_raw.y = [round(parse(Float16,replace(x,","=>"."))) for x in csv_raw.y]
    sort(csv_raw,:x)
    #prepend some data as guess for the trend
    fear_real_prepend = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,2,3,6,9,14,18,21,25,28,31]
    #try to delete row 3, doesnt work so far.
    csv_raw = csv_raw[setdiff(1:end, 3), :]
    #parse the strings to Float16s
    #starting at the 16.03.
    #adding the missing month, since the graph only starts from the 16.03. and not as the model the 14.02.
    fear_real = vcat(fear_real_prepend,csv_raw.y)
    fear_real = fear_real.*2
    #using normal fear since fear over 100 isnt consistent at all
    fear_model = b.mean_fear
    #println("rmse is $(rmse(fear_real[1:steps*7],fear_model[1:steps*7]))")
    Plots.plot(fear_real,label="fear_real")
    plot!(fear_model,label="fear_model")
end

function mape(series1, series2)
    errors = [abs((series1[i]-series2[i])/series1[i])*100 for i in 1:length(series2)]
    #replace NaNs,Infs for division by zero
    replace!(x -> (isnan(x) || isinf(x)) ? 0 : x,errors)
    m = (1/length(series2))*sum(errors)
end

function yougov_fit(x)
    return 31.11647 + 2.410283*x - 0.09911214*x^2 + 0.001044297*x^3
end

function run_multiple_fear(model,social_groups,distant_groups,steps,replicates)
    #reset the model for all workers and add 1 infected to it
    reset_model_parallel(1)
    #collect all data in one dataframe
    all_data = pmap(j -> agent_week!(deepcopy(model),social_groups,distant_groups,steps,false), 1:replicates)

    #get the data and average it
    infected = Array{Int32}(undef,steps*7)
    for elm in all_data
        infected = hcat(infected,elm.mean_fear)
    end

    infected = infected[:,setdiff(1:end,1)]
    print(infected)
    infected = mean(infected,dims=2)

    #get the case data from germany
    csv_raw = CSV.read("SourceData\\fear_real.csv";delim=";")
    DataFrames.rename!(csv_raw,[:x,:y])
    csv_raw.x = [round(parse(Float16,replace(x,","=>"."))) for x in csv_raw.x]
    csv_raw.y = [round(parse(Float16,replace(x,","=>"."))) for x in csv_raw.y]
    sort(csv_raw,:x)
    #prepend some data as guess for the trend

    fear_real_prepend = [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,1,1,2,3,6,9,14,18,21,25,28,31]
    #try to delete row 3, doesnt work so far.
    csv_raw = csv_raw[setdiff(1:end, 3), :]
    #parse the strings to Float16s
    #starting at the 16.03.
    #adding the missing month, since the graph only starts from the 16.03. and not as the model the 14.02.
    fear_real = vcat(fear_real_prepend,csv_raw.y)
    #scale it to 100
    fear_real = fear_real.*2

    #plot all results so we have an idea
    Plots.plot(fear_real,label="fear_real")
    display(plot!(infected,label="fear_model"))
    # display(plot!(attitude.*10000,label="attitude"))
    # display(plot!(norms.*10,label="norms"))

    println("fear model are $infected")

    error = mape(fear_real,infected)
    println("error is $error")
    return error
end


function run_multiple_behavior(model,social_groups,distant_groups,steps,replicates)
    reset_model_parallel(1)
    all_data = pmap(j -> agent_week!(deepcopy(model),social_groups,distant_groups,steps,false), 1:replicates)
    infected = Array{Int32}(undef,steps*7)
    for elm in all_data
        infected = hcat(infected,elm.mean_behavior)
    end

    infected = infected[:,setdiff(1:end,1)]
    infected = mean(infected,dims=2)
    println(infected)
    csv_raw = CSV.read("SourceData\\Mobility_Data.csv")
    Plots.plot(csv_raw.Value,label="behavior_real")
    display(plot!(infected,label="behavior_model"))

    error = mape(csv_raw.Value,infected)
    println("error is $error")
    return error
end

function run_multiple_both(model,social_groups,distant_groups,steps,replicates,enable_bootstrap)
    reset_model_parallel(1)
    all_data = pmap(j -> agent_week!(deepcopy(model),social_groups,distant_groups,steps,false), 1:replicates)
    println("finished computation of data")
    behavior = Array{Int32}(undef,steps*7)
    fear = Array{Int32}(undef,steps*7)
    infected = Array{Int32}(undef,steps*7)
    infected_bars = Array{Int32}(undef,steps*7)
    infected_no_adj = Array{Int32}(undef,steps*7)
    known_infected = Array{Int32}(undef,steps*7)
    mobility_cases = Array{Int32}(undef,steps*7)
    contact_cases = Array{Int32}(undef,steps*7)

    for elm in all_data
        behavior = hcat(behavior,elm.mean_behavior)
        infected = hcat(infected, elm.infected_adjusted)
        infected_bars = hcat(infected_bars, elm.daily_cases)
        infected_no_adj = hcat(infected_no_adj, elm.infected)

        known_infected = hcat(known_infected, elm.known_infected)
        mobility_cases = hcat(mobility_cases, elm.daily_mobility)
        contact_cases = hcat(contact_cases, elm.daily_contact)

        fear = hcat(fear,elm.mean_fear)
    end

    inf_no_adj = mean(infected_no_adj, dims=2)
    known_inf = mean(known_infected, dims=2)
    println("no adj $inf_no_adj")
    println("known_infected $known_infected")

    Plots.plot(inf_no_adj,label="infected_no_adj")
    Plots.plot!(mean(infected,dims=2),label="infected")
    display(Plots.plot!(known_inf, label="known_infected"))

    mobility_cases = mean(mobility_cases, dims=2)
    contact_cases = mean(contact_cases, dims=2)
    Plots.plot(mobility_cases, label="mobility_cases")
    display(Plots.plot!(contact_cases,label="contact_cases"))

    println("known infected is $(mean(known_infected, dims=2))")
    #delete first column that has garbage in it for some reason
    behavior = behavior[:,setdiff(1:end,1)]
    fear = fear[:,setdiff(1:end,1)]
    infected = infected[:,setdiff(1:end,1)]
    infected_bars = infected_bars[:,setdiff(1:end,1)]
    infected_no_adj = infected_no_adj[:,setdiff(1:end,1)]

    behavior_low = Array{Float64}(undef,steps*7)
    behavior_mean = Array{Float64}(undef,steps*7)
    behavior_high = Array{Float64}(undef,steps*7)
    if enable_bootstrap
        #for each row of samples, draw 10.000 samples and calculate the 2.5% CIs
        for row in eachrow(behavior)
            bs1 = bootstrap(mean, row, BasicSampling(5000))
            bs975ci = confint(bs1,PercentileConfInt(0.95))
            #and push it to the corresponding array
            #println(bs975ci)
            push!(behavior_low, bs975ci[1][2])
            push!(behavior_mean, bs975ci[1][1])
            push!(behavior_high, bs975ci[1][3])
        end
    end

    fear_low = Array{Float64}(undef,steps*7)
    fear_mean = Array{Float64}(undef,steps*7)
    fear_high = Array{Float64}(undef,steps*7)
    if enable_bootstrap
        #for each row of samples, draw 10.000 samples and calculate the 2.5% CIs
        for row in eachrow(fear)
            bs1 = bootstrap(mean, row, BasicSampling(5000))
            bs975ci = confint(bs1,PercentileConfInt(0.95))
            #and push it to the corresponding array
            push!(fear_low, bs975ci[1][2])
            push!(fear_mean, bs975ci[1][1])
            push!(fear_high, bs975ci[1][3])
        end
    end

    infected_low = Array{Float64}(undef,steps*7)
    infected_mean = Array{Float64}(undef,steps*7)
    infected_high = Array{Float64}(undef,steps*7)
    if enable_bootstrap
        #for each row of samples, draw 10.000 samples and calculate the 2.5% CIs
        for row in eachrow(infected)
            bs1 = bootstrap(mean, row, BasicSampling(5000))
            bs975ci = confint(bs1,PercentileConfInt(0.95))
            #and push it to the corresponding array
            push!(infected_low, bs975ci[1][2])
            push!(infected_mean, bs975ci[1][1])
            push!(infected_high, bs975ci[1][3])
        end
    end

    infected_bars_mean = Array{Float64}(undef,steps*7)
    if enable_bootstrap
        #for each row of samples, draw 10.000 samples and calculate the 2.5% CIs
        for row in eachrow(infected_bars)
            bs1 = bootstrap(mean, row, BasicSampling(5000))
            bs975ci = confint(bs1,PercentileConfInt(0.95))
            #and push it to the corresponding array
            push!(infected_bars_mean, bs975ci[1][1])
        end
    end

    fear_real, behavior_real, infected_real = get_validation_data()

    #remove leftover data that somehov gets prepended to CI data
    timeline_gap = length(fear_mean)-steps*7+1
    fear_mean = fear_mean[timeline_gap:end]
    fear_low = fear_low[timeline_gap:end]
    fear_high = fear_high[timeline_gap:end]
    behavior_mean = behavior_mean[timeline_gap:end]
    behavior_low = behavior_low[timeline_gap:end]
    behavior_high = behavior_high[timeline_gap:end]
    infected_mean = infected_mean[timeline_gap:end]
    infected_low = infected_low[timeline_gap:end]
    infected_high = infected_high[timeline_gap:end]
    infected_bars_mean = infected_bars_mean[timeline_gap:end]

    fear_return = (fear_low,fear_mean,fear_high)
    behavior_return = (behavior_low,behavior_mean,behavior_high)
    infected_return = (infected_low,infected_mean,infected_high)

    fear_real = fear_real[1:steps*7]
    behavior_real = behavior_real[1:steps*7]
    infected_real = infected_real[1:steps*7]


    # Plots.plot(csv_raw.Value.*100,label="behavior_real")
    # plot!(infected_real,label="infected_real")
    # plot!(infected,label="infected_model")
    Plots.plot(fear_mean,label="fear_model", ribbon = (fear_mean.-fear_low,fear_high.-fear_low), legend=:topleft, xlabel="Days", ylabel="Attribute Strength", seriescolor=:viridis)
    plot!(fear_real,label="fear_real")
    #Plots.bar!(infected_bars_mean, label="daily_cases", fillcolor = :lightblue)
    plot!(behavior_real,label="behavior_real")
    display(plot!(behavior_mean,label="behavior_model", ribbon = (behavior_mean.-behavior_low,behavior_high.-behavior_mean)))

    Plots.plot(infected_mean,label="infected_model", ribbon = (infected_mean.-infected_low,infected_mean.-infected_low),legend=:topleft,xlabel="Days", ylabel="Total Infections")
    #Plots.bar!(infected_bars_mean, label="daily_cases", fillcolor = :lightblue)
    display(plot!(infected_real,label="infected_real"))

    error = mape(behavior_real,behavior_mean)
    println("error behavior is $error")
    #println("behavior data is $behavior")
    error = mape(fear_real,fear_mean)
    println("error fear is $error")
    #println("fear data is $fear")
    error = mape(infected_real,infected_mean)
    println("error infected is $error")
    #println("infected data is $infected")

    #MAPEs
    error = mape(fear_real,fear_mean)
    println("error fear is $error")
    error = mape(behavior_real,behavior_mean)
    println("error behavior is $error")
    error = mape(infected_real,infected_mean)
    println("error infected is $error")
    #compute RMSE
    println("RMSE Fear is $(Distances.nrmsd(fear_mean,fear_real))")
    println("RMSE Behavior is $(Distances.nrmsd(behavior_mean,behavior_real))")
    println("RMSE Infected is $(Distances.nrmsd(infected_mean,infected_real))")
    #compute MAE%
    println("MAE% Fear is $(Distances.meanad(fear_mean,fear_real)/mean(fear_real))")
    println("MAE% Behavior is $(Distances.meanad(behavior_mean,behavior_real)/mean(behavior_real))")
    println("MAE% Infected is $(Distances.meanad(infected_mean,infected_real)/mean(infected_real))")
    #compute F-Test
    println("F-Test Fear is $(VarianceFTest(fear_mean,fear_real))")
    println("F-Test Behavior is $(VarianceFTest(behavior_mean,behavior_real))")
    println("F-Test Infected is $(VarianceFTest(infected_real,infected_mean))")
    println("total infected is $(infected_mean[25]) percent is $(infected_mean[25]/nagents(model))")
    println("total infected is $(infected_mean[50]) percent is $(infected_mean[50]/nagents(model))")
    println("total infected is $(infected_mean[75]) percent is $(infected_mean[75]/nagents(model))")
    println("total infected is $(infected_mean[100]) percent is $(infected_mean[100]/nagents(model))")

    #MAPEs 70s
    # error = mape(fear_real[1:70],fear_mean[1:70])
    # println("error fear 1-70is $error")
    # error = mape(behavior_real[1:70],behavior_mean[1:70])
    # println("error behavior is $error")
    # error = mape(infected_real[1:70],infected_mean[1:70])
    # println("error infected is $error")
    # #compute RMSE
    # println("RMSE Fear is $(Distances.nrmsd(fear_mean[1:70],fear_real[1:70]))")
    # println("RMSE Behavior is $(Distances.nrmsd(behavior_mean[1:70],behavior_real[1:70]))")
    # println("RMSE Infected is $(Distances.nrmsd(infected_mean[1:70],infected_real[1:70]))")
    # #compute MAE%
    # println("MAE% Fear is $(Distances.meanad(fear_mean[1:70],fear_real[1:70])/mean(fear_real[1:70]))")
    # println("MAE% Behavior is $(Distances.meanad(behavior_mean[1:70],behavior_real[1:70])/mean(behavior_real[1:70]))")
    # println("MAE% Infected is $(Distances.meanad(infected_mean[1:70],infected_real[1:70])/mean(infected_real[1:70]))")
    return (fear_return,behavior_return,infected_return)
end

#1. normal, 2. old fear model, 3.no messages
print(run_multiple_both(model,social_groups,distant_groups,12,6,true))
# print("Last run was no messages, only individual fear")


# 8ZjyCRiBWFYkneahHwxCv3wb2a1ORpYL
# 4wcYUJFw0k0XLShlDzztnTBHiqxU3b3e
# 15 BfMYroe26WYalil77FoDi9qh59eK5xNr
# 16 cluFn7wTiGryunymYOu4RcffSxQluehd
# 18 kfBf3eYk5BPBRzwjqutbbfE887SVc5Yd - w0Yfolrc5bwjS4qw5mq1nnQi6mF03bii
# 19 IueksS7Ubh8G3DCwVzrTd8rAVOwq3M5x
# 20 GbKksEFF4yrVs6il55v6gwY5aVje5f0j
# 21 gE269g2h3mw3pwgrj0Ha9Uoqen1c9DGr
