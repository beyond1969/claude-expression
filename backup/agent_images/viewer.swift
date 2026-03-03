import AppKit

let baseDir = "/Users/nhnent/agent_images"
let pidFile = NSString(string: "~/.agent_viewer.pid").expandingTildeInPath
let homeDir = NSString(string: "~").expandingTildeInPath

// 지원 에이전트 목록 (표시 우선순위 순)
let agentNames = ["klukai", "andoris", "mishuti", "viyolka"]

let agentSize = NSSize(width: 240, height: 240)
let agentSpacing: CGFloat = 8

// 말풍선 상수
let speechPaddingH: CGFloat = 12
let speechPaddingV: CGFloat = 8
let speechTailHeight: CGFloat = 10
let speechTailWidth: CGFloat = 16
let speechGap: CGFloat = 4
let speechMinHeight: CGFloat = 32
let speechCornerRadius: CGFloat = 10
let speechBubbleColor = NSColor(white: 0.15, alpha: 0.9)
let speechTextFont = NSFont.systemFont(ofSize: 13)

// 말풍선 높이 측정용 텍스트 필드 (실제 렌더링과 동일한 조건)
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

// 이전 인스턴스 종료
if let oldPidStr = try? String(contentsOfFile: pidFile, encoding: .utf8),
   let oldPid = Int32(oldPidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
   oldPid != getpid() {
    kill(oldPid, SIGTERM)
    usleep(200_000)
}
try? "\(getpid())".write(toFile: pidFile, atomically: true, encoding: .utf8)

// 초기 클루카이 표정 설정
let klukaiExpr = "\(homeDir)/.klukai_expression"
if !FileManager.default.fileExists(atPath: klukaiExpr) {
    try? "normal".write(toFile: klukaiExpr, atomically: true, encoding: .utf8)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

// 세로 회전 모니터(height > width)를 찾고, 없으면 메인 모니터 사용
func findTargetScreenFrame() -> NSRect {
    let target: NSScreen
    if let portrait = NSScreen.screens.first(where: { $0.frame.height > $0.frame.width }) {
        target = portrait
    } else {
        target = NSScreen.main ?? NSScreen.screens.first ?? {
            fatalError("No screen available")
        }()
    }
    return target.visibleFrame
}

// 윈도우 — 최대 4에이전트 수용 가능 크기로 생성 (가로 배치)
let maxWidth = (agentSize.width + agentSpacing) * CGFloat(agentNames.count)
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

// 갱신 버튼 (모니터 변경 시 위치 재계산)
class RefreshHelper: NSObject {
    @objc func refresh() {
        layoutAgents()
    }
}
let refreshHelper = RefreshHelper()

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
    btn.target = refreshHelper
    btn.action = #selector(RefreshHelper.refresh)
    btn.isHidden = true
    return btn
}()
var lastScreenFrame: NSRect = initialScreenFrame

// 에이전트별 뷰 관리
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

for name in agentNames {
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

    // placeholder: 이미지 없을 때 첫 글자 표시
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

    // 말풍선 배경
    let speechBubble = NSView(frame: .zero)
    speechBubble.wantsLayer = true
    speechBubble.layer?.cornerRadius = speechCornerRadius
    speechBubble.layer?.backgroundColor = speechBubbleColor.cgColor
    speechBubble.isHidden = true
    wrapper.addSubview(speechBubble)

    // 말풍선 텍스트
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

    // 말풍선 꼬리 (삼각형)
    let tailLayer = CAShapeLayer()
    tailLayer.fillColor = speechBubbleColor.cgColor
    tailLayer.isHidden = true
    wrapper.layer?.addSublayer(tailLayer)

    containerView.addSubview(wrapper)
    agentViews[name] = AgentView(
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

// 갱신 버튼을 에이전트 뷰 위에 배치 (z-order 최상위)
containerView.addSubview(refreshButton)

func expressionFilePath(for name: String) -> String {
    return "\(homeDir)/.\(name)_expression"
}

func speechFilePath(for name: String) -> String {
    return "\(homeDir)/.\(name)_speech"
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

        // 말풍선 배경 프레임
        agent.speechBubbleView.frame = NSRect(
            x: 0, y: bubbleY,
            width: agentSize.width, height: bubbleHeight
        )

        // 텍스트 프레임 (패딩 적용)
        agent.speechLabel.frame = NSRect(
            x: speechPaddingH, y: speechPaddingV,
            width: agentSize.width - speechPaddingH * 2,
            height: bubbleHeight - speechPaddingV * 2
        )

        // 꼬리 삼각형 (아래쪽 중앙, 말풍선과 이미지 사이)
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
    var visibleAgents: [String] = []
    for name in agentNames {
        if agentViews[name]?.isVisible == true {
            visibleAgents.append(name)
        }
    }

    // 총 너비 계산 (가로 배치)
    let totalWidth = CGFloat(visibleAgents.count) * agentSize.width +
        CGFloat(max(0, visibleAgents.count - 1)) * agentSpacing

    // 최대 높이 계산 (가장 높은 에이전트 기준, 말풍선 포함)
    var maxHeight: CGFloat = agentSize.height
    for name in visibleAgents {
        maxHeight = max(maxHeight, agentTotalHeight(for: name))
    }

    // 윈도우 크기 & 위치 재조정 (매번 현재 모니터 기준으로 계산)
    let currentScreenFrame = findTargetScreenFrame()
    let newWindowSize = NSSize(width: max(agentSize.width, totalWidth), height: maxHeight)
    let newOrigin = NSPoint(
        x: currentScreenFrame.minX + 20,
        y: currentScreenFrame.maxY - newWindowSize.height - 20
    )
    window.setFrame(NSRect(origin: newOrigin, size: newWindowSize), display: false)
    containerView.frame = NSRect(origin: .zero, size: newWindowSize)

    // 갱신 버튼 위치 (우하단)
    if !visibleAgents.isEmpty {
        refreshButton.frame.origin = NSPoint(
            x: totalWidth - refreshButton.frame.width - 2,
            y: 2
        )
        refreshButton.isHidden = false
    } else {
        refreshButton.isHidden = true
    }

    // 왼쪽에서 오른쪽으로 배치 (이미지 하단 정렬)
    var xOffset: CGFloat = 0
    for name in visibleAgents {
        let height = agentTotalHeight(for: name)

        agentViews[name]?.wrapperView.frame = NSRect(
            x: xOffset, y: 0,
            width: agentSize.width, height: height
        )

        // 이미지/플레이스홀더는 wrapper 하단 (y=0)
        agentViews[name]?.imageView.frame = NSRect(origin: .zero, size: agentSize)
        agentViews[name]?.placeholderView.frame = NSRect(origin: .zero, size: agentSize)

        // 말풍선 레이아웃
        layoutSpeechBubble(for: name)

        xOffset += agentSize.width + agentSpacing
    }
}

func updateAgents() {
    var needsLayout = false

    // 모니터 변경 자동 감지
    let currentScreen = findTargetScreenFrame()
    if currentScreen != lastScreenFrame {
        lastScreenFrame = currentScreen
        needsLayout = true
    }

    for name in agentNames {
        let exprFile = expressionFilePath(for: name)
        let fileExists = FileManager.default.fileExists(atPath: exprFile)

        guard var agent = agentViews[name] else { continue }

        if fileExists && !agent.isVisible {
            // 에이전트 활성화
            agent.isVisible = true
            agent.wrapperView.isHidden = false
            needsLayout = true
        } else if !fileExists && agent.isVisible {
            // 에이전트 비활성화
            agent.isVisible = false
            agent.wrapperView.isHidden = true
            agent.currentExpression = ""
            agent.currentSpeech = ""
            agent.speechBubbleView.isHidden = true
            agent.speechTailLayer.isHidden = true
            agentViews[name] = agent
            needsLayout = true
            continue
        }

        guard fileExists else {
            agentViews[name] = agent
            continue
        }

        // 표정 업데이트
        let expression = (try? String(contentsOfFile: exprFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "normal"

        if expression != agent.currentExpression {
            agent.currentExpression = expression
            let imagePath = "\(baseDir)/\(name)/\(expression).png"

            if let image = NSImage(contentsOfFile: imagePath) {
                agent.imageView.image = image
                agent.imageView.isHidden = false
                agent.placeholderView.isHidden = true
            } else {
                agent.imageView.isHidden = true
                agent.placeholderView.isHidden = false
            }
        }

        // 말풍선 업데이트
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

// 0.3초마다 파일 변경 확인
Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
    updateAgents()
}

signal(SIGTERM) { _ in
    try? FileManager.default.removeItem(atPath: pidFile)
    exit(0)
}

app.run()
