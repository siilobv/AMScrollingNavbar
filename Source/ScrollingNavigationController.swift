import UIKit

/**
 Scrolling Navigation Bar delegate protocol
 */
@objc public protocol ScrollingNavigationControllerDelegate: NSObjectProtocol {
  /// Called when the state of the navigation bar changes
  ///
  /// - Parameters:
  ///   - controller: the ScrollingNavigationController
  ///   - state: the new state
  @objc optional func scrollingNavigationController(_ controller: ScrollingNavigationController, didChangeState state: NavigationBarState)
  
  /// Called when the state of the navigation bar is about to change
  ///
  /// - Parameters:
  ///   - controller: the ScrollingNavigationController
  ///   - state: the new state
  @objc optional func scrollingNavigationController(_ controller: ScrollingNavigationController, willChangeState state: NavigationBarState)
  /// Called when the navigation bar position changed
  ///
  /// - Parameters:
  ///   - controller: the ScrollingNavigationController
  ///   - offset: changes amount
  ///   - state: the new state
  @objc optional func scrollingNavigationController(_ controller: ScrollingNavigationController,
                                                    didUpdateOffset offset: CGFloat,
                                                    forStateChange state: NavigationBarState)
}

/**
 The state of the navigation bar
 
 - collapsed: the navigation bar is fully collapsed
 - expanded: the navigation bar is fully visible
 - scrolling: the navigation bar is transitioning to either `Collapsed` or `Scrolling`
 */
@objc public enum NavigationBarState: Int {
  case collapsed, expanded, scrolling
}

/**
 The direction of scrolling that the navigation bar should be collapsed.
 The raw value determines the sign of content offset depending of collapse direction.
 
 - scrollUp: scrolling up direction
 - scrollDown: scrolling down direction
 */
@objc public enum NavigationBarCollapseDirection: Int {
  case scrollUp = -1
  case scrollDown = 1
}

/**
 The direction of scrolling that a follower should follow when the navbar is collapsing.
 The raw value determines the sign of content offset depending of collapse direction.
 
 - scrollUp: scrolling up direction
 - scrollDown: scrolling down direction
 */
@objc public enum NavigationBarFollowerCollapseDirection: Int {
  case scrollUp = -1
  case scrollDown = 1
}

/**
 The style used to collapse or expand the navbar.
 
 - interactive: the navbar follows alongside the current offset of the scrollable view
 - noninteractive: the navbar animates between collapsed and expanded states similar to the "Google" iOS app.
     This style ignores the `delay` property.
 */
@objc public enum AnimationStyle: Int {
  case interactive, nonInteractive
}

/**
 Wraps a view that follows the navigation bar, providing the direction that the view should follow
 
 - changeAlphaWhileCollapsing: update the follower's view alpha while the navigation bar collapses.
 */
@objcMembers
open class NavigationBarFollower: NSObject {
  public weak var view: UIView?
  public var direction = NavigationBarFollowerCollapseDirection.scrollUp
  public var changeAlphaWhileCollapsing = false
  
  public init(view: UIView, direction: NavigationBarFollowerCollapseDirection = .scrollUp,
              changeAlphaWhileCollapsing: Bool = false) {
    self.view = view
    self.direction = direction
    self.changeAlphaWhileCollapsing = changeAlphaWhileCollapsing
  }
}

/**
 A custom `UINavigationController` that enables the scrolling of the navigation bar alongside the
 scrolling of an observed content view
 */
@objcMembers
open class ScrollingNavigationController: UINavigationController, UIGestureRecognizerDelegate {
  
  /**
   Returns the `NavigationBarState` of the navigation bar
   */
  open var state: NavigationBarState {
    get {
      if navigationBar.frame.origin.y <= -navbarFullHeight {
        return .collapsed
      } else if navigationBar.frame.origin.y >= statusBarHeight {
        return .expanded
      } else {
        return .scrolling
      }
    }
  }
  
  /**
   Determines whether the navbar should scroll when the content inside the scrollview fits
   the view's size. Defaults to `false`
   */
  open var shouldScrollWhenContentFits = false
  
