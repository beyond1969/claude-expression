import AppKit

// Base directory: passed as first argument from start.sh
guard CommandLine.arguments.count > 1 else {
    fputs("Usage: swift viewer.swift <base-directory>\n", stderr)
    exit(1)
}
let baseDir = CommandLine.arguments[1]
let stateDir = "\(baseDir)/state"
let agentsDir = "\(baseDir)/agents"
let pidFile = "\(stateDir)/.viewer.pid"

let agentSize = NSSize(width: 240, height: 240)
let agentSpacing: CGFloat = 8

// Speech bubble constants
let speechPaddingH: CGFloat = 12
let speechPaddingV: CGFloat = 8
let speechTailHeight: CGFloat = 10
let speechTailWidth: CGFloat = 16
let speechGap: CGFloat = 4
let speechMinHeight: CGFloat = 32
let speechCornerRadius: CGFloat = 10
let speechBubbleColor = NSColor(white: 0.15, alpha: 0.9)
let speechTextFont = NSFont.systemFont(ofSize: 13)

// Measurement label for speech bubble height calculation
let measureLabel: NSTextField = {
    let field = NSTextField(frame: .zero)
    field.isEditable = false
    field.isBordered = false
    field.drawsBackground = false
    field.font = speechTextFont
    field.alignment = .center
    field.lineBreakMode = .byWordWrapping
    field.maximumNumberOfLines = 0
    field.cell?.wraps = true
    field.cell?.isScrollable = false
    return field
}()

// Kill previous instance
if let oldPidStr = try? String(contentsOfFile: pidFile, encoding: .utf8),
   let oldPid = Int32(oldPidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
   oldPid != getpid() {
    kill(oldPid, SIGTERM)
    usleep(200_000)
}
try? "\(getpid())".write(toFile: pidFile, atomically: true, encoding: .utf8)

// Scan agents/ directory for agent names
func scanAgentNames() -> [String] {
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: agentsDir) else {
        return []
    }
    var isDir: ObjCBool = false
    return entries
        .filter { name in
            !name.hasPrefix(".") &&
            FileManager.default.fileExists(atPath: "\(agentsDir)/\(name)", isDirectory: &isDir) &&
            isDir.boolValue
        }
        .sorted()
}

var knownAgentNames: [String] = scanAgentNames()

// Activation order — agents are displayed in the order they were activated
var visibleOrder: [String] = []

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// Selected screen (nil = auto: portrait preferred, fallback to main)
var selectedScreen: NSScreen? = nil

func findTargetScreen() -> NSScreen {
    if let selected = selectedScreen,
       NSScreen.screens.contains(where: { $0 == selected }) {
        return selected
    }
    if let portrait = NSScreen.screens.first(where: { $0.frame.height > $0.frame.width }) {
        return portrait
    }
    return NSScreen.main ?? NSScreen.screens.first ?? {
        fatalError("No screen available")
    }()
}

func findTargetScreenFrame() -> NSRect {
    return findTargetScreen().visibleFrame
}

// Window — initial size for up to 4 agents
let maxAgents = max(knownAgentNames.count, 4)
let maxWidth = (agentSize.width + agentSpacing) * CGFloat(maxAgents)
let windowSize = NSSize(width: maxWidth, height: agentSize.height)
let initialScreenFrame = findTargetScreenFrame()
let origin = NSPoint(
    x: initialScreenFrame.minX + 20,
    y: initialScreenFrame.maxY - windowSize.height - 20
)

let window = NSWindow(
    contentRect: NSRect(origin: origin, size: windowSize),
    styleMask: [.borderless],
    backing: .buffered,
    defer: false
)
window.level = .floating
window.isOpaque = false
window.backgroundColor = .clear
window.hasShadow = false

let containerView = NSView(frame: NSRect(origin: .zero, size: windowSize))
window.contentView = containerView

