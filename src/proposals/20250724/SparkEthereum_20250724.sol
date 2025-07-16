// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20 } from 'forge-std/interfaces/IERC20.sol';

import { IMetaMorpho, MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { IALMProxy } from 'spark-alm-controller/src/interfaces/IALMProxy.sol';

import { SparkPayloadEthereum, IEngine, EngineFlags } from "../../SparkPayloadEthereum.sol";

interface ITreasuryController {
    function transfer(
        address collector,
        address token,
        address recipient,
        uint256 amount
    ) external;
}

interface IController {
    function transferAsset(
        address asset,
        address destination,
        uint256 amount
    ) external;

    function grantRole(bytes32 role, address account) external;

    function revokeRole(bytes32 role, address account) external;
}

/**
 * @title  July 24, 2025 Spark Ethereum Proposal
 * @notice SparkLend:
 *         - Reduce WBTC Liquidation Threshold
 *         - Transfer BUIDL and JTRSY tokens to Grove
 *         SparkLend:
 *         - Transfer accumulated SparkLend ETH to multisig to be liquidated
 *         Spark USDS Vault:
 *         - Onboard PT-SPK-USDS Farm
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/july-24-2025-proposed-changes-to-spark-for-upcoming-spell/26796
 * Vote:   https://vote.sky.money/polling/QmP7RB2p
 *         https://vote.sky.money/polling/QmUYJ9YQ
 *         https://vote.sky.money/polling/QmaLxz19
 *         https://vote.sky.money/polling/Qme5qebN
 */
contract SparkEthereum_20250724 is SparkPayloadEthereum {

    address internal constant GROVE_ALM_PROXY                  = 0x491EDFB0B8b608044e227225C715981a30F3A44E;
    address internal constant LIQUIDATION_MULTISIG             = 0x2E1b01adABB8D4981863394bEa23a1263CBaeDfC;
    address internal constant PT_SPK_USDS_24SEP2025            = 0xC347584b415715B1b66774B2899Fef2FD3b56d6e;
    address internal constant PT_SPK_USDS_24SEP2025_PRICE_FEED = 0xaA31f21E3d23bF3A8F401E670171b0DA10F8466f;
    address internal constant SPARK_USDS_VAULT                 = 0xe41a0583334f0dc4E023Acd0bFef3667F6FE0597;

    function collateralsUpdates() public pure override returns (IEngine.CollateralUpdate[] memory) {
        IEngine.CollateralUpdate[] memory updates = new IEngine.CollateralUpdate[](1);

        updates[0] = IEngine.CollateralUpdate({
            asset:          Ethereum.WBTC,
            ltv:            EngineFlags.KEEP_CURRENT,
            liqThreshold:   35_00,
            liqBonus:       EngineFlags.KEEP_CURRENT,
            debtCeiling:    EngineFlags.KEEP_CURRENT,
            liqProtocolFee: EngineFlags.KEEP_CURRENT,
            eModeCategory:  EngineFlags.KEEP_CURRENT
        });

        return updates;
    }

    function _postExecute() internal override {
        ITreasuryController(Ethereum.TREASURY_CONTROLLER).transfer({
            collector: Ethereum.TREASURY,
            token:     Ethereum.WETH_ATOKEN,
            recipient: LIQUIDATION_MULTISIG,
            amount:    IERC20(Ethereum.WETH_ATOKEN).balanceOf(Ethereum.TREASURY)
        });

        // Grant controller role to Spark Proxy
        IController(Ethereum.ALM_PROXY).grantRole(
            IALMProxy(Ethereum.ALM_PROXY).CONTROLLER(),
            Ethereum.SPARK_PROXY
        );

        IALMProxy(Ethereum.ALM_PROXY).doCall(
            Ethereum.BUIDLI,
            abi.encodeCall(
                IERC20(Ethereum.BUIDLI).transfer,
                (GROVE_ALM_PROXY, IERC20(Ethereum.BUIDLI).balanceOf(Ethereum.ALM_PROXY))
            )
        );

        IALMProxy(Ethereum.ALM_PROXY).doCall(
            Ethereum.JTRSY,
            abi.encodeCall(
                IERC20(Ethereum.JTRSY).transfer,
                (GROVE_ALM_PROXY, IERC20(Ethereum.JTRSY).balanceOf(Ethereum.ALM_PROXY))
            )
        );

        // Revoke controller role from Spark Proxy
        IController(Ethereum.ALM_PROXY).revokeRole(
            IALMProxy(Ethereum.ALM_PROXY).CONTROLLER(),
            Ethereum.SPARK_PROXY
        );

        // Onboard PT-SPK-USDS Farm
        IMetaMorpho(SPARK_USDS_VAULT).submitCap(
            MarketParams({
                loanToken:       Ethereum.USDS,
                collateralToken: PT_SPK_USDS_24SEP2025,
                oracle:          PT_SPK_USDS_24SEP2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.965e18
            }),
            500_000_000e18
        );
    }

}
