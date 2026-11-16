import XCTest

final class ArrangementUITests: XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch(_ screen:String="grid",runtimeTrace:Bool=false)->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen",screen,"--arrangement-clips","-AppleLanguages","(en)","-AppleLocale","en_US"]
        if runtimeTrace{app.launchArguments.append("--runtime-trace")}
        app.launch();XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        if screen=="grid"{wait(app.buttons["grid.mode.clips"],NSPredicate(format:"value == 'Clips'"))}
        return app
    }
    @MainActor private func wait(_ element:XCUIElement,_ predicate:NSPredicate){
        let expectation=XCTNSPredicateExpectation(predicate:predicate,object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:6),.completed)
    }
    @MainActor private func drag(_ source:XCUICoordinate,to destination:XCUICoordinate){
        // Give UIKit time to lift the native Transferable before moving, then
        // dwell over the receiver. A 0.6s press with immediate release raced the
        // lift/target registration in the recorded iOS 26 simulator run.
        source.press(forDuration:1.2,thenDragTo:destination,withVelocity:.slow,thenHoldForDuration:0.6)
    }
    @MainActor private func waitForClipPosition(_ clip:XCUIElement,x:CGFloat,length:String,in app:XCUIApplication){
        // Releasing the native gesture precedes asynchronous String item loading
        // and SwiftUI's publication of the validated drop. Wait for the exact
        // result of this single gesture; an unmoved or incorrectly snapped clip
        // must still fail, and no second drag is attempted.
        let settled=NSPredicate{_,_ in
            clip.exists && abs(clip.frame.minX-x)<=3 && clip.value as? String==length
        }
        let result=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:settled,object:clip)],timeout:6)
        let trace=app.descendants(matching:.any)["grid.drag-diagnostics"].firstMatch
        let traceValue=trace.exists ? trace.value as? String:nil
        let receipt=XCTAttachment(string:"Expected x=\(x), length=\(length); result=\(result); actual frame=\(clip.frame)\n"+(traceValue ?? "QA trace heading unavailable"))
        receipt.name="Arrangement-native-drop-trace";receipt.lifetime = .keepAlways;add(receipt)
        XCTAssertEqual(result,.completed,"Clip did not settle at x=\(x), length=\(length); actual frame=\(clip.frame), value=\(String(describing:clip.value))")
    }

    @MainActor func testPinchRetainsScrolledMusicalCenterWithoutEditingOrStopping()throws {
        let app=launch(runtimeTrace:true)
        let timeline=app.scrollViews["grid.timeline"]
        let zoomDiagnostics=app.staticTexts["grid.zoom-diagnostics"]
        let third=app.staticTexts["grid.bar.2"],fourth=app.staticTexts["grid.bar.3"]
        let clip=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.' AND label == 'Harmony'")).firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout:5));XCTAssertTrue(clip.waitForExistence(timeout:5))
        XCTAssertTrue(zoomDiagnostics.waitForExistence(timeout:5))
        XCTAssertTrue(third.waitForExistence(timeout:5));XCTAssertTrue(fourth.waitForExistence(timeout:5))
        let clipID=clip.identifier,length=clip.value as? String
        XCTAssertEqual(length,"4.00 bars");XCTAssertFalse(app.buttons["Undo"].isEnabled)
        let initialClip=clip.frame,initialThird=third.frame,initialFourth=fourth.frame
        let initialWidth=initialFourth.minX-initialThird.minX
        XCTAssertGreaterThan(initialWidth,0)
        let transport=app.buttons["perform.transport"]
        wait(transport,NSPredicate(format:"value CONTAINS 'ready=true'"))
        app.buttons["Play"].tap()
        wait(transport,NSPredicate(format:"value CONTAINS 'actualPlaying=1'"))
        let beforeTrace=try XCTUnwrap(transport.value as? String)
        func field(_ name:String,in trace:String)throws->String {
            let current=String(trace.split(separator:"\n",maxSplits:1).first ?? "")
            let expression=try NSRegularExpression(pattern:"\\b"+NSRegularExpression.escapedPattern(for:name)+"=([^\\s|]+)")
            let match=try XCTUnwrap(expression.firstMatch(in:current,range:NSRange(current.startIndex...,in:current)))
            let range=try XCTUnwrap(Range(match.range(at:1),in:current));return String(current[range])
        }
        let project=try field("project",in:beforeTrace),revision=try field("revision",in:beforeTrace),kernel=try field("kernel",in:beforeTrace)
        let clock=try XCTUnwrap(UInt64(field("actualClock",in:beforeTrace)))
        // Drag the ruler to establish a real nonzero horizontal offset. Fully
        // visible ruler landmarks avoid assumptions about offscreen clip AX
        // clipping or hittability. Their leading-edge delta is the bar width.
        let ruler=timeline.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:timeline.frame.width*0.75,dy:14))
        ruler.press(forDuration:0.05,thenDragTo:ruler.withOffset(CGVector(dx:-initialWidth,dy:0)),withVelocity:.slow,thenHoldForDuration:0.4)
        let panSettled=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in
            let a=third.frame,b=fourth.frame,view=timeline.frame
            return a.minX<initialThird.minX-40 && a.minX>=view.minX && b.maxX<=view.maxX+1
        },object:third)],timeout:6)
        let scrolledThird=third.frame,scrolledFourth=fourth.frame,viewFrame=timeline.frame
        let panReceipt=XCTAttachment(string:"Settle result=\(panSettled)\nViewport=\(viewFrame)\nRuler03=\(initialThird) → \(scrolledThird), ruler04=\(initialFourth) → \(scrolledFourth)\nClip=\(initialClip) → \(clip.frame), hittable=\(clip.isHittable)\n\(transport.value as? String ?? "Missing runtime trace")")
        panReceipt.name="Anchored-pinch actual ruler pan";panReceipt.lifetime = .keepAlways;add(panReceipt)
        XCTAssertEqual(panSettled,.completed)
        let widthBefore=scrolledFourth.minX-scrolledThird.minX
        XCTAssertGreaterThan(widthBefore,0)
        XCTAssertLessThan(scrolledThird.minX,initialThird.minX-40)
        func number(_ key:String,line prefix:String,in report:String)->Double? {
            guard let line=report.split(separator:"\n").first(where:{$0.hasPrefix(prefix+" ")}),
                  let token=line.split(separator:" ").first(where:{$0.hasPrefix(key+"=")}) else{return nil}
            return Double(token.dropFirst(key.count+1))
        }
        // XCTest chooses its own actual hit point and touch trigger distance.
        // The framework's raw startAnchor is an input, not a target/result from
        // our zoom helper. Corroborate it against exported two-finger events.
        // Read its pinned report from the existing header StaticText, whose AX
        // value is independent of the timeline's hosted native clip controls.
        timeline.pinch(withScale:1.1,velocity:1)
        var firstInput="",firstAnchorX=CGFloat.nan,barsBefore=CGFloat.nan
        let enlargedSettled=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in
            firstInput=zoomDiagnostics.value as? String ?? ""
            guard number("id",line:"BEGIN",in:firstInput)==1,
                  number("id",line:"REQUEST",in:firstInput)==1,
                  number("id",line:"ACK",in:firstInput)==1,
                  let unit=number("unitAnchorX",line:"BEGIN",in:firstInput),unit.isFinite,(0...1).contains(unit),
                  let rawWidth=number("viewportWidth",line:"BEGIN",in:firstInput),abs(rawWidth-Double(viewFrame.width))<=0.5 else{return false}
            firstAnchorX=viewFrame.minX+CGFloat(unit)*viewFrame.width
            barsBefore=2+(firstAnchorX-scrolledThird.minX)/widthBefore
            let a=third.frame,b=fourth.frame,view=timeline.frame,width=b.minX-a.minX
            guard width>0 else{return false}
            let center=2+(firstAnchorX-a.minX)/width
            return width>widthBefore*1.2 && abs(center-barsBefore)<=0.04 && a.minX>=view.minX && b.maxX<=view.maxX+1
        },object:third)],timeout:6)
        let enlargedThird=third.frame,enlargedFourth=fourth.frame
        let enlargedWidth=enlargedFourth.minX-enlargedThird.minX
        let barsEnlarged=2+(firstAnchorX-enlargedThird.minX)/enlargedWidth
        let firstReceipt=XCTAttachment(string:"Settle result=\(enlargedSettled)\nViewport=\(viewFrame) → \(timeline.frame), ruler03=\(scrolledThird) → \(enlargedThird), ruler04=\(scrolledFourth) → \(enlargedFourth)\nRaw-input global anchorX=\(firstAnchorX), actual bar widths=\(widthBefore) → \(enlargedWidth), anchor bars=\(barsBefore) → \(barsEnlarged)\n\(firstInput)\n\(transport.value as? String ?? "Missing runtime trace")")
        firstReceipt.name="Anchored-pinch first actual geometry";firstReceipt.lifetime = .keepAlways;add(firstReceipt)
        XCTAssertEqual(enlargedSettled,.completed)
        XCTAssertEqual(barsEnlarged,barsBefore,accuracy:0.04,"The real musical point under the actual finger anchor moved")
        let secondViewport=timeline.frame
        // A second gesture has its own physical anchor, which need not match
        // the first. Freeze that gesture's before-frames before performing it.
        timeline.pinch(withScale:0.75,velocity:-1)
        var secondInput="",secondAnchorX=CGFloat.nan,secondBarsBefore=CGFloat.nan
        let reducedSettled=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in
            secondInput=zoomDiagnostics.value as? String ?? ""
            guard number("id",line:"BEGIN",in:secondInput)==2,
                  number("id",line:"REQUEST",in:secondInput)==2,
                  number("id",line:"ACK",in:secondInput)==2,
                  let unit=number("unitAnchorX",line:"BEGIN",in:secondInput),unit.isFinite,(0...1).contains(unit),
                  let rawWidth=number("viewportWidth",line:"BEGIN",in:secondInput),abs(rawWidth-Double(secondViewport.width))<=0.5 else{return false}
            secondAnchorX=secondViewport.minX+CGFloat(unit)*secondViewport.width
            secondBarsBefore=2+(secondAnchorX-enlargedThird.minX)/enlargedWidth
            let a=third.frame,b=fourth.frame,view=timeline.frame,width=b.minX-a.minX
            guard width>0 else{return false}
            let center=2+(secondAnchorX-a.minX)/width
            return width<enlargedWidth*0.9 && abs(center-secondBarsBefore)<=0.04 && a.minX>=view.minX && b.maxX<=view.maxX+1
        },object:third)],timeout:6)
        let reducedThird=third.frame,reducedFourth=fourth.frame
        let reducedWidth=reducedFourth.minX-reducedThird.minX
        let barsReduced=2+(secondAnchorX-reducedThird.minX)/reducedWidth
        let afterTrace=try XCTUnwrap(transport.value as? String)
        let repeatedReceipt=XCTAttachment(string:"Settle result=\(reducedSettled)\nViewport=\(secondViewport) → \(timeline.frame), ruler03=\(enlargedThird) → \(reducedThird), ruler04=\(enlargedFourth) → \(reducedFourth)\nRaw-input global anchorX=\(secondAnchorX), actual bar widths=\(enlargedWidth) → \(reducedWidth), anchor bars=\(secondBarsBefore) → \(barsReduced)\n\(secondInput)\nBEFORE\n\(beforeTrace)\nAFTER\n\(afterTrace)")
        repeatedReceipt.name="Anchored-pinch repeated actual geometry";repeatedReceipt.lifetime = .keepAlways;add(repeatedReceipt)
        XCTAssertEqual(reducedSettled,.completed)
        XCTAssertEqual(barsReduced,secondBarsBefore,accuracy:0.04)
        XCTAssertGreaterThanOrEqual(reducedWidth,68-0.000001);XCTAssertLessThanOrEqual(reducedWidth,640+0.000001)
        XCTAssertEqual(clip.identifier,clipID);XCTAssertEqual(clip.value as? String,length)
        XCTAssertFalse(app.buttons["Undo"].isEnabled);XCTAssertFalse(app.buttons["Redo"].isEnabled)
        XCTAssertEqual(try field("project",in:afterTrace),project);XCTAssertEqual(try field("revision",in:afterTrace),revision)
        XCTAssertEqual(try field("kernel",in:afterTrace),kernel);XCTAssertEqual(try field("actualPlaying",in:afterTrace),"1")
        XCTAssertEqual(try field("pending",in:afterTrace),"false")
        XCTAssertGreaterThan(try XCTUnwrap(UInt64(field("actualClock",in:afterTrace))),clock)
        app.buttons["Stop"].tap()
    }

    @MainActor func testClipTapResizeNativeDragAndUndo(){
        let app=launch()
        let clips=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.' AND label == 'Harmony'"))
        let harmony=clips.firstMatch
        XCTAssertTrue(harmony.waitForExistence(timeout:5))
        wait(harmony,NSPredicate(format:"hittable == true"))
        let id=harmony.identifier
        // This is the actual clip hit target, including its drawn waveform.
        harmony.coordinate(withNormalizedOffset:CGVector(dx:0.4,dy:0.5)).tap()
        XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout:5))
        let length=app.steppers["clip.length"]
        XCTAssertTrue(length.waitForExistence(timeout:5))
        let decrement=length.buttons["clip.length-Decrement"]
        XCTAssertTrue(decrement.waitForExistence(timeout:5))
        for _ in 0..<3{decrement.tap()}
        wait(length,NSPredicate(format:"value == '1.00 bars'"))
        app.buttons["Done"].tap()
        let clip=app.buttons[id]
        wait(clip,NSPredicate(format:"value == '1.00 bars'"))
        wait(clip,NSPredicate(format:"hittable == true"))
        wait(clip,NSPredicate{_,_ in clip.frame.width+6<app.windows.firstMatch.frame.width/2})
        let initialX=clip.frame.minX,bar=clip.frame.width+6
        XCTAssertLessThan(bar,app.windows.firstMatch.frame.width/2,"Clip accessibility frame must match the one-bar clip, not its entire lane")
        let finger=clip.coordinate(withNormalizedOffset:CGVector(dx:0.4,dy:0.5))
        drag(finger,to:finger.withOffset(CGVector(dx:bar,dy:0)))
        waitForClipPosition(clip,x:initialX+bar,length:"1.00 bars",in:app)
        XCTAssertGreaterThan(clip.frame.minX,initialX+bar*0.5)
        XCTAssertEqual(clip.frame.minX,initialX+bar,accuracy:3)
        clip.tap();XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout:5))
        XCTAssertEqual(app.steppers["clip.start"].value as? String,"2:1")
        app.buttons["Done"].tap()
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        shot.name="OriginalVision-original-vision-arrangement-clips";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Undo"].tap()
        waitForClipPosition(clip,x:initialX,length:"1.00 bars",in:app)
        XCTAssertEqual(clip.frame.minX,initialX,accuracy:3)
        XCTAssertEqual(clip.value as? String,"1.00 bars")
        app.buttons["Redo"].tap()
        waitForClipPosition(clip,x:initialX+bar,length:"1.00 bars",in:app)
        XCTAssertGreaterThan(clip.frame.minX,initialX+bar*0.5)
    }

    @MainActor func testAccessibleAddClipPreservesExistingClipsAndIsUndoable(){
        let app=launch()
        let originalDrums=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.' AND label == 'Drums'")).firstMatch
        XCTAssertTrue(originalDrums.waitForExistence(timeout:5))
        wait(originalDrums,NSPredicate(format:"hittable == true"))
        let originalID=originalDrums.identifier,originalLength=originalDrums.value as? String
        app.buttons["grid.clips.list"].tap()
        XCTAssertTrue(app.navigationBars["Clip list"].waitForExistence(timeout:5))
        let bass=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.add.bass.'")).firstMatch
        XCTAssertTrue(bass.exists);XCTAssertFalse(bass.isEnabled)
        XCTAssertTrue(app.staticTexts["Root bass follows harmony and cannot hold independent clips."].exists)
        let add=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.add.drums.'")).firstMatch
        XCTAssertTrue(add.exists);XCTAssertEqual(add.label,"Add clip to Drums")
        assertMinimumTouchDimension(add.frame.height)
        add.tap()
        XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout:5))
        XCTAssertEqual(app.steppers["clip.start"].value as? String,"5:1")
        XCTAssertEqual(app.steppers["clip.length"].value as? String,"1.00 bars")
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons[originalID].value as? String,originalLength)
        XCTAssertTrue(app.buttons["Undo"].isEnabled);app.buttons["Undo"].tap()
        app.buttons["grid.clips.list"].tap()
        let rows=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.list.'"))
        XCTAssertEqual(rows.count,2)
        app.buttons["Done"].tap();XCTAssertTrue(app.buttons["Redo"].isEnabled);app.buttons["Redo"].tap()
        app.buttons["grid.clips.list"].tap();XCTAssertEqual(rows.count,3)
    }

    @MainActor func testWideClipNativeDragRetainsTouchOffset(){
        let app=launch()
        let clip=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.' AND label == 'Harmony'")).firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout:5));wait(clip,NSPredicate(format:"hittable == true"))
        let initialX=clip.frame.minX,width=clip.frame.width,bar=(width+6)/4
        XCTAssertLessThan(width,app.windows.firstMatch.frame.width)
        XCTAssertGreaterThan(width,app.windows.firstMatch.frame.width/2)
        // At 20% of this four-bar clip, omitting the grab offset snaps a
        // one-bar finger movement to bar three. The musical start must be two.
        let finger=clip.coordinate(withNormalizedOffset:CGVector(dx:0.2,dy:0.25))
        drag(finger,to:finger.withOffset(CGVector(dx:bar,dy:0)))
        waitForClipPosition(clip,x:initialX+bar,length:"4.00 bars",in:app)
        XCTAssertEqual(clip.frame.minX,initialX+bar,accuracy:3)
        clip.tap();XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout:5))
        XCTAssertEqual(app.steppers["clip.start"].value as? String,"2:1")
        XCTAssertEqual(app.steppers["clip.length"].value as? String,"4.00 bars")
        app.buttons["Done"].tap();app.buttons["Undo"].tap()
        waitForClipPosition(clip,x:initialX,length:"4.00 bars",in:app)
        XCTAssertEqual(clip.frame.minX,initialX,accuracy:3)
        XCTAssertEqual(clip.value as? String,"4.00 bars")
    }

    @MainActor func testNativeCornerResizeKeepsClipStartAndIsUndoable(){
        let app=launch()
        let clip=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.' AND label == 'Harmony'")).firstMatch
        XCTAssertTrue(clip.waitForExistence(timeout:5));wait(clip,NSPredicate(format:"hittable == true"))
        let initialX=clip.frame.minX,width=clip.frame.width,bar=(width+6)/4
        let handle=clip.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.86))
        handle.press(forDuration:0.1,thenDragTo:handle.withOffset(CGVector(dx:-bar,dy:0)))
        wait(clip,NSPredicate(format:"value == '3.00 bars'"))
        XCTAssertEqual(clip.frame.minX,initialX,accuracy:3)
        XCTAssertEqual(clip.frame.width,width-bar,accuracy:3)
        app.buttons["Undo"].tap();wait(clip,NSPredicate(format:"value == '4.00 bars'"))
        XCTAssertEqual(clip.frame.minX,initialX,accuracy:3)
        XCTAssertEqual(clip.frame.width,width,accuracy:3)
    }

    @MainActor func testSectionChipsDragWholeSectionAndUndo(){
        let app=launch("perform")
        XCTAssertTrue(app.buttons["perform.done"].waitForExistence(timeout:5));app.buttons["perform.done"].tap()
        wait(app.buttons["grid.mode.clips"],NSPredicate(format:"value == 'Clips'"))
        let sections=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.section.'"))
        XCTAssertEqual(sections.count,2)
        let verse=sections.element(boundBy:0),chorus=sections.element(boundBy:1)
        let verseID=verse.identifier,chorusID=chorus.identifier
        wait(verse,NSPredicate(format:"hittable == true"));wait(chorus,NSPredicate(format:"hittable == true"))
        drag(verse.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)),to:chorus.coordinate(withNormalizedOffset:CGVector(dx:0.6,dy:0.5)))
        let movedVerse=app.buttons[verseID],movedChorus=app.buttons[chorusID]
        wait(movedVerse,NSPredicate(format:"label CONTAINS '5–8'"))
        XCTAssertLessThan(movedChorus.frame.minX,movedVerse.frame.minX)
        XCTAssertTrue(movedChorus.label.contains("1–4"))
        app.buttons["Undo"].tap()
        wait(movedVerse,NSPredicate(format:"label CONTAINS '1–4'"))
        XCTAssertLessThan(movedVerse.frame.minX,movedChorus.frame.minX)
    }
}
