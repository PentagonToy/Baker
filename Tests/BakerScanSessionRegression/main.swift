struct CaptureRegion {let screen:NSScreen;let rect:CGRect}
struct PreparedCapture {func image() async throws -> CGImage {throw CancellationError()};func preview() async throws -> CGImage {throw CancellationError()}}
struct PreparedWindowCapture {let region:CaptureRegion;let capture:PreparedCapture;let application:NSRunningApplication?;let frame:CGRect;let title:String}
@MainActor final class CaptureService {
 static var requests = 0
 var pending:CheckedContinuation<PreparedWindowCapture?,Error>?
 func prepareWindow() async throws -> PreparedWindowCapture? {Self.requests += 1;return try await withCheckedThrowingContinuation {pending=$0}}
 func prepare(_ region:CaptureRegion) async throws -> PreparedCapture {throw CancellationError()}
 func cancelSelection(){let callback=pending;pending=nil;callback?.resume(throwing:CancellationError())}
}
@MainActor final class ScanImagePicker {enum Mode{case area,point};func choose(image:CGImage,screen:NSScreen,mode:Mode) async -> CGRect? {nil};func cancel(){}}
@MainActor struct ScanTurnTarget {
 init(application:NSRunningApplication,region:CaptureRegion,point:CGPoint?,expectedWindow:CGRect?,expectedTitle:String?,keyCode:UInt16=124) throws {}
 func validate() throws {};func advance() throws {}
 static func focusSelected(_ app:NSRunningApplication,frame:CGRect,title:String) async throws {}
}
enum ControlAccess {static func request(){}}
struct ScanReview:View {let session:ScanSession;var body:some View {Text("Review fixture")}}
struct ScanControls:View {let session:ScanSession;var body:some View {Text("Controls fixture")}}
@MainActor final class CancelProbe {func cancel(){}}
@MainActor final class Workbench {var scanSession:ScanSession?;let plugins=CancelProbe(),filesInbox=CancelProbe(),captureFlow=CancelProbe(),recognitionFlow=CancelProbe(),documentFlow=CancelProbe(),fileExports=CancelProbe();var importTask:Task<Void,Never>?}
let app=NSApplication.shared
app.setActivationPolicy(.prohibited)
Task { @MainActor in
 let root=URL(fileURLWithPath:CommandLine.arguments[1]);try! FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
 for action in ["setup", "selecting", "review-selection"] {
  let selecting = action != "setup"
  let folder=root.appendingPathComponent(action)
  let draft=try! ScanDocument(directory:folder);var ended=0
  let session=ScanSession(draft:draft,saveDirectory:root,languages:[],ended:{ended += 1},saved:{_ in preconditionFailure("Cancel must not save")})
  let pixels=CGContext(data:nil,width:16,height:16,bitsPerComponent:8,bytesPerRow:0,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  _ = try! await draft.append(pixels.makeImage()!)
  let manifest=folder.appendingPathComponent("scan.json"), original=try! Data(contentsOf:folder.appendingPathComponent("scan.json"))
  session.start(resume:false)
  while session.resourceState["pendingWork"] as? Bool == true {try! await Task.sleep(for:.milliseconds(10))}
  if !selecting {
   let host=NSHostingView(rootView:ScanSetup(session:session));host.frame=NSRect(x:0,y:0,width:620,height:440);host.layoutSubtreeIfNeeded()
   func segments(_ v:NSView)->[NSSegmentedControl] {(v as? NSSegmentedControl).map {[$0]} ?? v.subviews.flatMap(segments)}
   let control=segments(host).first {$0.segmentCount==3}!
   precondition((0..<3).map {control.label(forSegment:$0) ?? ""} == ["→","↓","Click"] && control.segmentDistribution == .fillEqually)
   let bitmap=host.bitmapImageRepForCachingDisplay(in:host.bounds)!;host.cacheDisplay(in:host.bounds,to:bitmap)
   try! bitmap.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent("setup.png"))
  }
  if selecting {
   let before = CaptureService.requests
   session.chooseSource();try! await Task.sleep(for:.milliseconds(30))
   session.chooseSource();try! await Task.sleep(for:.milliseconds(30))
   precondition(CaptureService.requests == before + 1, "A second source picker must not replace pending selection work")
  }
  if action == "review-selection" {
   session.review();try! await Task.sleep(for:.milliseconds(50))
   precondition(session.phase == .review, "A cancelled picker must not replace Review with Setup")
  }
  let bench=Workbench();bench.scanSession=session;bench.cancelJob()
  let deadline=ContinuousClock.now.advanced(by:.seconds(2))
  while session.phase != .closed || session.working {precondition(ContinuousClock.now < deadline);try! await Task.sleep(for:.milliseconds(10))}
  await session.close()
  try! await Task.sleep(for:.milliseconds(30))
  precondition(session.phase == .closed && ended == 1 && !session.working)
  precondition(session.resourceState["pendingWork"] as? Bool == false)
  precondition(try! Data(contentsOf:manifest) == original, "Cancel must preserve captured pages")
  print("PASS: cancellation drains \(selecting ? "selection":"setup"), closes once and cannot reopen")
 }
 print("Passed scan session cancellation checks without capture or reader input");exit(0)
}
app.run()
