Rem
	===========================================================
	code for stationmap and broadcasting stations
	===========================================================
ENDREM
SuperStrict
Import "Dig/base.util.xmlhelper.bmx"
Import "Dig/base.util.registry.bmx"
Import "Dig/base.util.registry.imageloader.bmx"
Import "Dig/base.util.registry.spriteloader.bmx"
Import "Dig/base.util.color.bmx"
Import "Dig/base.util.time.bmx"
Import "Dig/base.gfx.sprite.bmx"
Import "Dig/base.gfx.bitmapfont.bmx"
Import "game.gamerules.bmx"
Import "game.player.color.bmx"
Import "game.player.finance.bmx"
Import "basefunctions.bmx"

'parent of all stationmaps
Type TStationMapCollection
	'list of stationmaps
	Field stationMaps:TStationMap[0]
	'map containing bitmask-coded information for "used" pixels
	Field shareMap:TMap = Null {nosave}
	Field shareCache:TMap = Null {nosave}
	Field antennaStationRadius:Int = 18
	Field population:Int = 0 {nosave}
	Field populationmap:Int[,] {nosave}
	Field populationImage:TImage {nosave}
	Field populationMapSize:TVec2D = New TVec2D.Init() {nosave}
	Field config:TData = New TData
	Field cityNames:TData = New TData
	Field sportsData:TData = New TData

	Field mapConfigFile:String = ""
	'does the shareMap has to get regenerated during the next
	'update cycle?
	Field _regenerateMap:Int = False

	'difference between screen0,0 and pixmap
	'->needed movement to have population-pixmap over country
	Global populationMapOffset:TVec2D = New TVec2D.Init(0, 0)
	Global _initDone:Int = False
	Global _instance:TStationMapCollection


	Method New()
		If Not _initDone
			'handle savegame loading (reload the map configuration)
			EventManager.registerListenerFunction("SaveGame.OnLoad", onSaveGameLoad)
			'handle <stationmapdata>-area in loaded xml files
			EventManager.registerListenerFunction("RegistryLoader.onLoadResourceFromXML", onLoadStationMapData, Null, "STATIONMAPDATA" )
			'handle activation of stations
			EventManager.registerListenerFunction("station.onSetActive", onSetStationActiveState)
			EventManager.registerListenerFunction("station.onSetInactive", onSetStationActiveState)

			_initdone = True
		EndIf
	End Method


	Function GetInstance:TStationMapCollection()
		If Not _instance Then _instance = New TStationMapCollection
		Return _instance
	End Function


	Method InitializeAll:Int()
		For Local map:TStationMap = EachIn stationMaps
			map.Initialize()
		Next
		'optional:
		'stationMaps = new TStationMap[0]
	End Method


	'as soon as a station gets active (again), the sharemap has to get
	'regenerated (for a correct audience calculation)
	Function onSetStationActiveState:int(triggerEvent:TEventBase)
		GetInstance()._regenerateMap = True
		'also set the owning stationmap to "changed" so only this single
		'audience sum only gets recalculated (saves cpu time)
		Local station:TStationBase = TStationBase(triggerEvent.GetSender())
		If station Then GetInstance().GetMap(station.owner).changed = True
	End Function


	'run when loading finished
	Function onSaveGameLoad:int(triggerEvent:TEventBase)
		TLogger.Log("TStationMapCollection", "Savegame loaded - reloading map data", LOG_DEBUG | LOG_SAVELOAD)

		_instance.LoadMapFromXML()
	End Function


	'run when an xml contains an <stationmapdata>-area
	Function onLoadStationMapData:Int(triggerEvent:TEventBase)
		Local mapDataRootNode:TxmlNode = TxmlNode(triggerEvent.GetData().Get("xmlNode"))
		Local registryLoader:TRegistryLoader = TRegistryLoader(triggerEvent.GetSender())
		If Not mapDataRootNode Or Not registryLoader Then Return False

		Local densityNode:TxmlNode = TXmlHelper.FindChild(mapDataRootNode, "densitymap")
		If Not densityNode Then Throw("File ~q"+_instance.mapConfigFile+"~q misses the <stationmapdata><densitymap>-entry.")

		Local surfaceNode:TxmlNode = TXmlHelper.FindChild(mapDataRootNode, "surface")
		If Not surfaceNode Then Throw("File ~q"+_instance.mapConfigFile+"~q misses the <stationmapdata><surface>-entry.")

		Local configNode:TxmlNode = TXmlHelper.FindChild(mapDataRootNode, "config")
		If Not configNode Then Throw("File ~q"+_instance.mapConfigFile+"~q misses the <stationmapdata><config>-entry.")

		Local cityNamesNode:TxmlNode = TXmlHelper.FindChild(mapDataRootNode, "citynames")
		If Not cityNamesNode Then Throw("File ~q"+_instance.mapConfigFile+"~q misses the <stationmapdata><citynames>-entry.")

		Local sportsDataNode:TxmlNode = TXmlHelper.FindChild(mapDataRootNode, "sports")
		'not mandatory
		'If Not sportsDataNode Then Throw("File ~q"+_instance.mapConfigFile+"~q misses the <stationmapdata><sports>-entry.")

		'directly load the given resources
		registryLoader.LoadSingleResourceFromXML(densityNode, True, New TData.AddString("name", "map_PopulationDensity"))
		registryLoader.LoadSingleResourceFromXML(surfaceNode, True, New TData.AddString("name", "map_Surface"))

		TXmlHelper.LoadAllValuesToData(configNode, _instance.config)
		TXmlHelper.LoadAllValuesToData(cityNamesNode, _instance.cityNames)
		if sportsDataNode
			TXmlHelper.LoadAllValuesToData(sportsDataNode, _instance.sportsData)
		endif

		'=== LOAD STATES ===
		'remove old states
		TStationMapSection.Reset()

		'find and load states configuration
		Local statesNode:TxmlNode = TXmlHelper.FindChild(mapDataRootNode, "states")
		If Not statesNode Then Throw("File ~q"+_instance.mapConfigFile+"~q misses the <map><states>-area.")

		For Local child:TxmlNode = EachIn TXmlHelper.GetNodeChildElements(statesNode)
			Local name:String	= TXmlHelper.FindValue(child, "name", "")
			Local sprite:String	= TXmlHelper.FindValue(child, "sprite", "")
			Local pos:TVec2D	= New TVec2D.Init( TXmlHelper.FindValueInt(child, "x", 0), TXmlHelper.FindValueInt(child, "y", 0) )
			'add state section if data is ok
			If name<>"" And sprite<>""
				New TStationMapSection.Create(pos,name, sprite).add()
			EndIf
		Next
	End Function


	'load a map configuration from a specific xml file
	'eg. "germany.xml"
	'we use xmlLoader so image ressources in the file get autoloaded
	Method LoadMapFromXML:Int(xmlFile:String="", baseUri:String = "")
		If xmlFile <> "" Then mapConfigFile = xmlFile

		'=== LOAD XML CONFIG ===
		Local registryLoader:TRegistryLoader = New TRegistryLoader
		registryLoader.baseURI = baseURI
		registryLoader.LoadFromXML(mapConfigFile, True)
		'TLogger.Log("TGetStationMapCollection().LoadMapFromXML", "config parsed", LOG_LOADING)

		'=== INIT MAP DATA ===
		CreatePopulationMap()

		Return True
	End Method
	

	Method CreatePopulationMap()
		Local stopWatch:TStopWatch = New TStopWatch.Init()
		Local srcPix:TPixmap = GetPixmapFromRegistry("map_PopulationDensity")
		If Not srcPix
			TLogger.Log("TGetStationMapCollection().CreatePopulationMap", "pixmap ~qmap_PopulationDensity~q is missing.", LOG_LOADING)
			Throw("TStationMap: ~qmap_PopulationDensity~q missing.")
			Return
		EndIf

		'move pixmap so it overlays the rest
		Local pix:TPixmap = CreatePixmap(Int(srcPix.width + populationMapOffset.x), Int(srcPix.height + populationMapOffset.y), srcPix.format)
		pix.ClearPixels(0)
		pix.paste(srcPix, Int(populationMapOffset.x), Int(populationMapOffset.y))

		populationMap = New Int[pix.width, pix.height]
		populationMapSize.SetXY(pix.width, pix.height)


		local maxBrightnessPop:int = getPopulationForBrightness(0)
		local minBrightnessPop:int = getPopulationForBrightness(255)

		'read all inhabitants of the map
		Local i:Int, j:Int, c:Int, s:Int = 0
		population = 0
		For j = 0 To pix.height-1
			For i = 0 To pix.width-1
				c = pix.ReadPixel(i, j)
				If ARGB_ALPHA(pix.ReadPixel(i, j)) = 0 Then Continue
				local brightness:int = ARGB_RED(c)
				populationmap[i, j] = getPopulationForBrightness( brightness )

				'store pixel with lower alpha for lower population
				'-20 is the base level to avoid colorization of "nothing"
				local brightnessRate:Float = Min(1.0, 2 * populationmap[i, j] / float(maxBrightnessPop))
				if brightnessRate < 0.1
					brightnessRate = 0
				else
					brightnessRate :* (1.0 - brightness/255.0)
					brightnessRate = brightnessRate^0.25

