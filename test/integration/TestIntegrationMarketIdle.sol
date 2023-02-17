// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {IMorpho} from "src/interfaces/IMorpho.sol";

import {Types} from "src/libraries/Types.sol";
import {Errors} from "src/libraries/Errors.sol";
import {Events} from "src/libraries/Events.sol";
import {MarketLib} from "src/libraries/MarketLib.sol";

import {Math} from "@morpho-utils/math/Math.sol";

import {DataTypes} from "@aave-v3-core/protocol/libraries/types/DataTypes.sol";
import {ReserveConfiguration} from "@aave-v3-core/protocol/libraries/configuration/ReserveConfiguration.sol";

import "test/helpers/IntegrationTest.sol";

contract TestIntegrationMarketIdle is IntegrationTest {
    using ReserveConfiguration for DataTypes.ReserveConfigurationMap;
    using MarketLib for Types.Market;
    using Math for uint256;

    Types.Market internal market;

    function testIncreaseIdleWhenSupplyCapIsMax(Types.Market memory _market, uint256 amount) public {
        market = _market;

        poolAdmin.setSupplyCap(dai, 0);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(dai);

        (uint256 suppliable, uint256 idleSupplyIncrease) = market.increaseIdle(dai, amount, reserve, indexes);
        assertEq(suppliable, amount, "suppliable");
        assertEq(idleSupplyIncrease, 0, "idleSupplyIncrease");
    }

    function testIncreaseIdle(Types.Market memory _market, uint256 amount, uint256 supplyCap) public {
        TestMarket storage testMarket = testMarkets[dai];
        supplyCap = _boundSupplyCapExceeded(testMarket, testMarket.minAmount * 10, supplyCap);
        amount = bound(amount, testMarket.minAmount, testMarket.maxAmount);

        _market.aToken = testMarket.aToken;
        _market.idleSupply = bound(_market.idleSupply, 0, testMarket.maxAmount);

        market = _market;

        _setSupplyCap(testMarket, supplyCap);

        uint256 supplyGap = _supplyGap(testMarket);

        DataTypes.ReserveData memory reserve = pool.getReserveData(dai);
        Types.Indexes256 memory indexes = morpho.updatedIndexes(dai);

        (uint256 suppliable, uint256 idleSupplyIncrease) = market.increaseIdle(dai, amount, reserve, indexes);

        assertEq(suppliable, supplyGap, "suppliable");
        assertEq(idleSupplyIncrease, amount.zeroFloorSub(supplyGap), "idleSupplyIncrease");
        assertEq(market.idleSupply, _market.idleSupply + idleSupplyIncrease, "market.idleSupply");
    }

    function testDecreaseIdle(Types.Market memory _market, uint256 amount) public {
        TestMarket storage testMarket = testMarkets[dai];
        amount = bound(amount, testMarket.minAmount, testMarket.maxAmount);

        _market.idleSupply = bound(_market.idleSupply, 0, testMarket.maxAmount);
        market = _market;

        uint256 expectedMatched = Math.min(_market.idleSupply, amount);
        (uint256 amountToProcess, uint256 matchedIdle) = market.decreaseIdle(dai, amount);

        assertEq(amountToProcess, amount - expectedMatched, "toProcess");
        assertEq(matchedIdle, expectedMatched, "matchedIdle");
        assertEq(market.idleSupply, _market.idleSupply - expectedMatched, "market.idleSupply");
    }
}
