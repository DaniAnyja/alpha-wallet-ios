import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import PriceFetcher

final class PriceFetcherTests: XCTestCase {
    private var fetcher: PriceFetcher!
    private var provider: MockTokenPriceProvider!

    override func setUp() {
        super.setUp()
        provider = MockTokenPriceProvider()
        fetcher = PriceFetcher(provider: provider)
    }

    override func tearDown() {
        fetcher = nil
        provider = nil
        super.tearDown()
    }

    func testFetchPriceSuccess() {
        provider.result = .success(1.23)

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

    func testFetchPriceFailure() {
        let error = NSError(domain: "test", code: 1)
        provider.result = .failure(error)

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

    func testHidePriceLabelWhenNetworkFails() {
        let error = NSError(domain: "test", code: 1)
        provider.result = .failure(error)

        let headerView = MockFungibleTokenHeaderView()

        let exp = expectation(description: "Hide price on failure")
        fetcher.fetchPriceUsd(for: "0x0") { result in
            switch result {
            case .success:
                XCTFail("Expected failure")
            case .failure:
                headerView.hideUsdPrice()
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertTrue(headerView.isPriceHidden)
    }
}

private final class MockTokenPriceProvider: TokenPriceProvider {
    var result: Result<Double, Error>!

    func fetchPriceUsd(for tokenAddress: String, completion: @escaping (Result<Double, Error>) -> Void) {
        completion(result)
    }
}

private final class MockFungibleTokenHeaderView {
    private(set) var isPriceHidden = false

    func hideUsdPrice() {
        isPriceHidden = true
    }
}

final class DexScreenerPriceProviderTests: XCTestCase {
    private var provider: DexScreenerPriceProvider!
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
        provider = DexScreenerPriceProvider(session: session)
    }

    override func tearDown() {
        provider = nil
        session = nil
        MockURLProtocol.stub = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testParsesResponseCorrectly() {
        let json = """
        {"pairs":[{"priceUsd":"1.23"}]}
        """.data(using: .utf8)
        MockURLProtocol.stub = (data: json, response: HTTPURLResponse(url: URL(string: "https://example.com")!, statusCode: 200,
                                                                        httpVersion: nil, headerFields: nil), error: nil)

        let exp = expectation(description: "Fetch price")
        provider.fetchPriceUsd(for: "0x0") { result in
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
        provider.fetchPriceUsd(for: "0x0") { result in
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

final class CustomURLPriceProviderTests: XCTestCase {
    private var provider: CustomURLPriceProvider!
    private var session: URLSession!
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = URL(string: "https://custom.example/price.json")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: configuration)
        provider = CustomURLPriceProvider(url: url, session: session)
    }

    override func tearDown() {
        provider = nil
        session = nil
        url = nil
        MockURLProtocol.stub = nil
        MockURLProtocol.lastRequest = nil
        super.tearDown()
    }

    func testInvokedWhenCustomURLConfigured() {
        let json = """
        {"pairs":[{"priceUsd":"1.23"}]}
        """.data(using: .utf8)
        MockURLProtocol.stub = (data: json, response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil), error: nil)

        let exp = expectation(description: "Fetch custom price")
        PriceFetcher(provider: provider).fetchPriceUsd(for: "ignored") { result in
            switch result {
            case .success(let price):
                XCTAssertEqual(price, 1.23)
            case .failure:
                XCTFail("Expected success")
            }
            exp.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(MockURLProtocol.lastRequest?.url, url)
    }
}

final class MockURLProtocol: URLProtocol {
    static var stub: (data: Data?, response: URLResponse?, error: Error?)?
    static var lastRequest: URLRequest?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
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