'					if brightnessRate < 0.15
'						brightnessRate :* 0.5*brightnessRate
'					endif
				endif

'				pix.WritePixel(i,j, ARGB_Color(brightnessRate*255, (1.0-brightnessRate)*255, 0, 0))
				pix.WritePixel(i,j, ARGB_Color(int(brightnessRate*255), int(brightnessRate*255), int(0.2 * brightnessRate*255), 0))

				population:+ populationmap[i, j]
			Next
		Next

		'load the manipulated population image
		populationImage = LoadImage(pix)

		TLogger.Log("TGetStationMapCollection().CreatePopulationMap", "calculated a population of:" + population + " in "+stopWatch.GetTime()+"ms", LOG_DEBUG | LOG_LOADING)
	End Method


	Method Add:Int(map:TStationMap)
		'check boundaries
		If map.owner < 1 Then Return False

		'resize if needed
		If map.owner > stationMaps.length Then stationMaps = stationMaps[ .. map.owner+1]

		'add to array array - zerobased
		stationMaps[map.owner-1] = map
		Return True
	End Method


	Method Remove:Int(map:TStationMap)
		'check boundaries
		If map.owner < 1 Or map.owner > stationMaps.length Return False
		'remove from array - zero based
		stationMaps[map.owner-1] = Null

		'invalidate caches
		'shareCache.Clear()
		'shareMap.Clear()
		GenerateShareMap()
		
		Return True
	End Method


	'return the stationmap of other channels
	'do not expose to Lua... else they get access to buy/sell
	Method GetMap:TStationMap(channelNumber:Int, createIfMissing:Int = False)
		'check boundaries
		If channelNumber < 1 Or (Not createIfMissing And channelNumber > stationMaps.length)
			Throw "GetStationMapCollection().GetMap: channelNumber ~q"+channelNumber+"~q is out of bounds."
		EndIf

		'create if missing
		If (channelNumber > stationMaps.length Or Not stationMaps[channelNumber-1]) And createIfMissing
			Add(TStationMap.Create(channelNumber))
		EndIf
		
		'zero based
		Return stationMaps[channelNumber-1]
	End Method


	'returns the average reach of all stationmaps
	Method GetAverageReach:Int()
		Local reach:Int = 0
		Local mapCount:Int = 0
		For Local map:TStationMap = EachIn stationMaps
			'skip empty maps
			'TODO: what happens with satellites?
			'if map.GetStationCount() = 0 then continue
			
			reach :+ map.GetReach()
			mapCount :+ 1
		Next
		if mapCount = 0 then return 0
		Return reach/mapCount
	End Method


	Method GenerateShareMap:Int()
		'reset values
		shareMap = New TMap
		'reset cache here too
		shareCache = New TMap

		'define locals outside of that for loops...
		Local posX:Int		= 0
		Local posY:Int		= 0
		Local stationX:Int	= 0
		Local stationY:Int	= 0
		Local mapKey:String	= ""
		Local mapValue:TVec3D = Null
		Local rect:TRectangle = New TRectangle.Init(0,0,0,0)
		For Local stationmap:TStationMap = EachIn stationMaps
			if stationmap.cheatedMaxReach
				'insert the players bitmask-number into the field
				'and if there is already one ... add the number
				For posX = 0 To populationImage.height-1
					For posY = 0 To populationImage.width-1
						mapKey = posX+","+posY
						mapValue = New TVec3D.Init(posX,posY, getMaskIndex(stationmap.owner) )
						If shareMap.Contains(mapKey)
							mapValue.z = Int(mapValue.z) | Int(TVec3D(shareMap.ValueForKey(mapKey)).z)
						EndIf
						shareMap.Insert(mapKey, mapValue)
					Next
				Next
			else
				For Local station:TStationBase = EachIn stationmap.stations
					'skip inactive stations
					If Not station.IsActive() Then Continue

					'mark the area within the stations circle
					posX = 0
					posY = 0
					stationX = Max(0, station.pos.x)
					stationY = Max(0, station.pos.y)
					Rect.position.SetXY( Max(stationX - antennaStationRadius,antennaStationRadius), Max(stationY - antennaStationRadius,antennaStationRadius) )
					Rect.dimension.SetXY( Min(stationX + antennaStationRadius, Self.populationMapSize.x-antennaStationRadius), Min(stationY + antennaStationRadius, Self.populationMapSize.y-antennaStationRadius) )

					For posX = Rect.getX() To Rect.getW()
						For posY = Rect.getY() To Rect.getH()
							' left the circle?
							If Self.calculateDistance( posX - stationX, posY - stationY ) > antennaStationRadius Then Continue

							'insert the players bitmask-number into the field
							'and if there is already one ... add the number
							mapKey = posX+","+posY
							mapValue = New TVec3D.Init(posX,posY, getMaskIndex(stationmap.owner) )
							If shareMap.Contains(mapKey)
								mapValue.z = Int(mapValue.z) | Int(TVec3D(shareMap.ValueForKey(mapKey)).z)
							EndIf
							shareMap.Insert(mapKey, mapValue)
						Next
					Next
				Next
			endif
		Next
	End Method



	'returns the shared amount of audience between channels
	Method GetShareAudience:Int(channelNumbers:Int[], withoutChannelNumbers:Int[]=Null)
		Return GetShare(channelNumbers, withoutChannelNumbers).x
	End Method


	Method GetSharePercentage:Float(channelNumbers:Int[], withoutChannelNumbers:Int[]=Null)
		Return GetShare(channelNumbers, withoutChannelNumbers).z
	End Method


	Method GetChannelExclusiveAudience:Int(channelNumber:int)
		local without:int[]
		for local i:int = 1 until 4
			if i <> channelNumber then without :+ [i]
		next
		return GetShare([channelNumber], without).x
	End Method


	'returns a share between channels, encoded in a TVec3D containing:
	'x=sharedAudience,y=totalAudience,z=percentageOfSharedAudience
	Method GetShare:TVec3D(channelNumbers:Int[], withoutChannelNumbers:Int[]=Null)
		If channelNumbers.length <1 Then Return New TVec3D.Init(0,0,0.0)
		If Not withoutChannelNumbers Then withoutChannelNumbers = New Int[0]

		Local result:TVec3D

		'=== CHECK CACHE ===
		'if already cached, save time...

		'== GENERATE KEY ==
		Local cacheKey:String = ""
		For Local i:Int = 0 To channelNumbers.length-1
			cacheKey:+ "_"+channelNumbers[i]
		Next
		If withoutChannelNumbers.length > 0
			cacheKey:+"_without_"
			For Local i:Int = 0 To withoutChannelNumbers.length-1
				cacheKey:+ "_"+withoutChannelNumbers[i]
			Next
		EndIf

		'== LOAD CACHE ==
		If shareCache And shareCache.contains(cacheKey)
			result = TVec3D(shareCache.ValueForKey(cacheKey))
		EndIf


		'== GENERATE CACHE ==
		If Not result
			result = New TVec3D.Init(0,0,0.0)
			Local map:TMap = GetShareMap()
			Local share:Int	= 0
			Local total:Int	= 0
			Local channelFlags:Int[]
			Local allFlag:Int = 0
			Local withoutChannelFlags:Int[]
			Local withoutFlag:Int = 0
			channelFlags = channelFlags[.. channelNumbers.length]
			withoutChannelFlags = withoutChannelFlags[.. withoutChannelNumbers.length]

			For Local i:Int = 0 To channelNumbers.length-1
				'channel 1=1, 2=2, 3=4, 4=8 ...
				channelFlags[i] = getMaskIndex( channelNumbers[i] )
				allFlag :| channelFlags[i]
			Next

			For Local i:Int = 0 To withoutChannelNumbers.length-1
				'channel 1=1, 2=2, 3=4, 4=8 ...
				withoutChannelFlags[i] = getMaskIndex( withoutChannelNumbers[i] )
				withoutFlag :| withoutChannelFlags[i]
			Next


			Local someoneUsesPoint:Int = False
			Local allUsePoint:Int = False
			For Local mapValue:TVec3D = EachIn map.Values()
				someoneUsesPoint = False
				allUsePoint = False

				'we need to check if one on our ignore list is there
					'no need to do this individual, we can just check the groupFlag
					Rem
					local someoneUnwantedUsesPoint:int	= FALSE
					for local i:int = 0 to withoutChannelFlags.length-1
						if int(mapValue.z) & withoutChannelFlags[i]
							someoneUnwantedUsesPoint = true
							exit
						endif
					Next
					if someoneUnwantedUsesPoint then continue
					endrem
				If Int(mapValue.z) & withoutFlag Then Continue

				'as we have multiple flags stored in AllFlag, we have to
				'compare the result to see if all of them hit,
				'if only one of it hits, we just check for <>0
				If (Int(mapValue.z) & allFlag) = allFlag
					allUsePoint = True
					someoneUsesPoint = True
				Else
					For Local i:Int = 0 To channelFlags.length-1
						If Int(mapValue.z) & channelFlags[i] Then someoneUsesPoint = True;Exit
					Next
				EndIf
				'someone has a station there
				If someoneUsesPoint Then total:+ populationmap[mapValue.x, mapValue.y]
				'all searched have a station there
				If allUsePoint Then share:+ populationmap[mapValue.x, mapValue.y]
			Next
			result.setXY(share, total)
			If total = 0 Then result.z = 0.0 Else result.z = Float(share)/Float(total)

			'store new cached data
			If shareCache Then shareCache.insert(cacheKey, result )

			'print "uncached: "+cacheKey
			'print "share:  total="+int(result.y)+"  share="+int(result.x)+"  share="+(result.z*100)+"%"
		'else
			'print "cached: "+cacheKey
			'print "share:  total="+int(result.y)+"  share="+int(result.x)+"  share="+(result.z*100)+"%"
		EndIf


		Return result
	End Method


	Method GetSportData:TData(sport:string, defaultData:TData = null)
		return sportsData.GetData(sport, defaultData)
	End Method


	Method GenerateCity:String(glue:String="")
		Local part1:String[] = cityNames.GetString("part1").Split(", ")
		Local part2:String[] = cityNames.GetString("part2").Split(", ")
		Local part3:String[] = cityNames.GetString("part3").Split(", ")
		if part1.length = 0 then return "part1Missing-Town"
		if part2.length = 0 then return "part2Missing-Town"
		if part3.length = 0 then return "part3Missing-Town"

		Local result:String = ""
		'use part 1?
		If part1.length > 0 and RandRange(0,100) < 35
			result :+ StringHelper.UCFirst(part1[RandRange(0, part1.length-1)])
		EndIf

		'no prefix, or " " or "-" (Bad Blaken, Alt-Drueben)
		If Not result Or Chr(result[result.length-1]) = " " Or Chr(result[result.length-1]) = "-"
			If result <> "" Then result :+ glue
			result :+ StringHelper.UCFirst(part2[RandRange(0, part2.length-1)])
		Else
			If result <> "" Then result :+ glue
			result :+ part2[RandRange(0, part2.length-1)]
		EndIf

		If RandRange(0,100) < 35
			result :+ glue
			result :+ part3[RandRange(0, part3.length-1)]
		EndIf

		if result.trim() = "" then return "partsMissing-Town"

		Return result
	End Method


	Method Update:Int()
		'update all stationmaps (and their stations)
		For Local i:Int = 0 Until stationMaps.length
			If Not stationMaps[i] Then Continue

			stationMaps[i].Update()
		Next


		'refresh the share map and refresh max audience sum
		'as soon as one of the stationmap changed
		If _regenerateMap
			GenerateShareMap()

			'recalculate the audience sums of all changed maps
			'maybe generalize it (recalculate ALL as soon as map
			'gets regenerated)
			'this individual way saves calculation time (only do what
			'is needed)
			Local m:TStationMap
			For Local i:Int = 1 To stationMaps.length
				m = GetMap(i)
				If Not m Then Continue
				
				If m.changed
					m.RecalculateAudienceSum()
					'we handled the changed flag
					m.changed = False
				EndIf
			Next

			'we handled regenerating the map
			_regenerateMap = False
		EndIf
	End Method



	'params of advanced types (no ints, strings, bytes) are automatically
	'passed "by reference" (change it here, and it is changed globally)
	Method _FillPoints(map:TMap, x:Int, y:Int, color:Int)
		Local posX:Int = 0, posY:Int = 0
		x = Max(0, x)
		y = Max(0, y)
		' innerhalb des Bildes?
		For posX = Max(x - antennaStationRadius,antennaStationRadius) To Min(x + antennaStationRadius, populationMapSize.x-antennaStationRadius)
			For posY = Max(y - antennaStationRadius,antennaStationRadius) To Min(y + antennaStationRadius, populationMapSize.y-antennaStationRadius)
				' noch innerhalb des Kreises?
				If Self.calculateDistance( posX - x, posY - y ) <= antennaStationRadius
					map.Insert(String((posX) + "," + (posY)), New TVec3D.Init((posX) , (posY), color ))
				EndIf
			Next
		Next
	End Method


	Method CalculateAudienceDecrease:Int(stations:TList, removeStation:TStationBase)
		If Not removeStation Then Return 0

		Local Points:TMap = New TMap
		Local returnValue:Int = 0

		'mark the station to removed as "blue"
		'mark all others (except the given one) as "white"
		'-> then count pop on all spots "just blue" and not "white"
		
		Self._FillPoints(Points, Int(removeStation.pos.x), Int(removeStation.pos.y), ARGB_Color(255, 0, 255, 255))

		'overwrite with stations owner already has - red pixels get overwritten with white,
		'count red at the end for increase amount
		For Local _Station:TStationBase = EachIn stations
			'DO NOT SKIP INACTIVE STATIONS !!
			'decreases are for estimations - so they should include
			'non-finished stations too

			'exclude the station to remove...
			If _Station = removeStation Then Continue
		
			If THelper.IsIn(Int(removeStation.pos.x), Int(removeStation.pos.y), Int(_station.pos.x - 2*antennaStationRadius), Int(_station.pos.y - 2 * antennaStationRadius), Int(4*antennaStationRadius), Int(4*antennaStationRadius))
				Self._FillPoints(Points, Int(_Station.pos.x), Int(_Station.pos.y), ARGB_Color(255, 255, 255, 255))
			EndIf
		Next

		'count all "exclusively blue" spots
		For Local point:TVec3D = EachIn points.Values()
			If ARGB_Red(Int(point.z)) = 0 'And ARGB_Blue(point.z) = 255
				returnvalue:+ populationmap[point.x, point.y]
			EndIf
		Next
		Return returnvalue
	End Method
	

	Method CalculateAudienceIncrease:Int(stations:TList, _x:Int, _y:Int)
		Local Points:TMap = New TMap
		Local returnValue:Int = 0

		'add "new" station which may be bought
		If _x = 0 And _y = 0 Then _x = MouseManager.x; _y = MouseManager.y
		Self._FillPoints(Points, _x,_y, ARGB_Color(255, 0, 255, 255))

		'overwrite with stations owner already has - red pixels get overwritten with white,
		'count red at the end for increase amount
		For Local _Station:TStationBase = EachIn stations
			'DO NOT SKIP INACTIVE STATIONS !!
			'increases are for estimations - so they should include
			'non-finished stations too
		
			If THelper.IsIn(Int(_x), Int(_y), Int(_station.pos.x - 2*antennaStationRadius), Int(_station.pos.y - 2 * antennaStationRadius), Int(4*antennaStationRadius), Int(4*antennaStationRadius))
				Self._FillPoints(Points, Int(_Station.pos.x), Int(_Station.pos.y), ARGB_Color(255, 255, 255, 255))
			EndIf
		Next

		For Local point:TVec3D = EachIn points.Values()
			If ARGB_Red(Int(point.z)) = 0 And ARGB_Blue(Int(point.z)) = 255
				returnvalue:+ populationmap[point.x, point.y]
			EndIf
		Next
		Return returnvalue
	End Method


	'summary: returns maximum audience a player has
	Method RecalculateAudienceSum:Int(stations:TList)
		Local Points:TMap = New TMap
		For Local station:TStationBase = EachIn stations
			'skip inactive stations
			If Not station.IsActive() Then Continue

			Self._FillPoints(Points, Int(station.pos.x), Int(station.pos.y), ARGB_Color(255, 255, 255, 255))
		Next
		Local returnValue:Int = 0

		For Local point:TVec3D = EachIn points.Values()
			If ARGB_Red(Int(point.z)) = 255 And ARGB_Blue(Int(point.z)) = 255
				returnValue:+ populationmap[point.x, point.y]
			EndIf
		Next

		Return returnValue
	End Method


	Method GetPopulation:Int()
		Return population
	End Method


	'summary: returns a stations maximum audience reach
	Method CalculateStationReach:Int(x:Int, y:Int)
		Local posX:Int, posY:Int
		Local returnValue:Int = 0
		' calc sum for current coord
		' min/max = everytime within boundaries
		For posX = Max(x - antennaStationRadius,antennaStationRadius) To Min(x + antennaStationRadius, populationMapSize.x - antennaStationRadius)
			For posY = Max(y - antennaStationRadius,antennaStationRadius) To Min(y + antennaStationRadius, populationMapSize.y - antennaStationRadius)
				' still within the circle?
				If calculateDistance( posX - x, posY - y ) <= antennaStationRadius
					returnvalue:+ populationmap[posX, posY]
				EndIf
			Next
		Next
		Return returnValue
	End Method


	'summary: returns calculated distance between 2 points
	Function calculateDistance:Double(x1:Int, x2:Int)
		Return Sqr((x1*x1) + (x2*x2))
	End Function


	Function getMaskIndex:Int(number:Int)
		Local t:Int = 1
		For Local i:Int = 1 To number-1
			t:*2
		Next
		Return t
	End Function


	Function getPopulationForBrightness:Int(value:Int)
		'attention: we use Ints, so values < 16 (sqrt 255) will be 0!
		value = Max(5, 255-value)
		value = (value*value)/255 '2 times so low values are getting much lower
		value:* 0.649

		If value > 110 Then value :* 2.0
		If value > 140 Then value :* 1.9
		If value > 180 Then value :* 1.3
		If value > 220 Then value :* 1.1	'population in big cities
		Return 26.0 * value					'population in general
	End Function


	Method GetShareMap:TMap()
		If Not shareMap Then GenerateShareMap()
		Return shareMap
	End Method
