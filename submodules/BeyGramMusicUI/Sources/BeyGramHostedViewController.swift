import UIKit
import Display
import SwiftSignalKit
import TelegramPresentationData
import AccountContext

/// Hosts a UIKit `UIViewController` inside a Telegram `ViewController` with native
/// navigation bar layout, theme updates, and safe area handling.
public final class BeyGramHostedViewController: ViewController {
    private let hosted: UIViewController
    private let context: AccountContext?
    private var presentationData: PresentationData
    private var presentationDataDisposable: Disposable?

    public init(context: AccountContext, title: String, hosted: UIViewController) {
        self.context = context
        self.hosted = hosted
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = title
        self.statusBar.statusBarStyle = self.presentationData.theme.rootController.statusBarStyle.style
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            guard let self else { return }
            self.presentationData = presentationData
            self.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
            self.navigationBar?.updatePresentationData(NavigationBarPresentationData(presentationData: presentationData), transition: .immediate)
            self.view.backgroundColor = presentationData.theme.list.plainBackgroundColor
        })
    }

    public init(title: String, hosted: UIViewController) {
        self.context = nil
        self.hosted = hosted
        self.presentationData = PresentationData(
            strings: defaultPresentationStrings,
            theme: defaultPresentationTheme,
            autoNightModeTriggered: false,
            chatWallpaper: defaultPresentationTheme.chat.defaultWallpaper,
            chatFontSize: .regular,
            chatBubbleCorners: PresentationChatBubbleCorners(mainRadius: 16.0, auxiliaryRadius: 8.0, mergeBubbleCorners: true),
            listsFontSize: .regular,
            dateTimeFormat: PresentationDateTimeFormat(),
            nameDisplayOrder: .firstLast,
            nameSortOrder: .firstLast,
            reduceMotion: false,
            largeEmoji: false
        )
        super.init(navigationBarPresentationData: NavigationBarPresentationData(presentationData: self.presentationData))
        self.title = title
    }

    required public init(coder aDecoder: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = self.presentationData.theme.list.plainBackgroundColor
        self.addChild(self.hosted)
        self.view.addSubview(self.hosted.view)
        self.hosted.didMove(toParent: self)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = self.navigationLayout(layout: layout).navigationFrame.maxY
        let targetFrame = CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top))
        transition.updateFrame(view: self.hosted.view, frame: targetFrame)
    }
}