  /**
   Determines if the navbar should expand once the application becomes active after entering background
   Defaults to `true`
   */
  open var expandOnActive = true
  
  /**
   Determines if the navbar should expand once the application becomes visible after entering background
   Defaults to `true`
   */
  open var expandOnVisible = true
  /**
   Determines if the navbar scrolling is enabled.
   Defaults to `true`
   */
  open var scrollingEnabled = true
  
  /**
   The delegate for the scrolling navbar controller
   */
  open weak var scrollingNavbarDelegate: ScrollingNavigationControllerDelegate?
  
  /**
   An array of `NavigationBarFollower`s that will follow the navbar
   */
  open var followers: [NavigationBarFollower] = []
  
  /**
   Determines if the top content inset should be updated with the navbar's delta movement. This should be enabled when dealing with table views with floating headers.
   It can however cause issues in certain configurations. If the issues arise, set this to false
   
   Defaults to `true`
   */
  open var shouldUpdateContentInset = true
  
  /**
   Determines if the navigation bar should scroll while following a UITableView that is in edit mode.
   
   Defaults to `false`
   */
  open var shouldScrollWhenTableViewIsEditing = false
  
  /**
   Detemines how the navbar animates between different states.
   
   Defaults to `interactive`
   */
  open var animationStyle: AnimationStyle = .interactive

  /// Holds the percentage of the navigation bar that is hidde. At 0 the navigation bar is fully visible, at 1 fully hidden. CGFloat with values from 0 to 1
  open var percentage: CGFloat {
    get {
      return (navigationBar.frame.origin.y - statusBarHeight) / (-navbarFullHeight - statusBarHeight)
    }
  }
  
  /// the additional distance that the navigation bar can move up after reaching the top of the screen. Defaults to 0
  open var additionalOffset: CGFloat = 0
 
  /// the additional scroll distance that scroll to top function should go to.  Defaults to 0
  open var additionalScrollToTopOffset: CGFloat = 0
  
  /// Stores some metadata of a UITabBar if one is passed in the followers array
  internal struct TabBarMock {
    var isTranslucent: Bool = false
    var origin: CGPoint = .zero
    
    init(origin: CGPoint, translucent: Bool) {
      self.origin = origin
      self.isTranslucent = translucent
    }
  }
  
  open fileprivate(set) var gestureRecognizer: UIPanGestureRecognizer?
  fileprivate var sourceTabBar: TabBarMock?
  fileprivate var previousOrientation: UIDeviceOrientation = UIDevice.current.orientation
  fileprivate var savedNavBarTintColor: UIColor?
  var delayDistance: CGFloat = 0
  var maxDelay: CGFloat = 0
  var scrollableView: UIView?
  var lastContentOffset = CGFloat(0.0)
  var scrollSpeedFactor: CGFloat = 1
  var collapseDirectionFactor: CGFloat = 1 // Used to determine the sign of content offset depending of collapse direction
  var previousState: NavigationBarState = .expanded // Used to mark the state before the app goes in background
  var scrollSearchBar: Bool = false
  
  public var isTopViewControllerExtendedUnderNavigationBar: Bool {
    guard let topViewController = topViewController, topViewController.edgesForExtendedLayout.contains(.top) else {
      return false
    }
    
    return topViewController.extendedLayoutIncludesOpaqueBars || navigationBar.isTranslucent
  }
  