End Type

'===== CONVENIENCE ACCESSOR =====
'return collection instance
Function GetStationMapCollection:TStationMapCollection()
	Return TStationMapCollection.GetInstance()
End Function

Function GetStationMap:TStationMap(playerID:Int, createIfMissing:Int = False)
	Return TStationMapCollection.GetInstance().GetMap(playerID, createIfMissing)
End Function




Type TStationMap extends TOwnedGameObject {_exposeToLua="selected"}
	'select whose players stations we want to see
	Field showStations:Int[4]
	'maximum audience possible
	Field reach:Int	= 0
	Field cheatedMaxReach:int = False
	'all stations of the map owner
	Field stations:TList = CreateList()
	Field stationsAdded:int[4]
	Field changed:Int = False

	'FALSE to avoid recursive handling (network)
	Global fireEvents:Int = True


	Function Create:TStationMap(playerID:Int)
		Local obj:TStationMap = New TStationMap
		obj.SetOwner(playerID)

		obj.Initialize()

		GetStationMapCollection().Add(obj)

		Return obj
	End Function


	Method Initialize:Int()
		changed = False
		stations.Clear()
		reach = 0
		showStations = [1,1,1,1]
	End Method


	'returns the maximum reach of the stations on that map
	Method GetReach:Int() {_exposeToLua}
		Return Self.reach
	End Method


	Method GetCoverage:Float() {_exposeToLua}
		Return Float(getReach()) / Float(GetStationMapCollection().getPopulation())
	End Method


	'returns a station-object wich can be used for further
	'information getting (share etc)
	Method GetTemporaryAntennaStation:TStationBase(x:Int,y:Int)  {_exposeToLua}
		local station:TStation = new TStation
		station.radius = GetStationMapCollection().antennaStationRadius

		Return station.Init(New TVec2D.Init(x,y),-1, owner)
	End Method


	'returns a station-object wich can be used for further
	'information getting (share etc)
	Method GetTemporaryCableNetworkStation:TStationBase(stateName:string)  {_exposeToLua}
		local mapSection:TStationMapSection = TStationMapSection.GetByName(stateName)
		if not mapSection then return null
		
		local station:TStationBase = new TStationCableNetwork
		Return station.Init(New TVec2D.Init(mapSection.rect.GetXCenter(), mapSection.rect.GetYCenter()),-1, owner)
	End Method


	'returns a station-object wich can be used for further
	'information getting (share etc)
	Method GetTemporarySatelliteStation:TStationBase(satelliteNumber:int)  {_exposeToLua}
		local station:TStationBase = new TStationSatellite

		'TODO: satellite positions

		Return station.Init(New TVec2D.Init(10,10),-1, owner)
	End Method


	'return a station at the given coordinates (eg. used by network)
	Method GetStationsByXY:TStationBase[](x:Int=0,y:Int=0) {_exposeToLua}
		Local res:TStationBase[]
		Local pos:TVec2D = New TVec2D.Init(x, y)
		For Local station:TStationBase = EachIn stations
			If Not station.pos.isSame(pos) Then Continue
			res :+ [station]
		Next
		Return res
	End Method


	Method GetStation:TStationBase(stationGUID:String) {_exposeToLua}
		For Local station:TStationBase = EachIn stations
			If station.GetGUID() = stationGUID Then Return station
		Next
		Return Null
	End Method


	'returns a station of a player at a given position in the list
	Method GetStationAtIndex:TStationBase(arrayIndex:Int=-1) {_exposeToLua}
		'out of bounds?
		If arrayIndex < 0 Or arrayIndex >= stations.count() Then Return Null

		Return TStationBase( stations.ValueAtIndex(arrayIndex) )
	End Method


	'returns the amount of stations a player has
	Method GetStationCount:Int() {_exposeToLua}
		Return stations.count()
	End Method


	Method CheatMaxAudience:int()
		cheatedMaxReach = true
		reach = GetStationMapCollection().population
		GetStationMapCollection().GenerateShareMap()
		return True
	End Method


	'returns maximum audience a player's stations cover
	Method RecalculateAudienceSum:Int() {_exposeToLua}
		local reachBefore:int = reach

		if cheatedMaxReach
			reach = GetStationMapCollection().population
		else
			reach = GetStationMapCollection().RecalculateAudienceSum(stations)
		endif

		'inform others
		EventManager.triggerEvent( TEventSimple.Create( "StationMap.onRecalculateAudienceSum", New TData.addNumber("reach", reach).AddNumber("reachBefore", reachBefore), Self ) )

		Return reach
	End Method


	'returns additional audience when placing a station at the given coord
	Method CalculateAudienceIncrease:Int(x:Int, y:Int) {_exposeToLua}
		Return GetStationMapCollection().CalculateAudienceIncrease(stations, x, y)
	End Method

	'returns audience loss when selling a station at the given coord
	'param is station (not coords) to avoid ambiguity of multiple
	'stations at the same spot
	Method CalculateAudienceDecrease:Int(station:TStationBase) {_exposeToLua}
		Return GetStationMapCollection().CalculateAudienceDecrease(stations, station)
	End Method


	'buy a new antenna station at the given coordinates
	Method BuyAntennaStation:Int(x:Int,y:Int)
		Return AddStation( GetTemporaryAntennaStation( x, y ), True )
	End Method


	'buy a new cable network station at the given coordinates
	Method BuyCableNetworkStationByMapSection:Int(mapSection:TStationMapSection)
		if not mapSection then return False
		
		Return AddStation( GetTemporaryCableNetworkStation( mapSection.name ), True )
	End Method


	'buy a new cable network station at the given coordinates
	Method BuyCableNetworkStation:Int(stateName:string)
		Return AddStation( GetTemporaryCableNetworkStation( stateName ), True )
	End Method


	'buy a new satellite station at the given coordinates
	Method BuySatelliteStation:Int(satelliteNumber:int)
		Return AddStation( GetTemporarySatelliteStation( satelliteNumber ), True )
	End Method


	'sell a station at the given position in the list
	Method SellStation:Int(position:Int)
		Local station:TStationBase = getStationAtIndex(position)
		If station Then Return RemoveStation(station, True)
		Return False
	End Method


	Method AddStation:Int(station:TStationBase, buy:Int=False)
		If Not station Then Return False

		'try to buy it (does nothing if already done)
		If buy And Not station.Buy(owner) Then Return False
		'set to paid in all cases
		station.SetFlag(TVTStationFlag.PAID, True)

		'so station names "grow"
		stationsAdded[station.stationType] :+ 1

		'give it a name
		if station.name = "" then station.name = "#"+stationsAdded[station.stationType]

		stations.AddLast(station)

		'DO NOT refresh the share map as ths would increase potential
		'audience in this moment. Generate it as soon as a station gets
		'"ready" (before next audience calculation - means xx:04 or xx:59)
		'GetStationMapCollection().GenerateShareMap()

		'ALSO DO NOT recalculate audience of channel
		'RecalculateAudienceSum()

		TLogger.Log("TStationMap.AddStation", "Player"+owner+" buys broadcasting station ["+station.GetTypeName()+"] for " + station.price + " Euro (reach +" + station.reach + ")", LOG_DEBUG)

		'emit an event so eg. network can recognize the change
		If fireEvents Then EventManager.triggerEvent( TEventSimple.Create( "stationmap.addStation", New TData.add("station", station), Self ) )

		Return True
	End Method


	Method RemoveStation:Int(station:TStationBase, sell:Int=False, forcedRemoval:Int=False)
		If Not station Then Return False

		If Not forcedRemoval
			'not allowed to sell this station
			If Not station.HasFlag(TVTStationFlag.SELLABLE) Then Return False

			'check if we try to sell our last station...
			If stations.count() = 1
				EventManager.triggerEvent(TEventSimple.Create("StationMap.onTrySellLastStation", Null, Self))
				Return False
			EndIf
		EndIf

		If sell And Not station.sell() Then Return False

		stations.Remove(station)

		If sell
			TLogger.Log("TStationMap.AddStation", "Player"+owner+" sells broadcasting station for " + station.getSellPrice() + " Euro (had a reach of " + station.reach + ")", LOG_DEBUG)
		Else
			TLogger.Log("TStationMap.AddStation", "Player"+owner+" trashes broadcasting station for 0 Euro (had a reach of " + station.reach + ")", LOG_DEBUG)
		EndIf


		'refresh the share map (needed for audience calculations)
		GetStationMapCollection().GenerateShareMap()
		'recalculate audience of channel
		RecalculateAudienceSum()

		'when station is sold, audience will decrease,
		'while a buy will not increase the current audience but the
		'next block (news or programme)
		'-> handled in main.bmx with a listener to "stationmap.removeStation"

		'emit an event so eg. network can recognize the change
		If fireEvents Then EventManager.triggerEvent(TEventSimple.Create("StationMap.removeStation", New TData.add("station", station), Self))

		Return True
    End Method


	Method CalculateStationCosts:Int() {_exposeToLua}
		Local costs:Int = 0
		For Local Station:TStationBase = EachIn stations
			costs :+ station.GetRunningCosts()
		Next
		Return costs
	End Method


	Method GetShowStation:int(channelNumber:int)
		if channelNumber > showStations.length or channelNumber <= 0 then return False

		Return showStations[channelNumber-1]
	End Method


	Method SetShowStation(channelNumber:int, enable:int)
		if channelNumber > showStations.length or channelNumber <= 0 then return

		showStations[channelNumber-1] = enable
	End Method
	

	Method Update()
		'delete unused
		if GetStationMapCollection().stationMaps.length < showStations.length
			showStations = showStations[.. GetStationMapCollection().stationMaps.length + 1]
		'add new one (show them by default)
		elseif GetStationMapCollection().stationMaps.length > showStations.length
			local add:int = GetStationMapCollection().stationMaps.length - showStations.length

			showStations = showStations[.. showStations.length + add]

			For local i:int = 0 until add
				showStations[showStations.length - 1 - i] = 1
			Next
		endif
	
		UpdateStations()
	End Method


	Method UpdateStations()
		For Local station:TStationBase = EachIn stations
			station.Update()
		Next
	End Method


	Method DrawStations()
		For Local station:TStationBase = EachIn stations
			station.Draw()
		Next
	End Method


	'draw a players stationmap
	Method Draw()
		SetColor 255,255,255

		'draw all stations from all players (except filtered)
		For local map:TStationMap = eachin GetStationMapCollection().stationMaps
			If Not GetShowStation(map.owner) Then Continue
			map.DrawStations()
		Next
	End Method
