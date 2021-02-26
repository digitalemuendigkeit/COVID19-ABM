@everywhere function agent_week!(model, social_groups, distant_groups,steps,paint_mode)
    #set up data structure to capture run infos
    agent_data = DataFrame(step=Int64[],infected=Int64[],recovered=Int64[],susceptible=Int64[],mean_behavior=Int64[],mean_fear=Float32[],behavior=Float32[],fear_over=Float32[],known_infected=Float32[],daily_cases=Int32[],daily_mobility=Int32[],daily_contact=Int32[],days_passed=Int32[],infected_adjusted=Int64[],IwS=Int64[])
    infected_timeline = Vector{Int32}(undef,0)
    infected_timeline_growth = Vector{Int32}(undef,0)
    iws_timeline = Vector{Int32}(undef,0)
    infection_age = Vector{Int32}(undef,0)
    death_age = Vector{Int32}(undef,0)
    #initialize the timline
    push!(infected_timeline,0)
    push!(infected_timeline_growth,100)
    #attitude, norms = read_message_data()
    #create a vector of plots if we want to create a GIF of the spread
    paint_mode && (plot_vector = Vector{Compose.Context}(undef,0))
    add_infected(1,model)
    for step in 1:steps
        for i in 1:7
            model.days_passed+=1
            #send_messages(model.days_passed,attitude,norms)
            #select social&distant active groups randomly, more agents are social active on the weekend
            if i < 6
                social_active_group = rand(social_groups,Int.(round.(length(social_groups)/10)))
                distant_active_group = rand(distant_groups,Int.(round.(length(distant_groups)/10)))
            else
                social_active_group = rand(social_groups,Int.(round.(length(social_groups)/3)))
                distant_active_group = rand(distant_groups,Int.(round.(length(distant_groups)/3)))
            end
            infected_edges = Vector{Int32}(undef,0)
            #to avoid costly recomputation in behavior, we collect all agents once and then use it in behavior
            all_agents = collect(allagents(model))

            #fill the iws timeline with value from last day so it can add up
            push!(iws_timeline,0)
            if model.properties[:days_passed] > 1
                iws_timeline[model.properties[:days_passed]]=iws_timeline[model.properties[:days_passed]-1]
            else
                iws_timeline[model.properties[:days_passed]] = 0
            end
            #run the model
            day_data = agent_day!(model, social_active_group, distant_active_group,infected_edges,all_agents,infected_timeline,infected_timeline_growth,iws_timeline,infection_age,death_age)
            #update the count of infected now and reported
            infected_count = last(infected_timeline)+model.properties[:daily_cases]
            push!(infected_timeline,infected_count)

            #get the current case growth
            if (length(infected_timeline)>1)
                today = infected_timeline[length(infected_timeline)]
                before = infected_timeline[length(infected_timeline)-1]
            else
                today = 100
                before = 100
            end
            push!(infected_timeline_growth,case_growth(today, before))

            model.infected_now = infected_count
            model.properties[:daily_cases] = 0
            #delay the reported infections by two days as Verzug COronadaten shows https://www.ndr.de/nachrichten/info/Coronavirus-Neue-Daten-stellen-Epidemie-Verlauf-infrage,corona2536.html
            #nowcast shows 3 days delay and 10% less infected as report delay
            length(infected_timeline)<4 ? model.infected_reported=round(last(infected_timeline)*0.9) : model.infected_reported = infected_timeline[length(infected_timeline)-3]
            # println("infected timeline is $infected_timeline")
            #println("infected growth is $infected_timeline_growth")
            # println("at time $(model.days_passed)")
            #and add the data to the dataframe
            append!(agent_data,day_data)
            #add the plot to the plot_vector if enabled
            paint_mode && (push!(plot_vector,draw_map(model,lat,long)))
        end
        #reset norms message property in each case so that it can be reactived when needed
        model.properties[:norms_message] = false
    end
    #return the data of the model if creating a chart and return plot vector if making a GIF
    #println("infection age is $infection_age")
    #println("death age is $death_age")
    #println("nr infected is $(infected_timeline[end])")
    if paint_mode return plot_vector else return agent_data end
