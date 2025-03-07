

import Cocoa
import CoreML
import SwiftUI
import Carbon.HIToolbox
import Security
import Foundation
import Carbon

enum Lang {
    case en, ko
}

@main
struct AutoHangulEnglishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings { EmptyView() }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    // Status bar properties
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    
    // Mouse click monitor
    var mouseClickMonitor: Any?
    var lastCapsLockTime: Date?
    
    // Puase hot key doulbe caps time tinerval
    let doubleClickInterval: TimeInterval = 0.3
    private var languageToggleOption = 1
    
    // Keyboard monitoring properties
    var currentKeyStream = ""
    var snippets = [String: String]()
    var longestShortcutLength = 0
    var monitoringEnabled = false
    var string_count = 0
    var eventMonitor: Any?
    var isPaused = false
    var pressedKeys = Set<UInt16>()
    var keyDownMonitor: Any?
    var keyUpMonitor: Any?
    
    // Hangul automata
    var automata = KeyboardAutomata()
    var hautomata = HangulAutomata()
     
    // File observation
    var eventStream: FSEventStreamRef?
    
    // Model
    var model: MLModel?
    let handler = LanguageClassifierHandler()
    
    // Settings
    var processOnSpace: Bool {
        get { UserDefaults.standard.bool(forKey: "processOnSpace") }
        set { UserDefaults.standard.set(newValue, forKey: "processOnSpace") }
    }
    var bufferLengthThreshold: Int {
        get { UserDefaults.standard.integer(forKey: "bufferLengthThreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "bufferLengthThreshold") }
    }
    var confidenceThreshold: Float {
        get { UserDefaults.standard.float(forKey: "confidenceThreshold") }
        set { UserDefaults.standard.set(newValue, forKey: "confidenceThreshold") }
    }
    
    // Conversion history for rollback
    var lastConversionTime: Date?
    var lastOriginalText: String?
    var lastConvertedText: String?
    var lastSwitchedFromLang: Lang?
    
    // MARK: - App Lifecycle
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        checkAccessibilityPermissions()
        setupApplication()
        setupSettings()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        stopFileMonitoring()
        if let monitor = keyDownMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = keyUpMonitor { NSEvent.removeMonitor(monitor) }
    }
    
    // MARK: - Initial Setup
    private func setupApplication() {
        loadModel()
        setupStatusMenu()
        setupFileSystem()
        reloadSnippets()
        startFileMonitoring()
        enableKeyMonitoring()
        // Observe input source changes for buffer reset and rollback
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }
    
    private func setupSettings() {
        UserDefaults.standard.register(defaults: [
            "processOnSpace": true,
            "bufferLengthThreshold": 10,
            "confidenceThreshold": 0.95
        ])
    }
    
    private func setupStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(named: "MenuIcon") ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)!
        icon.isTemplate = true
        statusItem.button?.image = icon
        
        updateMenuState()
    }
    
    // MARK: - Settings Window
    var settingsWindow: NSWindow?
    
    @objc private func openSettings() {
        if settingsWindow == nil {
            let hostingController = NSHostingController(rootView: SettingsView())
            settingsWindow = NSWindow(contentViewController: hostingController)
            settingsWindow?.title = "Settings"
            settingsWindow?.styleMask = [.titled, .closable]
            settingsWindow?.level = .floating
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - Accessibility Permissions
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
                                 options: .byComposedCharacterSequences) { _, _, _, _ in
            count += 1
        }
        return count
    }
    
    private func resetAutomata(stream: Bool = true) {
        hautomata.buffer.removeAll()
        hautomata.inpStack.removeAll()
        hautomata.currentHangulState = nil
        if stream {
            currentKeyStream = ""
        }
    }
    
    // MARK: - Pause Logic
    @objc private func togglePause() {
        isPaused.toggle()
        
        // Update icon based on pause state
        let iconName = isPaused ? "pause_keyboard" : "MenuIcon"
        let icon = NSImage(named: iconName) ?? NSImage(systemSymbolName: isPaused ? "pause.fill" : "keyboard", accessibilityDescription: nil)!
        icon.isTemplate = true
        statusItem.button?.image = icon
        
//        if isPaused {
//            disableKeyMonitoring()
//            print("Paused")
//        } else {
//            enableKeyMonitoring()
//            print("Resumed")
//        }
        
        // Update menu state to reflect the new pause status
        updateMenuState()
    }
    
    // MARK: - Key Event Handling
    private func handleKeyEvent(_ event: NSEvent) {
        // 오직 keyDown 이벤트만 처리
        guard event.type == .keyDown,
              let cgEvent = event.cgEvent,
              let chars = event.charactersIgnoringModifiers else { return }
        
        // 자신의 프로세스에서 발생한 이벤트는 무시
        let eventPID = cgEvent.getIntegerValueField(.eventSourceUnixProcessID)
        let appPID = Int64(ProcessInfo.processInfo.processIdentifier)
        if eventPID == appPID { return }
        
        // Pause Hot Key: 1, 2, 3 키가 동시에 눌렸는지 확인
        pressedKeys.insert(event.keyCode)
        let pauseKeys: Set<UInt16> = [UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3)]
        if pauseKeys.isSubset(of: pressedKeys) {
            pressedKeys.remove(event.keyCode)
            print("Detected simultaneous press of 1, 2, 3 ,Pausing now")
            togglePause()
            deleteCharacters(count: 3)
            return
        }
        
        // Pause 상태이면 더 이상 처리하지 않음
        if isPaused { return }
        
        // Shift를 제외한 modifier 키 체크
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) ||
           modifiers.contains(.option) ||
           modifiers.contains(.control) ||
           modifiers.contains(.function) {
            resetAutomata()
            return
        }
        
        // 텍스트 입력이 아닌 키(화살표, 펑션키 등) 체크
        let nonTextKeyCodes: Set<UInt16> = [
            UInt16(kVK_UpArrow), UInt16(kVK_DownArrow),
            UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow),
            UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
            UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
            UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
            UInt16(kVK_Home), UInt16(kVK_End),
            UInt16(kVK_PageUp), UInt16(kVK_PageDown),
            UInt16(kVK_Return)
        ]
        if nonTextKeyCodes.contains(event.keyCode) {
            resetAutomata()
            return
        }
        
        // 입력된 문자들을 누적
        currentKeyStream += chars
        
        // 백스페이스(Delete) 입력 시 자동 초기화
        if event.keyCode == kVK_Delete {
            resetAutomata()
            return
        } else if processOnSpace && event.keyCode == kVK_Space {
            processBuffer(isSpaceTriggered: true)
        } else if !processOnSpace && currentKeyStream.count >= bufferLengthThreshold {
            processBuffer(isSpaceTriggered: false)
        }
        
        print("기본: ", currentKeyStream)

    }
    // MARK: == MAIN ==
    private func processBuffer(isSpaceTriggered: Bool) {
        let currentLang = getCurrentLanguage()
        print("current lanauge:",currentLang)
        let bufferToProcess = currentLang == .ko ? hangulToQwerty(currentKeyStream) : currentKeyStream
        
        guard let prob = handler.predict(word: bufferToProcess) else {
            print("처리 불가")
            resetAutomata()
            return
        }
        if prob >= 0.5 {
            let englishProbability = String(format: "%.2f", prob * 100)
            print("영어 확률: \(englishProbability)%")
        } else {
            let koreanProbability = String(format: "%.2f", (1 - prob) * 100)
            print("한국어 확률: \(koreanProbability)%")
        }
        
        let isEnglish: Bool
        if prob < (1.0 - confidenceThreshold) {
            isEnglish = false
        } else if prob > confidenceThreshold {
            isEnglish = true
        } else {
            resetAutomata()
            return
        }
        
        let bufferLength = getVisibleCharacterCount(input: currentKeyStream)
        if (currentLang == .en && isEnglish) || (currentLang == .ko && !isEnglish) {
            resetAutomata()
            return
//          deleteCharacters(count: bufferLength)
//          typeText(currentKeyStream)
        }
        else if currentLang == .en && !isEnglish {
            for key in currentKeyStream {
                hautomata.hangulAutomata(key: qwertyToHangul(String(key)))
            }
            let buffer = hautomata.buffer.reduce("") { $0 + $1 }
            let deleteCount = isSpaceTriggered ? bufferLength + 1 : bufferLength
            deleteCharacters(count: deleteCount)
            let typeBuffer = isSpaceTriggered ? buffer + " " : buffer
            typeText(typeBuffer)
            //switchToLanguage(.ko)
            toggleLanguage(option: languageToggleOption)
            lastConversionTime = Date()
            lastOriginalText = currentKeyStream
            lastConvertedText = typeBuffer
            lastSwitchedFromLang = .en
        } else if currentLang == .ko && isEnglish {
            print("in swap ko-> en")
            print("debugmode")
            print("Current Key Stream")
            print(currentKeyStream)
            var newBuffer = ""
            for key in currentKeyStream {
                newBuffer.append(hangulToQwerty(String(key)))
            }
            let Kor_Buffer = convEn2Ko(newBuffer)
            print(Kor_Buffer)
            
            deleteCharacters(count: Kor_Buffer.count)
            print("how many del")
            print(Kor_Buffer.count)
            print("newbuffer")
            print(newBuffer)
            typeText(newBuffer)
            //switchToLanguage(.en)
            toggleLanguage(option: languageToggleOption)
            lastConversionTime = Date()
            lastConvertedText = newBuffer
            lastSwitchedFromLang = .ko
        }
        resetAutomata()
    }
    
    // MARK: - Language Utilities
    private func getCurrentLanguage() -> Lang {
        guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue() else {
            return .en
        }
        let languagesPtr = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceLanguages)
        if let languagesPtr = languagesPtr {
            let languages = Unmanaged<CFArray>.fromOpaque(languagesPtr).takeUnretainedValue() as? [String]
            return (languages?.first == "ko") ? .ko : .en
        }
        return .en
    }


    // MARK: Switch Language