End Type




Type TStationBase Extends TOwnedGameObject {_exposeToLua="selected"}
	'location at the station map
	'for satellites it is the "starting point", for cable networks and
	'antenna stations a point in the federal state
	Field pos:TVec2D {_exposeToLua}

	Field reach:Int	= -1
	'increase of reach at when bought
	Field reachIncrease:Int = -1
	'decrease of reach when bought (= increase in that state)
	Field reachDecrease:Int = -1
	Field price:Int	= -1
	'daily costs for "running" the station
	Field runningCosts:int = -1
	Field owner:Int = 0
	'time at which the station was bought
	Field built:Double = 0
	'time at which the station gets active (again)
	Field activationTime:Double = -1
	Field federalState:String = "" {nosave}
	Field name:string = ""
	Field stationType:int = 0
	'various settings (paid, fixed price, sellable, active...)
	Field _flags:Int = 0

	Field listSpriteNameOn:string = "gfx_datasheet_icon_antenna.on"
	Field listSpriteNameOff:string = "gfx_datasheet_icon_antenna.off"


	Method Init:TStationBase( pos:TVec2D, price:Int=-1, owner:Int)
		self.owner = owner
		self.pos = pos
		self.price = price
		self.built = GetWorldTime().getTimeGone()
		self.activationTime = -1

		self.SetFlag(TVTStationFlag.FIXED_PRICE, (price <> -1))
		'by default each station could get sold
		self.SetFlag(TVTStationFlag.SELLABLE, True)

		self.RefreshData()

		'save on compution for "initial states"
		self.reachDecrease = self.reachIncrease

		Return self
	End Method


	Method GenerateGUID:string()
		return "stationbase-"+id
	End Method


	'refresh the station data
	Method refreshData() {_exposeToLua}
		getReach(True)
		getReachIncrease(True)
		'save on compution for "initial states" - do it on "create"
		'getReachDecrease(True)
		getPrice( Not HasFlag(TVTStationFlag.FIXED_PRICE) )
	End Method


	Method HasFlag:Int(flag:Int)
		Return _flags & flag
	End Method


	Method SetFlag(flag:Int, enable:Int=True)
		If enable
			_flags :| flag
		Else
			_flags :& ~flag
		EndIf
	End Method


	'returns the age in days
	Method GetAge:Int()
		Return GetWorldTime().GetDay() - GetWorldTime().GetDay(Self.built)
	End Method


	'returns the age in minutes
	Method GetAgeInMinutes:Int()
		Return (GetWorldTime().GetTimeGone() - Self.built) / 60
	End Method


	Method GetActivationTime:Double()
		Return activationTime
	End Method


	'get the reach of that station
	Method GetReach:Int(refresh:Int=False) {_exposeToLua}
		If reach >= 0 And Not refresh Then Return reach
		reach = GetStationMapCollection().CalculateStationReach(Int(pos.x), Int(pos.y))

		Return reach
	End Method


	'get the relative reach increase of that station
	Method GetRelativeReachIncrease:Int(refresh:Int=False) {_exposeToLua}
		Local r:Float = getReach(refresh)
		If r = 0 Then Return 0

		Return getReachIncrease(refresh) / r
	End Method


	Method GetReachIncrease:Int(refresh:Int=False) {_exposeToLua}
		If reachIncrease >= 0 And Not refresh Then Return reachIncrease

		If owner <= 0
			Print "getReachIncrease: owner is not a player."
			Return 0
		EndIf

		reachIncrease = GetStationMap(owner).CalculateAudienceIncrease(Int(pos.x), Int(pos.y))

		Return reachIncrease
	End Method


	Method GetReachDecrease:Int(refresh:Int=False) {_exposeToLua}
		If reachDecrease >= 0 And Not refresh Then Return reachDecrease

		If owner <= 0
			Print "getReachDecrease: owner is not a player."
			Return 0
		EndIf

		reachDecrease = GetStationMapCollection().GetMap(owner).CalculateAudienceDecrease(Self)

		Return reachDecrease
	End Method


	Method GetFederalState:String(refresh:Int=False) {_exposeToLua}
		If federalState <> "" And Not refresh Then Return federalState

		Local hoveredSection:TStationMapSection = TStationMapSection.get(Int(pos.x), Int(pos.y))
		If hoveredSection Then federalState = hoveredSection.name

		Return federalState
	End Method


	Method GetSellPrice:Int(refresh:Int=False) {_exposeToLua}
		'price is multiplied by an age factor of 0.75-0.95
		Local factor:Float = Max(0.75, 0.95 - Float(getAge())/1.0)
		If price >= 0 And Not refresh Then Return Int(price * factor / 10000) * 10000

		Return Int( getPrice(refresh) * factor / 10000) * 10000
	End Method


	Method GetPrice:Int(refresh:Int=False) {_exposeToLua}
		If price >= 0 And Not refresh Then Return price
		price = Max( 30000, Int(Ceil(getReach() / 10000)) * 30000 )

		Return price
	End Method


	Method GetName:string()
		return name
	End Method


	Method GetTypeName:string()
		return "stationbase"
	End Method


	Method GetLongName:string()
		if GetName() then return GetTypeName() + " " + GetName()
		return GetTypeName()
	End Method


	Method IsActive:Int()
		Return HasFlag(TVTStationFlag.ACTIVE)
	End Method


	'set time a station begins to work (broadcast)
	Method SetActivationTime:Int(activationTime:Double = -1)
		If activationTime < 0 Then activationTime = GetWorldTime().GetTimeGone()
		Self.activationTime = activationTime

		If activationTime < GetWorldTime().GetTimeGone() Then SetActive()
	End Method


	'set time a station begins to work (broadcast)
	Method SetActive:Int()
		If IsActive() Then Return False

		Self.activationTime = GetWorldTime().GetTimeGone()
		SetFlag(TVTStationFlag.ACTIVE, True)

		'inform others (eg. to recalculate audience)
		EventManager.triggerEvent(TEventSimple.Create("station.onSetActive", Null, Self))
	End Method


	Method SetInactive:Int()
		If Not IsActive() Then Return False

		SetFlag(TVTStationFlag.ACTIVE, False)

		'inform others (eg. to recalculate audience)
		EventManager.triggerEvent(TEventSimple.Create("station.onSetInactive", Null, Self))
	End Method


	Method GetConstructionTime:Int()
		If GameRules.stationConstructionTime = 0 Then Return 0

		Local r:Int = GetReach()
		If r < 500000
			Return 1 * GameRules.stationConstructionTime
		ElseIf r < 1000000
			Return 2 * GameRules.stationConstructionTime
		ElseIf r < 2500000
			Return 3 * GameRules.stationConstructionTime
		ElseIf r < 5000000
			Return 4 * GameRules.stationConstructionTime
		Else
			Return 5 * GameRules.stationConstructionTime
		EndIf
	End Method


	Method GetRunningCosts:int() {_exposeToLua}
		return 0
	End Method


	Method Sell:Int()
		If Not GetPlayerFinance(owner) Then Return False

		If GetPlayerFinance(owner).SellStation( getSellPrice() )
			owner = 0
			Return True
		EndIf
		Return False
	End Method


	Method Buy:Int(playerID:Int)
		'set activation time (and refresh built time)
		built = GetWorldTime().GetTimeGone()

		Local constructionTime:Int = GetConstructionTime()
		'do not allow negative values as a "ready now" is not possible
		'because it affects broadcasted audience then.
		'if constructionTime <  0
		'	SetActivationTime( GetWorldTime().GetTimeGone()-1)
		'else
			If constructionTime <  0 Then constructionTime = 0

			constructionTime :+ 1

			'next hour (+construction hours) at xx:00
			If GetWorldTime().GetDayMinute(built + constructionTime*3600) >= 5
				SetActivationTime( GetWorldTime().MakeTime(0, 0, GetWorldTime().GetHour(built + constructionTime*3600), 0))
			'this hour (+construction hours) at xx:05
			Else
				SetActivationTime( GetWorldTime().MakeTime(0, 0, GetWorldTime().GetHour() + (constructionTime-1), 5, 0))
			EndIf
		'endif


		If HasFlag(TVTStationFlag.PAID) Then Return True
		If Not GetPlayerFinance(playerID) Then Return False

		If GetPlayerFinance(playerID).PayStation( getPrice() )
			owner = playerID
			SetFlag(TVTStationFlag.PAID, True)

			Return True
		EndIf

		Return False
	End Method


	Method Update:Int()
		'check if it becomes ready
		If Not IsActive()
			'TODO: if wanted, check for RepairStates or such things

			If GetActivationTime() < GetWorldTime().GetTimeGone()
				SetActive()
			EndIf
		EndIf
	End Method


	'how much a potentially drawn sprite is offset (eg. for a boundary
	'circle like for antennas)
	Method GetOverlayOffsetY:int()
		return 0
	End Method


	Method DrawInfoTooltip()
		Local textH:Int =  GetBitmapFontManager().baseFontBold.getHeight( "Tg" )
		Local tooltipW:Int = 180
		Local tooltipH:Int = textH * 4 + 10 + 5
		If GetConstructionTime() > 0
			tooltipH :+ textH
		EndIf

		Local tooltipX:Int = pos.x +20 - tooltipW/2
		Local tooltipY:Int = pos.y - GetOverlayOffsetY() - tooltipH

		'move below station if at screen top
		If tooltipY < 20 Then tooltipY = pos.y + GetOverlayOffsetY() + 10 +10
		tooltipX = Max(20,tooltipX)
		tooltipX = Min(585-tooltipW,tooltipX)

		SetAlpha 0.5
		SetColor 0,0,0
		DrawRect(tooltipX,tooltipY,tooltipW,tooltipH)
		SetColor 255,255,255
		SetAlpha 1.0

		Local textY:Int = tooltipY+5
		Local textX:Int = tooltipX+5
		Local textW:Int = tooltipW-10
		Local colorWhite:TColor = TColor.Create(255,255,255)
		GetBitmapFontManager().baseFontBold.drawStyled( getLocale("MAP_COUNTRY_"+getFederalState()), textX, textY, TColor.Create(255,255,0), 2)
		textY:+ textH + 5

		GetBitmapFontManager().baseFont.draw(GetLocale("REACH")+": ", textX, textY)
		GetBitmapFontManager().baseFontBold.drawBlock(TFunctions.convertValue(getReach(), 2), textX, textY, textW, 20, New TVec2D.Init(ALIGN_RIGHT), colorWhite)
		textY:+ textH

		GetBitmapFontManager().baseFont.draw(GetLocale("INCREASE")+": ", textX, textY)
		GetBitmapFontManager().baseFontBold.drawBlock(TFunctions.convertValue(getReachIncrease(), 2), textX, textY, textW, 20, New TVec2D.Init(ALIGN_RIGHT), colorWhite)
		textY:+ textH

		If GetConstructionTime() > 0
			GetBitmapFontManager().baseFont.draw(GetLocale("CONSTRUCTION_TIME")+": ", textX, textY)
			GetBitmapFontManager().baseFontBold.drawBlock(GetConstructionTime()+"h", textX, textY, textW, 20, New TVec2D.Init(ALIGN_RIGHT), colorWhite)
			textY:+ textH
		EndIf

		GetBitmapFontManager().baseFont.draw(GetLocale("PRICE")+": ", textX, textY)
		GetBitmapFontManager().baseFontBold.drawBlock(TFunctions.convertValue(getPrice(), 2), textX, textY, textW, 20, New TVec2D.Init(ALIGN_RIGHT), colorWhite)
	End Method


	Method DrawActivationTooltip()
		Local textCaption:String = getLocale("STATION_UNDER_CONSTRUCTION")
		Local textContent:String = GetLocale("READY_AT_TIME_X")
		Local readyTime:String = GetWorldTime().GetFormattedTime(GetActivationTime())
		'prepend day if it does not finish today
		If GetWorldTime().GetDay() < GetWorldTime().GetDay(GetActivationTime())
			readyTime = GetWorldTime().GetFormattedDay(GetWorldTime().GetDaysRun(GetActivationTime()) +1) + " " + readyTime
			textContent = GetLocale("READY_AT_DAY_X")
		EndIf
		textContent = textContent.Replace("%TIME%", readyTime)


		Local textH:Int = GetBitmapFontManager().baseFontBold.getHeight( "Tg" )
		Local textW:Int = GetBitmapFontManager().baseFontBold.getWidth(textCaption)
		textW = Max(textW, GetBitmapFontManager().baseFont.getWidth(textContent))
		Local tooltipW:Int = textW + 10
		Local tooltipH:Int = textH * 2 + 10 + 5
		Local tooltipX:Int = pos.x - tooltipW/2
		Local tooltipY:Int = pos.y - GetOverlayOffsetY() - tooltipH

		'move below station if at screen top
		If tooltipY < 20 Then tooltipY = pos.y + GetOverlayOffsetY() + 10 +10
		tooltipX = Max(20,tooltipX)
		tooltipX = Min(585-tooltipW,tooltipX)

		SetAlpha 0.5
		SetColor 0,0,0
		DrawRect(tooltipX,tooltipY,tooltipW,tooltipH)
		SetColor 255,255,255
		SetAlpha 1.0

		Local textY:Int = tooltipY+5
		Local textX:Int = tooltipX+5
		Local colorWhite:TColor = TColor.Create(255,255,255)
		GetBitmapFontManager().baseFontBold.drawStyled(textCaption, textX, textY, TColor.Create(255,255,0), 2)
		textY:+ textH + 5

		GetBitmapFontManager().baseFont.draw(textContent, textX, textY)
		textY:+ textH
	End Method


	Method Draw(selected:Int=False)
		'
	End Method
