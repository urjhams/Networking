# Networking
Formalized API requests calling by using URLSession.

<p align="left">
<a href="https://developer.apple.com/swift"><img src="https://img.shields.io/badge/language-Swift%205.5-brightgreen" alt="Swift 5" /></a>
<img src="https://img.shields.io/badge/platform-iOS-blue.svg?style=flat" alt="Platform iOS" />
<img src="https://img.shields.io/badge/platform-iPadOS-red.svg?style=flat" alt="Platform iPadOS" />
<img src="https://img.shields.io/badge/platform-watchOS-orange.svg?style=flat" alt="Platform watchOS" />
<img src="https://img.shields.io/badge/platform-macOS-cyan.svg?style=flat" alt="Platform macOS" />
<img src="https://img.shields.io/badge/platform-tvOS-purple.svg?style=flat" alt="Platform tvOS" />
<img src="https://img.shields.io/badge/platform-Catalyst-brown.svg?style=flat" alt="Platform macCatalyst" />
<a href="https://raw.githubusercontent.com/urjhams/Networking/main/LICENSE"><img src="https://img.shields.io/badge/license-MIT-red" alt="License: MIT" /></a>
</p>

## Installation

### Swift Package Manager

```Swift
dependencies: [
        .package(
            url: "git@github.com:urjhams/Networking.git",
            from: "1.0.0"
        )
    ]
```

## Usage

### Get the Networking instance
```Swift
let networking = Network.shared
```

### The Request object
With any Http request call, a single request object is used as the input. Create a `Request` object will automatically prepare the neccessary components for the request to use like header, parameter, etc. We can then later extract an `URLRequest` from this `Request` object.
```Swift
let postRequest = Request(
    from: "https://api.m3o.com/v1/helloworld/Call",
    as: .post,
    authorization: .bearerToken(
      token: "YzhiYmFlNTUtNDE2Mi00MDk5LTg1Y2UtNmNmZDFmMWE1MzY2"
    ),
    parameters: ["name" : "Quan"]
  )
```

### Standard call with callbacks
```Swift
// send a request with call back
networking.sendRequest(postRequest) { result in
  switch result {
  case .success(let data):
    // do smth with the data
  case .failure(let error):
    // do smth with the error
  }
}

// get a decoded json object from a request task
networking.getObjectViaRequest(
    postRequest
  ) { (result: Networking.GenericResult<Sample>) in
    switch result {
    case .success(let sample):
      // do smth with the success model with type `Sample`
    case .failure(_):
      break
  }
}
```

### Concurrency with async / await (available from iOS 13+, watchOS 6+, macOS 11+)
`getObjectViaRequest(_:)` has a supported version for concurrency. All we need to do is declare the output with the expected Type for the generic requirement and apply `try await`.
```Swift
  let sample: Sample = try await networking.getObjectViaRequest(postRequest)
  // do smth with the success model with type `Sample`
  
  // to simply get Data and HttpResponse:
  let (data, response) = try await networking.sendRequest(postRequest)
```

### Connectivity Observing
from iOS 12.0+, macOS 10.14+, the connectivity can be monitor via the `monitor` object. This object is a static object. All we need to do is append the desired handle via `Network.Connectivity.monitorChangeHandlers` static property. This stack up a list of handles we want call whenever there is a change of each network availibility state, and we can stack a handle from everywhere in the project.
```Swift
let handler: Networking.Connectivity.Handler  = { state in
  switch state {
  case .available:
    // do smth
  case .unavailable:
    // do smth
  case .noConnection:
    // do smth
  }
}

Network.Connectivity.monitorChangeHandlers.append(handler)
```
