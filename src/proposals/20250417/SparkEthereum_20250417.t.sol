// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/test-harness/SparkTestBase.sol';

import { IERC20 }   from 'forge-std/interfaces/IERC20.sol';
import { IERC4626 } from 'forge-std/interfaces/IERC4626.sol';

import { MarketParams } from 'metamorpho/interfaces/IMetaMorpho.sol';

import { Arbitrum } from 'spark-address-registry/Arbitrum.sol';
import { Base }     from 'spark-address-registry/Base.sol';
import { Ethereum } from 'spark-address-registry/Ethereum.sol';

import { MainnetController } from 'spark-alm-controller/src/MainnetController.sol';
import { RateLimitHelpers }  from 'spark-alm-controller/src/RateLimitHelpers.sol';

import { ChainIdUtils }  from 'src/libraries/ChainId.sol';

import { SparkLiquidityLayerContext } from "../../test-harness/SparkLiquidityLayerTests.sol";

interface IInvestmentManager {
    function fulfillCancelDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 fulfillment
    ) external;
    function fulfillCancelRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 shares
    ) external;
    function fulfillDepositRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;
    function fulfillRedeemRequest(
        uint64 poolId,
        bytes16 trancheId,
        address user,
        uint128 assetId,
        uint128 assets,
        uint128 shares
    ) external;
}

interface ISuperstateToken is IERC20 {
    function calculateSuperstateTokenOut(uint256, address)
        external view returns (uint256, uint256, uint256);
}

interface IMapleTokenExtended is IERC4626 {
    function manager() external view returns (address);
}

interface IWithdrawalManagerLike {
    function processRedemptions(uint256 maxSharesToProcess) external;
}

interface IPoolManagerLike {
    function withdrawalManager() external view returns (IWithdrawalManagerLike);
    function poolDelegate() external view returns (address);
}

interface IBuidlLike is IERC20 {
    function issueTokens(address to, uint256 amount) external;
}

contract SparkEthereum_20250417Test is SparkTestBase {

    address internal constant ETHEREUM_OLD_ALM_CONTROLLER = Ethereum.ALM_CONTROLLER;
    address internal constant ETHEREUM_NEW_ALM_CONTROLLER = 0xF8Dff673b555a225e149218C5005FC88f4a13870;

    address internal constant PT_SUSDE_31JUL2025_PRICE_FEED = address(0);  // TODO
    address internal constant PT_SUSDE_31JUL2025            = address(0);  // TODO

    constructor() {
        id = '20250417';
    }

    function setUp() public {
        setupDomains("2025-04-07T15:00:00Z");

        deployPayloads();

        //chainSpellMetadata[ChainIdUtils.ArbitrumOne()].payload = 0x545eeEc8Ca599085cE86ada51eb8c0c35Af1e9d6;
        //chainSpellMetadata[ChainIdUtils.Ethereum()].payload    = 0x6B34C0E12C84338f494efFbf49534745DDE2F24b;
    }

    // Overriding because of upgrade
    function _getLatestControllers() internal pure override returns (address, address, address) {
        return (
            ETHEREUM_NEW_ALM_CONTROLLER,
            Arbitrum.ALM_CONTROLLER,
            Base.ALM_CONTROLLER
        );
    }

    function test_ETHEREUM_controllerUpgrade() public onChain(ChainIdUtils.Ethereum()) {
        _testControllerUpgrade({
            oldController: ETHEREUM_OLD_ALM_CONTROLLER,
            newController: ETHEREUM_NEW_ALM_CONTROLLER
        });
    }

    function test_ETHEREUM_morpho_PTSUSDE31JUL2025Onboarding() public onChain(ChainIdUtils.Ethereum()) {
        _testMorphoCapUpdate({
            vault: Ethereum.MORPHO_VAULT_DAI_1,
            config: MarketParams({
                loanToken:       Ethereum.DAI,
                collateralToken: PT_SUSDE_31JUL2025,
                oracle:          PT_SUSDE_31JUL2025_PRICE_FEED,
                irm:             Ethereum.MORPHO_DEFAULT_IRM,
                lltv:            0.915e18
            }),
            currentCap: 0,
            newCap:     400_000_000e18
        });
        _testMorphoPendlePTOracleConfig({
            pt:           PT_SUSDE_31JUL2025,
            oracle:       PT_SUSDE_31JUL2025_PRICE_FEED,
            discount:     0.2e18,
            currentPrice: 0.960818791222729579e36
        });
    }

}
