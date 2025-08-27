//
//  FungibleTokenDetailsViewController.swift
//  AlphaWallet
//
//  Created by Vladyslav Shepitko on 19.11.2022.
//

import Combine
import os.log
import UIKit

import AlphaWalletFoundation
import PriceFetcher

private let logger = Logger(subsystem: MyApp.appBundleIdentifier, category: "UI")

protocol FungibleTokenDetailsViewControllerDelegate: AnyObject, CanOpenURL {
    func didTapSwap(swapTokenFlow: SwapTokenFlow, in viewController: FungibleTokenDetailsViewController)
    func didTapBridge(for token: Token, service: TokenActionProvider, in viewController: FungibleTokenDetailsViewController)
    func didTapBuy(for token: Token, service: TokenActionProvider, in viewController: FungibleTokenDetailsViewController)
    func didTapSend(for token: Token, in viewController: FungibleTokenDetailsViewController)
    func didTapReceive(for token: Token, in viewController: FungibleTokenDetailsViewController)
    func tokenScriptViewController(forFungibleContract: AlphaWallet.Address, server: RPCServer) -> UIViewController?
}

class FungibleTokenDetailsViewController: UIViewController {
    private let containerView: ScrollableStackView = ScrollableStackView()
    private let buttonsBar = HorizontalButtonsBar(configuration: .empty)
    private lazy var headerView: FungibleTokenHeaderView = {
        let view = FungibleTokenHeaderView(viewModel: viewModel.headerViewModel)
        view.delegate = self

        return view
    }()
    private lazy var chartView: TokenHistoryChartView = {
        let chartView = TokenHistoryChartView(viewModel: viewModel.chartViewModel)
        return chartView
    }()

    private let viewModel: FungibleTokenDetailsViewModel
    private var cancelable = Set<AnyCancellable>()
    private let willAppear = PassthroughSubject<Void, Never>()
    private let action = PassthroughSubject<TokenInstanceAction, Never>()

    weak var delegate: FungibleTokenDetailsViewControllerDelegate?

    init(viewModel: FungibleTokenDetailsViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)

        let footerBar = ButtonsBarBackgroundView(buttonsBar: buttonsBar)
        view.addSubview(footerBar)
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.topAnchor.constraint(equalTo: view.topAnchor),
            containerView.bottomAnchor.constraint(equalTo: footerBar.topAnchor),

