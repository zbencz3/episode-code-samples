import Foundation

struct Parser<Input, Output> {
  let run: (inout Input) -> Output?
}

extension Parser {
  func run(_ input: Input) -> (match: Output?, rest: Input) {
    var input = input
    let match = self.run(&input)
    return (match, input)
  }
}

extension Parser {
  @inlinable
  public func pullback<GlobalInput>(_ kp: WritableKeyPath<GlobalInput, Input>) -> Parser<GlobalInput, Output> {
    .init { i in
      self.run(&i[keyPath: kp])
    }
  }
}

extension Parser where Input == Substring, Output == Int {
  static let int = Self { input in
    let original = input

    let sign: Int // +1, -1
    if input.first == "-" {
      sign = -1
      input.removeFirst()
    } else if input.first == "+" {
      sign = 1
      input.removeFirst()
    } else {
      sign = 1
    }

    let intPrefix = input.prefix(while: \.isNumber)
    guard let match = Int(intPrefix)
    else {
      input = original
      return nil
    }
    input.removeFirst(intPrefix.count)
    return match * sign
  }
}

extension Parser where Input == Substring, Output == Double {
  static let double = Self { input in
    let original = input
    let sign: Double
    if input.first == "-" {
      sign = -1
      input.removeFirst()
    } else if input.first == "+" {
      sign = 1
      input.removeFirst()
    } else {
      sign = 1
    }

    var decimalCount = 0
    let prefix = input.prefix { char in
      if char == "." { decimalCount += 1 }
      return char.isNumber || (char == "." && decimalCount <= 1)
    }

    guard let match = Double(prefix)
    else {
      input = original
      return nil
    }

    input.removeFirst(prefix.count)

    return match * sign
  }
}



extension Parser where Input == Substring, Output == Character {
  static let char = Self { input in
    guard !input.isEmpty else { return nil }
    return input.removeFirst()
  }
}

extension Parser {
  static func always(_ output: Output) -> Self {
    Self { _ in output }
  }

  static var never: Self {
    Self { _ in nil }
  }
}

extension Parser {
  func map<NewOutput>(_ f: @escaping (Output) -> NewOutput) -> Parser<Input, NewOutput> {
    .init { input in
      self.run(&input).map(f)
    }
  }
}

extension Parser {
  func flatMap<NewOutput>(
    _ f: @escaping (Output) -> Parser<Input, NewOutput>
  ) -> Parser<Input, NewOutput> {
    .init { input in
      let original = input
      let output = self.run(&input)
      let newParser = output.map(f)
      guard let newOutput = newParser?.run(&input) else {
        input = original
        return nil
      }
      return newOutput
    }
  }
}
//
func zip<Input, Output1, Output2>(
  _ p1: Parser<Input, Output1>,
  _ p2: Parser<Input, Output2>
) -> Parser<Input, (Output1, Output2)> {

  .init { input -> (Output1, Output2)? in
    let original = input
    guard let output1 = p1.run(&input) else { return nil }
    guard let output2 = p2.run(&input) else {
      input = original
      return nil
    }
    return (output1, output2)
  }
}
extension Parser {
  static func oneOf(_ ps: [Self]) -> Self {
    .init { input in
      for p in ps {
        if let match = p.run(&input) {
          return match
        }
      }
      return nil
    }
  }

  static func oneOf(_ ps: Self...) -> Self {
    self.oneOf(ps)
  }
}

extension Parser
where Input: Collection,
      Input.SubSequence == Input,
      Input.Element: Equatable,
      Output == Void {
  static func prefix(_ p: Input.SubSequence) -> Self {
    Self { input in
      guard input.starts(with: p) else { return nil }
      input.removeFirst(p.count)
      return ()
    }
  }
}

extension Parser where Input == Substring, Output == Substring {
  static func prefix(while p: @escaping (Character) -> Bool) -> Self {
    Self { input in
      let output = input.prefix(while: p)
      input.removeFirst(output.count)
      return output
    }
  }
}

extension Parser where Input == Substring, Output == Substring {
  static func prefix(upTo substring: Substring) -> Self {
    Self { input in
      guard let endIndex = input.range(of: substring)?.lowerBound
      else { return nil }

      let match = input[..<endIndex]

      input = input[endIndex...]

      return match
    }
  }

