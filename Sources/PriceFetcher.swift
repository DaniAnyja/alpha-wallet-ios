import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum PriceFetcherError: Error {
    case invalidURL
    case noData
    case missingPrice
}

public final class PriceFetcher {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchPriceUsd(for tokenAddress: String, completion: @escaping (Result<Double, Error>) -> Void) {
        guard let url = URL(string: "https://api.dexscreener.com/latest/tokens/v1/56/" + tokenAddress) else {
            completion(.failure(PriceFetcherError.invalidURL))
            return
        }

        session.dataTask(with: url) { data, _, error in
            if let error = error {
                completion(.failure(error))
                return
            }
            guard let data = data else {
                completion(.failure(PriceFetcherError.noData))
                return
            }
            do {
                let response = try JSONDecoder().decode(DexScreenerResponse.self, from: data)
                if let priceString = response.pairs?.first?.priceUsd, let price = Double(priceString) {
                    completion(.success(price))
                } else {
                    completion(.failure(PriceFetcherError.missingPrice))
                }
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

struct DexScreenerResponse: Codable {
    let pairs: [Pair]?

    struct Pair: Codable {
        let priceUsd: String?
    }
}
