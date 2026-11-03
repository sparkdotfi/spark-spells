// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import { SparkPayloadEthereum } from "../../SparkPayloadEthereum.sol";

/**
 * @title  October 22, 2026 Spark Ethereum Proposal
 * @author Phoenix Labs
 * @notice Spark Liquidity Layer:
 *         - Bridge sUSDS from the Ethereum ALM Proxy to the Arbitrum ALM Proxy.
 *         SparkLend:
 *         - Lower Slope 2 on the WETH Interest Rate Model.
 *         - Update the PYUSD, RLUSD and USDG Interest Rate Models.
 *         Spark Treasury:
 *         - Transfer the November 2026 monthly grants to the Spark Foundation and the Spark Assets Foundation.
 *         - Transfer USDS to the buyback executor to fund SPK buybacks.
 * Forum:  https://forum.skyeco.com/t/october-22-2026-proposed-changes-to-spark-for-upcoming-spell/28298
 * Vote:   https://snapshot.box/#/s:sparkfi.eth/proposal/0x47341f1ff9453d3f3c6b088ebe1137c17a14536dde08aed2581019ca7ccef2f8
 */
contract SparkEthereum_20261022 is SparkPayloadEthereum {

    address internal constant NEW_WETH_IRM             = 0xD5114e1E780f13eD82fB36440Dc4d381D7743C81;
    address internal constant NEW_PYUSD_RLUSD_USDG_IRM = 0x5EB8926757E75D06d3014633FF1705Cab8dB0a17;

    uint256 internal constant ARBITRUM_SUSDS_AMOUNT = 100_000_000e18;

    uint256 internal constant SPARK_FOUNDATION_GRANT_AMOUNT       = 865_000e18;
    uint256 internal constant SPARK_ASSET_FOUNDATION_GRANT_AMOUNT = 45_000e18;

    uint256 internal constant USDS_SPK_BUYBACK_AMOUNT = 341_970e18;

    function _postExecute() internal override {
        // 1. Bridge sUSDS from the Ethereum ALM Proxy to the Arbitrum ALM Proxy.
        _transferAssetFromAlmProxy(Ethereum.SUSDS, Ethereum.SPARK_PROXY, ARBITRUM_SUSDS_AMOUNT);
        _sendArbTokens(Ethereum.SUSDS, ARBITRUM_SUSDS_AMOUNT);

        // 2. Lower Slope 2 on the WETH Interest Rate Model.
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.WETH, NEW_WETH_IRM);

        // 3. Update the PYUSD, RLUSD and USDG Interest Rate Models.
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.PYUSD, NEW_PYUSD_RLUSD_USDG_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.RLUSD, NEW_PYUSD_RLUSD_USDG_IRM);
        LISTING_ENGINE.POOL_CONFIGURATOR().setReserveInterestRateStrategyAddress(Ethereum.USDG,  NEW_PYUSD_RLUSD_USDG_IRM);

        // 4. Transfer the November 2026 monthly grants to the Spark Foundation and the Spark Assets Foundation.
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_FOUNDATION_MULTISIG,       SPARK_FOUNDATION_GRANT_AMOUNT);
        IERC20(Ethereum.USDS).transfer(Ethereum.SPARK_ASSET_FOUNDATION_MULTISIG, SPARK_ASSET_FOUNDATION_GRANT_AMOUNT);

        // 5. Transfer USDS to the buyback executor to fund SPK buybacks.
        IERC20(Ethereum.USDS).transfer(Ethereum.ALM_OPS_MULTISIG, USDS_SPK_BUYBACK_AMOUNT);
    }

}
