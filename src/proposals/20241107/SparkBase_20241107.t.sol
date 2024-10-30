// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.10;

import 'src/SparkTestBase.sol';

import { CCTPForwarder } from "xchain-helpers/forwarders/CCTPForwarder.sol";

import { IALMProxy }         from "spark-alm-controller/src/interfaces/IALMProxy.sol";
import { IRateLimits }       from "spark-alm-controller/src/interfaces/IRateLimits.sol";
import { ForeignController } from "spark-alm-controller/src/ForeignController.sol";
import { RateLimitHelpers }  from "spark-alm-controller/src/RateLimitHelpers.sol";

import { IPSM3 } from "spark-psm/src/interfaces/IPSM3.sol";

contract SparkBase_20241107Test is SparkBaseTestBase {

    constructor() {
        id = '20241107';
    }

    function setUp() public {
        vm.createSelectFork(getChain('base').rpcUrl, 21752609);  // Oct 30, 2024
        payload = deployPayload();
    }

    function testALMControllerDeployment() public {
        // Copied from the init library, but no harm checking this here
        IALMProxy almProxy           = IALMProxy(Base.ALM_PROXY);
        IRateLimits rateLimits       = IRateLimits(Base.ALM_RATE_LIMITS);
        ForeignController controller = ForeignController(Base.ALM_CONTROLLER);

        assertEq(almProxy.hasRole(0x0, Base.SPARK_EXECUTOR), true,   "incorrect-admin-almProxy");
        assertEq(rateLimits.hasRole(0x0, Base.SPARK_EXECUTOR), true, "incorrect-admin-rateLimits");
        assertEq(controller.hasRole(0x0, Base.SPARK_EXECUTOR), true, "incorrect-admin-controller");

        assertEq(address(controller.proxy()),      Base.ALM_PROXY,            "incorrect-almProxy");
        assertEq(address(controller.rateLimits()), Base.ALM_RATE_LIMITS,      "incorrect-rateLimits");
        assertEq(address(controller.psm()),        Base.PSM3,                 "incorrect-psm");
        assertEq(address(controller.usdc()),       Base.USDC,                 "incorrect-usdc");
        assertEq(address(controller.cctp()),       Base.CCTP_TOKEN_MESSENGER, "incorrect-cctp");

        assertEq(controller.active(), true, "controller-not-active");
    }

    function testPSM3Deployment() public {
        // Copied from the init library, but no harm checking this here
        IPSM3 psm = IPSM3(Base.PSM3);

        // Verify that the shares are burned (IE owned by the zero address)
        assertGe(psm.shares(address(0)), 1e18, "psm-totalShares-not-seeded");

        assertEq(address(psm.usdc()),  Base.USDC,  "psm-incorrect-usdc");
        assertEq(address(psm.usds()),  Base.USDS,  "psm-incorrect-usds");
        assertEq(address(psm.susds()), Base.SUSDS, "psm-incorrect-susds");
    }

    function testALMControllerConfiguration() public {
        ForeignController c = ForeignController(Base.ALM_CONTROLLER);

        executePayload(payload);

        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(c.LIMIT_PSM_DEPOSIT(), Base.USDC),
            4_000_000e6,
            2_000_000e6 / uint256(1 days)
        );
        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(c.LIMIT_PSM_WITHDRAW(), Base.USDC),
            7_000_000e6,
            2_000_000e6 / uint256(1 days)
        );
        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(c.LIMIT_PSM_DEPOSIT(), Base.USDS),
            5_000_000e18,
            2_000_000e18 / uint256(1 days)
        );
        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(c.LIMIT_PSM_WITHDRAW(), Base.USDS),
            type(uint256).max,
            0
        );
        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(c.LIMIT_PSM_DEPOSIT(), Base.SUSDS),
            8_000_000e18,
            2_000_000e18 / uint256(1 days)
        );
        _assertRateLimit(
            RateLimitHelpers.makeAssetKey(c.LIMIT_PSM_WITHDRAW(), Base.SUSDS),
            type(uint256).max,
            0
        );
        _assertRateLimit(c.LIMIT_USDC_TO_CCTP(), type(uint256).max, 0);
        _assertRateLimit(
            RateLimitHelpers.makeDomainKey(c.LIMIT_USDC_TO_DOMAIN(), CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM),
            4_000_000e6,
            2_000_000e6 / uint256(1 days)
        );

        assertEq(c.mintRecipients(CCTPForwarder.DOMAIN_ID_CIRCLE_ETHEREUM), bytes32(uint256(uint160(Ethereum.ALM_PROXY))));
    }

    function _assertRateLimit(
        bytes32 key,
        uint256 maxAmount,
        uint256 slope
    ) internal {
        IRateLimits.RateLimitData memory rateLimit = IRateLimits(Base.ALM_RATE_LIMITS).getRateLimitData(key);
        assertEq(rateLimit.maxAmount,   maxAmount);
        assertEq(rateLimit.slope,       slope);
        assertEq(rateLimit.lastAmount,  maxAmount);
        assertEq(rateLimit.lastUpdated, block.timestamp);
    }
    
}
