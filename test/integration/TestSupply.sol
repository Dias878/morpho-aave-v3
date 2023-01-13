// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.17;

import "test/helpers/IntegrationTest.sol";

contract TestSupply is IntegrationTest {
    using WadRayMath for uint256;

    // TODO: reverts with supply cap for now because idle supply not yet implemented
    function testShouldSupply(uint256 amount) public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            // TODO: pause supply collateral (thus we check if supply still works)

            amount = _boundSupply(market, amount);

            user1.approve(market.underlying, amount);
            user1.supply(market.underlying, amount);

            Types.Indexes256 memory indexes = morpho.updatedIndexes(market.underlying);

            assertEq(
                morpho.scaledPoolSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.poolIndex)
                    + morpho.scaledP2PSupplyBalance(market.underlying, address(user1)).rayMul(indexes.supply.p2pIndex),
                amount
            );
        }
    }

    function testShouldRevertSupplyZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AmountIsZero.selector);
            user1.supply(markets[marketIndex].underlying, 0);
        }
    }

    function testShouldRevertSupplyOnBehalfZero() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            vm.expectRevert(Errors.AddressIsZero.selector);
            user1.supply(markets[marketIndex].underlying, 100, address(0));
        }
    }

    function testShouldRevertSupplyWhenMarketNotCreated() public {
        vm.expectRevert(Errors.MarketNotCreated.selector);
        user1.supply(sAvax, 100);
    }

    function testShouldRevertSupplyWhenSupplyIsPaused() public {
        for (uint256 marketIndex; marketIndex < markets.length; ++marketIndex) {
            _revert();

            TestMarket memory market = markets[marketIndex];

            morpho.setIsSupplyPaused(market.underlying, true);

            vm.expectRevert(Errors.SupplyIsPaused.selector);
            user1.supply(market.underlying, 100);
        }
    }
}
