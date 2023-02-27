// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IWETHGateway} from "src/interfaces/IWETHGateway.sol";

import {WETHGateway} from "src/extensions/WETHGateway.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationWETHGateway is IntegrationTest {
    uint256 internal constant MIN_AMOUNT = 1e9;
    uint256 internal constant MAX_ITERATIONS = 10;

    IWETHGateway internal wethGateway;

    function setUp() public override {
        super.setUp();

        wethGateway = new WETHGateway(address(morpho));
    }

    /// @dev Assumes the receiver is able to receive ETH without reverting.
    function _assumeReceiver(address receiver) internal {
        (bool success,) = receiver.call("");
        vm.assume(success);
    }

    function invariantWETHAllowance() public {
        assertEq(ERC20(weth).allowance(address(wethGateway), address(morpho)), type(uint256).max);
    }

    function invariantETHBalance() public {
        assertEq(address(wethGateway).balance, 0);
    }

    function invariantWETHBalance() public {
        assertEq(ERC20(weth).balanceOf(address(wethGateway)), 0);
    }

    function testCannotSendETHToWETHGateway(uint256 amount) public {
        deal(address(this), amount);
        vm.expectRevert(abi.encodeWithSelector(WETHGateway.OnlyWETH.selector));
        payable(wethGateway).transfer(amount);
    }

    function testSupplyETH(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        assertEq(morpho.supplyBalance(weth, onBehalf), 0);

        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        uint256 onBehalfBalanceBefore = onBehalf.balance;
        uint256 supplied = _supplyETH(onBehalf, amount);

        if (onBehalf != address(this)) assertEq(onBehalf.balance, onBehalfBalanceBefore);
        assertEq(address(this).balance, 0);
        assertEq(supplied, amount);
        assertApproxEqAbs(morpho.supplyBalance(weth, onBehalf), amount, 1, "supply != amount");
    }

    function testSupplyCollateralETH(uint256 amount, address onBehalf) public {
        vm.assume(onBehalf != address(0));
        assertEq(morpho.collateralBalance(weth, onBehalf), 0);

        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        uint256 onBehalfBalanceBefore = onBehalf.balance;
        uint256 supplied = _supplyCollateralETH(onBehalf, amount);

        if (onBehalf != address(this)) assertEq(onBehalf.balance, onBehalfBalanceBefore);
        assertEq(address(this).balance, 0);
        assertEq(supplied, amount);
        assertApproxEqAbs(morpho.collateralBalance(weth, onBehalf), amount, 2);
    }

    function testCannotWithdrawIfWETHGatewayNotManager(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);
        deal(address(this), amount);

        _supplyETH(address(this), amount);

        vm.expectRevert(Errors.PermissionDenied.selector);
        wethGateway.withdrawETH(amount, address(this), MAX_ITERATIONS);
    }

    function testWithdrawETH(uint256 amount, uint256 toWithdraw, address receiver) public {
        _assumeReceiver(receiver);

        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        toWithdraw = bound(toWithdraw, 1, type(uint256).max);
        deal(address(this), amount);

        _supplyETH(address(this), amount);

        morpho.approveManager(address(wethGateway), true);

        uint256 balanceBefore = receiver.balance;
        uint256 withdrawn = wethGateway.withdrawETH(toWithdraw, receiver, MAX_ITERATIONS);

        if (receiver != address(this)) assertEq(address(this).balance, 0);
        assertApproxEqAbs(withdrawn, Math.min(toWithdraw, amount), 1);
        assertApproxEqAbs(morpho.supplyBalance(weth, address(this)), amount - withdrawn, 2, "supply != expected");
        assertApproxEqAbs(receiver.balance, balanceBefore + withdrawn, 1);
    }

    function testCannotWithdrawCollateralIfWETHGatewayNotManager(uint256 amount) public {
        amount = bound(amount, 1, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);

        vm.expectRevert(Errors.PermissionDenied.selector);
        wethGateway.withdrawCollateralETH(amount, address(this));
    }

    function testWithdrawCollateralETH(uint256 amount, uint256 toWithdraw, address receiver) public {
        _assumeReceiver(receiver);

        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        toWithdraw = bound(toWithdraw, 1, type(uint256).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);

        morpho.approveManager(address(wethGateway), true);

        uint256 balanceBefore = receiver.balance;
        uint256 withdrawn = wethGateway.withdrawCollateralETH(toWithdraw, receiver);

        if (receiver != address(this)) assertEq(address(this).balance, 0);
        assertApproxEqAbs(withdrawn, Math.min(toWithdraw, amount), 1);
        assertApproxEqAbs(
            morpho.collateralBalance(weth, address(this)), amount - withdrawn, 2, "collateral != expected"
        );
        assertApproxEqAbs(receiver.balance, balanceBefore + withdrawn, 1);
    }

    function testCannotBorrowIfWETHGatewayNotManager(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);

        vm.expectRevert(Errors.PermissionDenied.selector);
        wethGateway.borrowETH(amount / 2, address(this), MAX_ITERATIONS);
    }

    function testBorrowETH(uint256 amount, address receiver) public {
        _assumeReceiver(receiver);

        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);

        morpho.approveManager(address(wethGateway), true);

        uint256 balanceBefore = receiver.balance;
        uint256 toBorrow = amount / 2;
        uint256 borrowed = wethGateway.borrowETH(toBorrow, receiver, MAX_ITERATIONS);

        assertEq(borrowed, toBorrow);
        assertGt(morpho.borrowBalance(weth, address(this)), 0);
        assertApproxEqAbs(morpho.borrowBalance(weth, address(this)), toBorrow, 1);
        assertEq(receiver.balance, balanceBefore + toBorrow);
    }

    function testRepayETH(uint256 amount, uint256 toRepay, address onBehalf, address repayer) public {
        _assumeReceiver(onBehalf);
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);

        morpho.approveManager(address(wethGateway), true);

        uint256 toBorrow = amount / 2;
        wethGateway.borrowETH(toBorrow, onBehalf, MAX_ITERATIONS);

        toRepay = bound(toRepay, 1, toBorrow);
        deal(repayer, toRepay);
        vm.prank(repayer);
        uint256 repaid = wethGateway.repayETH{value: toRepay}(address(this));

        assertEq(repaid, toRepay);
        assertEq(repayer.balance, 0);
        assertApproxEqAbs(
            morpho.borrowBalance(weth, address(this)), toBorrow - toRepay, 2, "borrow balance != expected"
        );
    }

    function testRepayETHWithExcess(uint256 amount, uint256 toRepay, address onBehalf, address repayer) public {
        _assumeReceiver(onBehalf);
        _assumeReceiver(repayer);
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);
        deal(address(this), amount);

        _supplyCollateralETH(address(this), amount);

        morpho.approveManager(address(wethGateway), true);

        uint256 toBorrow = amount / 2;
        wethGateway.borrowETH(toBorrow, onBehalf, MAX_ITERATIONS);

        uint256 borrowBalance = morpho.borrowBalance(weth, address(this));

        toRepay = bound(toRepay, borrowBalance + 10, type(uint96).max);
        deal(repayer, toRepay);
        vm.prank(repayer);
        uint256 repaid = wethGateway.repayETH{value: toRepay}(address(this));

        assertEq(repaid, borrowBalance);
        assertEq(repayer.balance, toRepay - borrowBalance);
        assertApproxEqAbs(morpho.borrowBalance(weth, address(this)), 0, 2, "borrow balance != 0");
    }

    function _supplyETH(address onBehalf, uint256 amount) internal returns (uint256) {
        return wethGateway.supplyETH{value: amount}(onBehalf, MAX_ITERATIONS);
    }

    function _supplyCollateralETH(address onBehalf, uint256 amount) internal returns (uint256) {
        return wethGateway.supplyCollateralETH{value: amount}(onBehalf);
    }

    receive() external payable {}
}
