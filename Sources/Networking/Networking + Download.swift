import Foundation

/*
 Usage:
 - Create an instance of DownloadTask to keep track on it.
 - Use DownloadQueue to handle multiple DownloadTasks
 ```
 let request = createRequest(from:, as:, timeout:, authorization:, parameters:)
 let downloadTask = DownloadQueue.shared.downloadTask(from: request)
 downloadTask.completionHandler = {
 ...
 }
 downloadTask.progressHandler = {
 ...
 }
 
 downloadTask.resume()
 ```
 */

public protocol DownloadTask {
    var completionHandler: Networking.DownloadHandler? { get set }
    var progressHandler: Networking.ProcessHandler? { get set }
    
    func resume()
    func suspend()
    func cancel()
}

extension Networking {
    public typealias DownloadHandler = @Sendable (Result<Data, Error>) -> ()
    public typealias ProcessHandler = @Sendable (Double) -> Void
    
    class GenericDownloadTask: DownloadTask {
        var completionHandler: DownloadHandler?
        var progressHandler: ProcessHandler?
        
        private(set) var task: URLSessionDataTask
        var expectedContentLength: Int64 = 0
        
        /// A buffer that stores the downloaded data.
        var buffer = Data()
        
        init(_ task: URLSessionDataTask) {
            self.task = task
        }
        
        deinit {
#if DEBUG
            debugPrint("Deiniting: \(task.originalRequest?.url?.absoluteString ?? "no url")")
#endif
        }
        
        /// This will start or resume the download task
        func resume() {
            task.resume()
        }
        
        /// This will suspend the download task without terminal it
        func suspend() {
            task.suspend()
        }
        
        // this will cancel and terminal the download task
        func cancel() {
            task.cancel()
        }
    }
}

extension Networking {
    public actor DownloadQueue {
        private let session: URLSession
        private var queue: [GenericDownloadTask] = []
        private let delegate: DownloadSessionDelegate
        
        public static let shared = DownloadQueue()
        
        private init() {
            let configuration = URLSessionConfiguration.default
            delegate = DownloadSessionDelegate()
            session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
            delegate.downloadQueue = self
        }
        
        public func downloadTask(from request: URLRequest) -> DownloadTask {
            let task = self.session.dataTask(with: request)
            let downloadTask = GenericDownloadTask(task)
            queue.append(downloadTask)
            return downloadTask
        }
        
        func didReceiveResponse(_ response: URLResponse, for dataTask: URLSessionDataTask, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
            guard let task = queue.first(where: { $0.task == dataTask }) else {
                completionHandler(.cancel)
                return
            }
            task.expectedContentLength = response.expectedContentLength
            completionHandler(.allow)
        }
        
        func didReceiveData(_ data: Data, for dataTask: URLSessionDataTask) {
            guard let task = queue.first(where: { $0.task == dataTask }) else {
                return
            }
            task.buffer.append(data)
            let percentage = Double(task.buffer.count) / Double(task.expectedContentLength)
            
            Task { @MainActor in
                task.progressHandler?(percentage)
            }
        }
        
        func didCompleteWithError(_ error: Error?, for sessionTask: URLSessionTask) {
            guard let index = queue.firstIndex(where: { $0.task == sessionTask }) else {
                return
            }
            
            let task = queue.remove(at: index)
            Task { @MainActor in
                guard let error = error else {
                    task.completionHandler?(.success(task.buffer))
                    return
                }
                task.completionHandler?(.failure(error))
            }
        }
    }
}

extension Networking {
    final class DownloadSessionDelegate: NSObject, URLSessionDataDelegate {
        weak var downloadQueue: DownloadQueue?
        
        override init() {
            super.init()
        }
        
        public func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            Task {
                await downloadQueue?.didReceiveResponse(response, for: dataTask, completionHandler: completionHandler)
            }
        }
        
        public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            Task {
                await downloadQueue?.didReceiveData(data, for: dataTask)
            }
        }
        
        public func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didCompleteWithError error: Error?
        ) {
            Task {
                await downloadQueue?.didCompleteWithError(error, for: task)
            }
        }
    }
}