End Type




'compatibility for now
Type TStation Extends TStationAntenna {_exposeToLua="selected"}
	'override
	Method Init:TStation( pos:TVec2D, price:Int=-1, owner:Int)
		Super.Init(pos, price, owner)
		return self
	End Method
End Type




Type TStationAntenna Extends TStationBase {_exposeToLua="selected"}
	Field radius:Int = 0


	Method New()
		radius = GetStationMapCollection().antennaStationRadius
	End Method


	'override
	Method Init:TStationAntenna( pos:TVec2D, price:Int=-1, owner:Int)
		Super.Init(pos, price, owner)
		stationType = TVTStationType.ANTENNA
		return self
	End Method


	'override
	Method GenerateGUID:string()
		return "station-antenna-"+id
	End Method


	'override
	Method GetTypeName:string()
		return GetLocale("STATION")
	End Method


	'override
	Method GetRunningCosts:int() {_exposeToLua}
		if HasFlag(TVTStationFlag.NO_RUNNING_COSTS) then return 0
		
		local result:int = 0

		'== ADD STATIC RUNNING COSTS ==
		if runningCosts = -1
			rem
			                       daily costs
				   price       old    static   dynamic
				  100000      2000      3000      2000        2^1.2 =   2.30 =   2
				  250000      5000      7500      6000        5^1.2 =   6.90 =   6
				  500000     10000     15000     15000       10^1.2 =  15.85 =  15
				 1000000     20000     30000     36000       20^1.2 =  36.41 =  36
				 2500000     50000     75000    109000       50^1.2 = 109.34 = 109
				 5000000    100000    150000    251000      100^1.2 = 251.19 = 251
				10000000    200000    300000    577000      200^1.2 = 577.08 = 577
				25000000    500000    750000   1732000      500^1.2 =1732.86 =1732
			endrem
			'dynamic
			'runningCosts = 1000 * Floor(Ceil(price / 50000.0)^1.2)

			'static
			runningCosts = 1500 * ceil(price / 50000.0)
		endif
		result :+ runningCosts


		'== ADD RELATIVE MAINTENANCE COSTS ==
		if GameRules.stationIncreaseDailyMaintenanceCosts
			'the older a station gets, the more the running costs will be
			'(more little repairs and so on)
			'2% per day
			local maintenanceCostsPercentage:int = GameRules.stationDailyMaintenanceCostsPercentage * GetAge()
			'negative values deactivate the limit, positive once limit it
			if GameRules.stationDailyMaintenanceCostsPercentageTotalMax >= 0
				maintenanceCostsPercentage = Min(maintenanceCostsPercentage, GameRules.stationDailyMaintenanceCostsPercentageTotalMax)
			endif

			'1000 is "block size"
			result = 1000*int( (result * (1.0 + maintenanceCostsPercentage))/1000 )
		endif

		return result
	End Method


	'override
	Method GetOverlayOffsetY:int()
		return radius
	End Method
	

	Method Draw(selected:Int=False)
		Local sprite:TSprite = Null
		Local oldAlpha:Float = GetAlpha()

		If selected
			'white border around the colorized circle
			SetAlpha 0.25 * oldAlpha
			DrawOval(pos.x - radius - 2, pos.y - radius -2, 2 * (radius + 2), 2 * (radius + 2))

			SetAlpha Float(Min(0.9, Max(0,Sin(Time.GetAppTimeGone()/3)) + 0.5 ) * oldAlpha)
		Else
			SetAlpha 0.4 * oldAlpha
		EndIf

		Local color:TColor
		Select owner
			Case 1,2,3,4	color = TPlayerColor.GetByOwner(owner)
							sprite = GetSpriteFromRegistry("stationmap_antenna"+owner)
			Default			color = TColor.clWhite
							sprite = GetSpriteFromRegistry("stationmap_antenna0")
		End Select
		color.SetRGB()
		DrawOval(pos.x - radius, pos.y - radius, 2 * radius, 2 * radius)
		color.Copy().Mix(TColor.clWhite, 0.75).SetRGB()
		DrawOval(pos.x - radius + 2, pos.y - radius + 2, 2 * (radius - 2), 2 * (radius - 2))


		SetColor 255,255,255
		SetAlpha OldAlpha
		sprite.Draw(pos.x, pos.y + 1, -1, ALIGN_CENTER_CENTER)
	End Method
