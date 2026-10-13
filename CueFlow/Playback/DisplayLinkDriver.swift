import AppKit
import CueFlowCore
import QuartzCore

@MainActor final class WeakLinkProxy: NSObject {
  weak var driver: DisplayLinkDriver?
  @objc func tick(_ link: CADisplayLink) {
    guard let driver else {
      link.invalidate()
      return
    }
    driver.frame(link.targetTimestamp)
  }
}
@MainActor final class DisplayLinkDriver {
  private var link: CADisplayLink?
  private let proxy = WeakLinkProxy()
  weak var viewport: PrompterViewport?
  weak var session: PlaybackSession?
  var authoritative = false
  var onError: ((Error) -> Void)?
  init(viewport: PrompterViewport, session: PlaybackSession) {
    self.viewport = viewport
    self.session = session
    proxy.driver = self
  }
  func update() {
    guard let viewport, viewport.window != nil, let session else {
      stop()
      return
    }
    if session.state == .idle {
      stop()
      return
    }
    if session.state != .running {
      link?.isPaused = true
      return
    }
    if link == nil {
      let next = viewport.displayLink(target: proxy, selector: #selector(WeakLinkProxy.tick(_:)))
      next.add(to: .main, forMode: .common)
      link = next
    }
    link?.isPaused = false
  }
  func frame(_ target: Double) {
    guard let viewport, let session else {
      stop()
      return
    }
    do {
      if authoritative { try session.noteFrame(target: target, end: viewport.endPosition) }
      viewport.apply(position: try session.position(at: target))
      if session.state == .idle {
        stop()
        return
      }
      if session.state != .running { link?.isPaused = true }
    } catch let error as TimelineError {
      stop()
      onError?(error)
    } catch let error as NSError {
      stop()
      onError?(error)
    }
  }
  func stop() {
    link?.invalidate()
    link = nil
  }
}