  /**
   Start scrolling
   
   Enables the scrolling by observing a view
   
   - parameter scrollableView: The view with the scrolling content that will be observed
   - parameter delay: The delay expressed in points that determines the scrolling resistance. Defaults to `0`
   - parameter scrollSpeedFactor : This factor determines the speed of the scrolling content toward the navigation bar animation
   - parameter collapseDirection : The direction of scrolling that the navigation bar should be collapsed
   - parameter additionalOffset : The additional distance that the navigation bar can move up after reaching the top of the screen. Defaults to 0
   - parameter scrollSearchBar : Determines whether or not the navigation bar should scroll when the search bar is visible. Defaults to false
   - parameter followers: An array of `NavigationBarFollower`s that will follow the navbar. The wrapper holds the direction that the view will follow
   */
  open func followScrollView(_ scrollableView: UIView, delay: Double = 0, scrollSpeedFactor: Double = 1, collapseDirection: NavigationBarCollapseDirection = .scrollDown, additionalOffset: CGFloat = 0, scrollSearchBar: Bool = false, animationStyle: AnimationStyle = .interactive, followers: [NavigationBarFollower] = []) {
    savedNavBarTintColor = navigationBar.tintColor
    guard self.scrollableView == nil else {
      // Restore previous state. UIKit restores the navbar to its full height on view changes (e.g. during a modal presentation), so we need to restore the status once UIKit is done
      switch previousState {
      case .collapsed:
        hideNavbar(animated: false)
      case .expanded:
        showNavbar(animated: false)
      default: break
      }
      return
    }
    self.scrollableView = scrollableView
    
    gestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(ScrollingNavigationController.handlePan(_:)))
    gestureRecognizer?.maximumNumberOfTouches = 1
    gestureRecognizer?.delegate = self
    gestureRecognizer?.cancelsTouchesInView = false
    scrollableView.addGestureRecognizer(gestureRecognizer!)
    
    previousOrientation = UIDevice.current.orientation
    NotificationCenter.default.addObserver(self, selector: #selector(ScrollingNavigationController.willResignActive(_:)), name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(ScrollingNavigationController.didBecomeActive(_:)), name: UIApplication.didBecomeActiveNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(ScrollingNavigationController.didRotate(_:)), name: UIDevice.orientationDidChangeNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(ScrollingNavigationController.windowDidBecomeVisible(_:)), name: UIWindow.didBecomeVisibleNotification, object: nil)
    
    maxDelay = CGFloat(delay)
    delayDistance = CGFloat(delay)
    scrollingEnabled = true
    self.animationStyle = animationStyle
    self.additionalOffset = additionalOffset
    self.scrollSearchBar = scrollSearchBar
    
    // Save TabBar state (the state is changed during the transition and restored on compeltion)
    if let tab = followers.map({ $0.view }).first(where: { $0 is UITabBar }) as? UITabBar {
      self.sourceTabBar = TabBarMock(origin: CGPoint(x: tab.frame.origin.x, y: CGFloat(round(tab.frame.origin.y))), translucent: tab.isTranslucent)
    }
    self.followers = followers
    self.scrollSpeedFactor = CGFloat(scrollSpeedFactor)
    self.collapseDirectionFactor = CGFloat(collapseDirection.rawValue)
  }
  
  /**
   Hide the navigation bar
   
   - parameter animated: If true the scrolling is animated. Defaults to `true`
   - parameter duration: Optional animation duration. Defaults to 0.1
   */
  open func hideNavbar(animated: Bool = true, duration: TimeInterval = 0.1) {
    guard let _ = self.scrollableView, let visibleViewController = self.visibleViewController else { return }
    
    guard state == .expanded else {
      updateNavbarAlpha()
      return
    }
    
    gestureRecognizer?.isEnabled = false
    let animations = {
      self.scrollWithDelta(self.fullNavbarHeight, ignoreDelay: true)
      visibleViewController.view.setNeedsLayout()
      if !self.isTopViewControllerExtendedUnderNavigationBar {
        let currentOffset = self.contentOffset
        self.scrollView()?.contentOffset = CGPoint(x: currentOffset.x, y: currentOffset.y + self.navbarHeight)
      }
    }
    
    if animated {
      UIView.animate(withDuration: duration, animations: animations) { _ in
        self.gestureRecognizer?.isEnabled = true
      }
    } else {
      animations()
      gestureRecognizer?.isEnabled = true
    }
  }
  