//        private func switchToLanguage(_ lang: Lang) {
//            let targetLang = lang == .en ? "en" : "ko"
//            if let inputSource = getInputSources(forLanguage: targetLang).first {
//                TISSelectInputSource(inputSource)
//            }
//        }
//    
    private func toggleLanguage(option: Int) {
        // Get current language
        let currentLang = getCurrentLanguage()
        let targetLang: Lang = currentLang == .en ? .ko : .en
        
        switch option {
        case 1: // Default method - using TIS
            let targetLangCode = targetLang == .en ? "en" : "ko"
            if let inputSource = getInputSources(forLanguage: targetLangCode).first {
                TISSelectInputSource(inputSource)
            }
        case 2: // Simulate pressing Caps Lock
            let source = CGEventSource(stateID: .hidSystemState)
            let capsLockKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x39, keyDown: true)
            let capsLockKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x39, keyDown: false)
            capsLockKeyDown?.post(tap: .cghidEventTap)
            capsLockKeyUp?.post(tap: .cghidEventTap)
        case 3: // Simulate pressing Command+Space
            let source = CGEventSource(stateID: .hidSystemState)
            let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true)
            let spaceDown = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: true)
            let spaceUp = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: false)
            let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false)
            
            cmdDown?.flags = .maskCommand
            spaceDown?.flags = .maskCommand
            spaceUp?.flags = .maskCommand
            
            cmdDown?.post(tap: .cghidEventTap)
            spaceDown?.post(tap: .cghidEventTap)
            spaceUp?.post(tap: .cghidEventTap)
            cmdUp?.post(tap: .cghidEventTap)
        default:
            // Default to option 1 if invalid option
            let targetLangCode = targetLang == .en ? "en" : "ko"
            if let inputSource = getInputSources(forLanguage: targetLangCode).first {
                TISSelectInputSource(inputSource)
            }
        }
    }


    private func getInputSources(forLanguage lang: String) -> [TISInputSource] {
        let inputSources = TISCreateInputSourceList(nil, false).takeUnretainedValue() as? [TISInputSource] ?? []
        return inputSources.filter { source in
            let languagesPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages)
            if let languagesPtr = languagesPtr {
                let languages =	 Unmanaged<CFArray>.fromOpaque(languagesPtr).takeUnretainedValue() as? [String]
                return languages?.first == lang
            }
            return false
        }
    }

    @objc func inputSourceChanged() {
        let currentLang = getCurrentLanguage()
        if let lastTime = lastConversionTime, Date().timeIntervalSince(lastTime) < 1.0,
           let fromLang = lastSwitchedFromLang, currentLang == fromLang,
           let original = lastOriginalText, let converted = lastConvertedText {
            let convertedCount = getVisibleCharacterCount(input: converted)
            deleteCharacters(count: convertedCount)
            typeText(original)
        }
        resetAutomata()
    }
    
    // MARK: - Text Input Utilities
    private func deleteCharacters(count: Int) {
        // Add left arrow key press
        postKeyEvent(keyCode: kVK_LeftArrow, keyDown: true)
        postKeyEvent(keyCode: kVK_LeftArrow, keyDown: false)
        // Add right arrow key press
        postKeyEvent(keyCode: kVK_RightArrow, keyDown: true)
        postKeyEvent(keyCode: kVK_RightArrow, keyDown: false)
        (0..<count).forEach { _ in
            postKeyEvent(keyCode: kVK_Delete, keyDown: true)
            postKeyEvent(keyCode: kVK_Delete, keyDown: false)
        }

    }
    
    private func typeText(_ text: String) {
        text.utf16.forEach { postUnicodeChar($0) }
    }
    
    private func postKeyEvent(keyCode: Int, keyDown: Bool) {
        let eventSource = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
        let pid = ProcessInfo.processInfo.processIdentifier
        event?.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(pid))
        event?.post(tap: .cghidEventTap)
    }
    
    private func postUnicodeChar(_ char: UniChar) {
        let eventSource = CGEventSource(stateID: .hidSystemState)
        let event = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true)
        let pid = ProcessInfo.processInfo.processIdentifier
        event?.setIntegerValueField(.eventSourceUnixProcessID, value: Int64(pid))
        event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: [char])
        event?.post(tap: .cghidEventTap)
    }
    
    // MARK: - File Management (unchanged)
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
            longestShortcutLength = 20
        }
    }
    
    private func startFileMonitoring() {
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AutoHangulEnglish/snippets.json")
        
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
            { (stream, contextInfo, _, _, _, _) in
                guard let contextInfo = contextInfo else { return }
                let delegate = Unmanaged<AppDelegate>.fromOpaque(contextInfo).takeUnretainedValue()
                delegate.reloadSnippets()
            },
            &context,
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
    
    // MARK: - Key Monitoring Control
    private func enableKeyMonitoring() {
        guard keyDownMonitor == nil, keyUpMonitor == nil, mouseClickMonitor == nil else { return }
        
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        keyUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyUp) { [weak self] event in
            self?.handleKeyUp(event)
        }
        
        mouseClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.resetAutomata()
        }
        
        monitoringEnabled = true
    }
    
