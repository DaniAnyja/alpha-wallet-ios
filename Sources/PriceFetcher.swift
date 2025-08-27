import Foundation

public final class PriceFetcher {
    private let provider: TokenPriceProvider

    public init(provider: TokenPriceProvider = DexScreenerPriceProvider()) {
        self.provider = provider
    }

    public func fetchPriceUsd(for tokenAddress: String, completion: @escaping (Result<Double, Error>) -> Void) {
        provider.fetchPriceUsd(for: tokenAddress, completion: completion)
    }
}