end

@everywhere function read_message_data()
    rawdata_attitude = DataFrame!(CSV.File("SourceData\\attitude.csv",silencewarnings=true))
    #remove the first month so we start at the 14.02.2020 (16 cases in all of germany), no news found until then
    rawdata_attitude = rawdata_attitude[31:end,:]
    attitude = rawdata_attitude.Value
    rawdata_norms = DataFrame!(CSV.File("SourceData\\norms.csv",silencewarnings=true))
    rawdata_norms = rawdata_norms[41:end,:]
    norms = rawdata_norms.Value
    norms_data = rawdata_norms.Date
    return attitude, norms
end

@everywhere function send_messages(day,attitude,norms)
    attitude_message_frequency = round(attitude_frequency(day,attitude))
    norm_message_frequency = round(norm_frequency(day,norms))
    #println("frequencys are $attitude_message_frequency for attitude and $norm_message_frequency for norms at day $day")
    if day % attitude_message_frequency == 0
        send_attitude()
    end
    if day % norm_message_frequency == 0
        send_norms()
    end
end

@everywhere function attitude_frequency(day,attitude)
    #send at least every ten days and at most each day a message
    value = 10-attitude[day]*1000
    value < 1 && (value = 1)
    value > 10 && (value = 10)
    return value
end

@everywhere function norm_frequency(day,norm)
    #send at least every ten days and at most each day a message
    value = round(10-norm[day]*1/3)
    value < 1 && (value = 1)
    value > 10 && (value = 10)
    return value
end

@everywhere function send_norms()
    #slightly increase attitude by setting model parameter which influences norm calculation in agent behavior function
    model.properties[:norms_message] = model.days_passed
end

@everywhere function send_attitude()
    all_agents = collect(allagents(model))
    [agent.attitude = Int16(round(property_growth(agent.attitude))) for agent in all_agents]
end

@everywhere function fear_growth(case_growth,personal_cases)
    #lambda = max attainable fear factor -> 2?
    #us - unconditioned stimuli, cs - conditioned stimuli -> merge both to one stimuli, cases
    #return fear change of 1 if both rates are 1
    return Int16(round(100*2.2*(1-ℯ^(-case_growth*personal_cases))))
end

@everywhere function property_growth(property)
    #scale the attitude to fit e
    property_factor = scale(0,170,0,3,property)
    #return it with an increase of max. 1.58
    return property*(1+ℯ^(-property_factor))
end

@everywhere function attitude_decay(original_attitude, attitude)
    #has to decay back to regular attitude value
    unscaled_attitude=copy(attitude)
    #scale both values and get the difference
    original_attitude = scale(0,158,0,2,original_attitude)
    attitude = scale(0,158,0,2,attitude)
    difference = attitude-original_attitude
    #decrease the attitude the bigger  the difference
    return round(unscaled_attitude*(ℯ^(-difference/2)))
end

@everywhere function norm_decay(norm,time)
    #modify norms so that it decays over time
    return norm*ℯ^(-(time/340))
end

@everywhere function fear_decay(fear,time)
    #modify fear so that it decays over time
    return fear*ℯ^(-(time/150))
end

@everywhere function case_growth(today,before)
    if !in(0,(today,before))
        return Int16(round(100*(today/before)))
    else
        return 100
    end
end

#mossong 2008, contacts by age,
@everywhere function contacts_reworked(input)
    y = 11.17771 + 0.5156303*input - 0.01447889*input^2 + 0.00009245592*input^3
    return y
end