  static func prefix(through substring: Substring) -> Self {
    Self { input in
      guard let endIndex = input.range(of: substring)?.upperBound
      else { return nil }

      let match = input[..<endIndex]

      input = input[endIndex...]

      return match
    }
  }
}

extension Parser: ExpressibleByUnicodeScalarLiteral
where Input == Substring,
      Output == Void {
  typealias UnicodeScalarLiteralType = StringLiteralType
}

extension Parser: ExpressibleByExtendedGraphemeClusterLiteral
where Input == Substring,
      Output == Void {
  typealias ExtendedGraphemeClusterLiteralType = StringLiteralType
}

extension Parser: ExpressibleByStringLiteral
where Input == Substring,
      Output == Void {
  init(stringLiteral value: String) {
    self = .prefix(value[...])
  }
}


//
//extension Parser: ExpressibleByUnicodeScalarLiteral
//where Input: ExpressibleByUnicodeScalarLiteral,
//      Input: Collection,
//      Input.SubSequence == Input,
//      Input.Element: Equatable,
//      Output == Void {
//  init(unicodeScalarLiteral value: Input.UnicodeScalarLiteralType) {
//    self = .prefix(Input(unicodeScalarLiteral: value))
//  }
//}
//
//extension Parser: ExpressibleByExtendedGraphemeClusterLiteral
//where Input: ExpressibleByExtendedGraphemeClusterLiteral,
//  Input: Collection,
//  Input.SubSequence == Input,
//  Input.Element: Equatable,
//  Output == Void {
//  init(extendedGraphemeClusterLiteral value: Input.ExtendedGraphemeClusterLiteralType) {
//    self = .prefix(Input(extendedGraphemeClusterLiteral: value))
//  }
//}
//
//extension Parser: ExpressibleByStringLiteral
//where Input: ExpressibleByStringLiteral,
//      Input: Collection,
//      Input.SubSequence == Input,
//      Input.Element: Equatable,
//      Output == Void {
//  init(stringLiteral value: Input.StringLiteralType) {
//    self = .prefix(Input(stringLiteral: value))
//  }
//}
//


extension Parser {
  func zeroOrMore(
    separatedBy separator: Parser<Input, Void> = .always(())
  ) -> Parser<Input, [Output]> {
    Parser<Input, [Output]> { input in
      var rest = input
      var matches: [Output] = []
      while let match = self.run(&input) {
        rest = input
        matches.append(match)
        if separator.run(&input) == nil {
          return matches
        }
      }
      input = rest
      return matches
    }
  }
}

extension Parser {
  func skip<OtherOutput>(_ p: Parser<Input, OtherOutput>) -> Self {
    zip(self, p).map { a, _ in a }
  }
}

extension Parser {
  func take<NewOutput>(
    _ p: Parser<Input, NewOutput>
  ) -> Parser<Input, (Output, NewOutput)> {
    zip(self, p)
  }
}

extension Parser  {
  func take<Output1, Output2, Output3>(
    _ p: Parser<Input, Output3>
  ) -> Parser<Input, (Output1, Output2, Output3)>
  where Output == (Output1, Output2) {
    zip(self, p).map { ab, c in
      (ab.0, ab.1, c)
    }
  }
}

extension Parser {
  static func skip(_ p: Self) -> Parser<Input, Void> {
    p.map { _ in () }
  }
}

extension Parser {
  static func take (_ p: Self) -> Self { p }
}

extension Parser where Output == Void {
  func take<NewOutput>(
    _ p: Parser<Input, NewOutput>
  ) -> Parser<Input, NewOutput> {
    zip(self, p).map { _, a in a }
  }
}


//"98°F"
let temperature = Parser.int.skip("°F")

let northSouth = Parser.char.flatMap {
  $0 == "N" ? .always(1.0)
    : $0 == "S" ? .always(-1)
    : .never
}

let eastWest = Parser.char.flatMap {
  $0 == "E" ? .always(1.0)
    : $0 == "W" ? .always(-1)
    : .never
}


//"40.446° N"
//"40.446° S"
let latitude = Parser.double
  .skip("° ")
  .take(northSouth)
  .map(*)

let longitude = Parser.double
  .skip("° ")
  .take(eastWest)
  .map(*)

struct Coordinate {
  let latitude: Double
  let longitude: Double
}