End Type




Type TStationCableNetwork extends TStationBase
	'override
	Method Init:TStationCableNetwork( pos:TVec2D, price:Int=-1, owner:Int)
		Super.Init(pos, price, owner)
		stationType = TVTStationType.CABLE_NETWORK
		return self
	End Method


	'override
	Method GenerateGUID:string()
		return "station-cablenetwork-"+id
	End Method


	'override
	Method GetTypeName:string()
		return GetLocale("CABLE_NETWORK")
	End Method


	'override
	Method GetRunningCosts:int() {_exposeToLua}
		if HasFlag(TVTStationFlag.NO_RUNNING_COSTS) then return 0
		
		local result:int = 0

		'== ADD STATIC RUNNING COSTS ==
		if runningCosts = -1
			rem
			                       daily costs
				   price       old    static   dynamic
				  100000      2000      3000      2000        2^1.2 =   2.30 =   2
				  250000      5000      7500      6000        5^1.2 =   6.90 =   6
				  500000     10000     15000     15000       10^1.2 =  15.85 =  15
				 1000000     20000     30000     36000       20^1.2 =  36.41 =  36
				 2500000     50000     75000    109000       50^1.2 = 109.34 = 109
				 5000000    100000    150000    251000      100^1.2 = 251.19 = 251
				10000000    200000    300000    577000      200^1.2 = 577.08 = 577
				25000000    500000    750000   1732000      500^1.2 =1732.86 =1732
			endrem
			'dynamic
			'runningCosts = 1000 * Floor(Ceil(price / 50000.0)^1.2)

			'static
			runningCosts = 1500 * ceil(price / 50000.0)
		endif
		result :+ runningCosts


		'== ADD RELATIVE MAINTENANCE COSTS ==
		if GameRules.stationIncreaseDailyMaintenanceCosts
			'the older a station gets, the more the running costs will be
			'(more little repairs and so on)
			'2% per day
			local maintenanceCostsPercentage:int = GameRules.stationDailyMaintenanceCostsPercentage * GetAge()
			'negative values deactivate the limit, positive once limit it
			if GameRules.stationDailyMaintenanceCostsPercentageTotalMax >= 0
				maintenanceCostsPercentage = Min(maintenanceCostsPercentage, GameRules.stationDailyMaintenanceCostsPercentageTotalMax)
			endif

			'1000 is "block size"
			result = 1000*int( (result * (1.0 + maintenanceCostsPercentage))/1000 )
		endif

		return result
	End Method


	Method Draw(selected:Int=False)
		Local sprite:TSprite = Null
		Local oldAlpha:Float = GetAlpha()

		If selected
			'white border around the hovered map section
			SetAlpha 0.25 * oldAlpha

			'TODO
			DrawText("TODO SELECTED", pos.x, pos.y)

			SetAlpha Float(Min(0.9, Max(0,Sin(Time.GetAppTimeGone()/3)) + 0.5 ) * oldAlpha)
		Else
			SetAlpha 0.4 * oldAlpha
		EndIf

		Local color:TColor
		Select owner
			Case 1,2,3,4	color = TPlayerColor.GetByOwner(owner)
							sprite = GetSpriteFromRegistry("stationmap_antenna"+owner)
			Default			color = TColor.clWhite
							sprite = GetSpriteFromRegistry("stationmap_antenna0")
		End Select
		color.SetRGB()
		'TODO: section hervorheben
		color.Copy().Mix(TColor.clWhite, 0.75).SetRGB()
		'TODO: section hervorheben


		SetColor 255,255,255
		SetAlpha OldAlpha
		sprite.Draw(pos.x, pos.y + 1, -1, ALIGN_CENTER_CENTER)
	End Method
