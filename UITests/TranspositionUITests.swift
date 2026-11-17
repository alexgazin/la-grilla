import XCTest

/// Native UI/persistence and actual DSP revision adoption. Pitch names are
/// checked as notation; this does not infer acoustic frequency from a label.
final class TranspositionUITests:XCTestCase {
    private var recordedRevealOwner=false
    private struct VisibleControl {
        let snapshot:any XCUIElementSnapshot
        let appSnapshot:(any XCUIElementSnapshot)?
        let viewport:CGRect
    }
    override func setUp(){super.setUp();recordedRevealOwner=false;continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--screen","grid","--project-store-id",UUID().uuidString,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        return app
    }

    @MainActor func testTransposePreviewCancelApplyLiveUndoRedoAndReopen()throws {
        let app=launch();defer{app.terminate()}
        let transport=app.buttons["perform.transport"]
        let originalID=try XCTUnwrap(field("project",in:current(transport)))
        let originalRevision=try XCTUnwrap(field("revision",in:current(transport)))
        let chords=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'"))
        XCTAssertEqual(chords.count,4)
        let originalLabels=chords.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        app.buttons["Play"].tap()
        assertAdopted(transport,afterClock:0)
        let kernel=try XCTUnwrap(field("kernel",in:current(transport)))
        let initialClock=try XCTUnwrap(UInt64(field("actualClock",in:current(transport)) ?? ""))
        openSettings(app)
        openTranspose(app)
        let key=app.descendants(matching:.any).matching(NSPredicate(format:"identifier == 'transpose.key'")).firstMatch
        XCTAssertTrue(key.waitForExistence(timeout:5))
        let keyDescription=key.label+" "+(key.value as? String ?? "")
        XCTAssertTrue(keyDescription.contains("C major") && keyDescription.contains("D major"))
        let range=app.staticTexts["transpose.pitch-range"]
        XCTAssertTrue(range.exists);XCTAssertTrue(range.label.contains("→"))
        XCTAssertEqual(field("project",in:current(transport)),originalID)
        XCTAssertEqual(field("revision",in:current(transport)),originalRevision,"Review must not mutate the project")
        keepScreenshot("Audit-transpose-real-preview")
        app.buttons["transpose.cancel"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        XCTAssertEqual(field("revision",in:current(transport)),originalRevision)
        openTranspose(app)
        let apply=app.buttons["transpose.apply"]
        reveal(apply,in:app);XCTAssertTrue(apply.isEnabled);apply.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        app.buttons["Done"].tap()
        wait(app.navigationBars["Settings"]){!app.navigationBars["Settings"].exists}
        assertAdopted(transport,afterClock:initialClock)
        XCTAssertEqual(field("kernel",in:current(transport)),kernel)
        XCTAssertEqual(field("project",in:current(transport)),originalID)
        XCTAssertNotEqual(field("revision",in:current(transport)),originalRevision)
        for (index,symbol) in ["D","Bm","G","A"].enumerated(){
            XCTAssertTrue(chords.element(boundBy:index).label.hasPrefix(symbol),"Transposed grid chord \(index)")
        }
        XCTAssertTrue(app.staticTexts["D major"].exists)
        let transposedLabels=chords.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        app.buttons["Undo"].tap()
        wait(chords.firstMatch){chords.allElementsBoundByIndex.map(\.label)==originalLabels}
        assertAdopted(transport,afterClock:initialClock)
        XCTAssertEqual(field("kernel",in:current(transport)),kernel)
        XCTAssertFalse(app.buttons["Undo"].isEnabled,"One Undo must restore the entire transpose")
        XCTAssertTrue(app.buttons["Redo"].isEnabled)
        app.buttons["Redo"].tap()
        wait(chords.firstMatch){chords.allElementsBoundByIndex.map(\.label)==transposedLabels}
        assertAdopted(transport,afterClock:initialClock)
        XCTAssertEqual(field("kernel",in:current(transport)),kernel)
        keepScreenshot("Audit-transpose-live-adopted")
        keepReport(current(transport),name:"Audit-transpose-actual-live-kernel-and-generation")
        app.buttons["Stop"].tap()
        awaitSaved(app)
        let savedRevision=field("revision",in:current(transport))
        app.terminate();app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        XCTAssertEqual(field("project",in:current(transport)),originalID)
        XCTAssertEqual(field("revision",in:current(transport)),savedRevision)
        XCTAssertEqual(chords.allElementsBoundByIndex.map(\.label),transposedLabels)
        XCTAssertTrue(app.staticTexts["D major"].exists)
        app.buttons["Play"].tap();assertAdopted(transport,afterClock:0)
        keepReport("Same-store reopen matched project/revision and transposed Grid; actual output peak/clock adopted. Acoustic frequency was not measured.\n"+current(transport),name:"Audit-transpose-real-store-reopen")
        app.buttons["Stop"].tap()
    }

    @MainActor func testFlatsAndScaleDegreesPersistWithoutNotationChangingMusic()throws {
        let app=launch();defer{app.terminate()}
        let transport=app.buttons["perform.transport"]
        let initialReport=current(transport)
        let originalID=try XCTUnwrap(field("project",in:initialReport))
        let originalRevision=try XCTUnwrap(field("revision",in:initialReport))
        openSettings(app)
        let root=app.buttons["settings.key-root"]
        reveal(root,in:app);root.tap()
        selectVisibleListItem("F",identifier:"settings.key-option.5",pickerTitle:"Root",in:app)
        XCTAssertTrue(app.navigationBars["Settings"].exists,"Selecting a project key must keep Settings open")
        XCTAssertTrue(selected("F",in:try root.snapshot()),"The actual project-key picker must select F")
        let revisionAfterKey=try XCTUnwrap(field("revision",in:current(transport)))
        XCTAssertNotEqual(revisionAfterKey,originalRevision,"Choosing a different project key must be a real project edit")
        let spelling=app.buttons["settings.pitch-spelling"]
        let originalSpellingObservation=try XCTUnwrap(reveal(spelling,in:app)).snapshot
        let originalSpellingValue=originalSpellingObservation.value as? String,originalSpellingLabel=originalSpellingObservation.label
        let originalSpelling=try XCTUnwrap(["Auto (key)","Sharps","Flats"].first{value in
            originalSpellingValue==value || originalSpellingLabel==value || originalSpellingLabel.hasSuffix(", "+value)
        },"Read the original preference from the real native picker")
        spelling.tap();selectVisibleListItem("Flats",identifier:"settings.spelling-option.flats",pickerTitle:"Note names",in:app)
        XCTAssertTrue(selected("Flats",in:try spelling.snapshot()))
        let degrees=app.switches["settings.show-degrees"]
        let originalDegreesObservation=try XCTUnwrap(reveal(degrees,in:app))
        let originalDegrees=try XCTUnwrap(originalDegreesObservation.snapshot.value as? String)
        XCTAssertTrue(["0","1"].contains(originalDegrees))
        let enabledDegrees=setDegrees("1",control:degrees,observed:originalDegreesObservation)
        XCTAssertEqual(enabledDegrees,"1")
        XCTAssertEqual(field("revision",in:current(transport)),revisionAfterKey,"Display preferences must not edit music")
        app.buttons["Done"].tap()
        openChord(app)
        let symbol=app.textFields["chord.symbol"]
        symbol.tap()
        let old=symbol.value as? String ?? ""
        symbol.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+"Bb\n")
        let degree=app.staticTexts["chord.degree"]
        XCTAssertTrue(degree.waitForExistence(timeout:5));XCTAssertEqual(degree.label,"IV")
        let displayedNotes=try app.staticTexts["chord.notes"].snapshot().label
        XCTAssertTrue(displayedNotes.contains("B♭"))
        XCTAssertFalse(displayedNotes.contains("A♯"))
        let apply=app.buttons["chord.apply"];reveal(apply,in:app);apply.tap()
        wait(app.navigationBars["Edit chord"]){!app.navigationBars["Edit chord"].exists}
        awaitSaved(app)
        app.terminate();app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        XCTAssertEqual(field("project",in:current(transport)),originalID)
        openChord(app)
        XCTAssertEqual(app.staticTexts["chord.degree"].label,"IV")
        XCTAssertTrue(app.staticTexts["chord.notes"].label.contains("B♭"))
        keepScreenshot("Audit-flats-degrees-real-store-reopen")
        app.buttons["Cancel"].tap()
        openSettings(app)
        let persistedSpelling=try XCTUnwrap(reveal(spelling,in:app))
        XCTAssertTrue(selected("Flats",in:persistedSpelling.snapshot))
        let persistedDegrees=try XCTUnwrap(visibleSnapshot("settings.show-degrees",type:.switch,in:try XCTUnwrap(persistedSpelling.appSnapshot)))
        guard degrees.isHittable else{XCTFail("The persisted scale-degrees switch must remain hittable in Settings");return}
        XCTAssertEqual(persistedDegrees.snapshot.value as? String,"1")
        let revisionBeforeRestore=field("revision",in:current(transport))
        // Both preferences above come from one actual post-relaunch Settings
        // hierarchy. Restore through its real controls, never app defaults.
        // No gesture occurred since spelling's visibility/hittability check.
        if !selected(originalSpelling,in:persistedSpelling.snapshot){
            spelling.tap()
            let spellingIDs=["Auto (key)":"automatic","Sharps":"sharps","Flats":"flats"]
            let option=try XCTUnwrap(spellingIDs[originalSpelling])
            selectVisibleListItem(originalSpelling,identifier:"settings.spelling-option."+option,pickerTitle:"Note names",in:app)
        }
        // Picker navigation invalidates previous geometry. Reveal the actual
        // switch again and observe restored spelling in that fresh hierarchy.
        let restoreDegrees=try XCTUnwrap(reveal(degrees,in:app))
        let restoredSpelling=try XCTUnwrap(visibleSnapshot("settings.pitch-spelling",type:.button,in:try XCTUnwrap(restoreDegrees.appSnapshot)))
        XCTAssertTrue(selected(originalSpelling,in:restoredSpelling.snapshot))
        let restoredDegrees=setDegrees(originalDegrees,control:degrees,observed:restoreDegrees)
        XCTAssertEqual(restoredDegrees,originalDegrees)
        XCTAssertEqual(field("revision",in:current(transport)),revisionBeforeRestore)
        keepReport("Original native note names=\(originalSpelling), scale degrees=\(originalDegrees); both restored through visible Settings after relaunch/persistence assertions. Music revision unchanged.",name:"Audit-notation-original-preferences-restored")
        app.buttons["Done"].tap()
    }

