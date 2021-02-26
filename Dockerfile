FROM julia:latest

#install git
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y git

#clone the github folder
RUN git clone https://github.com/werzum/COVID19-ABM.git || (cd COVID19-ABM ; git pull)

#copy the datafiles to /app/Data
COPY ./SourceData /COVID19-ABM/SourceData
WORKDIR /COVID19-ABM


#add packages
RUN julia -e 'using Pkg; Pkg.add(["JSON","Gadfly", "Interact", "Compose", "Printf", "Reactive", "ColorSchemes", "Random", "DataFrames", "CSV", "Plots", "HypothesisTests", "Distances", "StatsBase", "Distributions", "Statistics", "Distributed", "GraphPlot", "GraphRecipes", "AgentsPlots", "StatsPlots", "Luxor", "LightGraphs", "OpenStreetMapX"])'

#add modified Agents so we have a mutable map
RUN julia -e 'using Pkg; Pkg.add(Pkg.PackageSpec(url="https://github.com/werzum/Agents.jl"))'

#do something
CMD export JULIA_DEPOT_PATH="/root/.julia/"