End Type




Type TStationSatellite extends TStationBase
	'override
	Method Init:TStationSatellite( pos:TVec2D, price:Int=-1, owner:Int)
		Super.Init(pos, price, owner)
		stationType = TVTStationType.SATELLITE
		return self
	End Method


	'override
	Method GenerateGUID:string()
		return "station-satellite-"+id
	End Method


	'override
	Method GetTypeName:string()
		return GetLocale("SATELLITE")
	End Method


	'override
	Method GetRunningCosts:int() {_exposeToLua}
		if HasFlag(TVTStationFlag.NO_RUNNING_COSTS) then return 0
		
		local result:int = 0

		'== ADD STATIC RUNNING COSTS ==
		if runningCosts = -1
			rem
			                       daily costs
				   price       old    static   dynamic
				  100000      2000      3000      2000        2^1.2 =   2.30 =   2
				  250000      5000      7500      6000        5^1.2 =   6.90 =   6
				  500000     10000     15000     15000       10^1.2 =  15.85 =  15
				 1000000     20000     30000     36000       20^1.2 =  36.41 =  36
				 2500000     50000     75000    109000       50^1.2 = 109.34 = 109
				 5000000    100000    150000    251000      100^1.2 = 251.19 = 251
				10000000    200000    300000    577000      200^1.2 = 577.08 = 577
				25000000    500000    750000   1732000      500^1.2 =1732.86 =1732
			endrem
			'dynamic
			'runningCosts = 1000 * Floor(Ceil(price / 50000.0)^1.2)

			'static
			runningCosts = 1500 * ceil(price / 50000.0)
		endif
		result :+ runningCosts


		'== ADD RELATIVE MAINTENANCE COSTS ==
		if GameRules.stationIncreaseDailyMaintenanceCosts
			'the older a station gets, the more the running costs will be
			'(more little repairs and so on)
			'2% per day
			local maintenanceCostsPercentage:int = GameRules.stationDailyMaintenanceCostsPercentage * GetAge()
			'negative values deactivate the limit, positive once limit it
			if GameRules.stationDailyMaintenanceCostsPercentageTotalMax >= 0
				maintenanceCostsPercentage = Min(maintenanceCostsPercentage, GameRules.stationDailyMaintenanceCostsPercentageTotalMax)
			endif

			'1000 is "block size"
			result = 1000*int( (result * (1.0 + maintenanceCostsPercentage))/1000 )
		endif

		return result
	End Method


	Method Draw(selected:Int=False)
		Local sprite:TSprite = Null
		Local oldAlpha:Float = GetAlpha()

		If selected
			'white border around the hovered map section
			SetAlpha 0.25 * oldAlpha

			'TODO
			DrawText("TODO SELECTED", pos.x, pos.y)

			SetAlpha Float(Min(0.9, Max(0,Sin(Time.GetAppTimeGone()/3)) + 0.5 ) * oldAlpha)
		Else
			SetAlpha 0.4 * oldAlpha
		EndIf

		Local color:TColor
		Select owner
			Case 1,2,3,4	color = TPlayerColor.GetByOwner(owner)
							sprite = GetSpriteFromRegistry("stationmap_antenna"+owner)
			Default			color = TColor.clWhite
							sprite = GetSpriteFromRegistry("stationmap_antenna0")
		End Select
		color.SetRGB()
		'TODO: section hervorheben
		color.Copy().Mix(TColor.clWhite, 0.75).SetRGB()
		'TODO: section hervorheben


		SetColor 255,255,255
		SetAlpha OldAlpha
		sprite.Draw(pos.x, pos.y + 1, -1, ALIGN_CENTER_CENTER)
	End Method
