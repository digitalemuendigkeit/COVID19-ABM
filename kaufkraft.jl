
#wrote changes to csv so we dont have to do basic cleaning again and again
#read the data
rawdata = CSV.read("SourceData\\zensus.csv", DataFrame)
#drop irrelevant columns and redundant rows
select!(rawdata,Not(16))
rawdata = rawdata[rawdata.Einwohner.!=-1,:]
# CSV.write("SourceData\\zensus.csv",rawdata)

#add povertydata to rawdata
rawdata[!,:kaufkraft] .= zeros(Int64)
subX = rawdata.X
subY = rawdata.Y
pointarray = Vector(undef,length(subY))
for i in 1:length(subY)
    pointarray[i] = Luxor.Point(subX[i], subY[i])
end
rawdata.Point= pointarray
pointarr = rawdata.Point

povertydata = CSV.read("SourceData\\Income_Regions.csv",DataFrame)
povertydata = select!(povertydata,:kaufkraft,:MultiPolygon)
replace.(povertydata.:MultiPolygon, r"[\\]" => "")
iterator = eachrow(povertydata)
inside = Array
for row in iterator
    array = split(row.:MultiPolygon,",")
    longs = array[1:2:end]
    lats = array[2:2:end]
    deleteat!(longs, (length(longs)-5):length(longs))
    deleteat!(lats, (length(lats)-5):length(lats))
    pointarray = Vector(undef,length(lats))
    arraysize = 0
    length(longs)<=length(lats) ? arraysize = length(longs) : arraysize = length(lats)
    for i in 1:arraysize
        point = Luxor.Point(parse(Float64,longs[i]),parse(Float64,lats[i]))
        pointarray[i] = point
    end
    deleteat!(pointarray, (length(pointarray)-1):length(pointarray))
    #print(pointarray)
    #deleteat!(pointarray, findall(x->!isa(x,Point2D), pointarray))
    pointarray = convert(Array{Luxor.Point,1},pointarray)
    #polygon = Luxor.Point(parse(Float64(lats)),parse(Float64(longs)))#Luxor.poly(pointarray;close=true)
    inside = [isinside(p,pointarray;allowonedge=true) for p in pointarr]
    # println(typeof(row.:kaufkraft))
    #println(count(inside))
    rawdata[inside,:kaufkraft] .= row.:kaufkraft
end

#write changes to zensus
CSV.write("SourceData\\zensus.csv",rawdata)
nrow(rawdata)
