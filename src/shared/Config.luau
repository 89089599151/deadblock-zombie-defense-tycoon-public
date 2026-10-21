--!strict
local droppers = {}
local prices = {0,100,350,750,1500,3000}
local values = {5,8,15,25,45,80}
local positions = {22,6,-10,-26,-50,-66}
local travelTimes = {2,4,6,8,11,13}
for id=1,6 do
	local value=values[id]
	droppers[id]=table.freeze({
		Id=id,Name="Дроппер "..id,Price=prices[id],
		RequiredExpansion=math.floor((id-1)/2),Prerequisite=if id>1 then id-1 else nil,
		Z=positions[id],TravelTime=travelTimes[id],
		Levels=table.freeze({table.freeze({Value=value}),table.freeze({Value=value*2,Cost=value*15}),table.freeze({Value=value*4,Cost=value*40})}),
	})
end
return table.freeze({
	GameName = "DEADBLOCK: Zombie Defense Tycoon",
	Stage = "Развитие тайкуна",
	PlotCount = 2,
	Production = table.freeze({ Interval = 2, TravelTime = 2, Value = 5 }),
	Droppers=table.freeze(droppers),
	Expansions=table.freeze({table.freeze({Price=250,Prerequisite=2}),table.freeze({Price=1200,Prerequisite=4})}),
	MaxLevel=3,
	PurchaseDistance=18,
	ServerStep = 0.05,
})
