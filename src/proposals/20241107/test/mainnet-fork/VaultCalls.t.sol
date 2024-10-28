// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.21;

import "./SparkEthereum_20241107TestBase.t.sol";

contract MainnetControllerMintUSDSTests is PostSpellExecutionEthereumTestBase {

    function test_mintUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            mainnetController.RELAYER()
        ));
        mainnetController.mintUSDS(1e18);
    }

    function test_mintUSDS_frozen() external {
        vm.prank(freezer);
        mainnetController.freeze();

        vm.prank(relayer);
        vm.expectRevert("MainnetController/not-active");
        mainnetController.mintUSDS(1e18);
    }

    function test_mintUSDS_rateLimitExceededBoundary() external {
        vm.startPrank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.mintUSDS(1_000_000e18 + 1);

        mainnetController.mintUSDS(1_000_000e18);
    }

    // Passes rate limit check, but can't mint because interest accrued on 9m USDS
    function test_mintUSDS_vatDebtCeilingExceededBoundary() external {
        vm.warp(block.timestamp + 1 seconds);

        vm.startPrank(relayer);
        vm.expectRevert("Vat/ceiling-exceeded");
        mainnetController.mintUSDS(1_000_000e18);

        // Demo original mint would have worked
        vm.warp(block.timestamp - 1 seconds);

        mainnetController.mintUSDS(1_000_000e18);
    }

    function test_mintUSDS() external {
        ( uint256 ink, uint256 art ) = vat.urns(ilk, VAULT);
        ( uint256 Art,,,, )          = vat.ilks(ilk);

        assertEq(vat.dai(USDS_JOIN), VAT_DAI_USDS_JOIN);

        assertEq(Art, USDS_MINT_AMOUNT);
        assertEq(ink, INK);
        assertEq(art, USDS_MINT_AMOUNT);

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usds.totalSupply(),                USDS_SUPPLY);

        vm.prank(relayer);
        mainnetController.mintUSDS(1_000_000e18);

        ( ink, art ) = vat.urns(ilk, VAULT);
        ( Art,,,, )  = vat.ilks(ilk);

        assertEq(vat.dai(USDS_JOIN), VAT_DAI_USDS_JOIN + 1_000_000e45);

        assertEq(Art, USDS_MINT_AMOUNT + 1_000_000e18);
        assertEq(ink, INK);
        assertEq(art, USDS_MINT_AMOUNT + 1_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.totalSupply(),                USDS_SUPPLY + 1_000_000e18);
    }

    function test_mintUSDS_rateLimited() external {
        bytes32 key = mainnetController.LIMIT_USDS_MINT();
        vm.startPrank(relayer);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e18);
        assertEq(usds.balanceOf(address(almProxy)),   0);

        mainnetController.mintUSDS(400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 600_000e18);
        assertEq(usds.balanceOf(address(almProxy)),   400_000e18);

        skip(1 hours);

        // Rate limit increases by 500k per day (133 wei rounding error)
        assertEq(rateLimits.getCurrentRateLimit(key), 600_000e18 + uint256(500_000e18) / 24 - 133);
        assertEq(usds.balanceOf(address(almProxy)),   400_000e18);

        // Can't mint full 600k cause vat ceiling gets hit because of 1 hour of interest
        mainnetController.mintUSDS(600_000e18 - 100e18);

        assertEq(rateLimits.getCurrentRateLimit(key), uint256(500_000e18) / 24 - 133 + 100e18);
        assertEq(usds.balanceOf(address(almProxy)),   999_900e18);

        skip(23 hours);

        // Rate limit goes up to 500k + 100 (3200 rounding error)
        assertEq(rateLimits.getCurrentRateLimit(key), uint256(500_000e18) + 100e18 - 3200);

        // NOTE: This test is skipped because the vat ceiling is lower than the rate limits
        // vm.expectRevert("RateLimits/rate-limit-exceeded");
        // mainnetController.mintUSDS(1);
    }

}

contract MainnetControllerBurnUSDSTests is PostSpellExecutionEthereumTestBase {

    function test_burnUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            mainnetController.RELAYER()
        ));
        mainnetController.burnUSDS(1e18);
    }

    function test_burnUSDS_frozen() external {
        vm.prank(freezer);
        mainnetController.freeze();

        vm.prank(relayer);
        vm.expectRevert("MainnetController/not-active");
        mainnetController.burnUSDS(1e18);
    }

    function test_burnUSDS() external {
        // Setup
        vm.prank(relayer);
        mainnetController.mintUSDS(1_000_000e18);

        ( uint256 ink, uint256 art ) = vat.urns(ilk, VAULT);
        ( uint256 Art,,,, )          = vat.ilks(ilk);

        assertEq(vat.dai(USDS_JOIN), VAT_DAI_USDS_JOIN + 1_000_000e45);

        assertEq(Art, USDS_MINT_AMOUNT + 1_000_000e18);
        assertEq(ink, INK);
        assertEq(art, USDS_MINT_AMOUNT + 1_000_000e18);

        assertEq(usds.balanceOf(address(almProxy)), 1_000_000e18);
        assertEq(usds.totalSupply(),                USDS_SUPPLY + 1_000_000e18);

        vm.prank(relayer);
        mainnetController.burnUSDS(1_000_000e18);

        ( ink, art ) = vat.urns(ilk, VAULT);
        ( Art,,,, )  = vat.ilks(ilk);

        assertEq(vat.dai(USDS_JOIN), VAT_DAI_USDS_JOIN);

        assertEq(Art, USDS_MINT_AMOUNT);
        assertEq(ink, INK);
        assertEq(art, USDS_MINT_AMOUNT);

        assertEq(usds.balanceOf(address(almProxy)), 0);
        assertEq(usds.totalSupply(),                USDS_SUPPLY);
    }

    function test_burnUSDS_rateLimited() external {
        bytes32 key = mainnetController.LIMIT_USDS_MINT();
        vm.startPrank(relayer);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e18);
        assertEq(usds.balanceOf(address(almProxy)),   0);

        mainnetController.mintUSDS(1_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);
        assertEq(usds.balanceOf(address(almProxy)),   1_000_000e18);

        mainnetController.burnUSDS(400_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 400_000e18);
        assertEq(usds.balanceOf(address(almProxy)),   600_000e18);

        skip(24 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 900_000e18 - 3200);  // Rounding
        assertEq(usds.balanceOf(address(almProxy)),   600_000e18);

        mainnetController.burnUSDS(600_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 1_000_000e18);  // Goes back to max
        assertEq(usds.balanceOf(address(almProxy)),   0);

        vm.stopPrank();
    }

}
