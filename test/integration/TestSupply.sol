// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationSupply is IntegrationTest {
    using WadRayMath for uint256;
    using TestMarketLib for TestMarket;

    function _boundAmount(uint256 amount) internal view returns (uint256) {
        return bound(amount, 1, type(uint256).max);
    }

    struct SupplyTest {
        uint256 supplied;
        uint256 balanceBefore;
        uint256 morphoSupplyBefore;
        uint256 scaledP2PSupply;
        uint256 scaledPoolSupply;
        uint256 scaledCollateral;
        Types.Indexes256 indexes;
        Types.Market morphoMarket;
    }

    function _assertSupplyPool(TestMarket storage market, uint256 amount, address onBehalf, SupplyTest memory test)
        internal
    {
        test.morphoMarket = morpho.market(market.underlying);
        test.indexes = morpho.updatedIndexes(market.underlying);
        test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
        test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
        test.scaledCollateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);
        uint256 poolSupply = test.scaledPoolSupply.rayMul(test.indexes.supply.poolIndex);

        // Assert balances on Morpho.
        assertEq(test.supplied, amount, "supplied != amount");
        assertEq(test.scaledP2PSupply, 0, "scaledP2PSupply != 0");
        assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
        assertApproxEqDust(poolSupply, amount, "poolSupply != amount");

        assertApproxEqDust(morpho.supplyBalance(market.underlying, onBehalf), amount, "totalSupply != amount");
        assertEq(morpho.collateralBalance(market.underlying, onBehalf), 0, "collateral != 0");

        // Assert Morpho's position on pool.
        assertApproxEqAbs(
            market.supplyOf(address(morpho)),
            test.morphoSupplyBefore + amount,
            1,
            "morphoSupply != morphoSupplyBefore + amount"
        );
        assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

        // Assert user's underlying balance.
        assertEq(
            test.balanceBefore, user.balanceOf(market.underlying) + amount, "balanceBefore - balanceAfter != amount"
        );

        // Assert Morpho's market state.
        assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
        assertEq(test.morphoMarket.deltas.supply.scaledTotalP2P, 0, "scaledTotalSupplyP2P != 0");
        assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
        assertEq(test.morphoMarket.deltas.borrow.scaledTotalP2P, 0, "scaledTotalBorrowP2P != 0");
        assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
    }

    function _assertSupplyP2P(TestMarket storage market, uint256 amount, address onBehalf, SupplyTest memory test)
        internal
    {
        test.morphoMarket = morpho.market(market.underlying);
        test.indexes = morpho.updatedIndexes(market.underlying);
        test.scaledP2PSupply = morpho.scaledP2PSupplyBalance(market.underlying, onBehalf);
        test.scaledPoolSupply = morpho.scaledPoolSupplyBalance(market.underlying, onBehalf);
        test.scaledCollateral = morpho.scaledCollateralBalance(market.underlying, onBehalf);
        uint256 p2pSupply = test.scaledP2PSupply.rayMul(test.indexes.supply.p2pIndex);

        // Assert balances on Morpho.
        assertEq(test.supplied, amount, "supplied != amount");
        assertEq(test.scaledCollateral, 0, "scaledCollateral != 0");
        assertApproxEqDust(test.scaledPoolSupply, 0, "scaledPoolSupply != 0");
        assertApproxEqDust(p2pSupply, amount, "p2pSupply != amount");
        assertApproxGeAbs(
            morpho.scaledP2PBorrowBalance(market.underlying, address(promoter1)),
            test.scaledP2PSupply,
            1,
            "promoterScaledP2PBorrow != scaledP2PSupply"
        );
        assertApproxEqDust(
            morpho.scaledPoolBorrowBalance(market.underlying, address(promoter1)), 0, "promoterScaledPoolBorrow != 0"
        );

        assertApproxEqDust(morpho.supplyBalance(market.underlying, onBehalf), amount, "supply != amount");
        assertEq(morpho.collateralBalance(market.underlying, onBehalf), 0, "collateral != 0");
        assertApproxEqDust(
            morpho.borrowBalance(market.underlying, address(promoter1)), amount, "promoterBorrow != amount"
        );

        // Assert Morpho's position on pool.
        assertApproxGeAbs(
            market.supplyOf(address(morpho)), test.morphoSupplyBefore, 2, "morphoSupplyAfter != morphoSupplyBefore"
        );
        assertApproxEqAbs(market.variableBorrowOf(address(morpho)), 0, 1, "morphoVariableBorrow != 0");
        assertEq(market.stableBorrowOf(address(morpho)), 0, "morphoStableBorrow != 0");

        // Assert user's underlying balance.
        assertEq(
            test.balanceBefore - user.balanceOf(market.underlying), amount, "balanceBefore - balanceAfter != amount"
        );

        // Assert Morpho's market state.
        assertEq(test.morphoMarket.deltas.supply.scaledDeltaPool, 0, "scaledSupplyDelta != 0");
        assertEq(
            test.morphoMarket.deltas.supply.scaledTotalP2P,
            test.scaledP2PSupply,
            "scaledTotalSupplyP2P != scaledP2PSupply"
        );
        assertEq(test.morphoMarket.deltas.borrow.scaledDeltaPool, 0, "scaledBorrowDelta != 0");
        assertEq(
            test.morphoMarket.deltas.borrow.scaledTotalP2P,
            test.scaledP2PSupply,
            "scaledTotalBorrowP2P != scaledP2PSupply"
        );
        assertEq(test.morphoMarket.idleSupply, 0, "idleSupply != 0");
    }

    function testShouldSupplyPoolOnly(uint256 amount, address onBehalf) public returns (SupplyTest memory test) {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            amount = _boundSupply(market, amount);

            test.balanceBefore = user.balanceOf(market.underlying);
            test.morphoSupplyBefore = market.supplyOf(address(morpho));

            user.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Supplied(address(user), onBehalf, market.underlying, 0, 0, 0);

            test.supplied = user.supply(market.underlying, amount, onBehalf); // 100% pool.

            _assertSupplyPool(market, amount, onBehalf, test);

            assertEq(market.variableBorrowOf(address(morpho)), 0, "morphoVariableBorrow != 0");
        }
    }

    // TODO: failing because supply cap exceeded and p2p supply sometimes end up supplying 1 wei to the pool.
    function testShouldSupplyP2POnly(uint256 supplyCap, uint256 amount, address onBehalf)
        public
        returns (SupplyTest memory test)
    {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundSupply(market, amount);
            amount = _promoteSupply(promoter1, market, amount); // 100% peer-to-peer.

            supplyCap = _boundSupplyCapExceeded(market, 0, supplyCap);
            _setSupplyCap(market, supplyCap);

            test.balanceBefore = user.balanceOf(market.underlying);
            test.morphoSupplyBefore = market.supplyOf(address(morpho));

            user.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.BorrowPositionUpdated(address(promoter1), market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.P2PTotalsUpdated(market.underlying, 0, 0);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Supplied(address(user), onBehalf, market.underlying, 0, 0, 0);

            test.supplied = user.supply(market.underlying, amount, onBehalf);

            _assertSupplyP2P(market, amount, onBehalf, test);
        }
    }

    function testShouldSupplyPoolWhenP2PDisabled(uint256 amount, address onBehalf)
        public
        returns (SupplyTest memory test)
    {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < borrowableUnderlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[borrowableUnderlyings[marketIndex]];

            amount = _boundSupply(market, amount);
            amount = _promoteSupply(promoter1, market, amount); // 100% peer-to-peer.

            morpho.setIsP2PDisabled(market.underlying, true);

            test.balanceBefore = user.balanceOf(market.underlying);
            test.morphoSupplyBefore = market.supplyOf(address(morpho));

            user.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.Supplied(address(user), onBehalf, market.underlying, 0, 0, 0);

            test.supplied = user.supply(market.underlying, amount, onBehalf); // 100% pool.

            _assertSupplyPool(market, amount, onBehalf, test);

            assertApproxEqAbs(market.variableBorrowOf(address(morpho)), amount, 1, "morphoVariableBorrow != amount");
        }
    }

    // TODO: should supply p2p when borrow delta

    // TODO: should not supply p2p when p2p disabled & borrow delta

    function testShouldNotSupplyPoolWhenSupplyCapExceeded(
        uint256 amount,
        address onBehalf,
        uint256 supplyCap,
        uint256 promoted
    ) public {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            amount = _boundSupply(market, amount);
            promoted = _promoteSupply(promoter1, market, bound(promoted, 0, amount - 1)); // < 100% peer-to-peer.

            // Set the supply cap so that the supply gap is lower than the amount supplied on pool.
            supplyCap = _boundSupplyCapExceeded(market, amount - promoted, supplyCap);
            _setSupplyCap(market, supplyCap);

            user.approve(market.underlying, amount);

            vm.expectRevert(bytes(AaveErrors.SUPPLY_CAP_EXCEEDED));
            user.supply(market.underlying, amount, onBehalf);
        }
    }

    function testShouldUpdateIndexesAfterSupply(uint256 amount, address onBehalf) public {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            amount = _boundSupply(market, amount);

            Types.Indexes256 memory futureIndexes = morpho.updatedIndexes(market.underlying);

            user.approve(market.underlying, amount);

            vm.expectEmit(true, true, true, false, address(morpho));
            emit Events.IndexesUpdated(market.underlying, 0, 0, 0, 0);

            user.supply(market.underlying, amount, onBehalf); // 100% pool.

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

    function testShouldRevertSupplyZero(address onBehalf) public {
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user.supply(testMarkets[underlyings[marketIndex]].underlying, 0, onBehalf);
        }
    }

    function testShouldRevertSupplyOnBehalfZero(uint256 amount) public {
        amount = _boundAmount(amount);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user.supply(testMarkets[underlyings[marketIndex]].underlying, amount, address(0));
        }
    }

    function testShouldRevertSupplyWhenMarketNotCreated(address underlying, uint256 amount, address onBehalf) public {
        for (uint256 i; i < allUnderlyings.length; ++i) {
            vm.assume(underlying != allUnderlyings[i]);
        }

        amount = _boundAmount(amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        vm.expectRevert(Errors.MarketNotCreated.selector);
        user.supply(underlying, amount, onBehalf);
    }

    function testShouldRevertSupplyWhenSupplyPaused(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            morpho.setIsSupplyPaused(market.underlying, true);

            vm.expectRevert(Errors.SupplyIsPaused.selector);
            user.supply(market.underlying, amount, onBehalf);
        }
    }

    function testShouldRevertSupplyNotEnoughAllowance(uint256 allowance, uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            amount = _boundSupply(market, amount);
            allowance = bound(allowance, 0, amount - 1);

            user.approve(market.underlying, allowance);

            vm.expectRevert(); // Cannot specify the revert reason as it depends on the ERC20 implementation.
            user.supply(market.underlying, amount, onBehalf);
        }
    }

    function testShouldSupplyWhenEverythingElsePaused(uint256 amount, address onBehalf) public {
        amount = _boundAmount(amount);
        onBehalf = _boundAddressNotZero(onBehalf);

        morpho.setIsPausedForAllMarkets(true);

        for (uint256 marketIndex; marketIndex < underlyings.length; ++marketIndex) {
            _revert();

            TestMarket storage market = testMarkets[underlyings[marketIndex]];

            amount = _boundSupply(market, amount);

            morpho.setIsSupplyPaused(market.underlying, false);

            user.approve(market.underlying, amount);
            user.supply(market.underlying, amount, onBehalf);
        }
    }
}