let zeroOrMoreSpaces = Parser<Substring, Void>.prefix(" ").zeroOrMore()

//"40.446° N, 79.982° W"
let coord = latitude
  .skip(",")
  .skip(zeroOrMoreSpaces)
  .take(longitude)
  .map(Coordinate.init)


//  .map { lat, long in
//    Coordinate(latitude: lat, longitude: long)
//  }

//zip(
//  latitude,
//  ",",
//  Parser.prefix(" ").zeroOrMore(),
//  longitude
//)
//.map { lat, _, _, long in
//  Coordinate(latitude: lat, longitude: long)
//}

enum Currency { case eur, gbp, usd }

let currency = Parser.oneOf(
  Parser<Substring, Void>.prefix("€").map { Currency.eur },
  Parser.prefix("£").map { .gbp },
  Parser.prefix("$").map { .usd }
)

struct Money {
  let currency: Currency
  let value: Double
}

//"$100"
let money = zip(currency, .double)
  .map(Money.init(currency:value:))

let upcomingRaces = """
  New York City, $300
  40.60248° N, 74.06433° W
  40.61807° N, 74.02966° W
  40.64953° N, 74.00929° W
  40.67884° N, 73.98198° W
  40.69894° N, 73.95701° W
  40.72791° N, 73.95314° W
  40.74882° N, 73.94221° W
  40.75740° N, 73.95309° W
  40.76149° N, 73.96142° W
  40.77111° N, 73.95362° W
  40.80260° N, 73.93061° W
  40.80409° N, 73.92893° W
  40.81432° N, 73.93292° W
  40.80325° N, 73.94472° W
  40.77392° N, 73.96917° W
  40.77293° N, 73.97671° W
  ---
  Berlin, €100
  13.36015° N, 52.51516° E
  13.33999° N, 52.51381° E
  13.32539° N, 52.51797° E
  13.33696° N, 52.52507° E
  13.36454° N, 52.52278° E
  13.38152° N, 52.52295° E
  13.40072° N, 52.52969° E
  13.42555° N, 52.51508° E
  13.41858° N, 52.49862° E
  13.40929° N, 52.48882° E
  13.37968° N, 52.49247° E
  13.34898° N, 52.48942° E
  13.34103° N, 52.47626° E
  13.32851° N, 52.47122° E
  13.30852° N, 52.46797° E
  13.28742° N, 52.47214° E
  13.29091° N, 52.48270° E
  13.31084° N, 52.49275° E
  13.32052° N, 52.50190° E
  13.34577° N, 52.50134° E
  13.36903° N, 52.50701° E
  13.39155° N, 52.51046° E
  13.37256° N, 52.51598° E
  ---
  London, £500
  51.48205° N, 0.04283° E
  51.47439° N, 0.02170° E
  51.47618° N, 0.02199° E
  51.49295° N, 0.05658° E
  51.47542° N, 0.03019° E
  51.47537° N, 0.03015° E
  51.47435° N, 0.03733° E
  51.47954° N, 0.04866° E
  51.48604° N, 0.06293° E
  51.49314° N, 0.06104° E
  51.49248° N, 0.04740° E
  51.48888° N, 0.03564° E
  51.48655° N, 0.01830° E
  51.48085° N, 0.02223° W
  51.49210° N, 0.04510° W
  51.49324° N, 0.04699° W
  51.50959° N, 0.05491° W
  51.50961° N, 0.05390° W
  51.49950° N, 0.01356° W
  51.50898° N, 0.02341° W
  51.51069° N, 0.04225° W
  51.51056° N, 0.04353° W
  51.50946° N, 0.07810° W
  51.51121° N, 0.09786° W
  51.50964° N, 0.11870° W
  51.50273° N, 0.13850° W
  51.50095° N, 0.12411° W
  """

struct Race {
  let location: String
  let entranceFee: Money
  let path: [Coordinate]
}

let locationName = Parser.prefix(while: { $0 != "," })

let race = locationName.map(String.init)
  .skip(",")
  .skip(zeroOrMoreSpaces)
  .take(money)
  .skip("\n")
  .take(coord.zeroOrMore(separatedBy: "\n"))
  .map(Race.init(location:entranceFee:path:))


let races = race.zeroOrMore(separatedBy: "\n---\n")


