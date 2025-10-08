// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.25;

import { IERC20, SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { Ethereum } from "spark-address-registry/Ethereum.sol";

import {
    ControllerInstance,
    ForeignControllerInit
} from "spark-alm-controller/deploy/ForeignControllerInit.sol";

import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";

import { SparkPayloadAvalanche, Avalanche, SLLHelpers } from "../../SparkPayloadAvalanche.sol";

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

interface ISparkVaultV2 {
    function asset() external view returns (address);
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function grantRole(bytes32 role, address account) external;
    function setDepositCap(uint256 newCap) external;
    function SETTER_ROLE() external view returns (bytes32);
    function setVsrBounds(uint256 minVsr_, uint256 maxVsr_) external;
    function TAKER_ROLE() external view returns (bytes32);
}

/**
 * @title  Oct 16, 2025 Spark Avalanche Proposal
 * @notice Spark Liquidity Layer:
 *         - Onboard Avalanche to Spark Liquidity Layer
 *         - Onboard Aave v3 Avalanche USDC
 * @author Phoenix Labs
 * Forum:  https://forum.sky.money/t/october-16-2025-proposed-changes-to-spark-for-upcoming-spell/27215
 * Vote:   
 */
contract SparkAvalanche_20251016 is SparkPayloadAvalanche {

    // > bc -l <<< 'scale=27; e( l(1.1)/(60 * 60 * 24 * 365) )'
    //   1.000000003022265980097387650
    uint256 internal constant TEN_PCT_APY = 1.000000003022265980097387650e27;

    function execute() external {
        ForeignControllerInit.MintRecipient[] memory mintRecipients = new ForeignControllerInit.MintRecipient[](1);
        mintRecipients[0] = ForeignControllerInit.MintRecipient({
            domain        : CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM,
            mintRecipient : SLLHelpers.addrToBytes32(Ethereum.ALM_PROXY)
        });
        ForeignControllerInit.LayerZeroRecipient[] memory layerZeroRecipients = new ForeignControllerInit.LayerZeroRecipient[](0);

        address[] memory relayers = new address[](1);
        relayers[0] = Avalanche.ALM_RELAYER;

        ForeignControllerInit.initAlmSystem({
            controllerInst: ControllerInstance({
                almProxy   : Avalanche.ALM_PROXY,
                controller : Avalanche.ALM_CONTROLLER,
                rateLimits : Avalanche.ALM_RATE_LIMITS
            }),
            configAddresses: ForeignControllerInit.ConfigAddressParams({
                freezer       : Avalanche.ALM_FREEZER,
                relayers      : relayers,
                oldController : address(0)
            }),
            checkAddresses: ForeignControllerInit.CheckAddressParams({
                admin : Avalanche.SPARK_EXECUTOR,
                psm   : address(0),
                cctp  : Avalanche.CCTP_TOKEN_MESSENGER,
                usdc  : Avalanche.USDC,
                usds  : address(0),
                susds : address(0)
            }),
            mintRecipients:      mintRecipients,
            layerZeroRecipients: layerZeroRecipients,
            checkPsm:            false
        });

        // Activate Spark Liquidity Layer on Avalanche
        IRateLimits(Avalanche.ALM_RATE_LIMITS).setUnlimitedRateLimitData(
            ForeignController(Avalanche.ALM_CONTROLLER).LIMIT_USDC_TO_CCTP()
        );

        SLLHelpers.setRateLimitData(
            RateLimitHelpers.makeDomainKey(
                ForeignController(Avalanche.ALM_CONTROLLER).LIMIT_USDC_TO_DOMAIN(),
                0  // Ethereum domain id (https://developers.circle.com/stablecoins/evm-smart-contracts)
            ),
            Avalanche.ALM_RATE_LIMITS,
            100_000_000e6,
            50_000_000e6 / uint256(1 days),
            6
        );

        ForeignController(Avalanche.ALM_CONTROLLER).grantRole(ForeignController(Avalanche.ALM_CONTROLLER).RELAYER(), Avalanche.ALM_RELAYER2);

        // --- Launch Savings v2 Vaults for USDC ---
        _configureVaultsV2({
            vault_        : Avalanche.SPARK_VAULT_V2_SPUSDC,
            supplyCap     : 50_000_000e6,
            minVsr        : 1e27,
            maxVsr        : TEN_PCT_APY,
            depositAmount : 1e6
        });

        _configureAaveToken(
            Avalanche.SPARK_VAULT_V2_SPUSDC,
            50_000_000e6,
            50_000_000e6 / uint256(1 days)
        );
    }

    function _configureVaultsV2(
        address vault_,
        uint256 supplyCap,
        uint256 minVsr,
        uint256 maxVsr,
        uint256 depositAmount
    ) internal {
        ISparkVaultV2     vault      = ISparkVaultV2(vault_);
        IRateLimits       rateLimits = IRateLimits(Avalanche.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Avalanche.ALM_CONTROLLER);

        // Grant SETTER_ROLE to Spark Operations Safe
        vault.grantRole(vault.SETTER_ROLE(), Ethereum.ALM_OPS_MULTISIG);

        // Grant TAKER_ROLE to Alm Proxy
        vault.grantRole(vault.TAKER_ROLE(), Ethereum.ALM_PROXY);

        // Set VSR bounds
        vault.setVsrBounds(minVsr, maxVsr);

        // Set the supply cap
        vault.setDepositCap(supplyCap);

        // Deposit into the vault
        SafeERC20.safeIncreaseAllowance(IERC20(vault.asset()), vault_, depositAmount);
        vault.deposit(depositAmount, address(1));

        rateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetKey(
                controller.LIMIT_SPARK_VAULT_TAKE(),
                address(vault)
            )
        );

        rateLimits.setUnlimitedRateLimitData(
            RateLimitHelpers.makeAssetDestinationKey(
                controller.LIMIT_ASSET_TRANSFER(),
                vault.asset(),
                address(vault)
            )
        );
    }

}
