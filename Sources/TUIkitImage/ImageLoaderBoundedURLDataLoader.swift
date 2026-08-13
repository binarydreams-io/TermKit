//  🖥️ TUIKit — Terminal UI Kit for Swift
//  ImageLoaderBoundedURLDataLoader.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum BoundedURLImageDataLoader {
  static func load(
    request: URLRequest,
    maxByteCount: Int,
    configuration: URLSessionConfiguration = .ephemeral
  ) throws -> Data {
    guard maxByteCount >= 0 else {
      throw ImageLoadError.inputTooLarge(byteCount: 0, limit: maxByteCount)
    }

    return try SessionDelegate(maxByteCount: maxByteCount).load(
      request: request,
      configuration: configuration
    )
  }
}

extension BoundedURLImageDataLoader {
  fileprivate final class SessionDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let maxByteCount: Int
    private let completionSemaphore = DispatchSemaphore(value: 0)
    private let stateLock = NSLock()
    private var bufferedData = Data()
    private var result: Result<Data, Error>?

    init(maxByteCount: Int) {
      self.maxByteCount = maxByteCount
    }

    func load(request: URLRequest, configuration: URLSessionConfiguration) throws -> Data {
      let session = URLSession(
        configuration: configuration,
        delegate: self,
        delegateQueue: nil
      )
      let task = session.dataTask(with: request)
      task.resume()
      completionSemaphore.wait()
      session.invalidateAndCancel()

      stateLock.lock()
      let completedResult = result
      stateLock.unlock()

      guard let completedResult else {
        throw ImageLoadError.downloadFailed("Download finished without a result")
      }
      return try completedResult.get()
    }

    func urlSession(
      _ session: URLSession,
      dataTask: URLSessionDataTask,
      didReceive response: URLResponse,
      completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
      let expectedByteCount = response.expectedContentLength
      if expectedByteCount > Int64(maxByteCount) {
        let reportedByteCount = min(expectedByteCount, Int64(Int.max))
        finish(
          with: .failure(
            ImageLoadError.inputTooLarge(
              byteCount: Int(reportedByteCount),
              limit: maxByteCount
            )
          )
        )
        completionHandler(.cancel)
        return
      }

      completionHandler(.allow)
    }

    func urlSession(
      _ session: URLSession,
      dataTask: URLSessionDataTask,
      didReceive data: Data
    ) {
      stateLock.lock()
      guard result == nil else {
        stateLock.unlock()
        dataTask.cancel()
        return
      }

      let remainingByteCount = maxByteCount - bufferedData.count
      guard data.count <= remainingByteCount else {
        let reportedByteCount = maxByteCount == Int.max ? Int.max : maxByteCount + 1
        result = .failure(
          ImageLoadError.inputTooLarge(
            byteCount: reportedByteCount,
            limit: maxByteCount
          )
        )
        stateLock.unlock()
        completionSemaphore.signal()
        dataTask.cancel()
        return
      }

      bufferedData.append(data)
      stateLock.unlock()
    }

    func urlSession(
      _ session: URLSession,
      task: URLSessionTask,
      didCompleteWithError error: Error?
    ) {
      if let error {
        finish(with: .failure(error))
      } else {
        stateLock.lock()
        let data = bufferedData
        stateLock.unlock()
        finish(with: .success(data))
      }
    }

    private func finish(with completedResult: Result<Data, Error>) {
      stateLock.lock()
      guard result == nil else {
        stateLock.unlock()
        return
      }
      result = completedResult
      stateLock.unlock()
      completionSemaphore.signal()
    }
  }
}