let logs = (0...10_000).map { _ in "Build logs\n" }.joined() + """
Test Case '-[VoiceMemosTests.VoiceMemosTests testDeleteMemo]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testDeleteMemo]' passed (0.004 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testDeleteMemoWhilePlaying]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testDeleteMemoWhilePlaying]' passed (0.002 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testPermissionDenied]' started.
/Users/point-free/projects/swift-composable-architecture/Examples/VoiceMemos/VoiceMemosTests/VoiceMemosTests.swift:107: error: -[VoiceMemosTests.VoiceMemosTests testPermissionDenied] : XCTAssertTrue failed
Test Case '-[VoiceMemosTests.VoiceMemosTests testPermissionDenied]' failed (0.003 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testPlayMemoFailure]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testPlayMemoFailure]' passed (0.002 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testPlayMemoHappyPath]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testPlayMemoHappyPath]' passed (0.002 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure]' started.
/Users/point-free/projects/swift-composable-architecture/Examples/VoiceMemos/VoiceMemosTests/VoiceMemosTests.swift:144: error: -[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure] : State change does not match expectation: …

      VoiceMemosState(
    −   alert: nil,
    +   alert: AlertState<VoiceMemosAction>(
    +     title: "Voice memo recording failed.",
    +     message: nil,
    +     primaryButton: nil,
    +     secondaryButton: nil
    +   ),
        audioRecorderPermission: RecorderPermission.allowed,
        currentRecording: nil,
        voiceMemos: [
        ]
      )

(Expected: −, Actual: +)
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoFailure]' failed (0.009 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoHappyPath]' started.
/Users/point-free/projects/swift-composable-architecture/Examples/VoiceMemos/VoiceMemosTests/VoiceMemosTests.swift:56: error: -[VoiceMemosTests.VoiceMemosTests testRecordMemoHappyPath] : State change does not match expectation: …

      VoiceMemosState(
        alert: nil,
        audioRecorderPermission: RecorderPermission.allowed,
        currentRecording: CurrentRecording(
          date: 2001-01-01T00:00:00Z,
    −     duration: 3.0,
    +     duration: 2.0,
          mode: Mode.recording,
          url: file:///tmp/DEADBEEF-DEAD-BEEF-DEAD-BEEFDEADBEEF.m4a
        ),
        voiceMemos: [
        ]
      )

(Expected: −, Actual: +)
Test Case '-[VoiceMemosTests.VoiceMemosTests testRecordMemoHappyPath]' failed (0.006 seconds).
Test Case '-[VoiceMemosTests.VoiceMemosTests testStopMemo]' started.
Test Case '-[VoiceMemosTests.VoiceMemosTests testStopMemo]' passed (0.001 seconds).
Test Suite 'VoiceMemosTests' failed at 2020-08-19 12:36:12.094.
   Executed 8 tests, with 3 failures (0 unexpected) in 0.029 (0.032) seconds
Test Suite 'VoiceMemosTests.xctest' failed at 2020-08-19 12:36:12.094.
   Executed 8 tests, with 3 failures (0 unexpected) in 0.029 (0.032) seconds
Test Suite 'All tests' failed at 2020-08-19 12:36:12.095.
   Executed 8 tests, with 3 failures (0 unexpected) in 0.029 (0.033) seconds
2020-08-19 12:36:19.538 xcodebuild[45126:3958202] [MT] IDETestOperationsObserverDebug: 14.165 elapsed -- Testing started completed.
2020-08-19 12:36:19.538 xcodebuild[45126:3958202] [MT] IDETestOperationsObserverDebug: 0.000 sec, +0.000 sec -- start
2020-08-19 12:36:19.538 xcodebuild[45126:3958202] [MT] IDETestOperationsObserverDebug: 14.165 sec, +14.165 sec -- end

Test session results, code coverage, and logs:
  /Users/point-free/Library/Developer/Xcode/DerivedData/ComposableArchitecture-fnpkwoynrpjrkrfemkkhfdzooaes/Logs/Test/Test-VoiceMemos-2020.08.19_12-35-57--0400.xcresult

Failing tests:
  VoiceMemosTests:
    VoiceMemosTests.testPermissionDenied()
    VoiceMemosTests.testRecordMemoFailure()
    VoiceMemosTests.testRecordMemoHappyPath()

"""

