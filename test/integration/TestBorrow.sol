// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationBorrow is IntegrationTest {
    using WadRayMath for uint256;
    using PercentageMath for uint256;
    using TestMarketLib for TestMarket;

    function _boundAmount(uint256 amount) internal view returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    function _boundOnBehalf(address onBehalf) internal view returns (address) {
        onBehalf = _boundAddressNotZero(onBehalf);

        vm.assume(onBehalf != address(proxyAdmin)); // TransparentUpgradeableProxy: admin cannot fallback to proxy target

        return onBehalf;
    }

    function _boundReceiver(address receiver) internal view returns (address) {
        return address(uint160(bound(uint256(uint160(receiver)), 1, type(uint160).max)));
    }

    function _prepareOnBehalf(address onBehalf) internal {
        if (onBehalf != address(user)) {
            vm.prank(onBehalf);
            morpho.approveManager(address(user), true);
        }
    }

    struct BorrowTest {
        uint256 borrowed;
        uint256 scaledP2PBorrow;
        uint256 scaledPoolBorrow;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function _assertBorrowPool(
        TestMarket storage market,
        uint256 amount,
        address onBehalf,
        address receiver,
        BorrowTest memory test,
        uint256 balanceBefore
    ) internal {
        test.morphoMarket = morpho.market(market.underlying);
        test.indexes = morpho.updatedIndexes(market.underlying);
        test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
        test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
        uint256 poolBorrow = test.scaledPoolBorrow.rayMulUp(test.indexes.borrow.poolIndex);

        // Assert balances on Morpho.
        assertEq(test.borrowed, amount, "borrowed != amount");
        assertEq(test.scaledP2PBorrow, 0, "scaledP2PBorrow != 0");
        assertApproxGeAbs(poolBorrow, amount, 2, "poolBorrow != amount");

        assertApproxGeAbs(morpho.borrowBalance(market.underlying, onBehalf), amount, 2, "borrow != amount");

        // Assert Morpho's position on pool.
        assertApproxEqAbs(market.variableBorrowOf(address(morpho)), amount, 1, "morphoVariableBorrow != amount");
        assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

        // Assert receiver's underlying balance.
        assertEq(
            ERC20(market.underlying).balanceOf(receiver),
            balanceBefore + amount,
            "balanceAfter - balanceBefore != amount"
        );

        // Assert Morpho's market state.
        assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
        assertEq(test.morphoMarket.deltas.supply.scaledTotalP2P, 0, "scaledTotalSupplyP2P != 0");
        assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
        assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
        assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
    }

    function _assertBorrowP2P(
        TestMarket storage market,
        uint256 amount,
        address onBehalf,
        address receiver,
        BorrowTest memory test,
        uint256 balanceBefore
    ) internal {
        test.morphoMarket = morpho.market(market.underlying);
        test.indexes = morpho.updatedIndexes(market.underlying);
        test.scaledP2PBorrow = morpho.scaledP2PBorrowBalance(market.underlying, onBehalf);
        test.scaledPoolBorrow = morpho.scaledPoolBorrowBalance(market.underlying, onBehalf);
        uint256 p2pBorrow = test.scaledP2PBorrow.rayMulUp(test.indexes.supply.p2pIndex);

        // Assert balances on Morpho.
        assertEq(test.borrowed, amount, "borrowed != amount");
        assertEq(test.scaledPoolBorrow, 0, "scaledPoolBorrow != 0");
        assertApproxGeAbs(p2pBorrow, amount, 1, "p2pBorrow != amount");
        assertApproxLeAbs(
            morpho.scaledP2PSupplyBalance(market.underlying, address(promoter1)),
            test.scaledP2PBorrow,
            2,
            "promoterScaledP2PSupply != scaledP2PBorrow"
        );
        assertEq(
            morpho.scaledPoolSupplyBalance(market.underlying, address(promoter1)), 0, "promoterScaledPoolSupply != 0"
        );

        assertApproxGeAbs(morpho.borrowBalance(market.underlying, onBehalf), amount, 2, "borrow != amount");
        assertApproxLeAbs(
            morpho.supplyBalance(market.underlying, address(promoter1)), amount, 2, "promoterSupply != amount"
        );

        // Assert Morpho's position on pool.
        assertApproxEqAbs(market.variableBorrowOf(address(morpho)), 0, 2, "morphoVariableBorrow != 0");
        assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

        // Assert receiver's underlying balance.
        assertEq(
            ERC20(market.underlying).balanceOf(receiver),
            balanceBefore + amount,
            "balanceAfter - balanceBefore != amount"
        );

        // Assert Morpho's market state.
        assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
        assertEq(
            test.morphoMarket.deltas.supply.scaledTotalP2P,
            test.scaledP2PBorrow,
            "scaledTotalSupplyP2P != scaledP2PBorrow"
        );
        assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
        assertEq(
            test.morphoMarket.deltas.borrow.scaledTotalP2P,
            test.scaledP2PBorrow,
            "scaledTotalBorrowP2P != scaledP2PBorrow"
        );
        assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
    }

    function testShouldBorrowPoolOnly(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            _assertBorrowPool(market, amount, onBehalf, receiver, test, balanceBefore);
        }
    }

    function testShouldBorrowP2POnly(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);
            amount = _promoteBorrow(promoter1, market, amount); // 100% peer-to-peer.

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.SupplyPositionUpdated(address(promoter1), market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            _assertBorrowP2P(market, amount, onBehalf, receiver, test, balanceBefore);
        }
    }

    function testShouldBorrowP2PWhenIdleSupply(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _increaseIdleSupply(promoter1, market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, true, address(morpho));
            emit Events.IdleSupplyUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            _assertBorrowP2P(market, amount, onBehalf, receiver, test, balanceBefore);
        }
    }

    function testShouldBorrowPoolWhenP2PDisabled(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);
            amount = _promoteBorrow(promoter1, market, amount); // 100% peer-to-peer.

            morpho.setIsP2PDisabled(market.underlying, true);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            _assertBorrowPool(market, amount, onBehalf, receiver, test, balanceBefore);
        }
    }

    function testShouldBorrowP2PWhenSupplyDelta(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _increaseSupplyDelta(promoter1, market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            vm.expectEmit(true, true, true, true, address(morpho));
            emit Events.P2PSupplyDeltaUpdated(market.underlying, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Borrowed(address(user), onBehalf, receiver, market.underlying, 0, 0, 0);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            _assertBorrowP2P(market, amount, onBehalf, receiver, test, balanceBefore);
        }
    }

    function testShouldNotBorrowP2PWhenP2PDisabledWithSupplyDelta(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _increaseSupplyDelta(promoter1, market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            _assertBorrowPool(market, amount, onBehalf, receiver, test, balanceBefore);
        }
    }

    function testShouldNotBorrowP2PWhenP2PDisabledWithIdleSupply(uint256 amount, address onBehalf, address receiver)
        public
        returns (BorrowTest memory test)
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _increaseIdleSupply(promoter1, market, amount);

            uint256 balanceBefore = ERC20(market.underlying).balanceOf(receiver);

            test.borrowed =
                _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);

            _assertBorrowPool(market, amount, onBehalf, receiver, test, balanceBefore);
        }
    }

    function testShouldNotBorrowWhenBorrowCapExceeded(
        uint256 amount,
        address onBehalf,
        address receiver,
        uint256 borrowCap,
        uint256 promoted
    ) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);
            promoted = _promoteBorrow(promoter1, market, bound(promoted, 1, amount)); // <= 100% peer-to-peer.

            // Set the borrow cap so that the borrow gap is lower than the amount borrowed on pool.
            borrowCap = bound(borrowCap, 10 ** market.decimals, market.totalBorrow() + amount - promoted);
            _setBorrowCap(market, borrowCap);

            vm.expectRevert(Errors.ExceedsBorrowCap.selector);
            user.borrow(market.underlying, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);
        }
    }

    function testShouldNotBorrowMoreThanLtv(uint256 collateral, uint256 borrowed, address onBehalf, address receiver)
        public
    {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (
            uint256 collateralMarketIndex; collateralMarketIndex < collateralUnderlyings.length; ++collateralMarketIndex
        ) {
            for (uint256 borrowedMarketIndex; borrowedMarketIndex < borrowableUnderlyings.length; ++borrowedMarketIndex)
            {
                _revert();

                TestMarket storage collateralMarket = testMarkets[collateralUnderlyings[collateralMarketIndex]];
                TestMarket storage borrowedMarket = testMarkets[borrowableUnderlyings[borrowedMarketIndex]];

                collateral = _boundSupply(collateralMarket, collateral);
                borrowed =
                    bound(borrowed, borrowedMarket.borrowable(collateralMarket, collateral), borrowedMarket.maxAmount);
                _promoteBorrow(promoter1, borrowedMarket, borrowed); // <= 100% peer-to-peer.

                user.approve(collateralMarket.underlying, collateral);
                user.supplyCollateral(collateralMarket.underlying, collateral, onBehalf);

                vm.expectRevert(Errors.UnauthorizedBorrow.selector);
                user.borrow(borrowedMarket.underlying, borrowed, onBehalf, receiver, DEFAULT_MAX_ITERATIONS);
            }
        }
    }

    function testShouldUpdateIndexesAfterBorrow(uint256 amount, address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundBorrow(market, amount);

            Types.Indexes256 memory futureIndexes = morpho.updatedIndexes(market.underlying);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IndexesUpdated(market.underlying, 0, 0, 0, 0);

            _borrowNoCollateral(address(user), market, amount, onBehalf, receiver, DEFAULT_MAX_ITERATIONS); // 100% pool.

            Types.Market memory morphoMarket = morpho.market(market.underlying);
            assertEq(
                morphoMarket.indexes.supply.poolIndex,
                futureIndexes.supply.poolIndex,
                "poolSupplyIndex != futurePoolSupplyIndex"
            );
            assertEq(
                morphoMarket.indexes.borrow.poolIndex,
                futureIndexes.borrow.poolIndex,
                "poolBorrowIndex != futurePoolBorrowIndex"
            );

            assertEq(
                morphoMarket.indexes.supply.p2pIndex,
                futureIndexes.supply.p2pIndex,
                "p2pSupplyIndex != futureP2PSupplyIndex"
            );
            assertEq(
                morphoMarket.indexes.borrow.p2pIndex,
                futureIndexes.borrow.p2pIndex,
                "p2pBorrowIndex != futureP2PBorrowIndex"
            );
        }
    }

    function testShouldRevertBorrowZero(address onBehalf, address receiver) public {
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.borrow(testMarkets[underlyings[marketIndex]].underlying, 0, onBehalf, receiver);
        }
    }

    function testShouldRevertBorrowOnBehalfZero(uint256 amount, address receiver) public {
        amount = _boundAmount(amount);
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.borrow(testMarkets[underlyings[marketIndex]].underlying, amount, address(0), receiver);
        }
    }

    function testShouldRevertBorrowToZero(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.borrow(testMarkets[underlyings[marketIndex]].underlying, amount, onBehalf, address(0));
        }
    }

    function testShouldRevertBorrowWhenMarketNotCreated(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user.borrow(sAvax, amount, onBehalf, receiver);
    }

    function testShouldRevertBorrowWhenBorrowPaused(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        receiver = _boundReceiver(receiver);

        _prepareOnBehalf(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsBorrowPaused(market.underlying, true);

            vm.expectRevert(Errors.BorrowIsPaused.selector);
            user.borrow(market.underlying, amount, onBehalf, receiver);
        }
    }

    function testShouldRevertBorrowWhenNotManaging(uint256 amount, address onBehalf, address receiver) public {
        amount = _boundAmount(amount);
        onBehalf = _boundOnBehalf(onBehalf);
        vm.assume(onBehalf != address(user));
        receiver = _boundReceiver(receiver);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.PermissionDenied.selector);
            user.borrow(testMarkets[underlyings[marketIndex]].underlying, amount, onBehalf, receiver);
        }
    }
}