  /**
   Show the navigation bar
   
   - parameter animated: If true the scrolling is animated. Defaults to `true`
   - parameter duration: Optional animation duration. Defaults to 0.1
   - parameter scrollToTop: Optional boolean to scroll also the scroll view to the top. Defaults to false
   - parameter completion: Optional completion block called when the navbar is shown
   */
  open func showNavbar(animated: Bool = true, duration: TimeInterval = 0.1, scrollToTop: Bool = false, completion showNavCompletion: (() -> Void)? = nil) {
    guard let _ = self.scrollableView, let visibleViewController = self.visibleViewController else { return }
    
    guard state == .collapsed else {
      self.updateNavbarAlpha()
      return
    }
        
    gestureRecognizer?.isEnabled = false
    
    let completion = {
      if scrollToTop {
        let followersFinalHeight = self.followersHeight + self.additionalScrollToTopOffset
        if self.isTopViewControllerExtendedUnderNavigationBar {
          self.scrollView()?.setContentOffset(CGPoint(x: 0, y: -self.fullNavbarHeight - followersFinalHeight), animated: true)
        } else {
          self.scrollView()?.setContentOffset(CGPoint(x: 0, y: -followersFinalHeight), animated: true)
        }
      }
      showNavCompletion?()
    }
    
    let animations = {
      self.lastContentOffset = 0
      self.scrollWithDelta(-self.fullNavbarHeight, ignoreDelay: true)
      visibleViewController.view.setNeedsLayout()
      if !self.isTopViewControllerExtendedUnderNavigationBar {
        let currentOffset = self.contentOffset
        self.scrollView()?.contentOffset = CGPoint(x: currentOffset.x, y: currentOffset.y - self.navbarHeight)
      }
    }
    if animated {
      UIView.animate(withDuration: duration, animations: animations) { _ in
        self.gestureRecognizer?.isEnabled = true
        completion()
      }
    } else {
      animations()
      completion()
      gestureRecognizer?.isEnabled = true
    }
  }
  
  /**
   Stop observing the view and reset the navigation bar
   
   - parameter showingNavbar: If true the navbar is show, otherwise it remains in its current state. Defaults to `true`
   */
  open func stopFollowingScrollView(showingNavbar: Bool = true) {
    if showingNavbar {
      showNavbar(animated: true)
    }
    if let gesture = gestureRecognizer {
      scrollableView?.removeGestureRecognizer(gesture)
    }
    scrollableView = .none
    gestureRecognizer = .none
    scrollingNavbarDelegate = .none
    scrollingEnabled = false
    
    let center = NotificationCenter.default
    center.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
    center.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
  }
  
  /**
  The app needs to call navBarTintUpdated() after setting a new value for navigationBar.tintColor (or the new tintColor value will not take effect)
  */
  open func navBarTintUpdated() {
    savedNavBarTintColor = navigationBar.tintColor
  }
  
  // MARK: - Gesture recognizer
  
  func handlePan(_ gesture: UIPanGestureRecognizer) {
    if let tableView = scrollableView as? UITableView, !shouldScrollWhenTableViewIsEditing && tableView.isEditing {
      return
    }
    if let superview = scrollableView?.superview {
      let translation = gesture.translation(in: superview)
      let delta = (lastContentOffset - translation.y) / scrollSpeedFactor
      
      if !scrollSearchBar, !checkSearchController(delta) {
        lastContentOffset = translation.y
        return
      }
      
      if gesture.state != .failed {
        lastContentOffset = translation.y
        if shouldScrollWithDelta(delta) {
          switch animationStyle {
          case .interactive:
            scrollWithDelta(delta)
          case .nonInteractive:
            scrollWithGestureRecognizer(gesture)
          }
        }
      }
    }
    
    if gesture.state == .ended || gesture.state == .cancelled || gesture.state == .failed {
      if case .interactive = animationStyle {
        checkForPartialScroll()
      }
      lastContentOffset = 0
    }
  }
  
  // MARK: - Fullscreen handling
  
  func windowDidBecomeVisible(_ notification: Notification) {
    if expandOnVisible {
      showNavbar()
    } else {
      if previousState == .collapsed {
        hideNavbar(animated: false)
      }
    }
  }
  
  // MARK: - Rotation handler
  