enum TestResult {
  case failed(failureMessage: Substring, file: Substring, line: Int, testName: Substring, time: TimeInterval)
  case passed(testName: Substring, time: TimeInterval)
}

let testCaseFinishedLine = Parser
  .skip(.prefix(through: " ("))
  .take(.double)
  .skip(" seconds).\n")

let testCaseStartedLine = Parser
  .skip(.prefix(upTo: "Test Case '-["))
  .take(.prefix(through: "\n"))
  .map { line in
    line.split(separator: " ")[3].dropLast(2)
  }

let fileName = Parser
  .skip("/")
  .take(.prefix(through: ".swift"))
  .flatMap { path in
    path.split(separator: "/").last.map(Parser.always)
      ?? .never
  }

let testCaseBody = fileName
  .skip(":")
  .take(.int)
  .skip(.prefix(through: "] : "))
  .take(Parser.prefix(upTo: "Test Case '-[").map { $0.dropLast() })

let testFailed = testCaseStartedLine
  .take(testCaseBody)
  .take(testCaseFinishedLine)
  .map { testName, bodyData, time in
    TestResult.failed(failureMessage: bodyData.2, file: bodyData.0, line: bodyData.1, testName: testName, time: time)
  }

let testPassed = testCaseStartedLine
  .take(testCaseFinishedLine)
  .map(TestResult.passed(testName:time:))

let testResult = Parser.oneOf(testFailed, testPassed)
let testResults = testResult.zeroOrMore()

//dump(
//)

//VoiceMemoTests.swift:123, testDelete failed in 2.00 seconds.
//  ┃
//  ┃  XCTAssertTrue failed
//  ┃
//  ┗━━──────────────
func format(result: TestResult) -> String {
  switch result {
  case .failed(failureMessage: let failureMessage, file: let file, line: let line, testName: let testName, time: let time):
    var output = "\(file):\(line), \(testName) failed in \(time) seconds."
    output.append("\n")
    output.append("  ┃")
    output.append("\n")
    output.append(
      failureMessage
        .split(separator: "\n")
        .map { "  ┃  \($0)" }
        .joined(separator: "\n")
    )
    output.append("\n")
    output.append("  ┃")
    output.append("\n")
    output.append("  ┗━━──────────────")
    output.append("\n")
    return output
  case .passed(testName: let testName, time: let time):
    return "\(testName) passed in \(time) seconds."
  }
}


extension Parser where Input == [String: String] {
  static func key(_ key: String, _ parser: Parser<Substring, Output>) -> Self {
    return .init { values in
      guard var value = values[key]?[...]
      else { return nil }
      guard let output = parser.run(&value)
      else { return nil }
      values[key] = nil
      return output
    }
  }
}

let path = Parser.key("DYLD_FRAMEWORK_PATH", .prefix(through: ".app"))
  .take(.key("HOME", Parser.skip("/Users/").take(.rest)))


struct RequestData {
  var body: Data? = nil
  var headers: [String: String] = [:]
  var method: String? = nil
  var pathComponents: ArraySlice<Substring> = []
  var queryItems: [(name: String, value: Substring)] = []
}

extension Parser where Input == RequestData, Output == Void {
  static func method(_ method: String) -> Self {
    .init { input in
      guard input.method?.uppercased() == method.uppercased()
      else { return nil }
      input.method = nil
      return ()
    }
  }
}

extension Parser where Input == RequestData {


  static func path(_ parser: Parser<Substring, Output>) -> Self {
    .init { input in
      guard var firstComponent = input.pathComponents.first
      else { return nil }

      let output = parser.run(&firstComponent)
      guard firstComponent.isEmpty
      else { return nil }

      input.pathComponents.removeFirst()
      return output
    }
  }

  static func query(name: String, _ parser: Parser<Substring, Output>) -> Self {
    .init { input in
      guard let index = input.queryItems.firstIndex(where: { name == $0.0 })
      else { return nil }

      let original = input.queryItems[index].value
      let output = parser.run(&input.queryItems[index].value)
      guard input.queryItems[index].value.isEmpty
      else {
        input.queryItems[index].value = original
        return nil
      }

      input.queryItems.remove(at: index)
      return output
    }
  }
}

extension Parser where Input == RequestData, Output == Void {
  static var end: Self {
    Self { input in
      guard input.pathComponents.isEmpty
      else { return nil }
      input = .init()
      return ()
    }
  }
}

