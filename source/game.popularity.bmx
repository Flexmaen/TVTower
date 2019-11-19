SuperStrict
Import Brl.LinkedList
Import "Dig/base.util.event.bmx"
Import "Dig/base.util.mersenne.bmx"
Import "game.modifier.base.bmx"


Type TPopularityManager
	Field Popularities:TMap = CreateMap()
	Field updateInterval:int = 720	'update every x minutes (720 = 12*60)
	Field updateTimeLeft:int = 720	'time till next update (in game minutes)
	Global _instance:TPopularityManager


	Function GetInstance:TPopularityManager()
		if not _instance then _instance = new TPopularityManager
		return _instance
	End Function


	Method Initialize:int()
		'reset list
		Popularities.Clear()
		updateInterval = 720
		updateTimeLeft = 720
	End Method


	Method GetByGUID:TPopularity(GUID:String)
		Return TPopularity(Popularities.ValueForKey(GUID.ToLower()))
	End Method


	'call this once a game minute
	Method Update:Int(triggerEvent:TEventBase)
		updateTimeLeft :- 1
		'do not update until interval is gone
		if updateTimeLeft > 0 then return FALSE

		'print "TPopularityManager: Updating popularities"
		For Local popularity:TPopularity = EachIn Self.Popularities.Values()
			popularity.UpdatePopularity()
			popularity.AdjustTrendDirectionRandomly()
			popularity.UpdateTrend()
			'print " - referenceGUID "+popularity.referenceGUID + ":  P: " + popularity.Popularity + " - L: " + popularity.LongTermPopularity + " - T: " + popularity.Trend + " - S: " + popularity.Surfeit
		Next
		'reset time till next update
		updateTimeLeft = updateInterval
	End Method


	Method RemovePopularity(popularity:TPopularity)
		Popularities.Remove(popularity.referenceGUID.ToLower())
	End Method


	Method AddPopularity(popularity:TPopularity)
		Popularities.insert(popularity.referenceGUID.ToLower(), popularity)
	End Method
End Type

'===== CONVENIENCE ACCESSOR =====
Function GetPopularityManager:TPopularityManager()
	Return TPopularityManager.GetInstance()
End Function




