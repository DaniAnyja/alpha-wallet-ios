import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PriceFetcher

final class PriceFetcherTests: XCTestCase {
    private var fetcher: PriceFetcher!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
        fetcher = PriceFetcher(session: session)
    }

    override func tearDown() {
        fetcher = nil
        session = nil
        MockURLProtocol.stub = nil
        super.tearDown()
    }

    func testFetchPriceSuccess() {
        let json = """
        {"pairs":[{"priceUsd":"1.23"}]}
        """.data(using: .utf8)
        MockURLProtocol.stub = (data: json, response: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200, httpVersion: nil, headerFields: nil), error: nil)

        let exp = expectation(description: "Fetch price")
        fetcher.fetchPriceUsd(for: "0x0") { result in
            switch result {
            case .success(let price):
                XCTAssertEqual(price, 1.23)
            case .failure:
                XCTFail("Expected success")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }

    func testFetchPriceNetworkFailure() {
        let error = NSError(domain: "test", code: 1)
        MockURLProtocol.stub = (data: nil, response: nil, error: error)

        let exp = expectation(description: "Fetch price fails")
        fetcher.fetchPriceUsd(for: "0x0") { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure(let err):
                XCTAssertEqual((err as NSError).domain, "test")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
    }
}

final class MockURLProtocol: URLProtocol {
    static var stub: (data: Data?, response: URLResponse?, error: Error?)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = MockURLProtocol.stub?.error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            if let response = MockURLProtocol.stub?.response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            if let data = MockURLProtocol.stub?.data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
