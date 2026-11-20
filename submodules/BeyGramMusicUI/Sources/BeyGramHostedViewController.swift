import UIKit
import Display

/// Puts a plain UIKit screen (for example BG Mix or BG Wave) inside a Telegram navigation controller.
///
/// Telegram pushes only `ViewController`s, and its own navigation bar sits above the content.
/// The hosted screen is added as a child view below that bar. Its own UIKit navigation items are not shown.
public final class BeyGramHostedViewController: ViewController {
    private let hosted: UIViewController
    private let navigationBarHeight: CGFloat = 44.0

    public init(title: String, hosted: UIViewController) {
        self.hosted = hosted
        super.init(navigationBarPresentationData: nil)
        self.title = title
    }

    required public init(coder aDecoder: NSCoder) {
        preconditionFailure("init(coder:) is not supported")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        self.addChild(self.hosted)
        self.view.addSubview(self.hosted.view)
        self.hosted.didMove(toParent: self)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        let top = (layout.statusBarHeight ?? 0.0) + self.navigationBarHeight
        self.hosted.view.frame = CGRect(x: 0.0, y: top, width: layout.size.width, height: max(0.0, layout.size.height - top))
    }
}
