SuperStrict
Import "Dig/base.gfx.gui.arrowbutton.bmx"
Import "game.screen.base.bmx"


Type TScreenHandler_OfficeStatistics extends TScreenHandler
	Field roomOwner:int = 0

	Field previousDayButton:TGUIArrowButton
	Field nextDayButton:TGUIArrowButton
	Field showDay:int = 0
	Field hoveredHour:int = -1

	Global LS_officeStatisticsScreen:TLowerString = TLowerString.Create("officeStatisticsScreen")

	Global programmeColor:TColor = new TColor.Create(110,180,100)
	Global newsColor:TColor = new TColor.Create(110,100,180)
	Global fontColor:TColor = TColor.CreateGrey(50)
	Global lightFontColor:TColor = TColor.CreateGrey(120)
	Global rankFontColor:TColor = TColor.CreateGrey(140)
	Global captionColor:TColor = new TColor.CreateGrey(70)
	Global backupColor:TColor = new TColor
	Global captionFont:TBitmapFont
	Global textFont:TBitmapFont
	Global boldTextFont:TBitmapFont
	Global smallTextFont:TBitmapFont
	Global smallBoldTextFont:TBitmapFont

	Global valueBG:TSprite
	Global valueBG2:TSprite

	Global _eventListeners:TLink[]
	Global _instance:TScreenHandler_OfficeStatistics


	Function GetInstance:TScreenHandler_OfficeStatistics()
		if not _instance then _instance = new TScreenHandler_OfficeStatistics
		return _instance
	End Function


	Method Initialize:int()
		local screen:TScreen = ScreenCollection.GetScreen("screen_office_statistics")
		if not screen then return False


		'=== create gui elements if not done yet
		if not previousDayButton
			previousDayButton = new TGUIArrowButton.Create(new TVec2D.Init(20, 10 + 11), new TVec2D.Init(24, 24), "LEFT", "officeStatisticsScreen")
			nextDayButton = new TGUIArrowButton.Create(new TVec2D.Init(20 + 175 + 20, 10 + 11), new TVec2D.Init(24, 24), "RIGHT", "officeStatisticsScreen")
		endif


		'=== remove all registered event listeners
		EventManager.unregisterListenersByLinks(_eventListeners)
		_eventListeners = new TLink[0]

		
		'=== register event listeners
		'listen to clicks on the four buttons
		_eventListeners :+ [ EventManager.registerListenerFunction("guiobject.onClick", onClickButtons, "TGUIArrowButton") ]
		'reset show day when entering a screen
		_eventListeners :+ [ EventManager.registerListenerFunction("screen.onBeginEnter", onEnterScreen, screen) ]


		'to update/draw the screen
		_eventListeners :+ _RegisterScreenHandler( onUpdate, onDraw, screen )

		'(re-)localize content
		SetLanguage()
	End Method


	Method SetLanguage()
		'nothing up to now
	End Method


	Method AbortScreenActions:Int()
		'nothing yet
	End Method


	'=== EVENTS ===

	'reset statistics show day to current when entering the screen
	Function onEnterScreen:int( triggerEvent:TEventBase )
		GetInstance().showDay = GetWorldTime().GetDay()
	End function

	
	Function onClickButtons:int(triggerEvent:TEventBase)
		local arrowButton:TGUIArrowButton = TGUIArrowButton(triggerEvent.GetSender())
		if not arrowButton then return False

		if arrowButton = GetInstance().nextDayButton then GetInstance().showDay :+ 1
		if arrowButton = GetInstance().previousDayButton then GetInstance().showDay :- 1
	End Function


	Function onDraw:int( triggerEvent:TEventBase )
		local room:TOwnedGameObject = TOwnedGameObject( triggerEvent.GetData().get("room") )
		if not room then return 0

		GetInstance().roomOwner = room.owner

		GetInstance().Render()
	End Function
	

	Function onUpdate:int( triggerEvent:TEventBase )
		local room:TOwnedGameObject = TOwnedGameObject( triggerEvent.GetData().get("room") )
		if not room then return 0

		GetInstance().roomOwner = room.owner

		GetInstance().Update()
	End Function


	Method Update()
		'disable "previou" or "newxt" button of finance display
		if showDay = 0 or showDay = GetWorldTime().GetStartDay()
			previousDayButton.Disable()
		else
			previousDayButton.Enable()
		endif

		if showDay = GetWorldTime().GetDay()
			nextDayButton.Disable()
		else
			nextDayButton.Enable()
		endif

		GetGameBase().cursorstate = 0
		GuiManager.Update( LS_officeStatisticsScreen)
	End Method
	

	Method Render()
		'=== CONFIG ===
		'to center it to table header according "font Baseline"
		local captionHeight:int = 20
		local startY:int
		'statistic for today
		local dailyBroadcastStatistic:TDailyBroadcastStatistic = GetDailyBroadcastStatistic(showDay, true)

		'fill cache
		if not valueBG then valueBG = GetSpriteFromRegistry("screen_financial_balanceValue")
		if not valueBG2 then valueBG2 = GetSpriteFromRegistry("screen_financial_balanceValue2filled")
		if not captionFont then captionFont = GetBitmapFont("Default", 14, BOLDFONT)
		if not textFont then textFont = GetBitmapFont("Default", 14)
		if not boldTextFont then boldTextFont = GetBitmapFont("Default", 14, BOLDFONT)
		if not smallTextFont then smallTextFont = GetBitmapFont("Default", 12)
		if not smallBoldTextFont then smallBoldTextFont = GetBitmapFont("Default", 12, BOLDFONt)

		'=== DAY CHANGER ===
		'how much days to draw
		local showHours:int = 24
		'where to draw + dimension
		local curveArea:TRectangle = new TRectangle.Init(29, 284, 738, 70)
		'heighest reached audience value of that hours
		Local maxValue:int = 0
		'minimum audience
		Local minValue:int = 0
		'color of labels
		Local labelColor:TColor = new TColor.CreateGrey(80)
		local audienceResult:TAudienceResultBase 

		'add 1 to "today" as we are on this day then
		local today:Double = GetWorldTime().MakeTime(0, showDay, 0, 0)
		local todayText:string = GetWorldTime().GetDayOfYear(today)+"/"+GetWorldTime().GetDaysPerYear()+" "+GetWorldTime().GetYear(today)
		textFont.DrawBlock(GetLocale("GAMEDAY")+" "+todayText, 50, 24, 160, 20, ALIGN_CENTER_CENTER, TColor.CreateGrey(30), 0, 1, 0.5)


		'=== UNAVAILABLE STATISTICS ===
		if GetDailyBroadcastStatisticCollection().minShowDay >= showDay
			textFont.DrawBlock(GetLocale("STATISTICS_NOT_AVAILABLE"), 20 + 4, 80 + 1, 175 - 4, 19, ALIGN_LEFT_CENTER, fontColor)

		'=== STATISTICS TABLE ===
		else
			'for PROGRAMME and NEWS
			For local progNewsIterator:int = 0 to 1
				local tableX:int = 20
				if progNewsIterator = 1 then tableX = 450 
			
				'the small added/subtracted numbers are for padding of the text
				local labelArea:TRectangle = new TRectangle.Init(tableX + 4, 80 + 1, 175-4, 19)
				local valueArea:TRectangle = new TRectangle.Init(labelArea.GetX2(), labelArea.GetY(), 155 - 5, 19)
				local captionArea:TRectangle = new TRectangle.Init(labelArea.GetX(), 57, 323, captionHeight)
				local bgArea:TRectangle = labelArea.Copy()
				bgArea.SetW( valueArea.GetX2() - labelArea.GetX() + 6)
				bgArea.position.SetXY( bgArea.GetX() - 3, bgArea.GetY() - 1 )

				local futureHour:int = False
				if showDay > GetWorldTime().GetDay()
					futureHour = True
				elseif showDay = GetWorldTime().GetDay()
					if hoveredHour > GetWorldTime().GetDayHour() or (progNewsIterator = 1 and hoveredHour = GetWorldTime().GetDayHour() and GetWorldTime().GetDayMinute() <= 4)
						futureHour = True
					endif
				endif
				
				'row backgrounds
				for local i:int = 0 to 7
					if i mod 2 = 0
						valueBG.DrawArea(bgArea.GetX(), bgArea.GetY(), bgArea.GetW(), bgArea.GetH())
					else
						valueBG2.DrawArea(bgArea.GetX(), bgArea.GetY(), bgArea.GetW(), bgArea.GetH())
					endif
					bgArea.position.AddY( bgArea.GetH() )
				Next


				audienceResult = null 
				local audienceRanks:int[]
				if hoveredHour >= 0
					if progNewsIterator = 1
						audienceResult = dailyBroadcastStatistic.GetAudienceResult(roomOwner, hoveredHour)
						audienceRanks = dailyBroadcastStatistic.GetAudienceRanking(roomOwner, hoveredHour)
					else
						audienceResult = dailyBroadcastStatistic.GetNewsAudienceResult(roomOwner, hoveredHour)
						audienceRanks = dailyBroadcastStatistic.GetNewsAudienceRanking(roomOwner, hoveredHour)
					endif
				endif

				'row entries
				if hoveredHour < 0 or hoveredHour > 23 or futureHour
					if progNewsIterator = 1
						captionFont.DrawBlock(GetLocale("PROGRAMME")+": "+GetLocale("AUDIENCE_RATING"), captionArea.GetX(), captionArea.GetY(),  captionArea.GetW(), captionArea.GetH(), ALIGN_CENTER_CENTER, captionColor, 1,,0.7)
					else
						captionFont.DrawBlock(GetLocale("NEWS")+": "+GetLocale("AUDIENCE_RATING"), captionArea.GetX(), captionArea.GetY(),  captionArea.GetW(), captionArea.GetH(), ALIGN_CENTER_CENTER, captionColor, 1,,0.7)
					endif
				elseif not audienceResult
					if progNewsIterator = 1
						captionFont.DrawBlock(GetLocale("PROGRAMME")+": "+GetLocale("BROADCASTING_OUTAGE"), captionArea.GetX(), captionArea.GetY(),  captionArea.GetW(), captionArea.GetH(), ALIGN_CENTER_CENTER, captionColor, 1,,0.5)
					else
						captionFont.DrawBlock(GetLocale("NEWS")+": "+GetLocale("BROADCASTING_OUTAGE"), captionArea.GetX(), captionArea.GetY(),  captionArea.GetW(), captionArea.GetH(), ALIGN_CENTER_CENTER, captionColor, 1,,0.5)
					endif
				else
					local title:string = audienceResult.GetTitle()
					if audienceResult.broadcastMaterial
						local programmePlan:TPlayerProgrammePlan = GetPlayerProgrammePlan(roomOwner)
						'real programme
						If TProgramme(audienceResult.broadcastMaterial)
							Local programme:TProgramme = TProgramme(audienceResult.broadcastMaterial)
							local blockText:string = " (" + getLocale("BLOCK") + " " + programmePlan.GetProgrammeBlock(showDay, hoveredHour) + "/" + programme.GetBlocks() + ")"
							If (programme.isSeriesEpisode() or programme.IsCollectionElement()) and programme.licence.parentLicenceGUID
								title = programme.licence.GetParentLicence().GetTitle() + " ("+ programme.GetEpisodeNumber() + "/" + programme.GetEpisodeCount()+"): " + programme.GetTitle() + blockText
							Else
								title = programme.GetTitle() + blockText
							EndIf
						ElseIf TAdvertisement(audienceResult.broadcastMaterial)
							title = GetLocale("PROGRAMME_PRODUCT_INFOMERCIAL")+": "+audienceResult.broadcastMaterial.GetTitle() + " (" + getLocale("BLOCK") + " " + programmePlan.GetProgrammeBlock(showDay, hoveredHour) + "/" + audienceResult.broadcastMaterial.GetBlocks() + ")"
						ElseIf TNews(audienceResult.broadcastMaterial)
							title = GetLocale("SPECIAL_NEWS_BROADCAST")+": "+audienceResult.broadcastMaterial.GetTitle() + " (" + getLocale("BLOCK") + " " + programmePlan.GetProgrammeBlock(showDay, hoveredHour) + "/" + audienceResult.broadcastMaterial.GetBlocks() + ")"
						ElseIf TNewsShow(audienceResult.broadcastMaterial)
							title = GetLocale("NEWS")+" - "+Rset(hoveredHour,2).Replace(" ","0")+":05"
						EndIf
					endif
					captionFont.DrawBlock(title, captionArea.GetX(), captionArea.GetY(),  captionArea.GetW(), captionArea.GetH(), ALIGN_CENTER_CENTER, captionColor, 1,,0.5)

					textFont.DrawBlock(GetLocale("AUDIENCE_NUMBER")+":", labelArea.GetX(), labelArea.GetY() + 0*labelArea.GetH(), labelArea.GetW(), labelArea.GetH(), ALIGN_LEFT_CENTER, fontColor)
					textFont.DrawBlock(GetLocale("POTENTIAL_AUDIENCE_NUMBER")+":", labelArea.GetX(), labelArea.GetY() + 1*labelArea.GetH(), labelArea.GetW(), labelArea.GetH(), ALIGN_LEFT_CENTER, fontColor)
					textFont.DrawBlock(GetLocale("BROADCASTING_AREA")+":", labelArea.GetX(), labelArea.GetY() + 2*labelArea.GetH(), labelArea.GetW(), labelArea.GetH(), ALIGN_LEFT_CENTER, fontColor)

					boldTextFont.drawBlock(MathHelper.DottedValue(audienceResult.audience.GetTotalSum()), valueArea.GetX(), valueArea.GetY() + 0*valueArea.GetH(), valueArea.GetW() - 80, valueArea.GetH(), ALIGN_RIGHT_CENTER, fontColor)
					boldTextFont.drawBlock(MathHelper.NumberToString(100.0 * audienceResult.GetAudienceQuotePercentage(), 2) + "%", valueArea.GetX(), valueArea.GetY() + 0*valueArea.GetH(), valueArea.GetW()-20, valueArea.GetH(), ALIGN_RIGHT_CENTER, lightFontColor)
					TextFont.drawBlock("#"+audienceRanks[0], valueArea.GetX(), valueArea.GetY() + 0*valueArea.GetH(), valueArea.GetW(), valueArea.GetH(), ALIGN_RIGHT_CENTER, rankFontColor)

					boldTextFont.drawBlock(TFunctions.convertValue(audienceResult.PotentialMaxAudience.GetTotalSum(),0), valueArea.GetX(), valueArea.GetY() + 1*valueArea.GetH(), valueArea.GetW() - 80, valueArea.GetH(), ALIGN_RIGHT_CENTER, fontColor)
					boldTextFont.drawBlock(MathHelper.NumberToString(100.0 * audienceResult.GetPotentialMaxAudienceQuotePercentage(), 2) + "%", valueArea.GetX(), valueArea.GetY() + 1*valueArea.GetH(), valueArea.GetW()-20, valueArea.GetH(), ALIGN_RIGHT_CENTER, lightFontColor)

					boldTextFont.drawBlock(TFunctions.convertValue(audienceResult.WholeMarket.GetTotalSum(),0), valueArea.GetX(), valueArea.GetY() + 2*valueArea.GetH(), valueArea.GetW() - 80, valueArea.GetH(), ALIGN_RIGHT_CENTER, fontColor)
					boldTextFont.drawBlock(MathHelper.NumberToString(100.0 * audienceResult.WholeMarket.GetTotalSum() / GetStationMapCollection().GetPopulation(), 2) + "%", valueArea.GetX(), valueArea.GetY() + 2*valueArea.GetH(), valueArea.GetW()-20, valueArea.GetH(), ALIGN_RIGHT_CENTER, lightFontColor)

					'target groups
					local halfWidth:int = 0.5 * (valueArea.GetX2() - labelArea.GetX())
					local splitter:int = 20

					local drawOnLeft:int = True
					For local i:int = 1 to 9
						local row:int = 3 + floor((i-1) / 2)

						if i >= 8 then row = 7
						if i = 8 then drawOnLeft = 1

						if drawOnLeft
							smallTextFont.DrawBlock(GetLocale("TARGETGROUP_"+TVTTargetGroup.GetAsString( TVTTargetGroup.GetAtIndex(i) )), labelArea.GetX(), labelArea.GetY() + row*labelArea.GetH(), halfWidth - splitter, labelArea.GetH(), ALIGN_LEFT_CENTER, fontColor)
							smallBoldTextFont.DrawBlock(TFunctions.convertValue( audienceResult.audience.GetTotalValue(TVTTargetGroup.GetAtIndex(i)), 0 ), labelArea.GetX(), labelArea.GetY() + row*labelArea.GetH(), halfWidth - splitter - 20, labelArea.GetH(), ALIGN_RIGHT_CENTER, fontColor)
							smallTextFont.DrawBlock("#"+audienceRanks[i], labelArea.GetX(), labelArea.GetY() + row*labelArea.GetH(), halfWidth - splitter, labelArea.GetH(), ALIGN_RIGHT_CENTER, rankFontColor)
						else
							smallTextFont.DrawBlock(GetLocale("TARGETGROUP_"+TVTTargetGroup.GetAsString( TVTTargetGroup.GetAtIndex(i) )), labelArea.GetX() + halfWidth + splitter, labelArea.GetY() + row*labelArea.GetH(), halfWidth - splitter, labelArea.GetH(), ALIGN_LEFT_CENTER, fontColor)
							smallBoldTextFont.DrawBlock(TFunctions.convertValue( audienceResult.audience.GetTotalValue(TVTTargetGroup.GetAtIndex(i)), 0 ), labelArea.GetX() +  halfWidth + splitter, labelArea.GetY() + row*labelArea.GetH(), halfWidth - splitter - 20, labelArea.GetH(), ALIGN_RIGHT_CENTER, fontColor)
							smallTextFont.DrawBlock("#"+audienceRanks[i], labelArea.GetX() +  halfWidth + splitter, labelArea.GetY() + row*labelArea.GetH(), halfWidth - splitter, labelArea.GetH(), ALIGN_RIGHT_CENTER, rankFontColor)
						endif
						drawOnLeft = 1 - drawOnLeft
					Next
				endif
			Next




			'=== DRAW MONEY CURVE ===
			startY = 253
			backupColor.Get()

			captionFont.DrawBlock(GetLocale("AUDIENCE_RATINGS"), 30, startY,  740, captionHeight, ALIGN_LEFT_CENTER, captionColor, 1,, 0.5)

			local dim:TVec2D
			local rightX:int = 0
			dim = smallTextFont.DrawBlock(GetLocale("PROGRAMME"), 30 + 370, startY+1, 370, 20, ALIGN_RIGHT_CENTER, TColor.CreateGrey(50), 1, 1, 0.7)
			rightX :+ dim.x + 5

			SetAlpha 0.5 * backupColor.a
			SetColor 0,0,0
			DrawRect(30 + 740 - rightX - 15 + 1, startY+3 +1, 15-2, 14-2)
			SetAlpha backupColor.a
			programmeColor.SetRGB()
			DrawRect(30 + 740 - rightX - 15, startY+3, 15, 14)
			rightX :+ 15 + 20

			dim = smallTextFont.DrawBlock(GetLocale("NEWS"), 30 + 370 , startY+1, 370 - rightX, 20, ALIGN_RIGHT_CENTER, TColor.CreateGrey(50), 1, 1, 0.7)
			rightX :+ dim.x + 5

			SetAlpha 0.5 * backupColor.a
			SetColor 0,0,0
			DrawRect(30 + 740 - rightX - 15 + 1, startY+3 +1, 15-2, 14-2)
			SetAlpha backupColor.a
			SetAlpha GetAlpha()*2.0
			newsColor.SetRGB()
			DrawRect(30 + 740 - rightX - 15, startY+3, 15, 14)

			backupColor.SetRGB()


			'first get the maximum value so we know how to scale the rest
			maxValue = dailyBroadcastStatistic.GetBestAudience(roomOwner).GetTotalSum()
			maxValue = max(maxValue, dailyBroadcastStatistic.GetBestNewsAudience(roomOwner).GetTotalSum())


			local slot:int				= 0
			local slotPos:TVec2D		= new TVec2D.Init(0,0)
			local previousSlotPos:TVec2D= new TVec2D.Init(0,0)
			'add 1 hour so half a slot could get added most left and right
			'to "center" the curve
			local slotWidth:Float 		= curveArea.GetW() / (showHours)

			local yPerViewer:Float = 0
			local yOfZero:Float = curveArea.GetH()
			if maxValue > 0 then yPerViewer = curveArea.GetH() / float(maxValue)

			hoveredHour = GetWorldTime().GetDayHour()
			For local i:Int = 0 To 23
				if THelper.MouseIn(int(curveArea.GetX() + slot * slotWidth), int(curveArea.GetY()), int(slotWidth), int(curveArea.GetH()))
					hoveredHour = i
					'leave for loop
					exit
				EndIf
				slot :+ 1
			Next

			if hoveredHour >= 0
				local time:Double = GetWorldTime().MakeTime(0, showDay, hoveredHour, 0)
				local gameDay:string = GetWorldTime().GetDay(time)

				local hoverX:int = curveArea.GetX() + slot * slotWidth
				local hoverW:int = Min(curveArea.GetX() + curveArea.GetW() - hoverX, slotWidth)
				if hoverX < curveArea.GetX() then hoverW = slotWidth / 2
				hoverX = Max(curveArea.GetX(), hoverX)

				local col:TColor = new TColor.Get()
				SetBlend LightBlend
				SetAlpha 0.1 * col.a
				DrawRect(hoverX, curveArea.GetY(), hoverW, curveArea.GetH())
				SetBlend AlphaBlend
				col.SetRGBA()
			EndIf

			'draw the curves
			SetLineWidth(2)
			GetGraphicsManager().EnableSmoothLines()

			local maxHour:int = 23
			if showDay = GetWorldTime().GetDay() then maxHour = GetWorldTime().GetDayHour()


			'CLOCK
			for local i:int = 0 to 23
				smallTextFont.DrawBlock(i, curveArea.GetX() + i*slotWidth, curveArea.GetY() + curveArea.GetH() + 2, slotWidth, 20, ALIGN_CENTER_CENTER, TColor.CreateGrey(80 + 40*(i mod 2)))
			next
			
			'NEWS and PROGRAMME
			for local broadcastType:int = Eachin [TVTBroadcastMaterialType.NEWSSHOW, TVTBroadcastMaterialType.PROGRAMME]
				local color:TColor
				local dx:int = 0
				slot = 0
				'move programmes a bit to the right (they are broadcasted
				'after the newsshow)
				if broadcastType = TVTBroadcastMaterialType.PROGRAMME
					color = programmeColor
					dx = 3
				else
					color = newsColor
					dx = -3
				endif

				slotPos.SetXY(dx - 0.5*slotWidth,0)

				
				For local i:Int = 0 To maxHour
					if broadcastType = TVTBroadcastMaterialType.PROGRAMME
						audienceResult = dailyBroadcastStatistic.GetAudienceResult(roomOwner, i)
					else
						audienceResult = dailyBroadcastStatistic.GetNewsAudienceResult(roomOwner, i)
					endif
					'skip not yet broadcasted programme
					if broadcastType = TVTBroadcastMaterialType.PROGRAMME
						if showDay = GetWorldTime().GetDay() and i = GetWorldTime().GetDayHour() and GetWorldTime().GetDayMinute() < 5 then continue
					endif

					previousSlotPos.SetXY(slotPos.x, slotPos.y)
					slotPos.AddX(slotWidth)
					'outtage?
					if not audienceResult
						slotPos.SetY(yOfZero)
						TColor.clRed.setRGB()
					else
						slotPos.SetY(yOfZero - audienceResult.audience.GetTotalSum() * yPerViewer)
						color.setRGB()
					endif
					
					SetAlpha 0.4
					DrawOval(curveArea.GetX() + slotPos.GetX()-4, curveArea.GetY() + slotPos.GetY()-4, 8, 8)
					SetAlpha 1.0
					'line color is not "red" if it is an outtage, only the ovals
					color.copy().AdjustRelative(-0.2).setRGB()
					if slot > 0
						DrawLine(curveArea.GetX() + previousSlotPos.GetX(), curveArea.GetY() + previousSlotPos.GetY(), curveArea.GetX() + slotPos.GetX(), curveArea.GetY() + slotPos.GetY())
					endif
					slot :+ 1
				Next
			Next
			SetColor 255,255,255

			SetLineWidth(1)

			'coord descriptor - min max values
			smallTextFont.drawBlock(TFunctions.convertValue(maxvalue,2,0), curveArea.GetX(), curveArea.GetY() + 1, curveArea.GetW() - 1, 20, ALIGN_RIGHT_TOP, labelColor)
			smallTextFont.drawBlock(TFunctions.convertValue(0 ,2,0), curveArea.GetX(), curveArea.GetY() + curveArea.GetH() - 19, curveArea.GetW() - 1, 20, ALIGN_RIGHT_BOTTOM, labelColor)
		endif

		GuiManager.Draw( LS_officeStatisticsScreen )
	End Method

	
End Type