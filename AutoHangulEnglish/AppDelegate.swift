import Cocoa
import CoreML
import SwiftUI
import Carbon.HIToolbox
import Security

enum Lang {
    case en, ko
}

@main
struct AutoHangulEnglishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() } // 빈 설정 창
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    // 상태 바 관련 프로퍼티
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    
    // 키보드 모니터링 관련
    var currentKeyStream = ""
    var snippets = [String: String]()
    var longestShortcutLength = 0
    var monitoringEnabled = false
    var string_count = 0
    var eventMonitor: Any?
    
    // 한글 오토마타
    var automata = KeyboardAutomata()
    var hautomata = HangulAutomata()
     
    // 파일 관찰 관련
    var eventStream: FSEventStreamRef?
    
    // 모델 관련
    var model: MLModel?
    let handler = LanguageClassifierHandler()
    
    // MARK: - 앱 라이프사이클
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        checkAccessibilityPermissions()
        setupApplication()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        stopFileMonitoring()
    }
    
    // MARK: - 초기 설정
    private func setupApplication() {
        // 모델 로딩 전 검증
        loadModel()
        setupStatusMenu()
        setupFileSystem()
        reloadSnippets()
        startFileMonitoring()
        enableKeyMonitoring()
    }
    
    private func setupStatusMenu() {
        print("settuping")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // 메뉴 아이콘 설정
        let icon = NSImage(named: "MenuIcon") ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)!
        icon.isTemplate = true
        statusItem.button?.image = icon
        
        // 컨텍스트 메뉴 구성
        menu.addItem(withTitle: "활성화 토글", action: #selector(toggleMonitoring), keyEquivalent: "")
        menu.addItem(withTitle: "스니펫 파일 열기", action: #selector(openSnippetsFile), keyEquivalent: "o")
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quitApp), keyEquivalent: "q")
        
        statusItem.menu = menu
    }

    // MARK: - 접근성 권한 확인
    private func checkAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let isTrusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        guard isTrusted else {
            showAccessibilityAlert()
            return
        }
    }
    
    private func showAccessibilityAlert() {
        let alert = NSAlert()
        alert.messageText = "접근성 권한 필요"
        alert.informativeText = "이 앱은 키보드 이벤트를 모니터링하기 위해 접근성 권한이 필요합니다."
        alert.addButton(withTitle: "설정 열기")
        alert.addButton(withTitle: "종료")
        
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
        NSApp.terminate(nil)
    }
    
    func loadModel() {
        guard let modelURL = Bundle.main.url(forResource: "model", withExtension: "mlpackage") else {
            print("Model not found")
            return
        }

        do {
            model = try MLModel(contentsOf: modelURL)
            print("Model loaded successfully.")
        } catch {
            print("Error loading model: \(error)")
        }
    }
    
    func getVisibleCharacterCount(input: String) -> Int {
        var count = 0
        
        input.enumerateSubstrings(in: input.startIndex..<input.endIndex,
                                 options: .byComposedCharacterSequences) {
            _, _, _, _ in
            count += 1
        }
        return count
    }
    
    private func resetAutomata() {
        hautomata.buffer.removeAll()
        hautomata.inpStack.removeAll()
        hautomata.currentHangulState = nil
        currentKeyStream = ""
    }
    
    // MARK: - 키 입력 처리
    private func handleKeyEvent(_ event: NSEvent) {
        guard let cgEvent = event.cgEvent else { return }
        let eventPID = cgEvent.getIntegerValueField(.eventSourceUnixProcessID)
        let appPID = Int64(ProcessInfo.processInfo.processIdentifier)
        if eventPID == appPID {
            return
        }

        guard let chars = event.charactersIgnoringModifiers else { return }

        // 공백 키 또는 삭제 키가 눌렸을 때 + 방향키 tab 등등 추가
        if event.keyCode == kVK_Delete {
            resetAutomata()
            return
        }
        else if event.keyCode == kVK_Space {
            var currentLang : Lang = .en
            if isKoreanInputSource() { currentLang = .ko }
            
            // model predict
            let prob: Float? = handler.predict(word: currentKeyStream)
            if prob != nil {
                print("영어 확률: \(prob! * 100)%")
            } else {
                print("처리 불가")
                resetAutomata()
                return
            }
            
            // check correct predict
            var isEnglish: Bool = false
            let percent: Float = 0.05
            if prob! < percent {
                isEnglish = false
            } else if prob! > 1.0 - percent {
                isEnglish = true
            } else {
                resetAutomata()
            }
            
            // decide whether to convert
            if (currentLang == .ko && isEnglish == false) && (currentLang == .en && isEnglish == true) {
                return
            }
            else if currentLang == .en && isEnglish == false {
                // automata insert
                for key in currentKeyStream {
                    hautomata.hangulAutomata(key: qwertyToHangul(String(key)))
                }
                
                // get word length
                var wordCount: Int = 0
                wordCount = currentKeyStream.count
                
                // swap string
                print("======================")
                print("deleting: ", hautomata, " / ", wordCount)
                print("currentKeyStream: ", currentKeyStream)
                deleteCharacters(count: wordCount+1)
                
                let buffer = hautomata.buffer.reduce("") { $0 + $1 }
                let typeBuffer : String = buffer + " "
                typeText(typeBuffer)
                print("======================")
                
                // reset buffer
                resetAutomata()
            }
            else if currentLang == .ko {
                var wordCount: Int = 0
                wordCount = currentKeyStream.count
                print("hangul",wordCount)
            }
            
            
            
            return
        }
        
        currentKeyStream += chars
//        print("변환 결과: ", automata.outputToDisplay)
//        if isKoreanInputSource() {
//            // 한글 처리
//            automata.insert(String(chars))
////            automata.insert(String(hangulToQwerty(chars)))
//            print("한글: ", hangulToQwerty(chars))
//        }
//        else {
//            // 영어 처리
//            automata.insert(String(chars))
//            print("영어: ", chars)
//        }
    }
    
    private func checkForSnippetMatch() {
        for (shortcut, text) in snippets {
            guard currentKeyStream.contains(shortcut) else { continue }
            
            currentKeyStream = ""
            deleteCharacters(count: shortcut.count)
            typeText(text)
        }
    }
    
    // MARK: - 텍스트 입력 유틸리티
    private func deleteCharacters(count: Int) {
        (0..<count).forEach { _ in
            postKeyEvent(keyCode: kVK_Delete, keyDown: true)
            postKeyEvent(keyCode: kVK_Delete, keyDown: false)
        }
    }
    
    private func typeText(_ text: String) {
        text.utf16.forEach { char in
//            if char == 10 {
//                postKeyEvent(keyCode: kVK_Return, keyDown: true)
//                postKeyEvent(keyCode: kVK_Return, keyDown: false)
//            } else {
                postUnicodeChar(char)
//            }
        }
    }
    
    private func postKeyEvent(keyCode: Int, keyDown: Bool) {
        let eventSource = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
        let pid = ProcessInfo.processInfo.processIdentifier
        event?.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(pid)) // Set PID
        event?.post(tap: .cghidEventTap)
    }
