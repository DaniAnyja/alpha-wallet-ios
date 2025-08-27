import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol TokenPriceProvider {
    func fetchPriceUsd(for tokenAddress: String, completion: @escaping (Result<Double, Error>) -> Void)
}

public enum DexScreenerPriceProviderError: Error {
    case invalidURL
    case noData
    case missingPrice
}

public struct DexScreenerPriceProvider: TokenPriceProvider {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchPriceUsd(for tokenAddress: String, completion: @escaping (Result<Double, Error>) -> Void) {
        guard let url = URL(string: "https://api.dexscreener.com/latest/tokens/v1/56/" + tokenAddress) else {
            completion(.failure(DexScreenerPriceProviderError.invalidURL))
            return
        }

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
