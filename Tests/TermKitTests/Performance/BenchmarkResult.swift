import Foundation
@testable import TermKit

struct BenchmarkResult: Codable, Hashable, Sendable {
  let name: String
  let samplesNanoseconds: [Int64]
  let warmupCount: Int
  let iterationsPerSample: Int

  init(
    name: String,
    samplesNanoseconds: [Int64],
    warmupCount: Int,
    iterationsPerSample: Int = 1
  ) {
    precondition(samplesNanoseconds.isEmpty == false)
    precondition(samplesNanoseconds.allSatisfy { $0 >= 0 })
    precondition(warmupCount >= 0)
    precondition(iterationsPerSample > 0)
    self.name = name
    self.samplesNanoseconds = samplesNanoseconds
    self.warmupCount = warmupCount
    self.iterationsPerSample = iterationsPerSample
  }

  var sampleCount: Int {
    samplesNanoseconds.count
  }

  var medianNanoseconds: Int64 {
    percentile(0.50)
  }

  var percentile95Nanoseconds: Int64 {
    percentile(0.95)
  }

  var maximumNanoseconds: Int64 {
    samplesNanoseconds.max() ?? 0
  }

  var medianMilliseconds: Double {
    Self.milliseconds(from: medianNanoseconds)
  }

  var percentile95Milliseconds: Double {
    Self.milliseconds(from: percentile95Nanoseconds)
  }

  var maximumMilliseconds: Double {
    Self.milliseconds(from: maximumNanoseconds)
  }

  func report(budgetMilliseconds: Double) -> String {
    "\(name): p50=\(Self.format(medianMilliseconds)) ms, "
      + "p95=\(Self.format(percentile95Milliseconds)) ms, "
      + "max=\(Self.format(maximumMilliseconds)) ms, "
      + "budget<\(Self.format(budgetMilliseconds)) ms, "
      + "samples=\(sampleCount), warmups=\(warmupCount), "
      + "iterations/sample=\(iterationsPerSample)"
  }

  func failureMessage(budgetMilliseconds: Double, guidance: String) -> String {
    "Performance gate failed. \(report(budgetMilliseconds: budgetMilliseconds)). \(guidance)"
  }

  private func percentile(_ fraction: Double) -> Int64 {
    precondition(fraction > 0 && fraction <= 1)
    let sorted = samplesNanoseconds.sorted()
    let rank = Int((Double(sorted.count) * fraction).rounded(.up))
    return sorted[max(0, rank - 1)]
  }

  private static func milliseconds(from nanoseconds: Int64) -> Double {
    Double(nanoseconds) / 1000000
  }

  private static func format(_ milliseconds: Double) -> String {
    String(format: "%.1f", milliseconds)
  }
}
