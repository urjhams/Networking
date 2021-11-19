import XCTest
@testable import Networking

// Here we use sample API from https://m3o.com/helloworld
final class NetworkingTests: XCTestCase {
  struct Sample: Codable {
    var message: String
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
    instance.getObjectViaRequest(
      postRequest
    ) { (result: Networking.GenericResult<Sample>) in
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
  
  func testConcurency() async throws {
    
    let expectation = XCTestExpectation(
      description: "The return should be: `message` : `Hello Quan`"
    )
    
    let sample: Sample = try await instance.getObjectViaRequest(postRequest)
    
    if sample.message == "Hello Quan" {
      expectation.fulfill()
    }
    
    wait(for: [expectation], timeout: 5.0)
  }
  
  func testBadUrl() async throws {
    let copyRequest = postRequest
    copyRequest.encodedUrl = "https://api.m3o.com/v1/helloworld/Callllllllllll"
    do {
      let _: Sample = try await instance.getObjectViaRequest(copyRequest)
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
}
