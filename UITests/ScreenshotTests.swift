import XCTest
import UIKit
final class ScreenshotTests:XCTestCase {
    override func setUp(){super.setUp();executionTimeAllowance=600}
    @MainActor func testCaptureNativeScreens(){capture(["grid","jam","mixer","projects","export","export-wav","export-stems","notes","notes-mixer","harmony","harmony-proposal","harmony-custom","harmony-custom-ru","assistant","assistant-proposal","assistant-song-proposal","voice","voice-draft","perform","perform-take","perform-export","midi","midi-mapped","grid-light","jam-light","mixer-light","notes-light","export-light","grid-ru","assistant-ru","mixer-ru","voice-ru","notes-large","mixer-large","jam-large","settings"])}
    private var russianRecapture:Bool{ProcessInfo.processInfo.environment["GRILLA_RU_RECAPTURE"]=="1"}
    @MainActor func testCaptureStoreScreens(){
        let locales=russianRecapture ? ["ru"]:["en-US","ru"]
        capture(locales.flatMap{locale in ["grid","jam","notes","harmony-proposal","perform-take","export"].map{"store-\(locale)-\($0)"}})
        if russianRecapture{capture(["grid-ru","assistant-ru","mixer-ru","voice-ru"])}
    }
    @MainActor func testCaptureCompactScreens(){capture(russianRecapture ? ["compact-grid-ru","compact-jam-ru","compact-mixer-ru","compact-harmony-custom-ru","compact-harmony-options-ru","compact-arrangement-clips-ru"]:["compact-grid","compact-jam","compact-mixer","compact-harmony-custom","compact-grid-ru","compact-jam-ru","compact-mixer-ru","compact-harmony-custom-ru","compact-harmony-options-ru","compact-arrangement-clips-ru"])}
    @MainActor private func capture(_ screens:[String]){
        for screen in screens {
            XCUIDevice.shared.orientation = .portrait
            var target=screen,args=["--uitesting"],language="en",locale="en_US"
            if screen.hasSuffix("-light"){target=String(screen.dropLast(6));args += ["--appearance","light"]}
            if screen.hasSuffix("-ru"){target=String(screen.dropLast(3));language="ru";locale="ru_RU"}
            if screen.hasSuffix("-large"){target=String(screen.dropLast(6));args.append("--large-type")}
            if screen.hasPrefix("compact-"){target=String(target.dropFirst(8));args += ["--appearance","light"]}
            if screen.hasPrefix("store-en-US-"){target=String(screen.dropFirst(12))}
            if screen.hasPrefix("store-ru-"){target=String(screen.dropFirst(9));language="ru";locale="ru_RU"}
            let customHarmony=target=="harmony-custom"
            let harmonyOptions=target=="harmony-options",arrangementClips=target=="arrangement-clips"
            if customHarmony || harmonyOptions || arrangementClips{target="grid"}
            let app=XCUIApplication();app.launchArguments=args+["--screen",target,"-AppleLanguages","(\(language))","-AppleLocale",locale];app.launch()
            guard app.buttons["perform.transport"].waitForExistence(timeout:20)else{XCTFail("The app did not open for \(screen)");continue}
            if screen.hasPrefix("compact-"){
                for label in language=="ru" ? ["Сетка","Джем","Микшер","Играть"]:["Grid","Jam","Mixer","Play"]{XCTAssertTrue(app.buttons[label].isHittable)}
                if target=="jam"{XCTAssertTrue(app.buttons[language=="ru" ? "Перкуссия":"Perc"].isHittable)}
                if target=="mixer"{XCTAssertTrue(app.buttons["mixer.mute.0"].isHittable);XCTAssertTrue(app.buttons["mixer.solo.0"].isHittable);XCTAssertTrue(app.sliders["mixer.pan.0"].isHittable)}
            }
            if customHarmony,!prepareCustomHarmony(app,russian:language=="ru"){continue}
            if harmonyOptions,!prepareHarmonyOptions(app){continue}
            if arrangementClips,!prepareClipInspector(app){continue}
            if target=="midi" || target=="midi-mapped" {
                if !prepareMIDICapture(app,mapped:target=="midi-mapped"){continue}
            }
            if target=="voice-draft"{XCTAssertTrue(app.staticTexts["voice.note-count"].waitForExistence(timeout:15))}
            Thread.sleep(forTimeInterval:target.hasPrefix("perform-") ? 5:1)
            let png=settledPNG()
            if screen.hasPrefix("store-"){
                let width=png[16..<20].reduce(0){($0<<8)|Int($1)},height=png[20..<24].reduce(0){($0<<8)|Int($1)}
                XCTAssertEqual(width,1320,"Store screenshot must preserve the native display width");XCTAssertEqual(height,2868)
            }
            let shot=XCTAttachment(data:png,uniformTypeIdentifier:"public.png");shot.name="OriginalVision-"+screen;shot.lifetime = .keepAlways;add(shot)
        }
    }
    @MainActor private func waitForCaptureState(_ element:XCUIElement,_ predicate:NSPredicate,_ message:String)->Bool {
        let ready=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:element)],timeout:6) == .completed
        if !ready{XCTFail(message+"; "+element.debugDescription)}
        return ready
    }
    @MainActor private func midiState(_ status:XCUIElement)->[String:String]{
        guard status.exists,let value=status.value as? String else{return [:]}
        return Dictionary(uniqueKeysWithValues:value.split(separator:";").compactMap{item in
            let pair=item.split(separator:"=",maxSplits:1,omittingEmptySubsequences:false)
            return pair.count==2 ? (String(pair[0]),String(pair[1])):nil
        })
    }
    @MainActor private func midiReady(_ status:XCUIElement)->Bool{
        let state=midiState(status)
        return ["requested","source","input","output"].allSatisfy{state[$0]=="1"} && (Int(state["received"] ?? "0") ?? 0)>0 && state["error"]=="0"
    }
    @MainActor private func preserveMIDIStartup(_ app:XCUIApplication,status:XCUIElement,name:String){
        let error=app.staticTexts["midi.error"]
        let receipt=XCTAttachment(string:"Actual CoreMIDI state: \(status.value ?? "missing")\nVisible error: \(error.exists ? error.label:"none")")
        receipt.name="MIDI-"+name+"-diagnostic";receipt.lifetime = .keepAlways;add(receipt)
        let image=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        image.name="MIDI-"+name+"-original-error";image.lifetime = .keepAlways;add(image)
    }
    @MainActor private func midiForm(_ app:XCUIApplication)->XCUIElement?{
        [app.collectionViews["midi.form"],app.tables["midi.form"],app.scrollViews["midi.form"],
         app.collectionViews.containing(.button,identifier:"midi.reconnect").firstMatch,
         app.tables.containing(.button,identifier:"midi.reconnect").firstMatch,
         app.scrollViews.containing(.button,identifier:"midi.reconnect").firstMatch].first{$0.exists}
    }
    @MainActor private func prepareMIDICapture(_ app:XCUIApplication,mapped:Bool)->Bool{
        let status=app.buttons["midi.done"]
        guard status.waitForExistence(timeout:6),let form=midiForm(app)else{XCTFail("The actual MIDI form did not open");return false}
        let ready=NSPredicate{_,_ in self.midiReady(status)}
        if XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:ready,object:status)],timeout:6) != .completed {
            preserveMIDIStartup(app,status:status,name:"before-reconnect")
            let state=midiState(status)
            // A recorded startup failure permits one real, visible reconnect.
            // No arbitrary delay, repeated tap or generated mapping replaces it.
            guard state["requested"]=="1",let failure=state["lastFailureStatus"],failure != "none" else{
                XCTFail("MIDI capture requires real input/output connections and received output notes: \(status.value ?? "missing")");return false
            }
            let reconnect=app.buttons["midi.reconnect"]
            guard revealForCapture([reconnect],scroll:form,in:app)else{return false}
            reconnect.tap()
            guard waitForCaptureState(status,ready,"The single MIDI reconnect did not restore the actual fixture")else{
                preserveMIDIStartup(app,status:status,name:"after-reconnect-failure");return false
            }
        }
        guard !app.staticTexts["midi.error"].exists else{preserveMIDIStartup(app,status:status,name:"unexpected-error");XCTFail("A MIDI error cannot be captured as ready");return false}
        if mapped {
            if midiState(status)["mapping"] != "1" {
                let learn=app.buttons["midi.learn"],send=app.buttons["midi.send-fixture"]
                guard revealForCapture([learn],scroll:form,in:app),learn.isEnabled else{XCTFail("Actual MIDI Learn is unavailable");return false}
                if midiState(status)["learning"] != "1" {
                    guard midiState(status)["learningActive"]=="0" else{XCTFail("Another MIDI control is already armed; capture must not cancel it");return false}
                    learn.tap()
                    guard waitForCaptureState(status,NSPredicate{_,_ in self.midiState(status)["learning"]=="1"},"MIDI Learn was not armed for the actual filter")else{return false}
                }
                guard revealForCapture([send],scroll:form,in:app)else{return false}
                send.tap()
                guard waitForCaptureState(status,NSPredicate{_,_ in self.midiReady(status) && self.midiState(status)["mapping"]=="1"},"The real CC 74 phrase did not produce a filter mapping")else{return false}
            }
            let mapping=app.staticTexts["midi.mapping.filter"],detail=app.staticTexts["midi.mapping-detail.filter"]
            guard revealForCapture([mapping,detail],scroll:form,in:app)else{return false}
            guard detail.label=="Ch 1 · CC 74",midiReady(status),midiState(status)["mapping"]=="1" else{
                XCTFail("The visible MIDI mapping does not match the connected source's actual CC 74");return false
            }
        }
        let receipt=XCTAttachment(string:"Actual ready MIDI capture: \(status.value ?? "missing")")
        receipt.name=mapped ? "MIDI-mapped-ready-diagnostic":"MIDI-connected-ready-diagnostic";receipt.lifetime = .keepAlways;add(receipt)
        return true
    }
    @MainActor private func revealForCapture(_ elements:[XCUIElement],scroll:XCUIElement,in app:XCUIApplication,bottom:XCUIElement?=nil)->Bool {
        guard scroll.waitForExistence(timeout:5)else{XCTFail("The actual presented scroll view is missing");return false}
        for _ in 0..<6 {
            let window=app.windows.firstMatch.frame,navigation=app.navigationBars.firstMatch
            var viewport=scroll.frame.intersection(window)
            if navigation.exists{viewport=viewport.intersection(CGRect(x:window.minX,y:navigation.frame.maxY,width:window.width,height:max(0,window.maxY-navigation.frame.maxY)))}
            if let bottom,bottom.exists{viewport.size.height=max(0,min(viewport.maxY,bottom.frame.minY-8)-viewport.minY)}
            viewport=viewport.insetBy(dx:2,dy:2)
            let frames=elements.filter(\.exists).map(\.frame)
            if frames.count==elements.count,elements.allSatisfy(\.isHittable),frames.allSatisfy({$0.width>0 && $0.height>0 && viewport.contains($0)}){return true}
            if let first=frames.min(by:{$0.minY<$1.minY}),first.minY<viewport.minY{scroll.swipeDown()}else{scroll.swipeUp()}
        }
        XCTFail("Capture controls did not fit the real presented viewport: "+elements.map(\.debugDescription).joined(separator:"; "))
        return false
    }
    @MainActor private func prepareHarmonyOptions(_ app:XCUIApplication)->Bool {
        let open=app.buttons["harmony.open"]
        guard open.waitForExistence(timeout:5),open.isHittable else{XCTFail("The real Harmony tool is unavailable");return false}
        open.tap()
        guard app.navigationBars["Гармоническая лаборатория"].waitForExistence(timeout:5)else{XCTFail("The Russian Harmony lab did not open");return false}
        let scroll=app.scrollViews["harmony.options-scroll"]
        let options=app.buttons["harmony.options"]
        guard revealForCapture([options],scroll:scroll,in:app,bottom:app.buttons["harmony.generate"])else{return false}
        options.tap()
        let voicing=app.buttons["harmony.voicing"]
        let low=app.buttons["harmony.lowest-note"]
        let high=app.buttons["harmony.highest-note"]
        guard revealForCapture([voicing,low,high],scroll:scroll,in:app,bottom:app.buttons["harmony.generate"])else{return false}
        for choice in ["Все ступени","Компактное джазовое"] {
            voicing.tap()
            let item=app.buttons[choice]
            guard item.waitForExistence(timeout:5),item.isHittable else{XCTFail("The actual voicing menu has no Russian option: "+choice);return false}
            item.tap()
            guard waitForCaptureState(voicing,NSPredicate(format:"label CONTAINS %@ OR value CONTAINS %@",choice,choice),"Voicing selection was not reflected by the real control")else{return false}
        }
        let labels=["Расположение голосов","Нижняя нота","Верхняя нота"].map{app.staticTexts[$0]}
        guard revealForCapture([options,voicing,low,high]+labels,scroll:scroll,in:app,bottom:app.buttons["harmony.generate"])else{return false}
        guard waitForCaptureState(low,NSPredicate(format:"label CONTAINS 'C3' OR value CONTAINS 'C3'"),"The actual low register changed unexpectedly"),waitForCaptureState(high,NSPredicate(format:"label CONTAINS 'C6' OR value CONTAINS 'C6'"),"The actual high register changed unexpectedly")else{return false}
        for control in [voicing,low,high]{XCTAssertGreaterThanOrEqual(control.frame.height,44)}
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        return !app.keyboards.firstMatch.exists
    }
    @MainActor private func prepareClipInspector(_ app:XCUIApplication)->Bool {
        let mode=app.buttons["grid.mode.clips"]
        guard mode.waitForExistence(timeout:5),mode.isHittable else{XCTFail("The real Clips mode control is unavailable");return false}
        mode.tap()
        guard waitForCaptureState(mode,NSPredicate(format:"value == %@","Клипы"),"The actual Grid did not enter Russian Clips mode")else{return false}
        let clip=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.' AND label == %@","Гармония")).firstMatch
        guard clip.waitForExistence(timeout:5),clip.isHittable else{XCTFail("No real Harmony clip is available to inspect");return false}
        clip.coordinate(withNormalizedOffset:CGVector(dx:0.4,dy:0.4)).tap()
        guard app.navigationBars["Настройки клипа"].waitForExistence(timeout:5)else{XCTFail("The actual Russian clip inspector did not open");return false}
        let start=app.steppers["clip.start"],length=app.steppers["clip.length"],offset=app.steppers["clip.offset"]
        guard start.waitForExistence(timeout:5),length.exists,offset.exists,app.buttons["clip.edit"].exists else{XCTFail("The real clip inspector is missing its source or position controls");return false}
        let valid=start.value as? String == "1:1" && offset.value as? String == "1:1"
        XCTAssertTrue(valid,"The inspector must describe the unchanged original clip")
        XCTAssertFalse((length.value as? String ?? "").isEmpty)
        let scrollCandidates=[app.collectionViews.containing(.stepper,identifier:"clip.start").firstMatch,app.tables.containing(.stepper,identifier:"clip.start").firstMatch,app.scrollViews.containing(.stepper,identifier:"clip.start").firstMatch]
        guard let scroll=scrollCandidates.first(where:{$0.exists}),revealForCapture([app.buttons["clip.edit"],start,length,offset],scroll:scroll,in:app)else{XCTFail("The compact inspector controls are not actually visible");return false}
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        return valid && !(length.value as? String ?? "").isEmpty && !app.keyboards.firstMatch.exists
    }
    @MainActor private func prepareCustomHarmony(_ app:XCUIApplication,russian:Bool)->Bool {
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","grid.chord.")).firstMatch
        guard chord.waitForExistence(timeout:5)else{XCTFail("No actual chord cell opened for the custom harmony capture");return false}
        chord.tap()
        let symbol=app.textFields["chord.symbol"]
        guard symbol.waitForExistence(timeout:5)else{XCTFail("The chord editor did not open");return false}
        symbol.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).tap()
        let old=symbol.value as? String ?? ""
        symbol.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+"C{0,3,7,11,14}\n")
        let notes=app.staticTexts["chord.notes"]
        let parsed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","C4 · E♭4 · G4 · B4 · D5"),object:notes)
        guard XCTWaiter.wait(for:[parsed],timeout:5) == .completed else{XCTFail("The actual chord parser did not produce the written custom tones");return false}
        let formula=app.textFields["chord.formula"]
        guard formula.waitForExistence(timeout:5)else{XCTFail("The parsed custom formula field is missing");return false}
        let formulaValue=formula.value as? String,symbolValue=symbol.value as? String,custom=app.switches["chord.custom"].value as? String
        let hasError=app.staticTexts["chord.error"].exists
        XCTAssertEqual(formulaValue,"0, 3, 7, 11, 14")
        XCTAssertEqual(symbolValue,"C{0,3,7,11,14}")
        XCTAssertEqual(custom,"1")
        XCTAssertFalse(hasError)
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.keyboards.firstMatch)
        let keyboardDismissed=XCTWaiter.wait(for:[dismissed],timeout:5) == .completed
        XCTAssertTrue(keyboardDismissed)
        let duration=app.steppers["chord.duration"]
        guard duration.waitForExistence(timeout:5)else{XCTFail("The actual chord duration control is missing");return false}
        if russian {
            let translated=duration.label.contains("Длительность") && duration.label.contains("1/16") && !duration.label.contains("Duration")
            XCTAssertTrue(translated,"Russian chord duration must use its real localized format: "+duration.label)
            guard translated else{return false}
        }
        return formulaValue=="0, 3, 7, 11, 14" && symbolValue=="C{0,3,7,11,14}" && custom=="1" && !hasError && keyboardDismissed
    }
    @MainActor private func settledPNG()->Data {
        // AX readiness can precede the simulator compositor's completed frame.
        // Compare actual pixels, excluding timestamp/metadata differences; keep
        // the final native PNG unchanged. Live Perform views may keep moving.
        var previous=XCUIScreen.main.screenshot()
        for _ in 0..<4 {
            Thread.sleep(forTimeInterval:0.5)
            let current=XCUIScreen.main.screenshot()
            if let before=previous.image.cgImage?.dataProvider?.data,
               let after=current.image.cgImage?.dataProvider?.data,CFEqual(before,after){return current.pngRepresentation}
            previous=current
        }
        return previous.pngRepresentation
    }
}