// Monitor select button — shows dropdown of available monitors
class MonitorSelectHelper: NSObject {
    @objc func showMenu(_ sender: NSButton) {
        let menu = NSMenu()

        // "Auto" option (portrait preferred → main)
        let autoItem = NSMenuItem(title: "Auto", action: #selector(selectAuto), keyEquivalent: "")
        autoItem.target = self
        if selectedScreen == nil {
            autoItem.state = .on
        }
        menu.addItem(autoItem)
        menu.addItem(NSMenuItem.separator())

        // List all connected monitors
        for (index, screen) in NSScreen.screens.enumerated() {
            let name = screen.localizedName
            let resolution = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
            let isMain = (screen == NSScreen.main) ? " (main)" : ""
            let title = "\(index + 1). \(name) — \(resolution)\(isMain)"

            let item = NSMenuItem(title: title, action: #selector(selectMonitor(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            if let sel = selectedScreen, sel == screen {
                item.state = .on
            }
            menu.addItem(item)
        }

        // Show popup below the button
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
    }

    @objc func selectAuto() {
        selectedScreen = nil
        layoutAgents()
    }

    @objc func selectMonitor(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index >= 0, index < NSScreen.screens.count else { return }
        selectedScreen = NSScreen.screens[index]
        layoutAgents()
    }
}
let monitorHelper = MonitorSelectHelper()

let refreshButton: NSButton = {
    let btn = NSButton(frame: NSRect(x: 0, y: 0, width: 26, height: 26))
    btn.isBordered = false
    btn.title = ""
    btn.wantsLayer = true
    btn.layer?.cornerRadius = 13
    btn.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.65).cgColor
    btn.attributedTitle = NSAttributedString(
        string: "⟳",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor(white: 1.0, alpha: 0.85)
        ]
    )
    btn.target = monitorHelper
    btn.action = #selector(MonitorSelectHelper.showMenu(_:))
    btn.isHidden = true
    return btn
}()
var lastScreenFrame: NSRect = initialScreenFrame

// Per-agent view state
struct AgentView {
    let imageView: NSImageView
    let placeholderView: NSTextField
    let speechBubbleView: NSView
    let speechLabel: NSTextField
    let speechTailLayer: CAShapeLayer
    let wrapperView: NSView
    var currentExpression: String = ""
    var currentSpeech: String = ""
    var isVisible: Bool = false
}

var agentViews: [String: AgentView] = [:]

func createAgentView(name: String) -> AgentView {
    let wrapper = NSView(frame: NSRect(origin: .zero, size: agentSize))
    wrapper.wantsLayer = true
    wrapper.isHidden = true

    let imageView = NSImageView(frame: NSRect(origin: .zero, size: agentSize))
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.wantsLayer = true
    imageView.layer?.cornerRadius = 16
    imageView.layer?.masksToBounds = true
    imageView.isHidden = true
    wrapper.addSubview(imageView)

    // Placeholder: show first letter when no image available
    let placeholder = NSTextField(frame: NSRect(origin: .zero, size: agentSize))
    placeholder.isEditable = false
    placeholder.isBordered = false
    placeholder.alignment = .center
    placeholder.font = NSFont.systemFont(ofSize: 80, weight: .bold)
    placeholder.textColor = .white
    placeholder.backgroundColor = .clear
    placeholder.wantsLayer = true
    placeholder.layer?.cornerRadius = 16
    placeholder.layer?.masksToBounds = true
    placeholder.layer?.backgroundColor = NSColor(white: 0.2, alpha: 0.85).cgColor
    placeholder.stringValue = String(name.prefix(1)).uppercased()
    placeholder.isHidden = true
    wrapper.addSubview(placeholder)

    // Speech bubble background
    let speechBubble = NSView(frame: .zero)
    speechBubble.wantsLayer = true
    speechBubble.layer?.cornerRadius = speechCornerRadius
    speechBubble.layer?.backgroundColor = speechBubbleColor.cgColor
    speechBubble.isHidden = true
    wrapper.addSubview(speechBubble)

    // Speech bubble text
    let speechLabel = NSTextField(frame: .zero)
    speechLabel.isEditable = false
    speechLabel.isBordered = false
    speechLabel.drawsBackground = false
    speechLabel.textColor = .white
    speechLabel.font = speechTextFont
    speechLabel.alignment = .center
    speechLabel.lineBreakMode = .byWordWrapping
    speechLabel.maximumNumberOfLines = 0
    speechLabel.cell?.wraps = true
    speechLabel.cell?.isScrollable = false
    speechBubble.addSubview(speechLabel)

    // Speech bubble tail (triangle)
    let tailLayer = CAShapeLayer()
    tailLayer.fillColor = speechBubbleColor.cgColor
    tailLayer.isHidden = true
    wrapper.layer?.addSublayer(tailLayer)

    containerView.addSubview(wrapper)

    return AgentView(
        imageView: imageView,
        placeholderView: placeholder,
        speechBubbleView: speechBubble,
        speechLabel: speechLabel,
        speechTailLayer: tailLayer,
        wrapperView: wrapper,
        currentExpression: "",
        currentSpeech: "",
        isVisible: false
    )
}

