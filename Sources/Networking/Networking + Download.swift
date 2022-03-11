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
    public typealias DownloadHandler = (Result<Data, Error>) -> ()
    public typealias ProcessHandler = (Double) -> Void
    
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
    public final class DownloadQueue: NSObject {
        private var session: URLSession!
        private var queue: [GenericDownloadTask] = []
        
        public static let shared = DownloadQueue()
        
        private override init() {
            super.init()
            let configuration = URLSessionConfiguration.default
            session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        }
        
        public func downloadTask(from request: URLRequest) -> DownloadTask {
            let task = self.session.dataTask(with: request)
            let downloadTask = GenericDownloadTask(task)
            queue.append(downloadTask)
            return downloadTask
        }
    }
}

extension Networking.DownloadQueue: URLSessionDataDelegate {
    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let task = queue.first(where: { $0.task == dataTask }) else {
            completionHandler(.cancel)
            return
        }
        task.expectedContentLength = response.expectedContentLength
        completionHandler(.allow)
    }
    
    public func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let task = queue.first(where: { $0.task == dataTask }) else {
            return
        }
        task.buffer.append(data)
        let percentage = Double(task.buffer.count) / Double(task.expectedContentLength)
        
        DispatchQueue.main.async {
            task.progressHandler?(percentage)
        }
    }
    
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let index = queue.firstIndex(where: { $0.task == task }) else {
            return
        }
        
        let task = queue.remove(at: index)
        DispatchQueue.main.async {
            guard let error = error else {
                task.completionHandler?(.success(task.buffer))
                return
            }
            task.completionHandler?(.failure(error))
        }
    }
}