//    private func postKeyEvent(keyCode: Int, keyDown: Bool) {
//        let eventSource = CGEventSource(stateID: .hidSystemState)
//        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
//        event?.post(tap: .cghidEventTap)
//    }
    
    private func postUnicodeChar(_ char: UniChar) {
        let eventSource = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        event?.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(pid)) // Set PID
        event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [char])
        event?.post(tap: .cghidEventTap)
    }
//    private func postUnicodeChar(_ char: UniChar) {
//        let eventSource = CGEventSource(stateID: .hidSystemState)
//        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
//        event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [char])
//        event?.post(tap: .cghidEventTap)
//    }
    
    // MARK: - 파일 관리
    private func setupFileSystem() {
        let fileManager = FileManager.default
        let appDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoHangulEnglish")
        
        if !fileManager.fileExists(atPath: appDir.path) {
            try? fileManager.createDirectory(at: appDir, withIntermediateDirectories: true)
        }
        
        let snippetsFile = appDir.appendingPathComponent("snippets.json")
        if !fileManager.fileExists(atPath: snippetsFile.path) {
            let defaultContent = """
            [{"shortcut": "test", "text": "실행 테스트"}]
            """
            try? defaultContent.write(to: snippetsFile, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - 스니펫 관리
    private func reloadSnippets() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoHangulEnglish/snippets.json")
        
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else {
            return
        }
        
        snippets.removeAll()
        json.forEach { item in
            guard let shortcut = item["shortcut"], let text = item["text"] else { return }
            snippets[shortcut] = text
//            longestShortcutLength = max(longestShortcutLength, shortcut.count)
            longestShortcutLength = 20
        }
    }
    
    // MARK: - 파일 모니터링
    private func startFileMonitoring() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoHangulEnglish/snippets.json")
        
        // 컨텍스트 구조체 생성
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        
        let paths = [fileURL.path] as CFArray
        
        eventStream = FSEventStreamCreate(
            nil,
            { (stream, contextInfo, numEvents, eventPaths, eventFlags, eventIDs) in
                guard let contextInfo = contextInfo else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(contextInfo).takeUnretainedValue()
                delegate.reloadSnippets()
            },
            &context,  // 수정된 부분: 컨텍스트 구조체의 포인터 전달
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )
        
        guard let stream = eventStream else { return }
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        FSEventStreamStart(stream)
    }
    
    private func stopFileMonitoring() {
        guard let stream = eventStream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
    
    // MARK: - 키 모니터링 제어
    private func enableKeyMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        monitoringEnabled = true
    }
    
    private func disableKeyMonitoring() {
        guard let monitor = eventMonitor else { return }
        NSEvent.removeMonitor(monitor)
        eventMonitor = nil
        monitoringEnabled = false
    }
    
    // MARK: - 메뉴 액션
    @objc private func toggleMonitoring() {
        monitoringEnabled ? disableKeyMonitoring() : enableKeyMonitoring()
        updateMenuState()
    }
    
    @objc private func openSnippetsFile() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoHangulEnglish/snippets.json")
        NSWorkspace.shared.open(fileURL)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func updateMenuState() {
        guard let toggleItem = menu.item(at: 0) else { return }
        toggleItem.state = monitoringEnabled ? .on : .off
    }
    
    // MARK: - 백그라운드 실행 설정
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}