// Initialize views for known agents
for name in knownAgentNames {
    agentViews[name] = createAgentView(name: name)
}

// Refresh button on top (z-order)
containerView.addSubview(refreshButton)

func expressionFilePath(for name: String) -> String {
    return "\(stateDir)/\(name)_expression"
}

func speechFilePath(for name: String) -> String {
    return "\(stateDir)/\(name)_speech"
}

func calculateSpeechBubbleHeight(text: String) -> CGFloat {
    let maxTextWidth = agentSize.width - speechPaddingH * 2
    measureLabel.stringValue = text
    let cellSize = measureLabel.cell!.cellSize(
        forBounds: NSRect(x: 0, y: 0, width: maxTextWidth, height: CGFloat.greatestFiniteMagnitude)
    )
    return max(speechMinHeight, ceil(cellSize.height) + speechPaddingV * 2)
}

func agentTotalHeight(for name: String) -> CGFloat {
    guard let agent = agentViews[name] else { return agentSize.height }
    if agent.currentSpeech.isEmpty {
        return agentSize.height
    }
    let bubbleHeight = calculateSpeechBubbleHeight(text: agent.currentSpeech)
    return agentSize.height + speechGap + speechTailHeight + bubbleHeight
}

func layoutSpeechBubble(for name: String) {
    guard let agent = agentViews[name] else { return }
    let hasSpeech = !agent.currentSpeech.isEmpty

    agent.speechBubbleView.isHidden = !hasSpeech
    agent.speechTailLayer.isHidden = !hasSpeech

    if hasSpeech {
        let bubbleHeight = calculateSpeechBubbleHeight(text: agent.currentSpeech)
        let bubbleY = agentSize.height + speechGap + speechTailHeight

        agent.speechBubbleView.frame = NSRect(
            x: 0, y: bubbleY,
            width: agentSize.width, height: bubbleHeight
        )

        agent.speechLabel.frame = NSRect(
            x: speechPaddingH, y: speechPaddingV,
            width: agentSize.width - speechPaddingH * 2,
            height: bubbleHeight - speechPaddingV * 2
        )

        // Tail triangle (center bottom, between bubble and image)
        let tailPath = CGMutablePath()
        let tailCenterX = agentSize.width / 2
        let tailTop = bubbleY
        let tailBottom = agentSize.height + speechGap
        tailPath.move(to: CGPoint(x: tailCenterX, y: tailBottom))
        tailPath.addLine(to: CGPoint(x: tailCenterX - speechTailWidth / 2, y: tailTop))
        tailPath.addLine(to: CGPoint(x: tailCenterX + speechTailWidth / 2, y: tailTop))
        tailPath.closeSubpath()
        agent.speechTailLayer.path = tailPath
    }
}