Type TPopularity
	Field referenceGUID:string
	'Zu welchem Wert entwickelt sich die Popularität langfristig ohne
	'den Spielereinfluss (-50 bis +50)
	Field LongTermPopularity:Float
	'Wie populär ist das Element. Ein Wert üblicherweise zwischen -50
	'und +100 (es kann aber auch mehr oder weniger werden...)
	Field Popularity:Float
	'Wie entwicklet sich die Popularität
	Field Trend:Float
	'1 = Übersättigung des Trends
	Field Surfeit:Int
	'wenn bei 3, dann ist er übersättigt
	Field SurfeitCounter:Int

	'Untere/Obere Grenze der LongTermPopularity
	Field LongTermPopularityLowerBound:Int
	Field LongTermPopularityUpperBound:Int

	'Surfeit wird erreicht, wenn
	'Popularity > (LongTermPopularity + SurfeitUpperBoundAdd)
	Field SurfeitLowerBoundAdd:Int
	'Surfeit wird zurückgesetzt, wenn
	'Popularity <= (LongTermPopularity + SurfeitLowerBoundAdd)
	Field SurfeitUpperBoundAdd:Int
	'Für welchen Abzug sorgt die Übersättigung
	Field SurfeitTrendMalus:Int
	'Wie viel darf die Popularity über LongTermPopularity um angezählt zu werden?
	Field SurfeitCounterUpperBoundAdd:Int

	'Untergrenze für den Bergabtrend
	Field TrendLowerBound:Int
	'Obergrenze für den Bergauftrend
	Field TrendUpperBound:Int
	'Um welchen Teiler wird der Trend angepasst?
	Field TrendAdjustDivider:Int
	'Untergrenze/Obergrenze für Zufallsänderungen des Trends
	Field TrendRandRangLower:Int
	Field TrendRandRangUpper:Int

	'X%-Chance das sich die LongTermPopularity komplett wendet
	Field ChanceToChangeCompletely:Int
	'X%-Chance das sich die LongTermPopularity um einen Wert zwischen
	'ChangeLowerBound und ChangeUpperBound ändert
	Field ChanceToChange:Int
	'X%-Chance das sich die LongTermPopularity an den aktuellen
	'Popularitywert + Trend anpasst
	Field ChanceToAdjustLongTermPopularity:Int

	'Untergrenze/Obergrenze für Wertänderung wenn ChanceToChange eintritt
	Field ChangeLowerBound:Int
	Field ChangeUpperBound:Int

	'Field LogFile:TLogFile

	Function Create:TPopularity(referenceGUID:string, popularity:Float = 0.0, longTermPopularity:Float = 0.0)
		Local obj:TPopularity = New TPopularity
		obj.referenceGUID = referenceGUID
		obj.SetPopularity(popularity)
		obj.SetLongTermPopularity(longTermPopularity)
		'obj.LogFile = TLogFile.Create("Popularity Log", "PopularityLog" + referenceGUID + ".txt")
		Return obj
	End Function


	'Die Popularität wird üblicherweise am Ende des Tages aktualisiert,
	'entsprechend des gesammelten Trend-Wertes
	Method UpdatePopularity()
		Popularity = Popularity + Trend
		'Über dem absoluten Maximum
		If Popularity > LongTermPopularityUpperBound Then
			'Popularity = RandRange(LongTermPopularityUpperBound - 5, LongTermPopularityUpperBound + 5)
			If Popularity > LongTermPopularityUpperBound + SurfeitUpperBoundAdd Then
				StartSurfeit()
			Elseif Surfeit = 0 Then
				SurfeitCounter = SurfeitCounter + 1 'Wird angezählt
			Endif
		'Unter dem absoluten Minimum
		Elseif Popularity < LongTermPopularityLowerBound Then
			Popularity = RandRange(LongTermPopularityLowerBound - 5, LongTermPopularityLowerBound + 5)
			SetLongTermPopularity(LongTermPopularity + RandRange(0, 15))
		'Über dem Langzeittrend
		Elseif Popularity > (LongTermPopularity + SurfeitUpperBoundAdd) Then
			If Surfeit = 0 Then
				SurfeitCounter = SurfeitCounter + 1 'Wird angezählt
			Endif
		'Unter dem Langzeittrend
		Elseif Popularity <= (LongTermPopularity + SurfeitLowerBoundAdd) Then
			Popularity = Popularity + RandRange(0, 5)
		Elseif Popularity < (LongTermPopularityUpperBound / 4) Then
			SurfeitCounter = 0
		Endif

		If SurfeitCounter >= SurfeitCounterUpperBoundAdd Then
			StartSurfeit()
		Elseif Surfeit = 1 And Popularity <= LongTermPopularity Then
			EndSurfeit()
		Endif

		'LogFile.AddLog(Popularity + ";" + LongTermPopularity + ";" + Trend + ";" + Surfeit + ";" + SurfeitCounter, False)
	End Method


	Method StartSurfeit()
		Surfeit = 1
		SurfeitCounter = 0
		SetLongTermPopularity(RandRange(LongTermPopularityLowerBound, 0))
	End Method


	Method EndSurfeit()
		Surfeit = 0
		SurfeitCounter = 0
		SetLongTermPopularity(Popularity + RandRange(0, 15))
	End Method


	'Passt die LongTermPopularity mit einigen Wahrscheinlichkeiten an
	'oder ändert sie komplett
	Method AdjustTrendDirectionRandomly()
		'2%-Chance das der langfristige Trend komplett umschwenkt
		If RandRange(1,100) <= ChanceToChangeCompletely Then
			SetLongTermPopularity(RandRange(LongTermPopularityLowerBound, LongTermPopularityUpperBound))
		'10%-Chance das der langfristige Trend umschwenkt
		ElseIf RandRange(1,100) <= ChanceToChange Then
			SetLongTermPopularity(LongTermPopularity + RandRange(ChangeLowerBound, ChangeUpperBound))
		'25%-Chance das sich die langfristige Popularität etwas dem aktuellen Trend/Popularität anpasst
		Elseif RandRange(1,100) <= ChanceToAdjustLongTermPopularity Then
			SetLongTermPopularity(LongTermPopularity + ((Popularity-LongTermPopularity)/2) + Trend)
		Endif
	End Method


	'Der Trend wird am Anfang des Tages aktualisiert, er versucht die
	'Popularity an die LongTermPopularity anzugleichen.
	Method UpdateTrend()
		If Surfeit = 1 Then
			Trend = Trend - SurfeitTrendMalus
		Else
			If (Popularity < LongTermPopularity And Trend < 0) Or (Popularity > LongTermPopularity And Trend > 0) Then
				Trend = 0
			ElseIf Trend <> 0 Then
				Trend = Trend/2
			Endif

			local distance:float = (LongTermPopularity - Popularity) / TrendAdjustDivider
			Local random:Float = Float(RandRange(TrendRandRangLower, TrendRandRangUpper ))/TrendAdjustDivider
			Trend = Max(TrendLowerBound, Min(TrendUpperBound, Trend + distance + random))
		Endif
	End Method


	'Every broadcast of a genre, every activity of a person, ...
	'adjusts the trend (except surfeit kicked in already)
	Method ChangeTrend(changeValue:Float, adjustLongTermPopularity:float=0)
		If Surfeit
			'when subtracting - this would add then...
			'Trend :- changeValue

			Trend :- Max(0, changeValue)
		Else
			Trend :+ changeValue
		Endif

		If adjustLongTermPopularity <> 0
			SetLongTermPopularity(LongTermPopularity + adjustLongTermPopularity)
		Endif
	End Method


	Method SetPopularity(value:float)
		Popularity = value
	End Method


	Method ModifyPopularity(addPercentage:Float = 0.0, addValue:Float = 0.0)
		if addPercentage <> 0.0
			Popularity :* (1.0 + addPercentage)
		endif

		Popularity :+ addValue
	End Method


	Method SetLongTermPopularity(value:float)
		LongTermPopularity = Max(LongTermPopularityLowerBound, Min(LongTermPopularityUpperBound, value))
	End Method