@everywhere function agent_day!(model, social_active_group, distant_active_group,infected_edges,all_agents,infected_timeline,infected_timeline_growth,iws_timeline,infection_age,death_age)

    #put functions within parent scope so we can read from this scope
    function move_infect!(agent)
        if agent.health_status == :Q || agent.health_status == :HS
            #if agent is quarantined or has heavy symptoms
            #agent goes home and does not move
            if agent.pos != agent.household
                move_agent!(agent,agent.household,model)
                return false
            else
                return false
            end
        elseif in(agent.health_status, (:E,:IwS,:NQ))
            #if agent is infected and moves, add edges on his way to the array of infected edges
            if time_of_day == :work || time_of_day == :work_back
                append!(infected_edges, collect(dst.(agent.workplaceroute)))
                append!(infected_edges, collect(src.(agent.workplaceroute)))
            elseif time_of_day == :social || time_of_day == :social_back
                append!(infected_edges, collect(dst.(agent.socialroute)))
                append!(infected_edges, collect(src.(agent.socialroute)))
            end
            return true
        elseif agent.health_status == :S
            #if not, see if the agents route coincides with the pool and see if the agent gets infected by this.
            if time_of_day == :work || time_of_day == :back_work
                possible_edges = length(filter(x -> in(x,infected_edges),vcat(collect(dst.(agent.workplaceroute)),collect(src.(agent.workplaceroute)))))
            elseif time_of_day == :social || time_of_day == :back_social
                possible_edges = length(filter(x -> in(x,infected_edges),vcat(collect(dst.(agent.socialroute)),collect(src.(agent.socialroute)))))
            end

            #if our route coincides with the daily route of others
            if (possible_edges>0)
                agent.behavior > 60 ? risk = 3.66 : risk = 9.5
                #use agent wealth as additional factor
                wealth_modificator = agent.wealth/208
                wealth_modificator < 0.01 && (wealth_modificator = 0.01)
                wealth_modificator > 1.9 && (wealth_modificator = 1.9)
                #risk increases when agentf
                risk=risk*(2-wealth_modificator)
                risk = risk*0.8
                #test for adjusting infection frequencys
                #see if the agent gets infected. Risk is taken from Chu 2020, /100 for scale and *0.03 for mossong travel rate of 3 perc of contacts and /10 for scale
                if rand(Binomial(possible_edges,(risk/1000)*0.003)) >= 1
                    agent.health_status = :E
                    model.properties[:daily_cases]+=1
                    model.properties[:daily_mobility]+=1
                    push!(infection_age,agent.wealth)
                end
            end
            return true
        end
    end

    function move_step!(agent, model)
        #check which time of day it is, then calculate move infection if not in quarantine, and finally move the agent
        if time_of_day == :work && agent.workplace != 0
            if model.properties[:work_closes] < model.properties[:days_passed] < model.properties[:work_opens] && 19 < agent.age <63 && rand()<0.498
                return
            end
            #schools closed, opening about in august
            if model.properties[:work_closes] < model.properties[:days_passed] < 175  && (4 < agent.age <19)
                return
            end
            #gradually reopening work
            percent_sd = (model.properties[:days_passed]-60)/50
            if model.properties[:days_passed] > model.properties[:work_opens] && rand()> percent_sd
                return
            end
            #on the weekends, only ~27% go to work
            if length(social_active_group)==Int(round(length(social_groups)/3)) && rand() > 0.0276
                return
            end
            move = move_infect!(agent)
            move == true && move_agent!(agent,agent.workplace,model)
        elseif time_of_day == :social && in(agent.socialgroup, social_active_group)
            #skip social interaction, ie. social distancing, when behavior is active and everything is closed
            if model.properties[:work_closes] < model.properties[:days_passed] < model.properties[:work_opens] && agent.behavior > 60 && rand()<0.9
                return
            end
            #gradually increase the percentage not SD after the lockdown has ended
            percent_sd = (model.properties[:days_passed]-60)/50
            if model.properties[:days_passed] > model.properties[:work_opens] && rand()> percent_sd
                return
            end
            move = move_infect!(agent)
            move == true && move_agent!(agent,agent.socialgroup,model)
        elseif time_of_day == :social && in(agent.distantgroup, distant_active_group)
            if model.properties[:work_closes] < model.properties[:days_passed] < model.properties[:work_opens] && agent.behavior > 60 && rand()<0.9
                return
            end
            percent_sd = (model.properties[:days_passed]-60)/50
            if model.properties[:days_passed] > model.properties[:work_opens] && rand()> percent_sd
                return
            end
            move = move_infect!(agent)
            move == true && move_agent!(agent,agent.distantgroup,model)
        else
            #move back home
            move = move_infect!(agent)
            move == true && move_agent!(agent,agent.household,model)
        end
    end

    function infect_step!(agent, model)
        agent.health_status == :D && return
        behavior!(agent,model)
        transmit!(agent,model)
        update!(agent,model)
        recover_or_die!(agent,model)
    end

    function behavior!(agent, model)
        #do this only once per day
        time_of_day != :work && return

        #get behavior of others in same nodes
        node_agents = get_node_agents(agent.pos,model)
        mean_behavior = mean([agent.behavior for agent in node_agents])
        #increase the perceived norms if a message was sent
        if(model.properties[:days_passed]==model.properties[:norms_message])
            mean_behavior = property_growth(mean_behavior)
        end
        #and let it decrease thereafter step by step. Dies out after about 7 days
        if(model.properties[:days_passed]>model.properties[:norms_message])
            time_passed = model.properties[:days_passed] - model.properties[:norms_message]
            mean_behavior = property_growth(mean_behavior)
            mean_behavior = norm_decay(mean_behavior,time_passed)
        end

        #model.properties[:norms_message] == true && rand()>0.1 && (mean_behavior*=1.05)

        #get the agents attitude with our decay
        attitude = attitude_decay(agent.original_attitude, agent.attitude)
        old_fear = agent.fear

        #get personal environment infected and compute a threat value
        #get #infected within agents environment
        acquaintances_infected = length(filter(x -> in(x.health_status, (:NQ,:Q,:HS)) && (x.household == agent.household || x.workplace == agent.workplace || x.socialgroup == agent.socialgroup || x.distantgroup == agent.distantgroup),all_agents))

        if acquaintances_infected == 0 || model.infected_reported == 0
            acquaintances_infected = 1
        end

        #get daily cases from three days ago(if possible)
        if length(infected_timeline)>3
            daily_cases = infected_timeline[end-2] - infected_timeline[end-3]
        else
            daily_cases = infected_timeline[end]
        end

        #use correction factors on both fear factors
        daily_cases = daily_cases/(nagents(model)/45)
        acquaintances_infected_now = acquaintances_infected/15
        new_fear = fear_growth(daily_cases,acquaintances_infected_now)
        time = length(infected_timeline_growth)

        #and apply the exponential decay to it after two weeks and we didnt have growth for three days
        if model.properties[:days_passed] > 20 && isequal(infected_timeline_growth[length(infected_timeline_growth)-2:length(infected_timeline_growth)].< 104,trues(3))
            new_fear = Int16(round(fear_decay(new_fear, time)))
        end

        #set bounds for fear growth&decay
        old_fear == 0 && (old_fear = new_fear)
        if new_fear>old_fear*1.4
            #round up to prevent behavior getting stuck at 1 for initially small increments
            new_fear = old_fear*1.4
        elseif new_fear < old_fear*0.9
            new_fear = old_fear*0.9
        end

        #get the new fear and add it to the fear history
        push!(agent.fear_history, new_fear)
        #calculate the average fear we use for the behavior calc
        if length(agent.fear_history)>6
            agent.fear = mean(agent.fear_history[end-6:end])
        else
            agent.fear = mean(agent.fear_history)
        end

        #agent behavior is computed as (norm + attitude)/2 + decay(threat)
        old_behavior = agent.behavior
        #reduced influence of fear so that messages can take over when due
        new_behavior = Int16(round(mean([mean_behavior,attitude])*agent.fear/100))
        #catch the Initialization of behavior
        old_behavior == 0 && (old_behavior = new_behavior)

        #prevent new behavior from jumping around too fast, a one-day stall in infection could reduce behavior too strong
        if new_behavior>old_behavior*1.4
            #round up to prevent behavior getting stuck at 1 for initially small increments
            new_behavior = Int16(ceil(old_behavior*1.4))
        elseif new_behavior < old_behavior*0.9
            new_behavior = Int16(ceil(old_behavior*0.9))
        end
        agent.behavior = new_behavior
    end

    function transmit!(agent, model)
        #increment the sickness state of immune agents
        #skip transmission for non-sick agents
        !in(agent.health_status, (:E,:IwS,:NQ,:Q,:HS)) && return
        #also skip if exposed, but not yet infectious. RKI Steckbrief says 2 days before onset of symptoms
        agent.health_status == :E && agent.days_infected < model.properties[:exposed_period]-2 && return
        #and 5 days after onset of symptoms
        agent.days_infected > model.properties[:exposed_period] + 5 && return
        prop = model.properties

        #mean rate Chu 2020 f
        risk = if agent.behavior > 60
            0.0366
        else
            0.095
        end
        #rate of secondary infections in household is present (Wei Li 2020), but at least contained to household
        if agent.health_status == :Q
            if agent.behavior > 60
                risk = 0.0063
            else
                risk = 0.0163
            end
        end

        #test for infection curve
        risk = risk*0.8

        #infect the number of contacts and then return
        #get node of agent, skip if only him
        node_contents = get_node_contents(agent.pos, model)
        length(node_contents)==1 && return
        contacts = contacts_reworked(Int32(agent.age))

        #if agent is older than 80, function gets negative. Fix this and also giving agents a contact ceiling of 30, set it to mean #contacts if outside bounds
        if 0 <= contacts < 30
            contacts = 14
        end

        #reduce it to the proporties of contact as mossong 2008.  Joined school and work, home and is about 35(work)+23(back)+16(social)+23(back) = 90 perc
        if time_of_day == :work
            contacts*=0.35
        elseif  time_of_day == :social
            contacts*=0.16
        else
            contacts*=0.26
        end
        contacts = round(contacts*0.7)
        #check if age_contacts bigger than available agents, set it then to the #available agents
        if contacts > length(node_contents) - 1
            contacts = length(node_contents) - 1
        end

        contacts < 0 && return
        #draw from bernoulli distribution with infection rate and average number of contacts according to age.
        infect_people = countmap(rand(Bernoulli(risk),Int32(round(contacts))))[1]
        #check if there are no people to infect
        infect_people  == 0 && return
        #if we have drawn more people than available, set infect_people to all other agents
        length(node_contents) < infect_people && (infect_people = length(node_contents)-1)
        timeout = infect_people*2
        t = 0

        #trying to infect n others in this node, timeout if in a node without eligible neighbors
        while infect_people > 0 && t < timeout
            target = model[rand(node_contents)]
            if target.health_status == :S
                model.properties[:daily_cases]+=1
                model.properties[:daily_contact]+=1
                target.health_status = :E
                infect_people -= 1
                push!(infection_age,agent.wealth)
            end
            t +=1
        end
    end

    #increase infection time once per day for eligible agents
    update!(agent, model) = time_of_day == :work && in(agent.health_status, (:E,:IWS,:NQ,:Q,:M, :HS)) && (agent.days_infected +=1)

    #transition agent to new state
    function recover_or_die!(agent, model)
        #some agents are asymptomatic(IwS), the rest first becomes NonQuarantined
        if agent.health_status == :E && agent.days_infected == model.properties[:exposed_period]
            if rand()>0.222 #streeck infection fatality asymptomatic cases
                agent.health_status = :NQ
            else
                agent.health_status = :IwS
                iws_timeline[model.properties[:days_passed]]+=1
            end
        elseif agent.health_status == :NQ && agent.days_infected == model.properties[:exposed_period]+1
            #decide if going into quarantine, influenced by behavior - since its mandatory by government, only small percentage doesnt go into quarantine
            #this decision is only taken once when becoming symptomatic
            if rand()*agent.behavior/100>0.05
                agent.health_status = :Q
            end
        elseif (agent.health_status == :NQ || agent.health_status ==:Q) && agent.days_infected == model.properties[:exposed_period]+4
            #see if agent gets severe symptoms or stays only mildly infected, happens ~4 days after symptoms show up
            #base rate is 12% in hospital, influenced by agent age, source RKI Situationsbericht 30.03
            #this distribution has on average (tested with age 10,40 and 70) the 12% base rate, fewer for children and more for the elderly
            if rand(Normal(1,1))*(rand(-35:1:35)+agent.age)/100 > 1.17
                agent.health_status = :HS
            end
        elseif in(agent.health_status,(:NQ,:Q, :IwS)) && agent.days_infected == 14 #RKI Krankheitsverlauf zwei Wochen
            #become immune again after being NQ,Q, without heavy symptoms
            agent.health_status == :M
        elseif agent.health_status == :HS && agent.days_infected == 9+10 #after RKI Durchschn. Zeitintervall Behandlung, Median 10 Tage nach Hospitalisierung
            #see if agent with heavy symptoms dies or recovers. Happens after three weeks as ? specifies
            #no age here, since we already used this for severe cases. Source RKI Steckbrief
                if rand()<0.22
                    agent.health_status = :D
                    push!(death_age,agent.age)
                else
                    agent.health_status = :M
                end
        elseif agent.health_status == :M && agent.days_infected == 75 #become susceptible again after two-three months (Long 2020)
            agent.health_status = :S
        end
    end

    #data collection :
    infected(x) = count(in(i,(:E,:IwS,:Q,:NQ,:HS)) for i in x)
    recovered(x) = count(in(i,(:M,:D)) for i in x)
    susceptible(x) = count(i == :S for i in x)
    mean_sentiment(x) = Int64(round(mean(x)))
    #get percentage of agents with behavior and fear > 100
    behavior(x) = count(i>=100 for i in x)/nagents(model)*100
    fear_over(x) = count(i>=100 for i in x)/nagents(model)*100
    known_infected(x) = count(in(i,(:Q,:NQ,:HS)) for i in x)

    data_to_collect = [(:health_status,infected),(:health_status,recovered),(:health_status,susceptible),(:behavior,mean_sentiment),(:fear,mean_sentiment),(:behavior,behavior),(:fear,fear_over),(:health_status,known_infected)]
    model_data_to_collect = [(:daily_cases),(:daily_mobility),(:daily_contact),(:days_passed)]
    #run the model - agents go to work, collect data
    time_of_day = :work
    Agents.run!(model, move_step!, 1)
    Agents.run!(model, infect_step!, 1)
    #back home
    time_of_day = :back_work
    Agents.run!(model, move_step!,1)
    Agents.run!(model, infect_step!,1)

    #if social/distant
    time_of_day = :social
    Agents.run!(model, move_step!,1)
    Agents.run!(model, infect_step!,1)

    #and back home - collect data only here at the end of the day
    time_of_day = :back_social
    Agents.run!(model, move_step!,1)
    data_a, data_m = Agents.run!(model, infect_step!,1; adata = data_to_collect,mdata = model_data_to_collect)

    #combine dfs,rename them appropriately and return them
    data_m = select(data_m,Not(:step))
    data = hcat(data_a,data_m)
    deleterows!(data,1)
    #add the daily cases and IwS since this is an accurate count of the new infections today
    data = hcat(data,DataFrame(infected_adjusted=last(infected_timeline)),DataFrame(iws_timeline=last(iws_timeline)))
    DataFrames.rename!(data,[:step, :infected, :recovered, :susceptible,:mean_behavior,:mean_fear,:behavior,:fear_over,:known_infected,:daily_cases,:daily_mobility,:daily_contact,:days_passed,:infected_adjusted,:IwS])
    return data
end

export agent_week!