func layoutAgents() {
    let visibleAgents = visibleOrder

    let totalWidth = CGFloat(visibleAgents.count) * agentSize.width +
        CGFloat(max(0, visibleAgents.count - 1)) * agentSpacing

    var maxHeight: CGFloat = agentSize.height
    for name in visibleAgents {
        maxHeight = max(maxHeight, agentTotalHeight(for: name))
    }

    let currentScreenFrame = findTargetScreenFrame()
    let newWindowSize = NSSize(width: max(agentSize.width, totalWidth), height: maxHeight)
    let newOrigin = NSPoint(
        x: currentScreenFrame.minX + 20,
        y: currentScreenFrame.maxY - newWindowSize.height - 20
    )
    window.setFrame(NSRect(origin: newOrigin, size: newWindowSize), display: false)
    containerView.frame = NSRect(origin: .zero, size: newWindowSize)

    if !visibleAgents.isEmpty {
        refreshButton.frame.origin = NSPoint(
            x: totalWidth - refreshButton.frame.width - 2,
            y: 2
        )
        refreshButton.isHidden = false
    } else {
        refreshButton.isHidden = true
    }

    var xOffset: CGFloat = 0
    for name in visibleAgents {
        let height = agentTotalHeight(for: name)

        agentViews[name]?.wrapperView.frame = NSRect(
            x: xOffset, y: 0,
            width: agentSize.width, height: height
        )

        agentViews[name]?.imageView.frame = NSRect(origin: .zero, size: agentSize)
        agentViews[name]?.placeholderView.frame = NSRect(origin: .zero, size: agentSize)

        layoutSpeechBubble(for: name)

        xOffset += agentSize.width + agentSpacing
    }
}

func updateAgents() {
    var needsLayout = false

    // Monitor change detection
    let currentScreen = findTargetScreenFrame()
    if currentScreen != lastScreenFrame {
        lastScreenFrame = currentScreen
        needsLayout = true
    }

    // Rescan agents/ directory for new agents
    let currentAgentNames = scanAgentNames()
    if currentAgentNames != knownAgentNames {
        for name in currentAgentNames where !knownAgentNames.contains(name) {
            agentViews[name] = createAgentView(name: name)
        }
        // Remove agents whose directories were deleted
        for name in knownAgentNames where !currentAgentNames.contains(name) {
            if let agent = agentViews[name] {
                agent.wrapperView.removeFromSuperview()
                agentViews.removeValue(forKey: name)
                visibleOrder.removeAll { $0 == name }
            }
        }
        knownAgentNames = currentAgentNames
        // Re-add refresh button on top after new subviews
        refreshButton.removeFromSuperview()
        containerView.addSubview(refreshButton)
        needsLayout = true
    }

    for name in knownAgentNames {
        let exprFile = expressionFilePath(for: name)
        let fileExists = FileManager.default.fileExists(atPath: exprFile)

        guard var agent = agentViews[name] else { continue }

        if fileExists && !agent.isVisible {
            agent.isVisible = true
            agent.wrapperView.isHidden = false
            if !visibleOrder.contains(name) {
                visibleOrder.append(name)
            }
            needsLayout = true
        } else if !fileExists && agent.isVisible {
            agent.isVisible = false
            agent.wrapperView.isHidden = true
            agent.currentExpression = ""
            agent.currentSpeech = ""
            agent.speechBubbleView.isHidden = true
            agent.speechTailLayer.isHidden = true
            visibleOrder.removeAll { $0 == name }
            agentViews[name] = agent
            needsLayout = true
            continue
        }

        guard fileExists else {
            agentViews[name] = agent
            continue
        }

        // Update expression
        let expression = (try? String(contentsOfFile: exprFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "normal"

        if expression != agent.currentExpression {
            agent.currentExpression = expression
            let imagePath = "\(agentsDir)/\(name)/\(expression).png"

            if let image = NSImage(contentsOfFile: imagePath) {
                agent.imageView.image = image
                agent.imageView.isHidden = false
                agent.placeholderView.isHidden = true
            } else {
                agent.imageView.isHidden = true
                agent.placeholderView.isHidden = false
            }
        }

        // Update speech bubble
        let speechFile = speechFilePath(for: name)
        let speech = ((try? String(contentsOfFile: speechFile, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if speech != agent.currentSpeech {
            agent.currentSpeech = speech
            agent.speechLabel.stringValue = speech
            needsLayout = true
        }

        agentViews[name] = agent
    }

    if needsLayout {
        layoutAgents()
    }
}

updateAgents()
window.makeKeyAndOrderFront(nil)

// Poll for file changes every 0.3 seconds
Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
    updateAgents()
}

signal(SIGTERM) { _ in
    try? FileManager.default.removeItem(atPath: pidFile)
    exit(0)
}

app.run()