extension Parser {
  static func optional<Wrapped>(
    _ parser: Parser<Input, Wrapped>
  ) -> Self where Output == Wrapped? {
    .init { input in
      .some(parser.run(&input))
    }
  }
}

let url = URL(string: "https://www.pointfree.co/episodes/1?ref=twitter")!
let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!


let request = RequestData(
  body: nil,
  headers: ["User-Agent": "Safari"],
  method: "GET",
  pathComponents: ["episodes", "1", "comments"],
  queryItems: [(name: "t", value: "120")]
)

enum Route {
  case episode(id: Int, time: Int?)
  case episodeComments(id: Int)
}

let router = Parser.oneOf(
  Parser
    .skip(Parser.method("GET"))
    .skip(.path("episodes"))
    .take(.path(.int))
    .take(.optional(.query(name: "t", .int)))
    .skip(.end)
    .map(Route.episode(id:time:)),

  Parser
    .skip(Parser.method("GET"))
    .skip(.path("episodes"))
    .take(.path(.int))
    .skip(.path("comments"))
    .skip(.end)
    .map(Route.episodeComments(id:))
)
//  .run(request)


//dump(
//  Parser
//    .skip(Parser.method("GET"))
//    .skip(.path("episodes"))
//    .take(.path(.int))
//    .take(.query(name: "ref", .rest))
//    .run(request)
//)

extension String {
  var substring: Substring {
    get { self[...] }
    set { self = String(newValue) }
  }
}



extension Parser where Input: RangeReplaceableCollection, Output == Input {
  static var rest: Parser<Input, Input> {
    .init { input in
      let original = input
      input = .init()
      return original
    }
  }
}

extension Parser where Input == Output {
  static var identity: Self {
    .init { $0 }
  }
}
extension Parser {
  func pipe<NewOutput>(_ parser: Parser<Output, NewOutput>) -> Parser<Input, NewOutput> {
    .init { input in
      let original = input
      guard var output = self.run(&input)
      else { return nil }
      guard let newOutput = parser.run(&output)
      else {
        input = original
        return nil
      }
      return newOutput
    }
  }
}



extension Parser {
  static func flag(
    long longFlag: String,
    short shortFlag: Unicode.Scalar
  ) -> Self
  where Input == ArraySlice<Substring>, Output == Bool {
    Self { input in
      var indicesToRemove: [Int] = []
      for (index, argument) in zip(input.indices, input) {
        if argument == "-\(shortFlag)" || argument == "--\(longFlag)" {
          indicesToRemove.append(index)
        }
      }
      indicesToRemove.reversed().forEach { index in input.remove(at: index) }
      return !indicesToRemove.isEmpty
    }
  }
}

extension Parser where Input == ArraySlice<Substring>, Output == [Substring] {
  static var files: Self {
    Self { input in
      var nonFlags: [Substring] = []
      var indicesToRemove: [Int] = []
      for (index, argument) in zip(input.indices, input) {
        if argument == "-" || !argument.starts(with: "-") {
          nonFlags.append(argument)
          indicesToRemove.append(index)
        }
      }
      indicesToRemove.reversed().forEach { index in input.remove(at: index) }
      return nonFlags
    }
  }
}

extension Parser where Input == ArraySlice<Substring>, Output == Void {
  static var end: Self {
    Self { input in
      input.isEmpty ? () : nil
    }
  }
}
extension Parser where Input: Collection, Input.SubSequence == Input, Output == Input.Element {
  static var first: Self {
    Self { input in
      guard !input.isEmpty else { return nil }
      return input.removeFirst()
    }
  }
}

// usage: generate-enum-properties [--help|-h] [--dry-run|-n] [<file>...]

// $ git ls "help me"
// ["git", "ls", "help me"]

var arguments = ["generate-enum-properties", "-n", "-"]

// Parser
//   .take(.flag(long: "help",    short: "h"))
//   .take(.flag(long: "dry-run", short: "n"))
//   .take(.nonFlags)
//   .skip(.end)

var toParse = arguments.map { $0[...] }

let cli = Parser
  .skip(.first)
  .take(.flag(long: "help",    short: "h"))
  .take(.flag(long: "dry-run", short: "n"))
  .take(.files)
  .skip(.end)