    @MainActor private func openSettings(_ app:XCUIApplication){
        // The ordinary 44pt tempo/key button opens the same Settings screen.
        // Source18 stalled in the system menu's invalid activation point
        // before either transposition scenario reached its first control.
        let entry=app.buttons["studio.tempo"]
        XCTAssertTrue(entry.waitForExistence(timeout:5))
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
    }
    @MainActor private func openTranspose(_ app:XCUIApplication){
        let link=app.buttons["settings.transpose"]
        reveal(link,in:app);link.tap()
        XCTAssertTrue(app.navigationBars["Transpose arrangement"].waitForExistence(timeout:5))
        XCTAssertEqual(app.steppers["transpose.semitones"].value as? String,"2")
    }
    @MainActor private func openChord(_ app:XCUIApplication){
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(chord.waitForExistence(timeout:5));chord.tap()
        XCTAssertTrue(app.navigationBars["Edit chord"].waitForExistence(timeout:5))
    }
    @MainActor private func assertAdopted(_ transport:XCUIElement,afterClock:UInt64){
        wait(transport,timeout:10){
            let report=self.current(transport)
            return report.contains("engineRunning=true") && report.contains("actualPlaying=1")
                && self.field("actualRevision",in:report)==self.field("revision",in:report)
                && self.field("actualGeneration",in:report)==self.field("submittedGeneration",in:report)
                && (UInt64(self.field("actualClock",in:report) ?? "") ?? 0)>afterClock
                && (Double(self.field("outputPeak",in:report) ?? "") ?? 0)>0.001
        }
    }
    @MainActor private func awaitSaved(_ app:XCUIApplication){
        let saved=app.descendants(matching:.any).matching(NSPredicate(format:"label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout:8))
    }
    @MainActor private func current(_ transport:XCUIElement)->String{(transport.value as? String ?? "").components(separatedBy:"\n").first ?? ""}
    @MainActor private func selected(_ value:String,in picker:any XCUIElementSnapshot)->Bool{
        (picker.value as? String)==value || picker.label==value || picker.label.hasSuffix(", "+value)
    }
    @MainActor private func visibleSnapshot(_ identifier:String,type:XCUIElement.ElementType,in root:any XCUIElementSnapshot)->VisibleControl? {
        let scrollTypes:[XCUIElement.ElementType]=[.collectionView,.table,.scrollView]
        var matches:[(node:any XCUIElementSnapshot,ancestors:[any XCUIElementSnapshot])]=[]
        var pending:[(node:any XCUIElementSnapshot,ancestors:[any XCUIElementSnapshot])]=[(root,[])]
        while let entry=pending.popLast(){
            if entry.node.identifier==identifier && entry.node.elementType==type{matches.append(entry)}
            for child in entry.node.children{pending.append((child,entry.ancestors+[entry.node]))}
        }
        guard matches.count==1,let match=matches.first,
              let window=match.ancestors.last(where:{$0.elementType == .window}),
              let owner=match.ancestors.last(where:{scrollTypes.contains($0.elementType)}) ?? match.ancestors.last(where:{$0.elementType == .window}) else{return nil}
        func finite(_ frame:CGRect)->Bool{!frame.isEmpty && [frame.minX,frame.minY,frame.maxX,frame.maxY].allSatisfy{$0.isFinite}}
        let viewport=owner.frame.intersection(root.frame.insetBy(dx:0,dy:44)).intersection(window.frame)
        guard match.node.isEnabled,finite(match.node.frame),finite(owner.frame),finite(window.frame),finite(root.frame),finite(viewport),viewport.contains(match.node.frame) else{return nil}
        return VisibleControl(snapshot:match.node,appSnapshot:root,viewport:viewport)
    }
    @MainActor private func setDegrees(_ desired:String,control:XCUIElement,observed:VisibleControl)->String? {
        let row=observed.snapshot
        guard ["0","1"].contains(desired),row.identifier=="settings.show-degrees",row.elementType == .switch,
              let actual=row.value as? String,["0","1"].contains(actual)else{
            XCTFail("The actual scale-degrees switch must expose its binary state");return nil
        }
        if actual != desired {
            func finite(_ frame:CGRect)->Bool{!frame.isEmpty && [frame.minX,frame.minY,frame.maxX,frame.maxY].allSatisfy{$0.isFinite}}
            let frame=row.frame,visible=observed.viewport
            guard finite(frame),finite(visible),visible.contains(frame),row.isEnabled else{
                XCTFail("The real scale-degrees switch must be enabled and fully visible");return nil
            }
            // The revealed row already contains its actual native child. Use
            // that coherent pre-gesture state/geometry instead of re-fetching
            // the row and every child attribute through separate AX requests.
            var nativeSnapshots:[any XCUIElementSnapshot]=[],pending=row.children
            while let node=pending.popLast(){
                if node.elementType == .switch{nativeSnapshots.append(node)}
                pending.append(contentsOf:node.children)
            }
            guard nativeSnapshots.count==1,let nativeSnapshot=nativeSnapshots.first,
                  (nativeSnapshot.value as? String)==actual,nativeSnapshot.isEnabled else{
                XCTFail("The actual native switch must exist, be enabled and agree with its row state");return nil
            }
            let nativeFrame=nativeSnapshot.frame
            guard finite(nativeFrame),visible.contains(nativeFrame),frame.contains(nativeFrame),nativeFrame != frame else{
                XCTFail("The actual native switch must be wholly visible inside its measured Form row");return nil
            }
            let native=control.switches.firstMatch
            guard native.isHittable else{XCTFail("The actual native switch must be hittable before the gesture");return nil}
            let velocity=XCUIGestureVelocity(rawValue:100)
            if desired=="1"{native.swipeRight(velocity:velocity)}else{native.swipeLeft(velocity:velocity)}
            var afterGesture:String?
            wait(control,timeout:5){
                afterGesture=(try? control.snapshot())?.value as? String
                return afterGesture==desired
            }
            // Both adjacent assertions use the same actual fresh observation;
            // no pre-gesture value is substituted for the gesture result.
            XCTAssertEqual(afterGesture,desired)
            return afterGesture
        }
        XCTAssertEqual(actual,desired)
        return actual
    }
    @MainActor private func selectVisibleListItem(_ title:String,identifier:String,pickerTitle:String,in app:XCUIApplication){
        let navigation=app.navigationBars[pickerTitle]
        XCTAssertTrue(navigation.waitForExistence(timeout:5))
        let optionTypes:[XCUIElement.ElementType]=[.button,.cell,.staticText]
        let scrollTypes:[XCUIElement.ElementType]=[.collectionView,.table,.scrollView]
        func finite(_ frame:CGRect)->Bool{!frame.isEmpty && [frame.minX,frame.minY,frame.maxX,frame.maxY].allSatisfy{$0.isFinite}}
        var visibleOption:XCUIElement?
        for _ in 0..<7 {
            // Read the option and its real scroll/window ancestors together.
            // Re-fetching label, enabled, frame and selection separately added
            // six AX round trips after this same native list was already ready.
            let root=try? app.snapshot()
            var matches:[(node:any XCUIElementSnapshot,ancestors:[any XCUIElementSnapshot])]=[]
            if let root {
                var pending:[(node:any XCUIElementSnapshot,ancestors:[any XCUIElementSnapshot])]=[(root,[])]
                while let entry=pending.popLast(){
                    if entry.node.identifier==identifier && optionTypes.contains(entry.node.elementType){matches.append(entry)}
                    for child in entry.node.children{pending.append((child,entry.ancestors+[entry.node]))}
                }
            }
            for type in optionTypes {
                let typed=matches.filter{$0.node.elementType==type}
                guard typed.count==1,let match=typed.first,let root,
                      let owner=match.ancestors.last(where:{scrollTypes.contains($0.elementType)}),
                      let window=match.ancestors.last(where:{$0.elementType == .window}) else{continue}
                let observed=match.node,frame=observed.frame
                let visible=owner.frame.intersection(root.frame.insetBy(dx:0,dy:44)).intersection(window.frame)
                guard observed.label==title || observed.label.hasPrefix(title+", "),observed.isEnabled,
                      finite(frame),finite(owner.frame),finite(root.frame),finite(window.frame),finite(visible),visible.contains(frame) else{continue}
                let option=app.descendants(matching:type).matching(NSPredicate(format:"identifier == %@",identifier)).firstMatch
                guard option.isHittable else{continue}
                keepReport("Public native Picker list=\(pickerTitle), option=\(observed.label), frame=\(frame), selectedBefore=\(observed.isSelected), owner.type=\(owner.elementType.rawValue), owner.frame=\(owner.frame), visible=\(visible), source=one-app-snapshot; liveHittable=true",name:"Audit-native-selection-list-"+identifier)
                visibleOption=option
                break
            }
            if visibleOption != nil{break}
            let lists=app.collectionViews.allElementsBoundByIndex.filter{$0.isHittable}+app.tables.allElementsBoundByIndex.filter{$0.isHittable}
            guard lists.count==1,let list=lists.first else{break}
            list.swipeUp()
        }
        guard let option=visibleOption else{XCTFail("The native selection list must expose its enabled, wholly visible real option: "+identifier);return}
        option.tap()
        let settingsNavigation=app.navigationBars["Settings"]
        if settingsNavigation.exists && settingsNavigation.isHittable{return}
        // Some supported iOS versions keep the checkmarked option list open.
        // Use its actual native Back button only while that list is present.
        let settingsBack=navigation.buttons["Settings"],genericBack=navigation.buttons["Back"]
        var previous:CGRect?
        wait(navigation){
            if settingsNavigation.exists && settingsNavigation.isHittable{return true}
            let back=settingsBack.exists ? settingsBack:genericBack
            guard navigation.exists,back.exists,back.isHittable else{return false}
            let value=back.frame;defer{previous=value}
            return !value.isEmpty && [value.minX,value.minY,value.maxX,value.maxY].allSatisfy{$0.isFinite} && value==previous
        }
        if !(settingsNavigation.exists && settingsNavigation.isHittable) {
            let back=settingsBack.exists ? settingsBack:genericBack
            XCTAssertTrue(back.exists && back.isHittable,"The presented native list must expose Back to Settings")
            back.tap()
        }
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
    }
    private func field(_ key:String,in report:String)->String?{report.split(separator:" ").first(where:{$0.hasPrefix(key+"=")}).map{String($0.dropFirst(key.count+1))}}
    @discardableResult @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication,up:Bool=true)->VisibleControl? {
        func finiteFrame(_ frame:CGRect)->Bool{!frame.isEmpty && [frame.minX,frame.minY,frame.maxX,frame.maxY].allSatisfy{$0.isFinite}}
        guard let initial=try? element.snapshot(),!initial.identifier.isEmpty else{XCTFail("A native control must expose its stable identifier before revealing it");return nil}
        let identifier=initial.identifier,targetType=initial.elementType
        let scrollTypes:[XCUIElement.ElementType]=[.collectionView,.table,.scrollView]
        struct Geometry {
            let targetFrame:CGRect
            let targetSnapshot:any XCUIElementSnapshot
            let ownerFrame:CGRect
            let ownerType:XCUIElement.ElementType
            let ownerIdentifier:String
            let ownerPath:[Int]
            let appFrame:CGRect
            let windowFrame:CGRect
            let source:String
        }
        func ownerQuery(_ type:XCUIElement.ElementType)->XCUIElementQuery {
            app.descendants(matching:type).containing(.any,identifier:identifier)
        }
        func geometry(in root:any XCUIElementSnapshot)->Geometry? {
            var pending:[(node:any XCUIElementSnapshot,ancestors:[any XCUIElementSnapshot],path:[Int])]=[(root,[],[])]
            var matches=0,found:Geometry?
            while let entry=pending.popLast(){
                let node=entry.node
                if node.identifier==identifier && node.elementType==targetType {
                    matches+=1
                    // A pinned action can be a window sibling of the scroll
                    // content. Use its real window only when no scroll owns it.
                    if let index=entry.ancestors.lastIndex(where:{scrollTypes.contains($0.elementType)}) ?? entry.ancestors.lastIndex(where:{$0.elementType == .window}) {
                        let owner=entry.ancestors[index]
                        found=Geometry(targetFrame:node.frame,targetSnapshot:node,ownerFrame:owner.frame,ownerType:owner.elementType,ownerIdentifier:owner.identifier,ownerPath:Array(entry.path.prefix(index)),appFrame:root.frame,windowFrame:entry.ancestors.last(where:{$0.elementType == .window})?.frame ?? root.frame,source:"one-app-snapshot")
                    }
                }
                for (index,child) in node.children.enumerated(){
                    pending.append((child,entry.ancestors+[node],entry.path+[index]))
                }
            }
            return matches==1 ? found:nil
        }
        var lastObservation=""
        for _ in 0..<7{
            let began=ProcessInfo.processInfo.systemUptime
            // One public AX hierarchy supplies the target and its actual
            // nearest scroll ancestor, window and frames at the same instant.
            // Do not infer a viewport from an unrelated background scroll view.
            let root=try? app.snapshot()
            var observed=root.flatMap{geometry(in:$0)}
            var scroll:XCUIElement?
            if observed==nil {
                // An absent/ambiguous snapshot keeps the target-scoped native
                // query fallback, in its existing collection/table/scroll order.
                guard element.exists,element.identifier==identifier,element.elementType==targetType else{XCTFail("The same native control must remain present while revealing it: "+identifier);return nil}
                var owners:[(XCUIElement,any XCUIElementSnapshot)]=[]
                for type in scrollTypes {
                    let candidates=ownerQuery(type).allElementsBoundByIndex.compactMap{candidate->(XCUIElement,any XCUIElementSnapshot)? in
                        guard let snapshot=try? candidate.snapshot(),finiteFrame(snapshot.frame) else{return nil}
                        return (candidate,snapshot)
                    }
                    if !candidates.isEmpty {
                        owners=candidates.sorted{$0.1.frame.width*$0.1.frame.height < $1.1.frame.width*$1.1.frame.height}
                        break
                    }
                }
                guard let (owner,snapshot)=owners.first else{
                    keepReport("target.exists=\(element.exists), target.hittable=\(element.isHittable), finiteOwningCandidates=\(owners.count)\n"+app.debugDescription,name:"Audit-native-reveal-owner-failure-"+identifier)
                    XCTFail("A real scroll container must own the native control: "+identifier);return nil
                }
                guard let targetSnapshot=try? element.snapshot()else{XCTFail("The native control must remain observable while revealing it: "+identifier);return nil}
                let appFrame=root?.frame ?? app.frame
                observed=Geometry(targetFrame:targetSnapshot.frame,targetSnapshot:targetSnapshot,ownerFrame:snapshot.frame,ownerType:snapshot.elementType,ownerIdentifier:snapshot.identifier,ownerPath:[],appFrame:appFrame,windowFrame:appFrame,source:"target-containing-query-fallback")
                scroll=owner
            }
            guard let observed,finiteFrame(observed.ownerFrame),finiteFrame(observed.appFrame),finiteFrame(observed.windowFrame) else{
                keepReport("Stable target=\(identifier), snapshotOwner=\(String(describing:observed))\n"+app.debugDescription,name:"Audit-native-reveal-owner-failure-"+identifier)
                XCTFail("A real scroll container must own the native control: "+identifier);return nil
            }
            // Keep the whole native control clear of sheet/home-indicator
            // boundaries, even when XCTest reports an offscreen row hittable.
            let visible=observed.ownerFrame.intersection(observed.appFrame.insetBy(dx:0,dy:44)).intersection(observed.windowFrame)
            guard finiteFrame(visible) else{XCTFail("The native control's owning scroll container must have a finite visible viewport: "+identifier);return nil}
            let targetHittable=element.isHittable
            lastObservation="sampleUptime=\(began)...\(ProcessInfo.processInfo.systemUptime), source=\(observed.source), target.identifier=\(identifier), target.type=\(targetType.rawValue), owner.type=\(observed.ownerType.rawValue), owner.identifier=\(observed.ownerIdentifier), owner.path=\(observed.ownerPath), owner.snapshotFrame=\(observed.ownerFrame), app.snapshotFrame=\(observed.appFrame), window.snapshotFrame=\(observed.windowFrame), visible=\(visible), target.hittable=\(targetHittable), target.snapshotFrame=\(observed.targetFrame)"
            if !recordedRevealOwner {
                keepReport(lastObservation,name:"Audit-native-reveal-owner-selection-"+identifier)
                recordedRevealOwner=true
            }
            let frame=observed.targetFrame
            if targetHittable && observed.targetSnapshot.isEnabled && finiteFrame(frame) && visible.contains(frame){
                return VisibleControl(snapshot:observed.targetSnapshot,appSnapshot:root,viewport:visible)
            }
            guard scrollTypes.contains(observed.ownerType)else{
                XCTFail("A fixed native control must be enabled and wholly visible in its actual window: "+identifier);return nil
            }
            if scroll==nil {
                // Only a needed scroll resolves a live container. Its scoped
                // ancestry, native type and measured frame must still agree
                // with the coherent hierarchy before it receives a gesture.
                let matches=ownerQuery(observed.ownerType).allElementsBoundByIndex.filter{candidate in
                    guard let snapshot=try? candidate.snapshot() else{return false}
                    return snapshot.elementType==observed.ownerType && snapshot.identifier==observed.ownerIdentifier && snapshot.frame==observed.ownerFrame
                }
                guard matches.count==1 else{
                    lastObservation+="; liveOwnerFrameMatches=\(matches.count)"
                    continue
                }
                scroll=matches[0]
            }
            guard let scroll else{XCTFail("A real scroll container must own the native control: "+identifier);return nil}
            if finiteFrame(frame) && frame.maxY>visible.maxY{scroll.swipeUp();continue}
            if finiteFrame(frame) && frame.minY<visible.minY{scroll.swipeDown();continue}
            if up{scroll.swipeUp()}else{scroll.swipeDown()}
        }
        keepReport(lastObservation+"\n"+app.debugDescription,name:"Audit-native-reveal-owner-failure-"+identifier)
        XCTFail("A real native control must be wholly visible inside its actual native viewport: \(element.debugDescription)")
        return nil
    }
    @MainActor private func wait(_ element:XCUIElement,timeout:TimeInterval=5,condition:()->Bool){
        let deadline=Date().addingTimeInterval(timeout)
        repeat{if condition(){return};RunLoop.current.run(until:Date().addingTimeInterval(0.1))}while Date()<deadline
        XCTFail("Condition not reached: \(element.debugDescription)")
    }
    @MainActor private func keepScreenshot(_ name:String){let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
    private func keepReport(_ text:String,name:String){let receipt=XCTAttachment(string:text);receipt.name=name;receipt.lifetime = .keepAlways;add(receipt)}
}
