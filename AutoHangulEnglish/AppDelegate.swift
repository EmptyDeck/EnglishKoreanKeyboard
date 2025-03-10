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
    // MARK: - Properties
    
    // Status bar properties
    var statusItem: NSStatusItem!
    let menu = NSMenu()
    
    // Mouse and keyboard monitoring
    var mouseClickMonitor: Any?
    var keyDownMonitor: Any?
    var keyUpMonitor: Any?
    var pressedKeys = Set<UInt16>()
    var lastCapsLockTime: Date?
    let doubleClickInterval: TimeInterval = 0.3
    var isPaused = false
    var monitoringEnabled = false
    
    // Text and language processing
    var currentKeyStream = ""
    var longestShortcutLength = 0
    var string_count = 0
    private var languageToggleOption = 1
    var lastConversionTime: Date?
    var lastOriginalText: String?
    var lastConvertedText: String?
    var lastSwitchedFromLang: Lang?
    
    // Hangul automata
    var automata = KeyboardAutomata()
    var hautomata = HangulAutomata()
    
    // File observation
    var eventStream: FSEventStreamRef?
    var snippets = [String: String]()
    
    // Machine learning model
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
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        return false
    }
    
    // MARK: - Setup Methods
    
    private func setupApplication() {
        loadModel()
        setupStatusMenu()
        setupFileSystem()
        reloadSnippets()
        startFileMonitoring()
        enableKeyMonitoring()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged),
            name: NSNotification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
            object: nil
        )
    }
    
    private func setupSettings() {
        UserDefaults.standard.register(defaults: [
            "processOnSpace": false,
            "bufferLengthThreshold": 10,
            "confidenceThreshold": 0.99
        ])
    }
    
    private func setupStatusMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(named: "MenuIcon") ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)!
        icon.isTemplate = true
        statusItem.button?.image = icon
        updateMenuState()
    }
    
    private func loadModel() {
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
    
    // MARK: - Accessibility
    
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
    
    // MARK: - Key Monitoring
    
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
    
    private func handleKeyUp(_ event: NSEvent) {
        pressedKeys.remove(event.keyCode)
    }
    // MARK: Handel Key Event
    private func handleKeyEvent(_ event: NSEvent) {
        guard event.type == .keyDown,
              let cgEvent = event.cgEvent,
              let chars = event.charactersIgnoringModifiers else { return }
        
        let eventPID = cgEvent.getIntegerValueField(.eventSourceUnixProcessID)
        let appPID = Int64(ProcessInfo.processInfo.processIdentifier)
        if eventPID == appPID { return }
        
        pressedKeys.insert(event.keyCode)
        let pauseKeys: Set<UInt16> = [UInt16(kVK_ANSI_1), UInt16(kVK_ANSI_2), UInt16(kVK_ANSI_3)]
        if pauseKeys.isSubset(of: pressedKeys) {
            pressedKeys.remove(event.keyCode)
            print("Detected simultaneous press of 1, 2, 3 ,Pausing now")
            togglePause()
            deleteCharacters(count: 3)
            return
        }
        
        if isPaused { return }
        
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.command) ||
            modifiers.contains(.option) ||
            modifiers.contains(.control) ||
            modifiers.contains(.function) {
            resetAutomata()
            return
        }
        
        // Reset buffer on non-text keys
        let nonTextKeyCodes: Set<UInt16> = [
            UInt16(kVK_UpArrow), UInt16(kVK_DownArrow),
            UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow),
            UInt16(kVK_F1), UInt16(kVK_F2), UInt16(kVK_F3), UInt16(kVK_F4),
            UInt16(kVK_F5), UInt16(kVK_F6), UInt16(kVK_F7), UInt16(kVK_F8),
            UInt16(kVK_F9), UInt16(kVK_F10), UInt16(kVK_F11), UInt16(kVK_F12),
            UInt16(kVK_F13), UInt16(kVK_F14), UInt16(kVK_F15), UInt16(kVK_F16),
            UInt16(kVK_Tab), UInt16(kVK_Shift), UInt16(kVK_Control),
            UInt16(kVK_Option), UInt16(kVK_Command), UInt16(kVK_Return)
        ]
        if nonTextKeyCodes.contains(event.keyCode) {
            resetAutomata()
            return
        }
        
        // First buffer cannot be space
        if currentKeyStream.isEmpty && chars == " " {
            return
        }
        
        // Define sentence-ending characters
        let sentenceEnders: Set<String> = [" ", "!", "?", "\n"]  // Enter is "\n"
        
        // Add character to buffer
        currentKeyStream += chars
        
        // Process buffer if Delete is pressed
        if event.keyCode == kVK_Delete {
            resetAutomata()
            return
        }
        // Process if it's a sentence-ender and buffer is long enough
        else if sentenceEnders.contains(chars) && currentKeyStream.count >= bufferLengthThreshold {
            processBuffer(isSpaceTriggered: true)
        }
        // Process if buffer exceeds max length (bufferLengthThreshold + 10)
        else if currentKeyStream.count >= bufferLengthThreshold + 10 {
            processBuffer(isSpaceTriggered: false)
        }
        
        print("기본: ", currentKeyStream)
    }
    
    // MARK: - Text Processing
    
    private func processBuffer(isSpaceTriggered: Bool) {
        let currentLang = getCurrentLanguage()
        print("current lanauge:", currentLang)
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
        
        if (currentLang == .en && isEnglish) || (currentLang == .ko && !isEnglish) {
            resetAutomata()
            return
        } else if currentLang == .en && !isEnglish {
            let newBuffer = convEn2Ko(currentKeyStream)
            print("newBuffer",newBuffer)
            print("delete", currentKeyStream.count)
            deleteCharacters(count: currentKeyStream.count)
            typeText(newBuffer)
            toggleLanguage(option: languageToggleOption)
            //
            //            for key in currentKeyStream {
            //                hautomata.hangulAutomata(key: qwertyToHangul(String(key)))
            //            }
            //            let buffer = hautomata.buffer.reduce("") { $0 + $1 }
            //            let deleteCount = isSpaceTriggered ? bufferLength + 1 : bufferLength
            //            deleteCharacters(count: deleteCount)
            //            let typeBuffer = isSpaceTriggered ? buffer + " " : buffer
            //            typeText(typeBuffer)
            //            toggleLanguage(option: languageToggleOption)
            //            lastConversionTime = Date()
            //            lastOriginalText = currentKeyStream
            //            lastConvertedText = typeBuffer
            //            lastSwitchedFromLang = .en
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
            toggleLanguage(option: languageToggleOption)
            lastConversionTime = Date()
            lastConvertedText = newBuffer
            lastSwitchedFromLang = .ko
        }
        resetAutomata()
    }
    
    private func resetAutomata(stream: Bool = true) {
        hautomata.buffer.removeAll()
        hautomata.inpStack.removeAll()
        hautomata.currentHangulState = nil
        if stream {
            currentKeyStream = ""
        }
    }
    
    private func getVisibleCharacterCount(input: String) -> Int {
        var count = 0
        input.enumerateSubstrings(in: input.startIndex..<input.endIndex,
                                  options: .byComposedCharacterSequences) { _, _, _, _ in
            count += 1
        }
        return count
    }
    
    // MARK: - Language Management
    
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
    
    private func toggleLanguage(option: Int) {
        let currentLang = getCurrentLanguage()
        let targetLang: Lang = currentLang == .en ? .ko : .en
        
        switch option {
        case 1:
            let targetLangCode = targetLang == .en ? "en" : "ko"
            if let inputSource = getInputSources(forLanguage: targetLangCode).first {
                TISSelectInputSource(inputSource)
            }
        case 2:
            let source = CGEventSource(stateID: .hidSystemState)
            let capsLockKeyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x39, keyDown: true)
            let capsLockKeyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x39, keyDown: false)
            capsLockKeyDown?.post(tap: .cghidEventTap)
            capsLockKeyUp?.post(tap: .cghidEventTap)
        case 3:
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
                let languages = Unmanaged<CFArray>.fromOpaque(languagesPtr).takeUnretainedValue() as? [String]
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
    
    // MARK: - Text Input
    
    private func deleteCharacters(count: Int) {
        postKeyEvent(keyCode: kVK_LeftArrow, keyDown: true)
        postKeyEvent(keyCode: kVK_LeftArrow, keyDown: false)
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
    
    // MARK: - File Management
    
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
    
    // MARK: - Menu Management
    
    @objc private func togglePause() {
        isPaused.toggle()
        let iconName = isPaused ? "pause_keyboard" : "MenuIcon"
        let icon = NSImage(named: iconName) ?? NSImage(systemSymbolName: isPaused ? "pause.fill" : "keyboard", accessibilityDescription: nil)!
        icon.isTemplate = true
        statusItem.button?.image = icon
        updateMenuState()
    }
    
    @objc private func toggleMonitoring() {
        // Placeholder for future toggle logic
    }
    
    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
    
    private func updateMenuState() {
        menu.removeAllItems()
        
        // "일시중지" 또는 "다시실행" 항목에 툴팁 추가
        let pauseTitle = isPaused ? "다시실행" : "일시중지"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        pauseItem.toolTip = "단축키: 1+2+3" // 툴팁으로 단축키 정보 표시
        menu.addItem(pauseItem)
        
        // "설정" 항목 추가
        menu.addItem(withTitle: "설정", action: #selector(openSettings), keyEquivalent: "")
        
        // 구분선 추가
        menu.addItem(.separator())
        
        // "종료" 항목 추가
        menu.addItem(withTitle: "종료", action: #selector(quitApp), keyEquivalent: "q")
        
        // 상태 바에 메뉴 연결
        statusItem.menu = menu
    }
    
    // GORK
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
    
    // MARK: - Settings View
    
    struct SettingsView: View {
        @AppStorage("processOnSpace") private var processOnSpace = false
        @AppStorage("bufferLengthThreshold") private var bufferLengthThreshold = 10
        @AppStorage("confidenceThreshold") private var confidenceThreshold: Double = 0.99
        @AppStorage("languageToggleOption") private var languageToggleOption = 1
        @State private var showLanguageHelp = false
        
        var body: some View {
            VStack(spacing: 20) {
                // Header
                Text("한영 자동 변경 설정")
                    .font(.headline)
                    .padding(.top, 20)
                
                // Settings Form
                VStack(alignment: .leading, spacing: 15) {
                    // Process on Space
                    Toggle(isOn: $processOnSpace) {
                        Text("스페이스바 누를때 감지")
                            .font(.system(size: 14))
                    }
                    .toggleStyle(SwitchToggleStyle(tint: .blue))
                    
                    // Buffer Length Threshold
                    HStack {
                        Text("특정 입력 길이에 감지: \(bufferLengthThreshold)")
                            .font(.system(size: 14))
                        Spacer()
                        Stepper("", value: $bufferLengthThreshold, in: 1...50)
                            .labelsHidden()
                            .frame(width: 50)
                    }
                    
                    // Confidence Threshold
                    VStack(alignment: .leading, spacing: 5) {
                        Text("변경 확신 % : \(confidenceThreshold, specifier: "%.2f")")
                            .font(.system(size: 14))
                        Slider(value: $confidenceThreshold, in: 0.5...1.0, step: 0.01)
                            .accentColor(.green)
                    }
                    
                    // Language Toggle Option
                    HStack {
                        Text("언어 변경 방법")
                            .font(.system(size: 14))
                        Button(action: { showLanguageHelp.toggle() }) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.gray)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .popover(isPresented: $showLanguageHelp) {
                            Text("이 옵션은 자동으로 언어가 안 변경될 경우, 자신에게 맞는 언어 변경 옵션을 선택합니다.")
                                .font(.system(size: 15))
                                .padding()
                                .frame(width: 250)
                        }
                        Spacer()
                        Picker("", selection: $languageToggleOption) {
                            Text("기본값").tag(1)
                            Text("캡스락").tag(2)
                            Text("컨트롤+스페이스").tag(3)
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 150)
                    }
                }
                .padding(.horizontal, 20)
                
                // Reset Button
                Button(action: {
                    processOnSpace = false
                    bufferLengthThreshold = 10
                    confidenceThreshold = 0.99
                    languageToggleOption = 1
                }) {
                    Text("Reset to Default")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 16)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Tip for pause shortcut
                Text("💡 1,2,3을 동시에 누르면 일시정지 됩니다")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
                    .padding(.bottom, 15)
                
                Spacer()
            }
            .frame(width: 350, height: 320) // 팁 추가로 높이를 약간 늘림
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}