  func didRotate(_ notification: Notification) {
    let newOrientation = UIDevice.current.orientation
    // Show the navbar if the orantation is the same (the app just got back from background) or if there is a switch between portrait and landscape (and vice versa)
    if (previousOrientation == newOrientation) || (previousOrientation.isPortrait && newOrientation.isLandscape) || (previousOrientation.isLandscape && newOrientation.isPortrait) {
      showNavbar()
    }
    previousOrientation = newOrientation
  }
  
  /**
   UIContentContainer protocol method.
   Will show the navigation bar upon rotation or changes in the trait sizes.
   */
  open override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
    super.viewWillTransition(to: size, with: coordinator)
    showNavbar()
  }
  
  // MARK: - Notification handler
  
  func didBecomeActive(_ notification: Notification) {
    if expandOnActive {
      showNavbar(animated: false)
    } else {
      if previousState == .collapsed {
        hideNavbar(animated: false)
      }
    }
  }
  
  func willResignActive(_ notification: Notification) {
    previousState = state
  }
  
  /// Handles when the status bar changes
  func willChangeStatusBar() {
    showNavbar(animated: true)
  }
  
  // MARK: - Scrolling functions
  
  private func scrollWithGestureRecognizer(_ gestureRecognizer: UIGestureRecognizer) {
    guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer, let scrollView = self.scrollView() else { return }
    
    let velocity = panGesture.velocity(in: scrollView).y
    
    guard velocity != 0 else { return }
        
    let isCloseToTop = contentOffset.y <= navbarFullHeight
    
    // (Roughly) the velocity necessary to cause decelaration in a scrollview with default deceleration rate
    let minimumFlickScrollVelocity: CGFloat = 200
        
    let targetState: NavigationBarState
    if velocity < 0 {
      // Hide navbar when user scrolls downwards
      targetState = .collapsed
    } else if isCloseToTop {
      // Show navbar if user is near top of scrollable view and is scrolling upward
      targetState = .expanded
    } else if velocity > minimumFlickScrollVelocity, panGesture.state == .ended, scrollView.isDecelerating {
      // Show navbar if user releases scrollable view with enough flick to cause scrollable view to decelerate
      targetState = .expanded
    } else {
      return
    }
    
    guard targetState != state else { return }
    
    let scrollDelta = scrollDeltaForNavbar(expanded: targetState == .expanded)
    let distance = scrollDelta / (navigationBar.frame.height / 2)
    let duration = TimeInterval(abs(distance * 0.1))

    UIView.animate(withDuration: duration, delay: 0, options: .curveEaseInOut, animations: {
        self.commitScrollWithDelta(scrollDelta)
    })
  }
  
  private func shouldScrollWithDelta(_ delta: CGFloat) -> Bool {
    let scrollDelta = delta
    // Do not hide too early
    if contentOffset.y < ((isTopViewControllerExtendedUnderNavigationBar ? -fullNavbarHeight : -followersHeight) + scrollDelta) {
      return false
    }
    // Check for rubberbanding
    if scrollDelta < 0 {
      if let scrollableView = scrollableView , contentOffset.y + scrollableView.frame.size.height > contentSize.height && scrollableView.frame.size.height < contentSize.height {
        // Only if the content is big enough
        return false
      }
    }
    return true
  }
  
  private func scrollWithDelta(_ delta: CGFloat, ignoreDelay: Bool = false) {
    var scrollDelta = delta
    let frame = navigationBar.frame
    
    // View scrolling up, hide the navbar
    if scrollDelta > 0 {
      // Update the delay
      if !ignoreDelay {
        delayDistance -= scrollDelta
        
        // Skip if the delay is not over yet
        if delayDistance > 0 {
          return
        }
      }
      
      // No need to scroll if the content fits
      if !shouldScrollWhenContentFits && state != .collapsed &&
        (scrollableView?.frame.size.height)! >= contentSize.height {
        return
      }
      
      // Compute the bar position
      if frame.origin.y - scrollDelta < -navbarFullHeight {
        scrollDelta = scrollDeltaForNavbar(expanded: false)
      }
      
      // Detect when the bar is completely collapsed
      if frame.origin.y <= -navbarFullHeight {
        delayDistance = maxDelay
      }
    }
    
    if scrollDelta < 0 {
      // Update the delay
      if !ignoreDelay {
        delayDistance += scrollDelta
        
        // Skip if the delay is not over yet
        if delayDistance > 0 && maxDelay < contentOffset.y {
          return
        }
      }
      
      // Compute the bar position
      if frame.origin.y - scrollDelta > statusBarHeight {
        scrollDelta = scrollDeltaForNavbar(expanded: true)
      }
      
      // Detect when the bar is completely expanded
      if frame.origin.y >= statusBarHeight {
        delayDistance = maxDelay
      }
    }
    
    commitScrollWithDelta(scrollDelta)
  }
  
  private func scrollDeltaForNavbar(expanded: Bool) -> CGFloat {
    let navbarYOrigin = navigationBar.frame.minY
    return expanded ? navbarYOrigin - statusBarHeight : navbarYOrigin + navbarFullHeight
  }
  
  private func commitScrollWithDelta(_ scrollDelta: CGFloat) {
    updateSizing(scrollDelta)
    updateNavbarAlpha()
    restoreContentOffset(scrollDelta)
    updateFollowers()
    updateContentInset(scrollDelta)
    
    let newState = state
    if newState != previousState {
      scrollingNavbarDelegate?.scrollingNavigationController?(self, willChangeState: newState)
      navigationBar.isUserInteractionEnabled = (newState == .expanded)
    }
    previousState = newState
  }
  
  /// Adjust the top inset (useful when a table view has floating headers, see issue #219
  private func updateContentInset(_ delta: CGFloat) {
    if self.shouldUpdateContentInset, let contentInset = scrollView()?.contentInset, let scrollInset = scrollView()?.scrollIndicatorInsets {
      
      scrollView()?.contentInset = UIEdgeInsets(top: contentInset.top - delta, left: contentInset.left, bottom: contentInset.bottom, right: contentInset.right)
      scrollView()?.scrollIndicatorInsets = UIEdgeInsets(top: scrollInset.top - delta, left: scrollInset.left, bottom: scrollInset.bottom, right: scrollInset.right)
      scrollingNavbarDelegate?.scrollingNavigationController?(self,
                                                              didUpdateOffset: contentInset.top - delta,
                                                              forStateChange: state)
    }
  }
  
  private func updateFollowers() {
    followers.forEach { follower in
      defer {
        follower.view?.layoutIfNeeded()
      }
      guard let tabBar = follower.view as? UITabBar else {
        let height = follower.view?.frame.height ?? 0
        var safeArea: CGFloat = 0
        if #available(iOS 11.0, *) {
          // Account for the safe area for footers and toolbars at the bottom of the screen
          safeArea = (follower.direction == .scrollDown) ? (topViewController?.view.safeAreaInsets.bottom ?? 0) : 0
        }
        switch follower.direction {
        case .scrollDown:
          follower.view?.transform = CGAffineTransform(translationX: 0, y: percentage * (height + safeArea))
        case .scrollUp:
          follower.view?.transform = CGAffineTransform(translationX: 0, y: -(statusBarHeight - navigationBar.frame.origin.y))
        }
        
        return
      }
      tabBar.isTranslucent = true
      tabBar.transform = CGAffineTransform(translationX: 0, y: percentage * tabBar.frame.height)
      
      // Set the bar to its original state if it's in its original position
      if let originalTabBar = sourceTabBar, originalTabBar.origin.y == round(tabBar.frame.origin.y) {
        tabBar.isTranslucent = originalTabBar.isTranslucent
      }
    }
  }
  
  private func updateSizing(_ delta: CGFloat) {
    guard let topViewController = self.topViewController else { return }
    
    var frame = navigationBar.frame
    
    // Move the navigation bar
    frame.origin = CGPoint(x: frame.origin.x, y: frame.origin.y - delta)
    navigationBar.frame = frame
    
    // Resize the view if it does not extend under navigation bar
    if !isTopViewControllerExtendedUnderNavigationBar {
      let navBarY = frame.origin.y + frame.size.height
      frame = topViewController.view.frame
      frame.origin = CGPoint(x: frame.origin.x, y: navBarY)
      frame.size = CGSize(width: frame.size.width, height: view.frame.size.height - navBarY - tabBarOffset)
      topViewController.view.frame = frame
      topViewController.view.layoutIfNeeded()
    }
  }
  
  private func restoreContentOffset(_ delta: CGFloat) {
    if isTopViewControllerExtendedUnderNavigationBar || delta == 0 {
      return
    }
    
    // Hold the scroll steady until the navbar appears/disappears
    if let scrollView = scrollView() {
      scrollView.setContentOffset(CGPoint(x: contentOffset.x, y: contentOffset.y - delta), animated: false)
    }
  }
  
  private func checkForPartialScroll() {
    let frame = navigationBar.frame
    var duration = TimeInterval(0)
    var delta = CGFloat(0.0) // The amount that needs to be traveled
    let navBarHeightWithOffset = frame.size.height + additionalOffset
    let threshold = statusBarHeight - (navBarHeightWithOffset / 2)
    
    if navigationBar.frame.origin.y >= threshold {
      // Scroll back down
      delta = frame.origin.y - statusBarHeight
    } else {
      // Scroll up
      delta = frame.origin.y + navbarFullHeight
    }

    let distance = delta / (navBarHeightWithOffset / 2)
    duration = TimeInterval(abs(distance * 0.2))
    scrollingNavbarDelegate?.scrollingNavigationController?(self, willChangeState: state)
    
    delayDistance = maxDelay
    
    UIView.animate(withDuration: duration, delay: 0, options: UIView.AnimationOptions.beginFromCurrentState, animations: {
      self.updateSizing(delta)
      self.updateFollowers()
      self.updateNavbarAlpha()
      self.updateContentInset(delta)
      self.scrollingNavbarDelegate?.scrollingNavigationController?(self, willChangeState: self.state)
    }, completion: { _ in
      self.navigationBar.isUserInteractionEnabled = (self.state == .expanded)
      self.scrollingNavbarDelegate?.scrollingNavigationController?(self, didChangeState: self.state)
    })
  }
  
  private func updateNavbarAlpha() {
    guard let navigationItem = topViewController?.navigationItem else { return }
    
    // Change the alpha channel of every item on the navbr
    let alpha = 1 - percentage
    
    // Hide all the possible tgit push origin masteritles (See #398)
    if #available(iOS 13.0, *) {
      if let color = navigationBar.scrollEdgeAppearance?.titleTextAttributes [NSAttributedString.Key.foregroundColor] as? UIColor {
        navigationBar.scrollEdgeAppearance?.titleTextAttributes [NSAttributedString.Key.foregroundColor] = color.withAlphaComponent(alpha)
      }

      if let color = navigationBar.standardAppearance.titleTextAttributes [NSAttributedString.Key.foregroundColor] as? UIColor {
        navigationBar.standardAppearance.titleTextAttributes [NSAttributedString.Key.foregroundColor] = color.withAlphaComponent(alpha)
      }
      
      if let color = navigationBar.compactAppearance?.titleTextAttributes [NSAttributedString.Key.foregroundColor] as? UIColor {
        navigationBar.compactAppearance?.titleTextAttributes [NSAttributedString.Key.foregroundColor] = color.withAlphaComponent(alpha)
      }
    }
    navigationItem.titleView?.alpha = alpha
    navigationBar.tintColor = savedNavBarTintColor?.withAlphaComponent(alpha)
    navigationItem.leftBarButtonItem?.tintColor = navigationItem.leftBarButtonItem?.tintColor?.withAlphaComponent(alpha)
    navigationItem.rightBarButtonItem?.tintColor = navigationItem.rightBarButtonItem?.tintColor?.withAlphaComponent(alpha)
    navigationItem.leftBarButtonItems?.forEach { $0.tintColor = $0.tintColor?.withAlphaComponent(alpha) }
    navigationItem.rightBarButtonItems?.forEach { $0.tintColor = $0.tintColor?.withAlphaComponent(alpha) }
    if #available(iOS 11.0, *) {
      navigationItem.searchController?.searchBar.alpha = alpha
    }
    if let titleColor = navigationBar.titleTextAttributes?[NSAttributedString.Key.foregroundColor] as? UIColor {
      navigationBar.titleTextAttributes?[NSAttributedString.Key.foregroundColor] = titleColor.withAlphaComponent(alpha)
    } else {
      let blackAlpha = UIColor.black.withAlphaComponent(alpha)
      if navigationBar.titleTextAttributes == nil {
        navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: blackAlpha]
      } else {
        navigationBar.titleTextAttributes?[NSAttributedString.Key.foregroundColor] = blackAlpha
      }
    }
    
    // Hide all possible button items and navigation items
    func shouldHideView(_ view: UIView) -> Bool {
      let className = view.classForCoder.description().replacingOccurrences(of: "_", with: "")
      var viewNames = ["UINavigationButton", "UINavigationItemView", "UIImageView", "UISegmentedControl"]
      if #available(iOS 11.0, *) {
        viewNames.append(navigationBar.prefersLargeTitles ? "UINavigationBarLargeTitleView" : "UINavigationBarContentView")
      } else {
        viewNames.append("UINavigationBarContentView")
      }
      return viewNames.contains(className)
    }
    
    func setAlphaOfSubviews(view: UIView, alpha: CGFloat) {
      if let label = view as? UILabel {
        label.textColor = label.textColor == .clear ? .clear : label.textColor.withAlphaComponent(alpha)
      } else if let label = view as? UITextField {
        label.textColor = label.textColor == .clear ? .clear : label.textColor?.withAlphaComponent(alpha)
      } else if view.classForCoder == NSClassFromString("_UINavigationBarContentView") {
        // do nothing
      } else {
        view.alpha = alpha
      }
      view.subviews.forEach { setAlphaOfSubviews(view: $0, alpha: alpha) }
    }
    
    navigationBar.subviews
      .filter(shouldHideView)
      .forEach { setAlphaOfSubviews(view: $0, alpha: alpha) }
    
    //Update followers alpha
    followers.filter { $0.changeAlphaWhileCollapsing }.forEach { $0.view?.alpha = alpha }
    
    // Hide the left items
    navigationItem.leftBarButtonItem?.customView?.alpha = alpha
    navigationItem.leftBarButtonItems?.forEach { $0.customView?.alpha = alpha }
    
    // Hide the right items
    navigationItem.rightBarButtonItem?.customView?.alpha = alpha
    navigationItem.rightBarButtonItems?.forEach { $0.customView?.alpha = alpha }
  }
  
  private func checkSearchController(_ delta: CGFloat) -> Bool {
    if #available(iOS 11.0, *) {
      if let searchController = topViewController?.navigationItem.searchController, delta > 0 {
        if searchController.searchBar.frame.height != 0 {
          return false
        }
      }
    }
    return true
  }
  
  // MARK: - UIGestureRecognizerDelegate
  
  /**
   UIGestureRecognizerDelegate function. Begin scrolling only if the direction is vertical (prevents conflicts with horizontal scroll views)
   */
  open func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    // Default system behavior returns `true`
    guard gestureRecognizer == self.gestureRecognizer, let gestureRecognizer = gestureRecognizer as? UIPanGestureRecognizer else { return true }
    let velocity = gestureRecognizer.velocity(in: gestureRecognizer.view)
    return abs(velocity.y) > abs(velocity.x)
  }
  
  /**
   UIGestureRecognizerDelegate function. Enables the scrolling of both the content and the navigation bar
   */
  open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    // Default system behavior returns `false`
    guard [gestureRecognizer, otherGestureRecognizer].contains(self.gestureRecognizer) else { return false }
    return true
  }
  
  /**
   UIGestureRecognizerDelegate function. Only scrolls the navigation bar with the content when `scrollingEnabled` is true
   */
  open func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    // Default system behavior returns `true`
    guard gestureRecognizer == self.gestureRecognizer else { return true }
    return scrollingEnabled
  }
  
  deinit {
    NotificationCenter.default.removeObserver(self)
  }

}
