import XCTest
import Combine
@testable import Networking

// Here we use sample API from https://m3o.com/helloworld
final class NetworkingTests: XCTestCase, @unchecked Sendable {
  struct Sample: Codable, @unchecked Sendable {
    var message: String = ""
  }
  
  let instance = Networking.shared
  
  let postRequest = Request(
    from: "https://api.m3o.com/v1/helloworld/Call",
    as: .post,
    authorization: .bearerToken(
      token: "YzhiYmFlNTUtNDE2Mi00MDk5LTg1Y2UtNmNmZDFmMWE1MzY2"
    ),
    parameters: ["name" : "Quan"]
  )
  
  func testStandard() throws {
    
    let expectation = XCTestExpectation(
      description: "The return should be: `message` : `Hello Quan`"
    )
    instance.get(
      Sample.self,
      from: postRequest
    ) { result in
      switch result {
      case .success(let sample):
        if sample.message == "Hello Quan" {
          expectation.fulfill()
        }
      case .failure(_):
        break
      }
    }
    wait(for: [expectation], timeout: 5.0)
  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  func testConcurency() async throws {
    
    let expectation = XCTestExpectation(
      description: "The return should be: `message` : `Hello Quan`"
    )
    
    async let sample = instance.get(Sample.self, from: postRequest)
    
    let message = try await sample.message
    
    if message == "Hello Quan" {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 5.0)
  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  func testError() async throws {
    let copyRequest = postRequest
    copyRequest.baseURL = "https://api.m3o.com/v1/helloworld/Callllllllllll"
    do {
      let _ = try await instance.get(Sample.self, from: copyRequest)
      XCTFail("Expected to throw an error since we put a transport error")
    } catch {
      switch error {
      case Networking.NetworkError.transportError:
        XCTAssertTrue(true)
      default:
        XCTFail("Expected to throw a transport error instead")
      }
    }
  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  func testCombine() throws {
    let expectation = XCTestExpectation(
      description: "The return should be: `message` : `Hello Quan`"
    )
    
    var subcriptions = Set<AnyCancellable>()
    
    instance
      .publisher(for: Sample.self, from: postRequest)
      .sink { completion in
        switch completion {
        case .finished:
          break
        case .failure(let error):
          print("got an error: \(error.localizedDescription)")
        }
      } receiveValue: { sample in
        if sample.message == "Hello Quan" {
          print(sample)
          expectation.fulfill()
        }
      }
      .store(in: &subcriptions)
    
    wait(for: [expectation], timeout: 5.0)
  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  func testCombineUseWithStandard() throws {
    let expectation = XCTestExpectation(
      description: "The return should be: `message` : `Hello Quan`"
    )
    
    var subcriptions = Set<AnyCancellable>()
    
    Deferred {
      Future { [unowned self] promise in
        self
          .instance
          .get(Sample.self, from: self.postRequest, completion: promise)
      }
    }
    .eraseToAnyPublisher()
    .sink { completion in
      switch completion {
      case .finished:
        break
      case .failure(let error):
        print("got an error: \(error.localizedDescription)")
      }
    } receiveValue: { sample in
      if sample.message == "Hello Quan" {
        print(sample)
        expectation.fulfill()
      }
    }
    .store(in: &subcriptions)
    
    wait(for: [expectation], timeout: 5.0)
  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  func testConcurencyUseWithStandard() async throws {
    
    let expectation = XCTestExpectation(
      description: "The return should be: `message` : `Hello Quan`"
    )
    
    let sample =
    try await withCheckedThrowingContinuation { [unowned self] continuation in
      self.instance.get(Sample.self, from: self.postRequest) { result in
        continuation.resume(with: result)
      }
    }
    
    if sample.message == "Hello Quan" {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 5.0)
  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  func testConcurencyUseWithCombine() async throws {
    let expectation = XCTestExpectation(
      description: "The return should be: `message` : `Hello Quan`"
    )
    
    var subcriptions = Set<AnyCancellable>()
    
    let sample: Sample =
    try await withCheckedThrowingContinuation { [unowned self] continuation in
      self
        .instance
        .publisher(for: Sample.self, from: self.postRequest)
        .sink { completion in
          switch completion {
          case .finished:
            break
          case .failure(let error):
            continuation.resume(throwing: error)
          }
        } receiveValue: { sample in
          continuation.resume(returning: sample)
        }
        .store(in: &subcriptions)
    }
    
    if sample.message == "Hello Quan" {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 5.0)
  }
  
  @available(iOS 13.0, tvOS 13.0, watchOS 6.0, macOS 10.15, macCatalyst 15.0, *)
  func testCombineUseWithConcurency() async throws {
    let expectation = XCTestExpectation(
      description: "The return should be: `message` : `Hello Quan`"
    )
    
    var subscription = Set<AnyCancellable>()
    Deferred {
        Future<Sample, Error> { [unowned self] promise in
        Task {
          do {
            async let result = self
              .instance
              .get(Sample.self, from: self.postRequest)
            
            print("result: \(try await result)")
            
            try await promise(.success(result))
          } catch {
            print("error: \(error.localizedDescription)")
            promise(.failure(error))
          }
        }
      }
    }
    .eraseToAnyPublisher()
    .sink { completion in
      switch completion {
      case .finished:
        print("finished")
      case .failure(let error):
        print("got an error: \(error.localizedDescription)")
      }
    } receiveValue: { sample in
      print(sample)
      if sample.message == "Hello Quan" {
        print(sample)
        expectation.fulfill()
      }
    }
    .store(in: &subscription)
    
    wait(for: [expectation], timeout: 5.0)
  }
}