End Type




'=== POPULARITY MODIFIERS ===

Type TGameModifierPopularity_ModifyPopularity extends TGameModifierBase
	Field popularityGUID:string = ""
	'value is divided by 100 - so 1000 becomes 10, 50 becomes 0.5)
	Field valueMin:Float = 0
	Field valueMax:Float = 0
	Field modifyProbability:int = 100


	'override to create this type instead of the generic one
	Function CreateNewInstance:TGameModifierPopularity_ModifyPopularity()
		return new TGameModifierPopularity_ModifyPopularity
	End Function


	Method Copy:TGameModifierPopularity_ModifyPopularity()
		local clone:TGameModifierPopularity_ModifyPopularity = new TGameModifierPopularity_ModifyPopularity
		clone.CopyBaseFrom(self)
		clone.popularityGUID = self.popularityGUID
		clone.valueMin = self.valueMin
		clone.valueMax = self.valueMax
		clone.modifyProbability = self.modifyProbability
		return clone
	End Method


	Method Init:TGameModifierPopularity_ModifyPopularity(data:TData, extra:TData=null)
		if not data then return null

		local index:string = ""
		if extra and extra.GetInt("childIndex") > 0 then index = extra.GetInt("childIndex")
		popularityGUID = data.GetString("guid"+index, data.GetString("guid", ""))
		if popularityGUID = ""
			TLogger.Log("TGameModifierPopularity_ModifyPopularity", "Init() failed - no popularity GUID given.", LOG_ERROR)
			return Null
		endif

		valueMin = data.GetFloat("valueMin"+index, 0.0)
		valueMax = data.GetFloat("valueMax"+index, 0.0)
		modifyProbability = data.GetInt("probability"+index, 100)

		return self
	End Method


	Method ToString:string()
		local name:string = data.GetString("name", "default")
		return "TGameModifierPopularity_ModifyPopularity ("+name+")"
	End Method


	'override to trigger a specific news
	Method RunFunc:int(params:TData)
		'skip if probability is missed
		if modifyProbability <> 100 and RandRange(0, 100) > modifyProbability then return False

		local popularity:TPopularity = GetPopularityManager().GetByGUID(popularityGUID)
		if not popularity
			TLogger.Log("TGameModifierPopularity_ModifyPopularity", "cannot find popularity to trigger: "+popularityGUID, LOG_ERROR)
			return false
		endif
		local changeBy:Float = RandRange(int(valueMin*1000), int(valueMax*1000))/1000.0
		'does adjust the "trend" (growth direction of popularity) not
		'popularity directly
		popularity.ChangeTrend(changeBy)
		popularity.SetPopularity(popularity.popularity + changeBy)
		'print "TGameModifierPopularity_ModifyPopularity: changed trend for ~q"+popularityGUID+"~q by "+changeBy+" to " + popularity.Popularity+"."

		return True
	End Method
End Type


GetGameModifierManager().RegisterCreateFunction("ModifyPopularity", TGameModifierPopularity_ModifyPopularity.CreateNewInstance)
