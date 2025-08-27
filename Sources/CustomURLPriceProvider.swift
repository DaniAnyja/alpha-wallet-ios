import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CustomURLPriceProvider: TokenPriceProvider {
    private let url: URL
    private let session: URLSession

    public init(url: URL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func fetchPriceUsd(for tokenAddress: String, completion: @escaping (Result<Double, Error>) -> Void) {
        session.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(DexScreenerPriceProviderError.noData))
                return
            }
            do {
                let response = try JSONDecoder().decode(DexScreenerResponse.self, from: data)
                if let priceString = response.pairs?.first?.priceUsd, let price = Double(priceString) {
                    completion(.success(price))
                } else {
                    completion(.failure(DexScreenerPriceProviderError.missingPrice))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }

    private struct DexScreenerResponse: Codable {
        let pairs: [Pair]?

        struct Pair: Codable {
            let priceUsd: String?
        }
    }
}