            footerBar.anchorsConstraint(to: view),
        ])

        buttonsBar.viewController = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Configuration.Color.Semantic.defaultViewBackground
        bind(viewModel: viewModel)
        fetchPrice()

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Custom Price API", style: .plain, target: self, action: #selector(promptCustomPriceApi))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        willAppear.send(())
    }

    private func buildSubviews(for viewTypes: [FungibleTokenDetailsViewModel.ViewType]) -> [UIView] {
        var subviews: [UIView] = []
        subviews += [headerView]

        for each in viewTypes {
            switch each {
            case .testnet:
                subviews += [UIView.spacer(height: 40)]
                subviews += [UIView.spacer(backgroundColor: Configuration.Color.Semantic.tableViewSeparator)]

                let view = TestnetTokenInfoView()
                view.configure(viewModel: .init())

                subviews += [view]
            case .charts:
                subviews += [chartView]

                subviews += [UIView.spacer(height: 10)]
                subviews += [UIView.spacer(backgroundColor: Configuration.Color.Semantic.tableViewSeparator)]
                subviews += [UIView.spacer(height: 10)]
            case .field(let viewModel):
                let view = TokenAttributeView(indexPath: IndexPath(row: 0, section: 0))
                view.configure(viewModel: viewModel)

                subviews += [view]
            case .header(let viewModel):
                let view = TokenInfoHeaderView()
                view.configure(viewModel: viewModel)

                subviews += [view]
            }
        }

        return subviews
    }

    private func layoutSubviews(_ subviews: [UIView]) {
        containerView.stackView.removeAllArrangedSubviews()
        containerView.stackView.addArrangedSubviews(subviews)
    }

    private func bind(viewModel: FungibleTokenDetailsViewModel) {
        let input = FungibleTokenDetailsViewModelInput(
            willAppear: willAppear.eraseToAnyPublisher(),
            action: action.eraseToAnyPublisher())

        let output = viewModel.transform(input: input)
        output.viewState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] viewState in
                guard let strongSelf = self else { return }

                strongSelf.layoutSubviews(strongSelf.buildSubviews(for: viewState.views))
                strongSelf.configureActionButtons(with: viewState.actionButtons)
            }.store(in: &cancelable)

        output.action
            .sink { [weak self] action in self?.perform(action: action) }
            .store(in: &cancelable)
    }

    private func fetchPrice() {
        headerView.hideUsdPrice()

        let provider: TokenPriceProvider?
        if let url = Config.customPriceURL(for: viewModel.token.contractAddress) {
            provider = CustomURLPriceProvider(url: url)
        } else if viewModel.token.server == .binance_smart_chain {
            provider = DexScreenerPriceProvider()
        } else {
            provider = nil
        }

        guard let provider else { return }

        let tokenAddress = viewModel.token.contractAddress.eip55String
        PriceFetcher(provider: provider).fetchPriceUsd(for: tokenAddress) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let price):
                    self?.headerView.updateUsdPrice(price)
                case .failure:
                    self?.headerView.hideUsdPrice()
                }
            }
        }
    }

    @objc private func promptCustomPriceApi() {
        let alert = UIAlertController(title: "Custom Price API", message: "Enter URL", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = "https://example.com/price.json"
            if let existing = Config.customPriceURL(for: self.viewModel.token.contractAddress) {
                textField.text = existing.absoluteString
            }
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self] _ in
            guard let self = self else { return }
            guard let text = alert.textFields?.first?.text,
                  let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
                self.showInvalidUrlAlert()
                return
            }
            Config.setCustomPriceURL(url, for: self.viewModel.token.contractAddress)
            self.fetchPrice()
        })
        present(alert, animated: true)
    }

    private func showInvalidUrlAlert() {
        let alert = UIAlertController(title: "Invalid URL", message: "Please enter a valid URL.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    private func configureActionButtons(with buttons: [TokenInstanceActionButton]) {
        buttonsBar.configure(.combined(buttons: buttons.count))

        for (button, view) in zip(buttons, buttonsBar.buttons) {
            view.setTitle(button.name, for: .normal)

            view.publisher(forEvent: .touchUpInside)
                .map { _ in button.actionType }
                .multicast(subject: action)
                .connect()
                .store(in: &buttonsBar.cancellable)

            switch button.state {
            case .isEnabled(let isEnabled):
                view.isEnabled = isEnabled
            case .isDisplayed(let isDisplayed):
                view.displayButton = isDisplayed
            case .noOption:
                continue
            }
        }
    }

    private func perform(action: FungibleTokenDetailsViewModel.FungibleTokenAction) {
        switch action {
        case .swap(let flow):
            delegate?.didTapSwap(swapTokenFlow: flow, in: self)
        case .erc20Transfer(let token):
            delegate?.didTapSend(for: token, in: self)
        case .erc20Receive(let token):
            delegate?.didTapReceive(for: token, in: self)
        case .display(let warning):
            show(message: warning)
        case .bridge(let token, let service):
            delegate?.didTapBridge(for: token, service: service, in: self)
        case .buy(let token, let service):
            delegate?.didTapBuy(for: token, service: service, in: self)
        case .tokenScriptViewer(let token):
            if let viewController = delegate?.tokenScriptViewController(forFungibleContract: token.contractAddress, server: token.server) {
                logger.info("Opening TokenScript Viewer for fungible: \(token.contractAddress) server: \(token.server.chainID)")
                navigationController?.present(viewController, animated: true, completion: nil)
            } else {
                logger.info("No TokenScript Viewer to open for fungible: \(token.contractAddress) server: \(token.server.chainID)")
            }
        }
    }

    private func show(message: String) {
        UIAlertController.alert(message: message, alertButtonTitles: [R.string.localizable.oK()], alertButtonStyles: [.default], viewController: self)
    }

}

extension FungibleTokenDetailsViewController: FungibleTokenHeaderViewDelegate {
    func didPressViewContractWebPage(inHeaderView: FungibleTokenHeaderView) {
        delegate?.didPressViewContractWebPage(forContract: viewModel.token.contractAddress, server: viewModel.token.server, in: self)
    }
}