//    private func disableKeyMonitoring() {
//        if let monitor = keyDownMonitor {
//            NSEvent.removeMonitor(monitor)
//            keyDownMonitor = nil
//        }
//        if let monitor = keyUpMonitor {
//            NSEvent.removeMonitor(monitor)
//            keyUpMonitor = nil
//        }
//        if let monitor = mouseClickMonitor {
//            NSEvent.removeMonitor(monitor)
//            mouseClickMonitor = nil
//        }
//        monitoringEnabled = false
//    }
    
    private func handleKeyUp(_ event: NSEvent) {
        pressedKeys.remove(event.keyCode)
    }
    
    // MARK: - Menu Actions
    @objc private func toggleMonitoring() {
        
//        monitoringEnabled ? disableKeyMonitoring() : enableKeyMonitoring()
//        updateMenuState()
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func updateMenuState() {
        menu.removeAllItems() // Clear existing items
        
        // Add pause/resume toggle with changing text
        let pauseTitle = isPaused ? "다시실행" : "일시중지"
        menu.addItem(withTitle: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        
        menu.addItem(withTitle: "설정", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "종료", action: #selector(quitApp), keyEquivalent: "q")
        
        statusItem.menu = menu
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
}

// MARK: - UI Settings View
struct SettingsView: View {
    @AppStorage("processOnSpace") private var processOnSpace = true
    @AppStorage("bufferLengthThreshold") private var bufferLengthThreshold = 10
    @AppStorage("confidenceThreshold") private var confidenceThreshold: Double = 0.95
    @AppStorage("languageToggleOption") private var languageToggleOption = 1
    
    @State private var showLanguageHelp = false
    
    var body: some View {
        Form {
            Toggle("Process buffer on space", isOn: $processOnSpace)
            Stepper("Buffer length threshold: \(bufferLengthThreshold)", value: $bufferLengthThreshold, in: 1...50)
            Slider(value: $confidenceThreshold, in: 0.5...1.0, step: 0.01) {
                Text("Confidence threshold: \(confidenceThreshold, specifier: "%.2f")")
            }
            
            HStack {
                Text("언어 변경 방법")
                Button(action: {
                    showLanguageHelp.toggle()
                }) {
                    Image(systemName: "questionmark.circle")
                }
                .popover(isPresented: $showLanguageHelp) {
                    Text("이 옵션은 자동으로 언어가 안 변경될 경우, 자신에게 맞는 언어 변경 옵션을 선택합니다")
                        .padding()
                        .frame(width: 300)
                }
            }
            
            Picker("", selection: $languageToggleOption) {
                Text("기본값").tag(1)
                Text("캡스락").tag(2)
                Text("컨트롤+스페이스").tag(3)
            }
            .pickerStyle(MenuPickerStyle())
            
            Button("Reset to default") {
                processOnSpace = true
                bufferLengthThreshold = 10
                confidenceThreshold = 0.95
                languageToggleOption = 1
            }
        }
        .padding()
        .frame(width: 300, height: 250)
    }
}
