import Testing
import Foundation
import Combine
@testable import Networking

// Here we use sample API from https://m3o.com/helloworld
struct NetworkingTests: @unchecked Sendable {
  struct Sample: Decodable, @unchecked Sendable {
    var message: String = ""
  }
  
  let instance = Networking.shared
  
  let postRequest: Request = Request(
    from: "https://local-testing.com/greeting",
    as: .post,
    authorization: .bearerToken(
      token: "YzhiYmFlNTUtNDE2Mi00MDk5LTg1Y2UtNmNmZDFmMWE1MzY2"
    ),
    parameters: ["name" : "Quan"]
  )
  
  init() async {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    await instance.set(URLSession(configuration: configuration))
  }
  
//  @Test("Test the original call with result handler block")
//  func standard() async throws {
//    
//    await instance.get(
//      Sample.self,
//      from: postRequest
//    ) { result in
//      switch result {
//      case .success(let sample):
//        #expect(sample.message == "Hello Quan", "The return should be: `message` : `Hello Quan`")
//      case .failure(_):
//        Issue.record("The return should be success")
//        break
//      }
//      
//    }
//  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  @Test("Concurrency test with async await")
  func concurency() async throws {
    
    async let sample = instance.getObject(Sample.self, from: postRequest, session: instance.session)
    
    let message = try await sample.message
    
    #expect(message == "Hello Quan", "The return should be: `message` : `Hello Quan`")
  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  @Test("Error testing")
  func error() async throws {
    let copyRequest = postRequest
    copyRequest.baseURL = "https://local-testing.com/greetingggg"
    await #expect(throws: Networking.NetworkError.httpSeverSideError(Data(), statusCode: .forbidden)) {
      try await instance
        .getObject(Sample.self, from: copyRequest, session: instance.session)
    }
  }
  
//  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
//  @Test("Combine framework test")
//  func combine() throws {
//    var subcriptions = Set<AnyCancellable>()
//    
//    instance
//      .publisher(for: Sample.self, from: postRequest)
//      .sink { completion in
//        switch completion {
//        case .finished:
//          break
//        case .failure(let error):
//          Issue.record("got an error: \(error.localizedDescription)")
//        }
//      } receiveValue: { sample in
//        #expect(sample.message == "Hello Quan", "The return should be: `message` : `Hello Quan`")
//      }
//      .store(in: &subcriptions)
//    
//  }
//  
//  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
//  @Test("Combien framework test with standard call")
//  func vombineUseWithStandard() throws {
//    
//    var subcriptions = Set<AnyCancellable>()
//    
//    Deferred {
//      Future { promise in
//        self
//          .instance
//          .get(Sample.self, from: self.postRequest, completion: promise)
//      }
//    }
//    .eraseToAnyPublisher()
//    .sink { completion in
//      switch completion {
//      case .finished:
//        break
//      case .failure(let error):
//        Issue.record("got an error: \(error.localizedDescription)")
//      }
//    } receiveValue: { sample in
//      #expect(sample.message == "Hello Quan", "The return should be: `message` : `Hello Quan`")
//    }
//    .store(in: &subcriptions)
//    
//  }
//  
//  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
//  @Test("Test concurency mix with standard call")
//  func concurencyUseWithStandard() async throws {
//    
//    let sample = try await withCheckedThrowingContinuation { continuation in
//      self.instance.get(Sample.self, from: self.postRequest) { result in
//        continuation.resume(with: result)
//      }
//    }
//    
//    #expect(sample.message == "Hello Quan", "The return should be: `message` : `Hello Quan`")
//  }
//  
//  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
//  @Test("Test concurrency mix with combine framework usage")
//  func concurencyUseWithCombine() async throws {
//    
//    var subcriptions = Set<AnyCancellable>()
//    
//    let sample: Sample =
//    try await withCheckedThrowingContinuation { continuation in
//      self
//        .instance
//        .publisher(for: Sample.self, from: self.postRequest)
//        .sink { completion in
//          switch completion {
//          case .finished:
//            break
//          case .failure(let error):
//            continuation.resume(throwing: error)
//          }
//        } receiveValue: { sample in
//          continuation.resume(returning: sample)
//        }
//        .store(in: &subcriptions)
//    }
//    
//    #expect(sample.message == "Hello Quan", "The return should be: `message` : `Hello Quan`")
//  }
//  
//  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
//  @Test("Test combine framwork mix with concurency call")
//  func combineUseWithConcurency() async throws {
//    
//    var subscription = Set<AnyCancellable>()
//    Deferred {
//        Future<Sample, Error> { promise in
//        Task {
//          #expect(throws: Never.self) {
//            async let result = self
//              .instance
//              .getObject(Sample.self, from: self.postRequest)
//            
//            print("result: \(try await result)")
//            
//            try await promise(.success(result))
//          }
//        }
//      }
//    }
//    .eraseToAnyPublisher()
//    .sink { completion in
//      switch completion {
//      case .finished:
//        print("finished")
//      case .failure(let error):
//        Issue.record(error, "got an error: \(error.localizedDescription)")
//      }
//    } receiveValue: { sample in
//      #expect(sample.message == "Hello Quan", "The return should be: `message` : `Hello Quan`")
//    }
//    .store(in: &subscription)
//  }
}