End Type




Type TStationMapSection
	Field rect:TRectangle
	Field sprite:TSprite
	Field spriteName:String
	Field name:String
	Global sections:TList = CreateList()


	Method Create:TStationMapSection(pos:TVec2D, name:String, spriteName:String)
		Self.spriteName = spriteName
		Self.rect = New TRectangle.Init(pos.x,pos.y, 0, 0)
		Self.name = name
		Self.sprite = sprite
		Return Self
	End Method


	Method LoadSprite()
		sprite = GetSpriteFromRegistry(spriteName)
		'resize rect
		rect.dimension.SetXY(sprite.area.GetW(), sprite.area.GetH())
	End Method


	Function Get:TStationMapSection(x:Int,y:Int)
		For Local section:TStationMapSection = EachIn sections
			If Not section.sprite Then section.LoadSprite()
			If Not section.sprite Then Continue

			If section.rect.containsXY(x,y)
				If section.sprite.PixelIsOpaque(Int(x-section.rect.getX()), Int(y-section.rect.getY())) > 0
					Return section
				EndIf
			EndIf
		Next
		Return Null
	End Function


	Function GetByName:TStationMapSection(name:string)
		name = name.ToLower()
		For Local section:TStationMapSection = EachIn sections
			if section.name.ToLower() = name then return section
		Next
		return null
	End Function


	Function GetByListPosition:TStationMapSection(position:int)
		return TStationMapSection(sections.ValueAtIndex(position))
	End Function


	Function GetCount:int()
		return sections.Count()
	End Function


	Function GetNames:string[]()
		local names:string[] = new String[ sections.Count() ]
		For Local i:int = 0 until sections.Count()
			names[i] = TStationMapSection(sections.ValueAtIndex(i)).name.ToLower()
		Next
		return names
	End Function


	Function DrawAll()
		If Not sections Then Return
		Local oldA:Float = GetAlpha()
		SetAlpha oldA * 0.8
		For Local section:TStationMapSection = EachIn sections
			If Not section.sprite Then Continue
			section.sprite.Draw(section.rect.getx(), section.rect.gety())
		Next
		SetAlpha oldA
	End Function
	

	Function Reset:Int()
		sections = CreateList()
	End Function


	Method Add()
		sections.addLast(Self)
	End Method
End Type