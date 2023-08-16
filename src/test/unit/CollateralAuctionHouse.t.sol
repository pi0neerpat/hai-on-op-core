// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {
  CollateralAuctionHouseForTest, ICollateralAuctionHouse
} from '@contracts/for-test/CollateralAuctionHouseForTest.sol';
import {ISAFEEngine} from '@interfaces/ISAFEEngine.sol';
import {ILiquidationEngine} from '@interfaces/ILiquidationEngine.sol';
import {IOracleRelayer} from '@interfaces/IOracleRelayer.sol';
import {IDelayedOracle} from '@interfaces/oracles/IDelayedOracle.sol';
import {IAuthorizable} from '@interfaces/utils/IAuthorizable.sol';
import {IModifiable} from '@interfaces/utils/IModifiable.sol';
import {HaiTest, stdStorage, StdStorage} from '@test/utils/HaiTest.t.sol';

import {Math, RAY, WAD} from '@libraries/Math.sol';
import {Assertions} from '@libraries/Assertions.sol';

contract Base is HaiTest {
  using stdStorage for StdStorage;

  struct CollateralAuction {
    uint256 id;
    uint256 amountToSell;
    uint256 amountToRaise;
    uint256 initialTimestamp;
    address forgoneCollateralReceiver;
    address auctionIncomeRecipient;
  }

  address deployer = label('deployer');
  address authorizedAccount = label('authorizedAccount');
  address user = label('user');

  ISAFEEngine mockSafeEngine = ISAFEEngine(mockContract('SafeEngine'));
  ILiquidationEngine mockLiquidationEngine = ILiquidationEngine(mockContract('LiquidationEngine'));
  IOracleRelayer mockOracleRelayer = IOracleRelayer(mockContract('OracleRelayer'));
  IDelayedOracle mockDelayedOracle = IDelayedOracle(mockContract('DelayedOracle'));

  CollateralAuctionHouseForTest collateralAuctionHouse;

  bytes32 collateralType = 'collateralType';
  ICollateralAuctionHouse.CollateralAuctionHouseParams cahParams = ICollateralAuctionHouse.CollateralAuctionHouseParams({
    minDiscount: 0.95e18, // 5% discount
    maxDiscount: 0.95e18, // 5% discount
    perSecondDiscountUpdateRate: RAY, // [ray]
    minimumBid: 1e18 // 1 system coin
  });

  function setUp() public virtual {
    vm.startPrank(deployer);

    collateralAuctionHouse =
    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(mockLiquidationEngine), address(mockOracleRelayer), collateralType, cahParams);
    label(address(collateralAuctionHouse), 'CollateralAuctionHouse');

    collateralAuctionHouse.addAuthorization(authorizedAccount);

    vm.stopPrank();
  }

  // --- Registry ---

  function _mockLiquidationEngine(address _liquidationEngine) internal {
    stdstore.target(address(collateralAuctionHouse)).sig(ICollateralAuctionHouse.liquidationEngine.selector)
      .checked_write(_liquidationEngine);
  }

  // --- Params ---

  function _mockMinimumBid(uint256 _minumumBid) internal {
    stdstore.target(address(collateralAuctionHouse)).sig(ICollateralAuctionHouse.params.selector).depth(0).checked_write(
      _minumumBid
    );
  }

  function _mockMinDiscount(uint256 _minDiscount) internal {
    stdstore.target(address(collateralAuctionHouse)).sig(ICollateralAuctionHouse.params.selector).depth(1).checked_write(
      _minDiscount
    );
  }

  function _mockMaxDiscount(uint256 _maxDiscount) internal {
    stdstore.target(address(collateralAuctionHouse)).sig(ICollateralAuctionHouse.params.selector).depth(2).checked_write(
      _maxDiscount
    );
  }

  function _mockPerSecondDiscountUpdateRate(uint256 _perSecondDiscountUpdateRate) internal {
    stdstore.target(address(collateralAuctionHouse)).sig(ICollateralAuctionHouse.params.selector).depth(3).checked_write(
      _perSecondDiscountUpdateRate
    );
  }

  // --- Data ---

  function _mockAuction(CollateralAuction memory _auction) internal {
    // BUG: Accessing packed slots is not supported by Std Storage
    collateralAuctionHouse.addAuction(
      _auction.id,
      _auction.amountToSell,
      _auction.amountToRaise,
      _auction.initialTimestamp,
      _auction.forgoneCollateralReceiver,
      _auction.auctionIncomeRecipient
    );
  }

  function _mockAuctionsStarted(uint256 _auctionsStarted) internal {
    stdstore.target(address(collateralAuctionHouse)).sig(ICollateralAuctionHouse.auctionsStarted.selector).checked_write(
      _auctionsStarted
    );
  }

  // --- Mocked calls ---

  function _mockOracleRelayerCParams(bytes32 _cType, IDelayedOracle _oracle) internal {
    vm.mockCall(
      address(mockOracleRelayer), abi.encodeCall(mockOracleRelayer.cParams, (_cType)), abi.encode(_oracle, 0, 0)
    );
  }

  function _mockOracleRelayerRedemptionPrice(uint256 _redemptionPrice) internal {
    vm.mockCall(
      address(mockOracleRelayer), abi.encodeCall(mockOracleRelayer.redemptionPrice, ()), abi.encode(_redemptionPrice)
    );
  }

  function _mockOracleRelayerCalcRedemptionPrice(uint256 _calcRedemptionPrice) internal {
    vm.mockCall(
      address(mockOracleRelayer),
      abi.encodeCall(mockOracleRelayer.calcRedemptionPrice, ()),
      abi.encode(_calcRedemptionPrice)
    );
  }

  function _mockDelayedOracleGetResultWithValidity(uint256 _result, bool _validity) internal {
    vm.mockCall(
      address(mockDelayedOracle),
      abi.encodeCall(mockDelayedOracle.getResultWithValidity, ()),
      abi.encode(_result, _validity)
    );
  }
}

contract Unit_CollateralAuctionHouse_Constants is Base {
  function test_Set_AUCTION_HOUSE_TYPE() public {
    assertEq(collateralAuctionHouse.AUCTION_HOUSE_TYPE(), bytes32('COLLATERAL'));
  }

  function test_Set_SURPLUS_AUCTION_TYPE() public {
    assertEq(collateralAuctionHouse.AUCTION_TYPE(), bytes32('INCREASING_DISCOUNT'));
  }
}

contract Unit_CollateralAuctionHouse_Constructor is Base {
  event AddAuthorization(address _account);

  modifier happyPath() {
    vm.startPrank(user);
    _;
  }

  function test_Emit_AddAuthorization() public happyPath {
    vm.expectEmit();
    emit AddAuthorization(user);

    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(mockLiquidationEngine), address(mockOracleRelayer), collateralType, cahParams);
  }

  function test_Set_SafeEngine() public happyPath {
    assertEq(address(collateralAuctionHouse.safeEngine()), address(mockSafeEngine));
  }

  function test_Set_LiquidationEngine() public happyPath {
    assertEq(address(collateralAuctionHouse.liquidationEngine()), address(mockLiquidationEngine));
  }

  function test_Emit_AddAuthorization_LiquidationEngine() public happyPath {
    vm.expectEmit();
    emit AddAuthorization(address(mockLiquidationEngine));

    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(mockLiquidationEngine), address(mockOracleRelayer), collateralType, cahParams);
  }

  function test_Set_OracleRelayer() public happyPath {
    assertEq(address(collateralAuctionHouse.oracleRelayer()), address(mockOracleRelayer));
  }

  function test_Set_CollateralType() public happyPath {
    assertEq(collateralAuctionHouse.collateralType(), collateralType);
  }

  function test_Set_CAH_Params(ICollateralAuctionHouse.CollateralAuctionHouseParams memory _cahParams) public happyPath {
    vm.assume(_cahParams.minDiscount >= _cahParams.maxDiscount && _cahParams.minDiscount <= WAD);
    vm.assume(_cahParams.maxDiscount > 0);
    vm.assume(_cahParams.perSecondDiscountUpdateRate <= RAY);

    collateralAuctionHouse =
    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(mockLiquidationEngine), address(mockOracleRelayer), collateralType, _cahParams);

    assertEq(abi.encode(collateralAuctionHouse.params()), abi.encode(_cahParams));
  }

  function test_Revert_NullAddress_SafeEngine() public {
    vm.expectRevert(Assertions.NullAddress.selector);

    new CollateralAuctionHouseForTest(address(0), address(mockLiquidationEngine), address(mockOracleRelayer), collateralType, cahParams);
  }

  function test_Revert_NullAddress_LiquidationEngine() public {
    vm.expectRevert(Assertions.NullAddress.selector);

    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(0), address(mockOracleRelayer), collateralType, cahParams);
  }

  function test_Revert_NullAddress_OracleRelayer() public {
    vm.expectRevert(Assertions.NullAddress.selector);

    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(mockLiquidationEngine), address(0), collateralType, cahParams);
  }

  function test_Revert_NotGreaterOrEqualThan_MinDiscount(
    ICollateralAuctionHouse.CollateralAuctionHouseParams memory _cahParams
  ) public {
    vm.assume(_cahParams.minDiscount < _cahParams.maxDiscount);

    vm.expectRevert(
      abi.encodeWithSelector(Assertions.NotGreaterOrEqualThan.selector, _cahParams.minDiscount, _cahParams.maxDiscount)
    );

    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(mockLiquidationEngine), address(mockOracleRelayer), collateralType, _cahParams);
  }

  function test_Revert_NotLesserOrEqualThan_MinDiscount(
    ICollateralAuctionHouse.CollateralAuctionHouseParams memory _cahParams
  ) public {
    vm.assume(_cahParams.minDiscount >= _cahParams.maxDiscount && _cahParams.minDiscount > WAD);

    vm.expectRevert(abi.encodeWithSelector(Assertions.NotLesserOrEqualThan.selector, _cahParams.minDiscount, WAD));

    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(mockLiquidationEngine), address(mockOracleRelayer), collateralType, _cahParams);
  }

  function test_Revert_NotGreaterThan_MaxDiscount(
    ICollateralAuctionHouse.CollateralAuctionHouseParams memory _cahParams
  ) public {
    _cahParams.maxDiscount = 0;
    vm.assume(_cahParams.minDiscount >= _cahParams.maxDiscount && _cahParams.minDiscount <= WAD);

    vm.expectRevert(abi.encodeWithSelector(Assertions.NotGreaterThan.selector, _cahParams.maxDiscount, 0));

    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(mockLiquidationEngine), address(mockOracleRelayer), collateralType, _cahParams);
  }

  function test_Revert_NotLesserOrEqualThan_PerSecondDiscountUpdateRate(
    ICollateralAuctionHouse.CollateralAuctionHouseParams memory _cahParams
  ) public {
    vm.assume(_cahParams.minDiscount >= _cahParams.maxDiscount && _cahParams.minDiscount <= WAD);
    vm.assume(_cahParams.maxDiscount > 0);
    vm.assume(_cahParams.perSecondDiscountUpdateRate > RAY);

    vm.expectRevert(
      abi.encodeWithSelector(Assertions.NotLesserOrEqualThan.selector, _cahParams.perSecondDiscountUpdateRate, RAY)
    );

    new CollateralAuctionHouseForTest(address(mockSafeEngine), address(mockLiquidationEngine), address(mockOracleRelayer), collateralType, _cahParams);
  }
}

contract Unit_CollateralAuctionHouse_StartAuction is Base {
  event StartAuction(uint256 indexed _id, uint256 _blockTimestamp, uint256 _amountToSell, uint256 _amountToRaise);

  modifier happyPath(CollateralAuction memory _auction, uint256 _auctionsStarted) {
    vm.startPrank(authorizedAccount);
    _assumeHappyPath(_auction, _auctionsStarted);
    _mockValues(_auctionsStarted);
    _;
  }

  function _assumeHappyPath(CollateralAuction memory _auction, uint256 _auctionsStarted) internal pure {
    vm.assume(_auction.amountToSell > 0);
    vm.assume(_auction.amountToRaise >= RAY);
    vm.assume(_auctionsStarted < type(uint256).max);
  }

  function _mockValues(uint256 _auctionsStarted) internal {
    _mockAuctionsStarted(_auctionsStarted);
  }

  function test_Revert_Unauthorized(CollateralAuction memory _auction) public {
    vm.expectRevert(IAuthorizable.Unauthorized.selector);

    collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );
  }

  function test_Revert_CAH_NoCollateralForSale(CollateralAuction memory _auction) public {
    vm.startPrank(authorizedAccount);
    _auction.amountToSell = 0;

    vm.expectRevert(ICollateralAuctionHouse.CAH_NoCollateralForSale.selector);

    collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );
  }

  function test_Revert_CAH_NothingToRaise(CollateralAuction memory _auction) public {
    vm.startPrank(authorizedAccount);
    vm.assume(_auction.amountToSell > 0);
    _auction.amountToRaise = 0;

    vm.expectRevert(ICollateralAuctionHouse.CAH_NothingToRaise.selector);

    collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );
  }

  function test_Revert_CAH_DustyAuction(CollateralAuction memory _auction) public {
    vm.startPrank(authorizedAccount);
    vm.assume(_auction.amountToSell > 0);
    vm.assume(_auction.amountToRaise > 0 && _auction.amountToRaise < RAY);

    vm.expectRevert(ICollateralAuctionHouse.CAH_DustyAuction.selector);

    collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );
  }

  function test_Revert_Overflow_AuctionsStarted(CollateralAuction memory _auction) public {
    vm.startPrank(authorizedAccount);
    vm.assume(_auction.amountToSell > 0);
    vm.assume(_auction.amountToRaise >= RAY);
    _mockValues({_auctionsStarted: type(uint256).max});

    vm.expectRevert();

    collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );
  }

  function test_Set_AuctionsStarted(
    CollateralAuction memory _auction,
    uint256 _auctionsStarted
  ) public happyPath(_auction, _auctionsStarted) {
    collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );

    assertEq(collateralAuctionHouse.auctionsStarted(), _auctionsStarted + 1);
  }

  function test_Set_Auctions(
    CollateralAuction memory _auction,
    uint256 _auctionsStarted
  ) public happyPath(_auction, _auctionsStarted) {
    collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );

    ICollateralAuctionHouse.Auction memory __auction = collateralAuctionHouse.auctions(_auctionsStarted + 1);

    assertEq(__auction.amountToSell, _auction.amountToSell);
    assertEq(__auction.amountToRaise, _auction.amountToRaise);
    assertEq(__auction.initialTimestamp, block.timestamp);
    assertEq(__auction.forgoneCollateralReceiver, _auction.forgoneCollateralReceiver);
    assertEq(__auction.auctionIncomeRecipient, _auction.auctionIncomeRecipient);
  }

  function test_Call_SafeEngine_TransferCollateral(
    CollateralAuction memory _auction,
    uint256 _auctionsStarted
  ) public happyPath(_auction, _auctionsStarted) {
    vm.expectCall(
      address(mockSafeEngine),
      abi.encodeCall(
        mockSafeEngine.transferCollateral,
        (collateralType, authorizedAccount, address(collateralAuctionHouse), _auction.amountToSell)
      ),
      1
    );

    collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );
  }

  function test_Emit_StartAuction(
    CollateralAuction memory _auction,
    uint256 _auctionsStarted
  ) public happyPath(_auction, _auctionsStarted) {
    vm.expectEmit();
    emit StartAuction(_auctionsStarted + 1, block.timestamp, _auction.amountToSell, _auction.amountToRaise);

    collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );
  }

  function test_Return_Id(
    CollateralAuction memory _auction,
    uint256 _auctionsStarted
  ) public happyPath(_auction, _auctionsStarted) {
    uint256 _id = collateralAuctionHouse.startAuction(
      _auction.forgoneCollateralReceiver, _auction.auctionIncomeRecipient, _auction.amountToRaise, _auction.amountToSell
    );

    assertEq(_id, _auctionsStarted + 1);
  }
}

contract Unit_CollateralAuctionHouse_GetAdjustedBid is Base {
  struct GetAdjustedBidScenario {
    CollateralAuction auction;
    uint256 bid;
  }

  modifier happyPath(GetAdjustedBidScenario memory _getAdjustedBidScenario) {
    _assumeHappyPath(_getAdjustedBidScenario);
    _mockValues(_getAdjustedBidScenario);
    _;
  }

  function _assumeHappyPath(GetAdjustedBidScenario memory _getAdjustedBidScenario) internal pure {
    vm.assume(notOverflowMul(_getAdjustedBidScenario.bid, RAY));
  }

  function _mockValues(GetAdjustedBidScenario memory _getAdjustedBidScenario) internal {
    _mockAuction(_getAdjustedBidScenario.auction);
  }

  function test_Return_InvalidBid_AmountToSell(GetAdjustedBidScenario memory _getAdjustedBidScenario)
    public
    happyPath(_getAdjustedBidScenario)
  {
    _getAdjustedBidScenario.auction.amountToSell = 0;
    _mockValues(_getAdjustedBidScenario);

    (bool __valid, uint256 __adjustedBid) =
      collateralAuctionHouse.getAdjustedBid(_getAdjustedBidScenario.auction.id, _getAdjustedBidScenario.bid);

    assertEq(__valid, false);
    assertEq(__adjustedBid, _getAdjustedBidScenario.bid);
  }

  function test_Return_InvalidBid_AmountToRaise(GetAdjustedBidScenario memory _getAdjustedBidScenario)
    public
    happyPath(_getAdjustedBidScenario)
  {
    vm.assume(_getAdjustedBidScenario.auction.amountToSell > 0);
    _getAdjustedBidScenario.auction.amountToRaise = 0;
    _mockValues(_getAdjustedBidScenario);

    (bool __valid, uint256 __adjustedBid) =
      collateralAuctionHouse.getAdjustedBid(_getAdjustedBidScenario.auction.id, _getAdjustedBidScenario.bid);

    assertEq(__valid, false);
    assertEq(__adjustedBid, _getAdjustedBidScenario.bid);
  }

  function test_Return_InvalidBid_Bid(GetAdjustedBidScenario memory _getAdjustedBidScenario)
    public
    happyPath(_getAdjustedBidScenario)
  {
    vm.assume(_getAdjustedBidScenario.auction.amountToSell > 0);
    vm.assume(_getAdjustedBidScenario.auction.amountToRaise > 0);
    _getAdjustedBidScenario.bid = 0;

    (bool __valid, uint256 __adjustedBid) =
      collateralAuctionHouse.getAdjustedBid(_getAdjustedBidScenario.auction.id, _getAdjustedBidScenario.bid);

    assertEq(__valid, false);
    assertEq(__adjustedBid, _getAdjustedBidScenario.bid);
  }

  function test_Return_InvalidBid_MinimumBid(GetAdjustedBidScenario memory _getAdjustedBidScenario)
    public
    happyPath(_getAdjustedBidScenario)
  {
    vm.assume(_getAdjustedBidScenario.auction.amountToSell > 0);
    vm.assume(_getAdjustedBidScenario.auction.amountToRaise > 0);
    vm.assume(_getAdjustedBidScenario.bid > 0 && _getAdjustedBidScenario.bid < cahParams.minimumBid);

    (bool __valid, uint256 __adjustedBid) =
      collateralAuctionHouse.getAdjustedBid(_getAdjustedBidScenario.auction.id, _getAdjustedBidScenario.bid);

    assertEq(__valid, false);
    assertEq(__adjustedBid, _getAdjustedBidScenario.bid);
  }

  function test_Return_InvalidBid_RemainingToRaise(GetAdjustedBidScenario memory _getAdjustedBidScenario)
    public
    happyPath(_getAdjustedBidScenario)
  {
    vm.assume(_getAdjustedBidScenario.auction.amountToSell > 0);
    vm.assume(_getAdjustedBidScenario.auction.amountToRaise > 0);
    vm.assume(_getAdjustedBidScenario.bid != 0 && _getAdjustedBidScenario.bid >= cahParams.minimumBid);

    _getAdjustedBidScenario.auction.amountToRaise = _getAdjustedBidScenario.bid * RAY + WAD;
    _mockValues(_getAdjustedBidScenario);

    (bool __valid, uint256 __adjustedBid) =
      collateralAuctionHouse.getAdjustedBid(_getAdjustedBidScenario.auction.id, _getAdjustedBidScenario.bid);

    assertEq(__valid, false);
    assertEq(__adjustedBid, _getAdjustedBidScenario.bid);
  }

  function test_Return_ValidBid_RemainingToRaise_0(GetAdjustedBidScenario memory _getAdjustedBidScenario)
    public
    happyPath(_getAdjustedBidScenario)
  {
    vm.assume(_getAdjustedBidScenario.auction.amountToSell > 0);
    vm.assume(_getAdjustedBidScenario.auction.amountToRaise > 0);
    vm.assume(_getAdjustedBidScenario.bid != 0 && _getAdjustedBidScenario.bid >= cahParams.minimumBid);
    _getAdjustedBidScenario.auction.amountToRaise = _getAdjustedBidScenario.bid * RAY;
    _mockValues(_getAdjustedBidScenario);

    (bool __valid, uint256 __adjustedBid) =
      collateralAuctionHouse.getAdjustedBid(_getAdjustedBidScenario.auction.id, _getAdjustedBidScenario.bid);

    assertEq(__valid, true);
    assertEq(__adjustedBid, _getAdjustedBidScenario.bid);
  }

  function test_Return_ValidBid_RemainingToRaise_1(GetAdjustedBidScenario memory _getAdjustedBidScenario)
    public
    happyPath(_getAdjustedBidScenario)
  {
    vm.assume(_getAdjustedBidScenario.auction.amountToSell > 0);
    vm.assume(_getAdjustedBidScenario.auction.amountToRaise > 0);
    vm.assume(_getAdjustedBidScenario.bid != 0 && _getAdjustedBidScenario.bid >= cahParams.minimumBid);
    vm.assume(_getAdjustedBidScenario.bid * RAY <= _getAdjustedBidScenario.auction.amountToRaise);
    uint256 _remainingToRaise = _getAdjustedBidScenario.auction.amountToRaise - _getAdjustedBidScenario.bid * RAY;
    vm.assume(_remainingToRaise >= RAY);

    (bool __valid, uint256 __adjustedBid) =
      collateralAuctionHouse.getAdjustedBid(_getAdjustedBidScenario.auction.id, _getAdjustedBidScenario.bid);

    assertEq(__valid, true);
    assertEq(__adjustedBid, _getAdjustedBidScenario.bid);
  }

  function test_Return_ValidAdjustedBid(GetAdjustedBidScenario memory _getAdjustedBidScenario)
    public
    happyPath(_getAdjustedBidScenario)
  {
    vm.assume(_getAdjustedBidScenario.auction.amountToSell > 0);
    vm.assume(_getAdjustedBidScenario.auction.amountToRaise > 0);
    vm.assume(_getAdjustedBidScenario.bid != 0 && _getAdjustedBidScenario.bid >= cahParams.minimumBid);
    vm.assume(_getAdjustedBidScenario.bid * RAY > _getAdjustedBidScenario.auction.amountToRaise);

    uint256 _adjustedBid = _getAdjustedBidScenario.auction.amountToRaise / RAY + 1;

    (bool __valid, uint256 __adjustedBid) =
      collateralAuctionHouse.getAdjustedBid(_getAdjustedBidScenario.auction.id, _getAdjustedBidScenario.bid);

    assertEq(__valid, true);
    assertEq(__adjustedBid, _adjustedBid);
  }
}

contract Unit_CollateralAuctionHouse_GetCollateralBought is Base {
  using Math for uint256;

  struct GetCollateralBoughtScenario {
    CollateralAuction auction;
    uint256 bid;
    uint256 calcRedemptionPrice;
    uint256 collateralPrice;
    bool validCollateralPrice;
  }

  modifier happyPath(GetCollateralBoughtScenario memory _getCollateralBoughtScenario) {
    _assumeHappyPath(_getCollateralBoughtScenario);
    _mockValues(_getCollateralBoughtScenario);
    _;
  }

  function _assumeHappyPath(GetCollateralBoughtScenario memory _getCollateralBoughtScenario) internal view {
    vm.assume(notOverflowMul(_getCollateralBoughtScenario.bid, RAY));
    uint256 _adjustedBid = _computeAdjustedBid(_getCollateralBoughtScenario);

    vm.assume(_getCollateralBoughtScenario.calcRedemptionPrice > 0);

    vm.assume(block.timestamp >= _getCollateralBoughtScenario.auction.initialTimestamp);
    uint256 _auctionDiscount = _computeAuctionDiscount(_getCollateralBoughtScenario);

    vm.assume(notOverflowMul(_getCollateralBoughtScenario.collateralPrice, RAY));
    vm.assume(_getCollateralBoughtScenario.calcRedemptionPrice > 0);
    vm.assume(
      notOverflowMul(
        _getCollateralBoughtScenario.collateralPrice.rdiv(_getCollateralBoughtScenario.calcRedemptionPrice),
        _auctionDiscount
      )
    );
    uint256 _discountedPrice = _computeDiscountedPrice(_getCollateralBoughtScenario, _auctionDiscount);

    vm.assume(notOverflowMul(_adjustedBid, WAD));
    vm.assume(_discountedPrice > 0);
    uint256 _boughtCollateral = _adjustedBid.wdiv(_discountedPrice);

    if (_boughtCollateral > _getCollateralBoughtScenario.auction.amountToSell) {
      vm.assume(notOverflowMul(_adjustedBid, _getCollateralBoughtScenario.auction.amountToSell));
      vm.assume(_boughtCollateral > 0);
    }
  }

  function _mockValues(GetCollateralBoughtScenario memory _getCollateralBoughtScenario) internal {
    _mockAuction(_getCollateralBoughtScenario.auction);
    _mockOracleRelayerCalcRedemptionPrice(_getCollateralBoughtScenario.calcRedemptionPrice);
    _mockOracleRelayerCParams(collateralType, mockDelayedOracle);
    _mockDelayedOracleGetResultWithValidity(
      _getCollateralBoughtScenario.collateralPrice, _getCollateralBoughtScenario.validCollateralPrice
    );
  }

  function _computeAdjustedBid(GetCollateralBoughtScenario memory _getCollateralBoughtScenario)
    internal
    pure
    returns (uint256 _adjustedBid)
  {
    if (_getCollateralBoughtScenario.bid * RAY > _getCollateralBoughtScenario.auction.amountToRaise) {
      _adjustedBid = _getCollateralBoughtScenario.auction.amountToRaise / RAY + 1;
    } else {
      _adjustedBid = _getCollateralBoughtScenario.bid;
    }
  }

  function _computeRemainingToRaise(GetCollateralBoughtScenario memory _getCollateralBoughtScenario)
    internal
    pure
    returns (uint256 _remainingToRaise)
  {
    if (_getCollateralBoughtScenario.bid * RAY <= _getCollateralBoughtScenario.auction.amountToRaise) {
      _remainingToRaise = _getCollateralBoughtScenario.auction.amountToRaise - _getCollateralBoughtScenario.bid * RAY;
    }
  }

  function _computeAuctionDiscount(GetCollateralBoughtScenario memory _getCollateralBoughtScenario)
    internal
    view
    returns (uint256 _auctionDiscount)
  {
    uint256 _timeSinceCreation = block.timestamp - _getCollateralBoughtScenario.auction.initialTimestamp;
    _auctionDiscount = cahParams.perSecondDiscountUpdateRate.rpow(_timeSinceCreation).rmul(cahParams.minDiscount);

    if (_getCollateralBoughtScenario.auction.initialTimestamp == 0) return WAD;
    if (_getCollateralBoughtScenario.auction.initialTimestamp == block.timestamp) return cahParams.minDiscount;
    if (_auctionDiscount < cahParams.maxDiscount) return cahParams.maxDiscount;
  }

  function _computeDiscountedPrice(
    GetCollateralBoughtScenario memory _getCollateralBoughtScenario,
    uint256 _auctionDiscount
  ) internal pure returns (uint256 _discountedPrice) {
    _discountedPrice = _getCollateralBoughtScenario.collateralPrice.rdiv(
      _getCollateralBoughtScenario.calcRedemptionPrice
    ).wmul(_auctionDiscount);
  }

  function _computeBoughtCollateral(
    GetCollateralBoughtScenario memory _getCollateralBoughtScenario,
    uint256 _adjustedBid,
    uint256 _discountedPrice
  ) internal pure returns (uint256 _boughtCollateral, uint256 _readjustedBid) {
    _boughtCollateral = _adjustedBid.wdiv(_discountedPrice);

    if (_boughtCollateral <= _getCollateralBoughtScenario.auction.amountToSell) {
      return (_boughtCollateral, _adjustedBid);
    } else {
      _readjustedBid = _adjustedBid * _getCollateralBoughtScenario.auction.amountToSell / _boughtCollateral;
      return (_getCollateralBoughtScenario.auction.amountToSell, _readjustedBid);
    }
  }

  function test_Revert_CAH_InvalidRedemptionPriceProvided(
    GetCollateralBoughtScenario memory _getCollateralBoughtScenario
  ) public {
    vm.assume(_getCollateralBoughtScenario.auction.amountToSell > 0);
    vm.assume(_getCollateralBoughtScenario.auction.amountToRaise > 0);
    vm.assume(_getCollateralBoughtScenario.bid != 0 && _getCollateralBoughtScenario.bid >= cahParams.minimumBid);
    vm.assume(notOverflowMul(_getCollateralBoughtScenario.bid, RAY));
    uint256 _remainingToRaise = _computeRemainingToRaise(_getCollateralBoughtScenario);
    vm.assume(_remainingToRaise == 0 || _remainingToRaise >= RAY);

    _getCollateralBoughtScenario.calcRedemptionPrice = 0;
    _mockValues(_getCollateralBoughtScenario);

    vm.expectRevert(ICollateralAuctionHouse.CAH_InvalidRedemptionPriceProvided.selector);

    collateralAuctionHouse.getCollateralBought(
      _getCollateralBoughtScenario.auction.id, _getCollateralBoughtScenario.bid
    );
  }

  function test_Return_InvalidAuctionAndBid(GetCollateralBoughtScenario memory _getCollateralBoughtScenario)
    public
    happyPath(_getCollateralBoughtScenario)
  {
    uint256 _remainingToRaise = _computeRemainingToRaise(_getCollateralBoughtScenario);
    vm.assume(
      _getCollateralBoughtScenario.auction.amountToSell == 0 || _getCollateralBoughtScenario.auction.amountToRaise == 0
        || _getCollateralBoughtScenario.bid == 0 || _getCollateralBoughtScenario.bid < cahParams.minimumBid
        || (_remainingToRaise > 0 && _remainingToRaise < RAY)
    );

    (uint256 __boughtCollateral, uint256 __readjustedBid) = collateralAuctionHouse.getCollateralBought(
      _getCollateralBoughtScenario.auction.id, _getCollateralBoughtScenario.bid
    );

    assertEq(__boughtCollateral, 0);
    assertEq(__readjustedBid, _getCollateralBoughtScenario.bid);
  }

  function test_Return_InvalidCollateralPrice(GetCollateralBoughtScenario memory _getCollateralBoughtScenario)
    public
    happyPath(_getCollateralBoughtScenario)
  {
    vm.assume(_getCollateralBoughtScenario.auction.amountToSell > 0);
    vm.assume(_getCollateralBoughtScenario.auction.amountToRaise > 0);
    vm.assume(_getCollateralBoughtScenario.bid != 0 && _getCollateralBoughtScenario.bid >= cahParams.minimumBid);
    uint256 _remainingToRaise = _computeRemainingToRaise(_getCollateralBoughtScenario);
    vm.assume(_remainingToRaise == 0 || _remainingToRaise >= RAY);
    vm.assume(
      _getCollateralBoughtScenario.collateralPrice == 0 || _getCollateralBoughtScenario.validCollateralPrice == false
    );

    uint256 _adjustedBid = _computeAdjustedBid(_getCollateralBoughtScenario);

    (uint256 __boughtCollateral, uint256 __readjustedBid) = collateralAuctionHouse.getCollateralBought(
      _getCollateralBoughtScenario.auction.id, _getCollateralBoughtScenario.bid
    );

    assertEq(__boughtCollateral, 0);
    assertEq(__readjustedBid, _adjustedBid);
  }

  function test_Return_BoughtCollateral_ReadjustedBid(GetCollateralBoughtScenario memory _getCollateralBoughtScenario)
    public
    happyPath(_getCollateralBoughtScenario)
  {
    vm.assume(_getCollateralBoughtScenario.auction.amountToSell > 0);
    vm.assume(_getCollateralBoughtScenario.auction.amountToRaise > 0);
    vm.assume(_getCollateralBoughtScenario.bid != 0 && _getCollateralBoughtScenario.bid >= cahParams.minimumBid);
    uint256 _remainingToRaise = _computeRemainingToRaise(_getCollateralBoughtScenario);
    vm.assume(_remainingToRaise == 0 || _remainingToRaise >= RAY);
    vm.assume(
      _getCollateralBoughtScenario.collateralPrice > 0 && _getCollateralBoughtScenario.validCollateralPrice == true
    );

    (uint256 _boughtCollateral, uint256 _readjustedBid) = _computeBoughtCollateral(
      _getCollateralBoughtScenario,
      _computeAdjustedBid(_getCollateralBoughtScenario),
      _computeDiscountedPrice(_getCollateralBoughtScenario, _computeAuctionDiscount(_getCollateralBoughtScenario))
    );

    (uint256 __boughtCollateral, uint256 __readjustedBid) = collateralAuctionHouse.getCollateralBought(
      _getCollateralBoughtScenario.auction.id, _getCollateralBoughtScenario.bid
    );

    assertEq(__boughtCollateral, _boughtCollateral);
    assertEq(__readjustedBid, _readjustedBid);
  }
}

contract Unit_CollateralAuctionHouse_GetCollateralPrice is Base {
  modifier happyPath(uint256 _collateralPrice, bool _hasValidValue) {
    _mockValues(_collateralPrice, _hasValidValue);
    _;
  }

  function _mockValues(uint256 _collateralPrice, bool _hasValidValue) internal {
    _mockOracleRelayerCParams(collateralType, mockDelayedOracle);
    _mockDelayedOracleGetResultWithValidity(_collateralPrice, _hasValidValue);
  }

  function test_Return_InvalidCollateralPrice(
    uint256 _collateralPrice,
    bool _hasValidValue
  ) public happyPath(_collateralPrice, _hasValidValue) {
    vm.assume(!_hasValidValue);

    assertEq(collateralAuctionHouse.getCollateralPrice(), 0);
  }

  function test_Return_ValidCollateralPrice(
    uint256 _collateralPrice,
    bool _hasValidValue
  ) public happyPath(_collateralPrice, _hasValidValue) {
    vm.assume(_hasValidValue);

    assertEq(collateralAuctionHouse.getCollateralPrice(), _collateralPrice);
  }
}

contract Unit_CollateralAuctionHouse_GetAuctionDiscount is Base {
  using Math for uint256;

  modifier happyPath(CollateralAuction memory _auction) {
    _assumeHappyPath(_auction);
    _mockValues(_auction);
    _;
  }

  function _assumeHappyPath(CollateralAuction memory _auction) internal view {
    vm.assume(block.timestamp >= _auction.initialTimestamp);
  }

  function _mockValues(CollateralAuction memory _auction) internal {
    _mockAuction(_auction);
  }

  function test_Return_AuctionDiscount_NoDiscount(CollateralAuction memory _auction) public happyPath(_auction) {
    _auction.initialTimestamp = 0;
    _mockValues(_auction);

    assertEq(collateralAuctionHouse.getAuctionDiscount(_auction.id), WAD);
  }

  function test_Return_AuctionDiscount_MinDiscount(CollateralAuction memory _auction) public happyPath(_auction) {
    _auction.initialTimestamp = block.timestamp;
    _mockValues(_auction);

    assertEq(collateralAuctionHouse.getAuctionDiscount(_auction.id), cahParams.minDiscount);
  }

  function test_Return_AuctionDiscount_MaxDiscount(CollateralAuction memory _auction) public happyPath(_auction) {
    vm.assume(_auction.initialTimestamp > 0);
    uint256 _perSecondDiscountUpdateRate = 0;
    uint256 _timeSinceCreation = block.timestamp - _auction.initialTimestamp;
    uint256 _auctionDiscount = _perSecondDiscountUpdateRate.rpow(_timeSinceCreation).rmul(cahParams.minDiscount);
    vm.assume(_auctionDiscount < cahParams.maxDiscount);
    _mockPerSecondDiscountUpdateRate(_perSecondDiscountUpdateRate);

    assertEq(collateralAuctionHouse.getAuctionDiscount(_auction.id), cahParams.maxDiscount);
  }

  function test_Return_AuctionDiscount(CollateralAuction memory _auction) public happyPath(_auction) {
    vm.assume(_auction.initialTimestamp > 0);
    uint256 _timeSinceCreation = block.timestamp - _auction.initialTimestamp;
    uint256 _auctionDiscount =
      cahParams.perSecondDiscountUpdateRate.rpow(_timeSinceCreation).rmul(cahParams.minDiscount);
    vm.assume(_auctionDiscount >= cahParams.maxDiscount);

    assertEq(collateralAuctionHouse.getAuctionDiscount(_auction.id), _auctionDiscount);
  }
}

contract Unit_CollateralAuctionHouse_GetBoughtCollateral is Base {
  using Math for uint256;

  struct GetBoughtCollateralScenario {
    uint256 collateralPrice;
    uint256 systemCoinPrice;
    uint256 amountToSell;
    uint256 adjustedBid;
    uint256 customDiscount;
  }

  function _assumeHappyPath(GetBoughtCollateralScenario memory _getBoughtCollateralScenario)
    internal
    pure
    returns (uint256 _boughtCollateral)
  {
    vm.assume(notOverflowMul(_getBoughtCollateralScenario.collateralPrice, RAY));
    vm.assume(_getBoughtCollateralScenario.systemCoinPrice > 0);
    vm.assume(
      notOverflowMul(
        _getBoughtCollateralScenario.collateralPrice.rdiv(_getBoughtCollateralScenario.systemCoinPrice),
        _getBoughtCollateralScenario.customDiscount
      )
    );
    uint256 _discountedPrice = _getBoughtCollateralScenario.collateralPrice.rdiv(
      _getBoughtCollateralScenario.systemCoinPrice
    ).wmul(_getBoughtCollateralScenario.customDiscount);

    vm.assume(notOverflowMul(_getBoughtCollateralScenario.adjustedBid, WAD));
    vm.assume(_discountedPrice > 0);
    _boughtCollateral = _getBoughtCollateralScenario.adjustedBid.wdiv(_discountedPrice);

    if (_boughtCollateral > _getBoughtCollateralScenario.amountToSell) {
      vm.assume(notOverflowMul(_getBoughtCollateralScenario.adjustedBid, _getBoughtCollateralScenario.amountToSell));
      vm.assume(_boughtCollateral > 0);
    }
  }

  function test_Return_BoughtCollateral_AdjustedBid(GetBoughtCollateralScenario memory _getBoughtCollateralScenario)
    public
  {
    uint256 _boughtCollateral = _assumeHappyPath(_getBoughtCollateralScenario);
    vm.assume(_boughtCollateral <= _getBoughtCollateralScenario.amountToSell);

    (uint256 __boughtCollateral, uint256 __readjustedBid) = collateralAuctionHouse.getBoughtCollateral(
      _getBoughtCollateralScenario.collateralPrice,
      _getBoughtCollateralScenario.systemCoinPrice,
      _getBoughtCollateralScenario.amountToSell,
      _getBoughtCollateralScenario.adjustedBid,
      _getBoughtCollateralScenario.customDiscount
    );

    assertEq(__boughtCollateral, _boughtCollateral);
    assertEq(__readjustedBid, _getBoughtCollateralScenario.adjustedBid);
  }

  function test_Return_AmountToSell_ReadjustedBid(GetBoughtCollateralScenario memory _getBoughtCollateralScenario)
    public
  {
    uint256 _boughtCollateral = _assumeHappyPath(_getBoughtCollateralScenario);
    vm.assume(_boughtCollateral > _getBoughtCollateralScenario.amountToSell);

    uint256 _readjustedBid =
      _getBoughtCollateralScenario.adjustedBid * _getBoughtCollateralScenario.amountToSell / _boughtCollateral;

    (uint256 __boughtCollateral, uint256 __readjustedBid) = collateralAuctionHouse.getBoughtCollateral(
      _getBoughtCollateralScenario.collateralPrice,
      _getBoughtCollateralScenario.systemCoinPrice,
      _getBoughtCollateralScenario.amountToSell,
      _getBoughtCollateralScenario.adjustedBid,
      _getBoughtCollateralScenario.customDiscount
    );

    assertEq(__boughtCollateral, _getBoughtCollateralScenario.amountToSell);
    assertEq(__readjustedBid, _readjustedBid);
  }
}

contract Unit_CollateralAuctionHouse_BuyCollateral is Base {
  using Math for uint256;

  event BuyCollateral(
    uint256 indexed _id, address _bidder, uint256 _blockTimestamp, uint256 _raisedAmount, uint256 _soldAmount
  );
  event SettleAuction(
    uint256 indexed _id, uint256 _blockTimestamp, address _leftoverReceiver, uint256 _leftoverCollateral
  );

  struct BuyCollateralScenario {
    CollateralAuction auction;
    uint256 bid;
    uint256 redemptionPrice;
    uint256 collateralPrice;
  }

  modifier happyPath(BuyCollateralScenario memory _buyCollateralScenario) {
    vm.startPrank(user);
    _assumeHappyPath(_buyCollateralScenario);
    _mockValues(_buyCollateralScenario);
    _;
  }

  function _assumeHappyPath(BuyCollateralScenario memory _buyCollateralScenario) internal view {
    vm.assume(_buyCollateralScenario.auction.amountToSell > 0);
    vm.assume(_buyCollateralScenario.auction.amountToRaise > 0);
    vm.assume(_buyCollateralScenario.bid != 0 && _buyCollateralScenario.bid >= cahParams.minimumBid);
    vm.assume(_buyCollateralScenario.redemptionPrice > 0);
    vm.assume(_buyCollateralScenario.collateralPrice > 0);

    vm.assume(notOverflowMul(_buyCollateralScenario.bid, RAY));
    uint256 _adjustedBid = _computeAdjustedBid(_buyCollateralScenario);

    vm.assume(block.timestamp >= _buyCollateralScenario.auction.initialTimestamp);
    uint256 _auctionDiscount = _computeAuctionDiscount(_buyCollateralScenario);

    vm.assume(notOverflowMul(_buyCollateralScenario.collateralPrice, RAY));
    vm.assume(
      notOverflowMul(
        _buyCollateralScenario.collateralPrice.rdiv(_buyCollateralScenario.redemptionPrice), _auctionDiscount
      )
    );
    uint256 _discountedPrice = _computeDiscountedPrice(_buyCollateralScenario, _auctionDiscount);
    vm.assume(_discountedPrice > 0);

    vm.assume(notOverflowMul(_adjustedBid, _buyCollateralScenario.auction.amountToSell));
    (uint256 _boughtCollateral, uint256 _readjustedBid) =
      _computeBoughtCollateral(_buyCollateralScenario, _adjustedBid, _discountedPrice);
    vm.assume(_boughtCollateral > 0);

    uint256 _leftToRaise = _computeLeftToRaise(_buyCollateralScenario, _readjustedBid);
    vm.assume(_leftToRaise == 0 || _leftToRaise >= RAY);
  }

  function _mockValues(BuyCollateralScenario memory _buyCollateralScenario) internal {
    _mockAuction(_buyCollateralScenario.auction);
    _mockOracleRelayerRedemptionPrice(_buyCollateralScenario.redemptionPrice);
    _mockOracleRelayerCParams(collateralType, mockDelayedOracle);
    _mockDelayedOracleGetResultWithValidity(_buyCollateralScenario.collateralPrice, true);
  }

  function _computeAdjustedBid(BuyCollateralScenario memory _buyCollateralScenario)
    internal
    pure
    returns (uint256 _adjustedBid)
  {
    if (_buyCollateralScenario.bid * RAY > _buyCollateralScenario.auction.amountToRaise) {
      _adjustedBid = _buyCollateralScenario.auction.amountToRaise / RAY + 1;
    } else {
      _adjustedBid = _buyCollateralScenario.bid;
    }
  }

  function _computeAuctionDiscount(BuyCollateralScenario memory _buyCollateralScenario)
    internal
    view
    returns (uint256 _auctionDiscount)
  {
    uint256 _timeSinceCreation = block.timestamp - _buyCollateralScenario.auction.initialTimestamp;
    _auctionDiscount = cahParams.perSecondDiscountUpdateRate.rpow(_timeSinceCreation).rmul(cahParams.minDiscount);

    if (_buyCollateralScenario.auction.initialTimestamp == 0) return WAD;
    if (_buyCollateralScenario.auction.initialTimestamp == block.timestamp) return cahParams.minDiscount;
    if (_auctionDiscount < cahParams.maxDiscount) return cahParams.maxDiscount;
  }

  function _computeDiscountedPrice(
    BuyCollateralScenario memory _buyCollateralScenario,
    uint256 _auctionDiscount
  ) internal pure returns (uint256 _discountedPrice) {
    _discountedPrice =
      _buyCollateralScenario.collateralPrice.rdiv(_buyCollateralScenario.redemptionPrice).wmul(_auctionDiscount);
  }

  function _computeBoughtCollateral(
    BuyCollateralScenario memory _buyCollateralScenario,
    uint256 _adjustedBid,
    uint256 _discountedPrice
  ) internal pure returns (uint256 _boughtCollateral, uint256 _readjustedBid) {
    _boughtCollateral = _adjustedBid.wdiv(_discountedPrice);

    if (_boughtCollateral <= _buyCollateralScenario.auction.amountToSell) {
      return (_boughtCollateral, _adjustedBid);
    } else {
      _readjustedBid = _adjustedBid * _buyCollateralScenario.auction.amountToSell / _boughtCollateral;
      return (_buyCollateralScenario.auction.amountToSell, _readjustedBid);
    }
  }

  function _computeLeftToSell(
    BuyCollateralScenario memory _buyCollateralScenario,
    uint256 _boughtCollateral
  ) internal pure returns (uint256 _leftToSell) {
    _leftToSell = _buyCollateralScenario.auction.amountToSell - _boughtCollateral;
  }

  function _computeLeftToRaise(
    BuyCollateralScenario memory _buyCollateralScenario,
    uint256 _readjustedBid
  ) internal pure returns (uint256 _leftToRaise) {
    if (_readjustedBid * RAY <= _buyCollateralScenario.auction.amountToRaise) {
      _leftToRaise = _buyCollateralScenario.auction.amountToRaise - _readjustedBid * RAY;
    }
  }

  function _computeRemainingToRaise(
    BuyCollateralScenario memory _buyCollateralScenario,
    uint256 _leftToSell
  ) internal pure returns (uint256 _remainingToRaise) {
    if (_leftToSell == 0 || _buyCollateralScenario.bid * RAY >= _buyCollateralScenario.auction.amountToRaise) {
      _remainingToRaise = _buyCollateralScenario.auction.amountToRaise;
    } else {
      _remainingToRaise = _buyCollateralScenario.auction.amountToRaise - _buyCollateralScenario.bid * RAY;
    }
  }

  function _computeSoldAll(uint256 _leftToSell, uint256 _leftToRaise) internal pure returns (bool _soldAll) {
    _soldAll = _leftToSell == 0 || _leftToRaise == 0;
  }

  function test_Revert_CAH_InexistentAuction_AmountToSell(BuyCollateralScenario memory _buyCollateralScenario) public {
    _buyCollateralScenario.auction.amountToSell = 0;
    _mockValues(_buyCollateralScenario);

    vm.expectRevert(ICollateralAuctionHouse.CAH_InexistentAuction.selector);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Revert_CAH_InexistentAuction_AmountToRaise(BuyCollateralScenario memory _buyCollateralScenario) public {
    vm.assume(_buyCollateralScenario.auction.amountToSell > 0);

    _buyCollateralScenario.auction.amountToRaise = 0;
    _mockValues(_buyCollateralScenario);

    vm.expectRevert(ICollateralAuctionHouse.CAH_InexistentAuction.selector);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Revert_CAH_InvalidBid_Null(BuyCollateralScenario memory _buyCollateralScenario) public {
    vm.assume(_buyCollateralScenario.auction.amountToSell > 0);
    vm.assume(_buyCollateralScenario.auction.amountToRaise > 0);

    _buyCollateralScenario.bid = 0;
    _mockValues(_buyCollateralScenario);

    vm.expectRevert(ICollateralAuctionHouse.CAH_InvalidBid.selector);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Revert_CAH_InvalidBid_MinimumBid(BuyCollateralScenario memory _buyCollateralScenario) public {
    vm.assume(_buyCollateralScenario.auction.amountToSell > 0);
    vm.assume(_buyCollateralScenario.auction.amountToRaise > 0);

    vm.assume(_buyCollateralScenario.bid > 0 && _buyCollateralScenario.bid < cahParams.minimumBid);
    _mockValues(_buyCollateralScenario);

    vm.expectRevert(ICollateralAuctionHouse.CAH_InvalidBid.selector);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Revert_CAH_InvalidRedemptionPriceProvided(BuyCollateralScenario memory _buyCollateralScenario) public {
    vm.assume(_buyCollateralScenario.auction.amountToSell > 0);
    vm.assume(_buyCollateralScenario.auction.amountToRaise > 0);
    vm.assume(_buyCollateralScenario.bid != 0 && _buyCollateralScenario.bid >= cahParams.minimumBid);
    vm.assume(notOverflowMul(_buyCollateralScenario.bid, RAY));

    _buyCollateralScenario.redemptionPrice = 0;
    _mockValues(_buyCollateralScenario);

    vm.expectRevert(ICollateralAuctionHouse.CAH_InvalidRedemptionPriceProvided.selector);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Revert_CAH_CollateralOracleInvalidValue(BuyCollateralScenario memory _buyCollateralScenario) public {
    vm.assume(_buyCollateralScenario.auction.amountToSell > 0);
    vm.assume(_buyCollateralScenario.auction.amountToRaise > 0);
    vm.assume(_buyCollateralScenario.bid != 0 && _buyCollateralScenario.bid >= cahParams.minimumBid);
    vm.assume(_buyCollateralScenario.redemptionPrice > 0);
    vm.assume(notOverflowMul(_buyCollateralScenario.bid, RAY));

    _buyCollateralScenario.collateralPrice = 0;
    _mockValues(_buyCollateralScenario);

    vm.expectRevert(ICollateralAuctionHouse.CAH_CollateralOracleInvalidValue.selector);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Revert_CAH_NullBoughtAmount(BuyCollateralScenario memory _buyCollateralScenario) public {
    vm.assume(_buyCollateralScenario.auction.amountToSell > 0);
    vm.assume(_buyCollateralScenario.auction.amountToRaise > 0);
    vm.assume(_buyCollateralScenario.bid != 0 && _buyCollateralScenario.bid >= cahParams.minimumBid);
    vm.assume(_buyCollateralScenario.redemptionPrice > 0);
    vm.assume(_buyCollateralScenario.collateralPrice > 0);
    vm.assume(notOverflowMul(_buyCollateralScenario.bid, RAY));
    uint256 _adjustedBid = _computeAdjustedBid(_buyCollateralScenario);
    vm.assume(block.timestamp >= _buyCollateralScenario.auction.initialTimestamp);
    uint256 _auctionDiscount = _computeAuctionDiscount(_buyCollateralScenario);
    vm.assume(notOverflowMul(_buyCollateralScenario.collateralPrice, RAY));
    vm.assume(
      notOverflowMul(
        _buyCollateralScenario.collateralPrice.rdiv(_buyCollateralScenario.redemptionPrice), _auctionDiscount
      )
    );
    uint256 _discountedPrice = _computeDiscountedPrice(_buyCollateralScenario, _auctionDiscount);
    vm.assume(_discountedPrice > 0);
    vm.assume(notOverflowMul(_adjustedBid, _buyCollateralScenario.auction.amountToSell));

    (uint256 _boughtCollateral,) = _computeBoughtCollateral(_buyCollateralScenario, _adjustedBid, _discountedPrice);
    vm.assume(_boughtCollateral == 0);
    _mockValues(_buyCollateralScenario);

    vm.expectRevert(ICollateralAuctionHouse.CAH_NullBoughtAmount.selector);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Revert_CAH_InvalidLeftToRaise(BuyCollateralScenario memory _buyCollateralScenario) public {
    vm.assume(_buyCollateralScenario.auction.amountToSell > 0);
    vm.assume(_buyCollateralScenario.auction.amountToRaise > 0);
    vm.assume(_buyCollateralScenario.bid != 0 && _buyCollateralScenario.bid >= cahParams.minimumBid);
    vm.assume(_buyCollateralScenario.redemptionPrice > 0);
    vm.assume(_buyCollateralScenario.collateralPrice > 0);
    vm.assume(notOverflowMul(_buyCollateralScenario.bid, RAY));
    uint256 _adjustedBid = _computeAdjustedBid(_buyCollateralScenario);
    vm.assume(block.timestamp >= _buyCollateralScenario.auction.initialTimestamp);
    uint256 _auctionDiscount = _computeAuctionDiscount(_buyCollateralScenario);
    vm.assume(notOverflowMul(_buyCollateralScenario.collateralPrice, RAY));
    vm.assume(
      notOverflowMul(
        _buyCollateralScenario.collateralPrice.rdiv(_buyCollateralScenario.redemptionPrice), _auctionDiscount
      )
    );
    uint256 _discountedPrice = _computeDiscountedPrice(_buyCollateralScenario, _auctionDiscount);
    vm.assume(_discountedPrice > 0);
    vm.assume(notOverflowMul(_adjustedBid, _buyCollateralScenario.auction.amountToSell));
    (uint256 _boughtCollateral, uint256 _readjustedBid) =
      _computeBoughtCollateral(_buyCollateralScenario, _adjustedBid, _discountedPrice);
    vm.assume(_boughtCollateral > 0);

    uint256 _leftToRaise = _computeLeftToRaise(_buyCollateralScenario, _readjustedBid);
    vm.assume(_leftToRaise > 0 && _leftToRaise < RAY);
    _mockValues(_buyCollateralScenario);

    vm.expectRevert(ICollateralAuctionHouse.CAH_InvalidLeftToRaise.selector);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Set_Auctions(BuyCollateralScenario memory _buyCollateralScenario)
    public
    happyPath(_buyCollateralScenario)
  {
    (uint256 _boughtCollateral, uint256 _readjustedBid) = _computeBoughtCollateral(
      _buyCollateralScenario,
      _computeAdjustedBid(_buyCollateralScenario),
      _computeDiscountedPrice(_buyCollateralScenario, _computeAuctionDiscount(_buyCollateralScenario))
    );
    uint256 _leftToSell = _computeLeftToSell(_buyCollateralScenario, _boughtCollateral);
    uint256 _leftToRaise = _computeLeftToRaise(_buyCollateralScenario, _readjustedBid);
    bool _soldAll = _computeSoldAll(_leftToSell, _leftToRaise);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);

    ICollateralAuctionHouse.Auction memory _auction = collateralAuctionHouse.auctions(_buyCollateralScenario.auction.id);

    if (_soldAll) {
      assertEq(_auction.amountToSell, 0);
      assertEq(_auction.amountToRaise, 0);
      assertEq(_auction.initialTimestamp, 0);
      assertEq(_auction.forgoneCollateralReceiver, address(0));
      assertEq(_auction.auctionIncomeRecipient, address(0));
    } else {
      assertEq(_auction.amountToSell, _leftToSell);
      assertEq(_auction.amountToRaise, _leftToRaise);
      assertEq(_auction.initialTimestamp, _buyCollateralScenario.auction.initialTimestamp);
      assertEq(_auction.forgoneCollateralReceiver, _buyCollateralScenario.auction.forgoneCollateralReceiver);
      assertEq(_auction.auctionIncomeRecipient, _buyCollateralScenario.auction.auctionIncomeRecipient);
    }
  }

  function test_Call_SafeEngine_TransferInternalCoins(BuyCollateralScenario memory _buyCollateralScenario)
    public
    happyPath(_buyCollateralScenario)
  {
    (, uint256 _readjustedBid) = _computeBoughtCollateral(
      _buyCollateralScenario,
      _computeAdjustedBid(_buyCollateralScenario),
      _computeDiscountedPrice(_buyCollateralScenario, _computeAuctionDiscount(_buyCollateralScenario))
    );

    vm.expectCall(
      address(mockSafeEngine),
      abi.encodeCall(
        mockSafeEngine.transferInternalCoins,
        (user, _buyCollateralScenario.auction.auctionIncomeRecipient, _readjustedBid * RAY)
      ),
      1
    );

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Call_SafeEngine_TransferCollateral(BuyCollateralScenario memory _buyCollateralScenario)
    public
    happyPath(_buyCollateralScenario)
  {
    (uint256 _boughtCollateral, uint256 _readjustedBid) = _computeBoughtCollateral(
      _buyCollateralScenario,
      _computeAdjustedBid(_buyCollateralScenario),
      _computeDiscountedPrice(_buyCollateralScenario, _computeAuctionDiscount(_buyCollateralScenario))
    );
    uint256 _leftToSell = _computeLeftToSell(_buyCollateralScenario, _boughtCollateral);
    bool _soldAll = _computeSoldAll(_leftToSell, _computeLeftToRaise(_buyCollateralScenario, _readjustedBid));

    vm.expectCall(
      address(mockSafeEngine),
      abi.encodeCall(
        mockSafeEngine.transferCollateral, (collateralType, address(collateralAuctionHouse), user, _boughtCollateral)
      ),
      1
    );
    if (_soldAll) {
      vm.expectCall(
        address(mockSafeEngine),
        abi.encodeCall(
          mockSafeEngine.transferCollateral,
          (
            collateralType,
            address(collateralAuctionHouse),
            _buyCollateralScenario.auction.forgoneCollateralReceiver,
            _leftToSell
          )
        ),
        1
      );
    } else {
      vm.expectCall(
        address(mockSafeEngine),
        abi.encodeCall(
          mockSafeEngine.transferCollateral,
          (
            collateralType,
            address(collateralAuctionHouse),
            _buyCollateralScenario.auction.forgoneCollateralReceiver,
            _leftToSell
          )
        ),
        0
      );
    }

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Emit_BuyCollateral(BuyCollateralScenario memory _buyCollateralScenario)
    public
    happyPath(_buyCollateralScenario)
  {
    (uint256 _boughtCollateral, uint256 _readjustedBid) = _computeBoughtCollateral(
      _buyCollateralScenario,
      _computeAdjustedBid(_buyCollateralScenario),
      _computeDiscountedPrice(_buyCollateralScenario, _computeAuctionDiscount(_buyCollateralScenario))
    );

    vm.expectEmit();
    emit BuyCollateral(_buyCollateralScenario.auction.id, user, block.timestamp, _readjustedBid, _boughtCollateral);

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Call_LiquidationEngine_RemoveCoinsFromAuction(BuyCollateralScenario memory _buyCollateralScenario)
    public
    happyPath(_buyCollateralScenario)
  {
    (uint256 _boughtCollateral, uint256 _readjustedBid) = _computeBoughtCollateral(
      _buyCollateralScenario,
      _computeAdjustedBid(_buyCollateralScenario),
      _computeDiscountedPrice(_buyCollateralScenario, _computeAuctionDiscount(_buyCollateralScenario))
    );
    uint256 _leftToSell = _computeLeftToSell(_buyCollateralScenario, _boughtCollateral);
    uint256 _remainingToRaise = _computeRemainingToRaise(_buyCollateralScenario, _leftToSell);
    bool _soldAll = _computeSoldAll(_leftToSell, _computeLeftToRaise(_buyCollateralScenario, _readjustedBid));

    if (_soldAll) {
      vm.expectCall(
        address(mockLiquidationEngine),
        abi.encodeCall(mockLiquidationEngine.removeCoinsFromAuction, (_remainingToRaise)),
        1
      );
    } else {
      vm.expectCall(
        address(mockLiquidationEngine),
        abi.encodeCall(mockLiquidationEngine.removeCoinsFromAuction, (_readjustedBid * RAY)),
        1
      );
    }

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Emit_SettleAuction(BuyCollateralScenario memory _buyCollateralScenario)
    public
    happyPath(_buyCollateralScenario)
  {
    (uint256 _boughtCollateral, uint256 _readjustedBid) = _computeBoughtCollateral(
      _buyCollateralScenario,
      _computeAdjustedBid(_buyCollateralScenario),
      _computeDiscountedPrice(_buyCollateralScenario, _computeAuctionDiscount(_buyCollateralScenario))
    );
    uint256 _leftToSell = _computeLeftToSell(_buyCollateralScenario, _boughtCollateral);
    bool _soldAll = _computeSoldAll(_leftToSell, _computeLeftToRaise(_buyCollateralScenario, _readjustedBid));

    vm.assume(_soldAll);
    vm.expectEmit();
    emit SettleAuction(
      _buyCollateralScenario.auction.id,
      block.timestamp,
      _buyCollateralScenario.auction.forgoneCollateralReceiver,
      _leftToSell
    );

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function testFail_Emit_SettleAuction(BuyCollateralScenario memory _buyCollateralScenario)
    public
    happyPath(_buyCollateralScenario)
  {
    (uint256 _boughtCollateral, uint256 _readjustedBid) = _computeBoughtCollateral(
      _buyCollateralScenario,
      _computeAdjustedBid(_buyCollateralScenario),
      _computeDiscountedPrice(_buyCollateralScenario, _computeAuctionDiscount(_buyCollateralScenario))
    );
    uint256 _leftToSell = _computeLeftToSell(_buyCollateralScenario, _boughtCollateral);
    bool _soldAll = _computeSoldAll(_leftToSell, _computeLeftToRaise(_buyCollateralScenario, _readjustedBid));

    vm.assume(!_soldAll);
    vm.expectEmit(false, false, false, false);
    emit SettleAuction(
      _buyCollateralScenario.auction.id,
      block.timestamp,
      _buyCollateralScenario.auction.forgoneCollateralReceiver,
      _leftToSell
    );

    collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);
  }

  function test_Return_BoughtCollateral_ReadjustedBid(BuyCollateralScenario memory _buyCollateralScenario)
    public
    happyPath(_buyCollateralScenario)
  {
    (uint256 _boughtCollateral, uint256 _readjustedBid) = _computeBoughtCollateral(
      _buyCollateralScenario,
      _computeAdjustedBid(_buyCollateralScenario),
      _computeDiscountedPrice(_buyCollateralScenario, _computeAuctionDiscount(_buyCollateralScenario))
    );

    (uint256 __boughtCollateral, uint256 __readjustedBid) =
      collateralAuctionHouse.buyCollateral(_buyCollateralScenario.auction.id, _buyCollateralScenario.bid);

    assertEq(__boughtCollateral, _boughtCollateral);
    assertEq(__readjustedBid, _readjustedBid);
  }
}

contract Unit_CollateralAuctionHouse_TerminateAuctionPrematurely is Base {
  event TerminateAuctionPrematurely(
    uint256 indexed _id, uint256 _blockTimestamp, address _leftoverReceiver, uint256 _leftoverCollateral
  );

  modifier happyPath(CollateralAuction memory _auction) {
    vm.startPrank(authorizedAccount);
    _assumeHappyPath(_auction);
    _mockValues(_auction);
    _;
  }

  function _assumeHappyPath(CollateralAuction memory _auction) internal pure {
    vm.assume(_auction.amountToSell > 0);
    vm.assume(_auction.amountToRaise > 0);
  }

  function _mockValues(CollateralAuction memory _auction) internal {
    _mockAuction(_auction);
  }

  function test_Revert_Unauthorized(CollateralAuction memory _auction) public {
    vm.expectRevert(IAuthorizable.Unauthorized.selector);

    collateralAuctionHouse.terminateAuctionPrematurely(_auction.id);
  }

  function test_Revert_CAH_InexistentAuction_AmountToSell(CollateralAuction memory _auction) public {
    vm.startPrank(authorizedAccount);
    _auction.amountToSell = 0;
    _mockValues({_auction: _auction});

    vm.expectRevert(ICollateralAuctionHouse.CAH_InexistentAuction.selector);

    collateralAuctionHouse.terminateAuctionPrematurely(_auction.id);
  }

  function test_Revert_CAH_InexistentAuction_AmountToRaise(CollateralAuction memory _auction) public {
    vm.startPrank(authorizedAccount);
    vm.assume(_auction.amountToSell > 0);
    _auction.amountToRaise = 0;
    _mockValues({_auction: _auction});

    vm.expectRevert(ICollateralAuctionHouse.CAH_InexistentAuction.selector);

    collateralAuctionHouse.terminateAuctionPrematurely(_auction.id);
  }

  function test_Call_LiquidationEngine_RemoveCoinsFromAuction(CollateralAuction memory _auction)
    public
    happyPath(_auction)
  {
    vm.expectCall(
      address(mockLiquidationEngine),
      abi.encodeCall(mockLiquidationEngine.removeCoinsFromAuction, (_auction.amountToRaise)),
      1
    );

    collateralAuctionHouse.terminateAuctionPrematurely(_auction.id);
  }

  function test_Call_SafeEngine_TransferCollateral(CollateralAuction memory _auction) public happyPath(_auction) {
    vm.expectCall(
      address(mockSafeEngine),
      abi.encodeCall(
        mockSafeEngine.transferCollateral,
        (collateralType, address(collateralAuctionHouse), authorizedAccount, _auction.amountToSell)
      ),
      1
    );

    collateralAuctionHouse.terminateAuctionPrematurely(_auction.id);
  }

  function test_Emit_TerminateAuctionPrematurely(CollateralAuction memory _auction) public happyPath(_auction) {
    vm.expectEmit();
    emit TerminateAuctionPrematurely(
      _auction.id, block.timestamp, _auction.forgoneCollateralReceiver, _auction.amountToSell
    );

    collateralAuctionHouse.terminateAuctionPrematurely(_auction.id);
  }

  function test_Set_Auctions(CollateralAuction memory _auction) public happyPath(_auction) {
    collateralAuctionHouse.terminateAuctionPrematurely(_auction.id);

    ICollateralAuctionHouse.Auction memory __auction = collateralAuctionHouse.auctions(_auction.id);

    assertEq(__auction.amountToSell, 0);
    assertEq(__auction.amountToRaise, 0);
    assertEq(__auction.initialTimestamp, 0);
    assertEq(__auction.forgoneCollateralReceiver, address(0));
    assertEq(__auction.auctionIncomeRecipient, address(0));
  }
}

contract Unit_CollateralAuctionHouse_ModifyParameters is Base {
  event AddAuthorization(address _account);
  event RemoveAuthorization(address _account);

  modifier happyPath() {
    vm.startPrank(authorizedAccount);
    _;
  }

  function test_Set_Parameters(ICollateralAuctionHouse.CollateralAuctionHouseParams memory _fuzz) public happyPath {
    vm.assume(_fuzz.minDiscount >= _fuzz.maxDiscount && _fuzz.minDiscount <= WAD);
    vm.assume(_fuzz.maxDiscount > 0);
    vm.assume(_fuzz.perSecondDiscountUpdateRate <= RAY);

    collateralAuctionHouse.modifyParameters('minimumBid', abi.encode(_fuzz.minimumBid));
    collateralAuctionHouse.modifyParameters('maxDiscount', abi.encode(_fuzz.maxDiscount));
    collateralAuctionHouse.modifyParameters('minDiscount', abi.encode(_fuzz.minDiscount));
    collateralAuctionHouse.modifyParameters(
      'perSecondDiscountUpdateRate', abi.encode(_fuzz.perSecondDiscountUpdateRate)
    );

    ICollateralAuctionHouse.CollateralAuctionHouseParams memory _params = collateralAuctionHouse.params();

    assertEq(abi.encode(_params), abi.encode(_fuzz));
  }

  function test_Set_LiquidationEngine(address _liquidationEngine) public happyPath {
    vm.assume(_liquidationEngine != address(0));
    vm.assume(_liquidationEngine != deployer);
    vm.assume(_liquidationEngine != authorizedAccount);

    collateralAuctionHouse.modifyParameters('liquidationEngine', abi.encode(_liquidationEngine));

    assertEq(address(collateralAuctionHouse.liquidationEngine()), _liquidationEngine);
  }

  function test_Emit_Authorization_LiquidationEngine(
    address _oldLiquidationEngine,
    address _newLiquidationEngine
  ) public happyPath {
    vm.assume(_newLiquidationEngine != address(0));
    vm.assume(_newLiquidationEngine != deployer);
    vm.assume(_newLiquidationEngine != authorizedAccount);
    vm.assume(_oldLiquidationEngine != deployer);
    vm.assume(_oldLiquidationEngine != authorizedAccount);

    _mockLiquidationEngine(_oldLiquidationEngine);
    collateralAuctionHouse.removeAuthorization(address(mockLiquidationEngine));
    collateralAuctionHouse.addAuthorization(_oldLiquidationEngine);

    if (_oldLiquidationEngine != address(0)) {
      vm.expectEmit();
      emit RemoveAuthorization(_oldLiquidationEngine);
    }
    vm.expectEmit();
    emit AddAuthorization(_newLiquidationEngine);

    collateralAuctionHouse.modifyParameters('liquidationEngine', abi.encode(_newLiquidationEngine));
  }

  function test_Set_OracleRelayer(address _oracleRelayer) public happyPath {
    vm.assume(_oracleRelayer != address(0));

    collateralAuctionHouse.modifyParameters('oracleRelayer', abi.encode(_oracleRelayer));

    assertEq(address(collateralAuctionHouse.oracleRelayer()), _oracleRelayer);
  }

  function test_Revert_NullAddress_LiquidationEngine() public {
    vm.startPrank(authorizedAccount);

    vm.expectRevert(Assertions.NullAddress.selector);

    collateralAuctionHouse.modifyParameters('liquidationEngine', abi.encode(0));
  }

  function test_Revert_NullAddress_OracleRelayer() public {
    vm.startPrank(authorizedAccount);

    vm.expectRevert(Assertions.NullAddress.selector);

    collateralAuctionHouse.modifyParameters('oracleRelayer', abi.encode(0));
  }

  function test_Revert_NotGreaterOrEqualThan_MinDiscount(uint256 _minDiscount) public {
    vm.startPrank(authorizedAccount);
    vm.assume(_minDiscount < cahParams.maxDiscount);

    vm.expectRevert(
      abi.encodeWithSelector(Assertions.NotGreaterOrEqualThan.selector, _minDiscount, cahParams.maxDiscount)
    );

    collateralAuctionHouse.modifyParameters('minDiscount', abi.encode(_minDiscount));
  }

  function test_Revert_NotLesserOrEqualThan_MinDiscount(uint256 _minDiscount) public {
    vm.startPrank(authorizedAccount);
    vm.assume(_minDiscount >= cahParams.maxDiscount && _minDiscount > WAD);

    vm.expectRevert(abi.encodeWithSelector(Assertions.NotLesserOrEqualThan.selector, _minDiscount, WAD));

    collateralAuctionHouse.modifyParameters('minDiscount', abi.encode(_minDiscount));
  }

  function test_Revert_NotGreaterThan_MaxDiscount(uint256 _maxDiscount) public {
    vm.startPrank(authorizedAccount);
    _maxDiscount = 0;

    vm.expectRevert(abi.encodeWithSelector(Assertions.NotGreaterThan.selector, _maxDiscount, 0));

    collateralAuctionHouse.modifyParameters('maxDiscount', abi.encode(_maxDiscount));
  }

  function test_Revert_NotLesserOrEqualThan_PerSecondDiscountUpdateRate(uint256 _perSecondDiscountUpdateRate) public {
    vm.startPrank(authorizedAccount);
    vm.assume(_perSecondDiscountUpdateRate > RAY);

    vm.expectRevert(abi.encodeWithSelector(Assertions.NotLesserOrEqualThan.selector, _perSecondDiscountUpdateRate, RAY));

    collateralAuctionHouse.modifyParameters('perSecondDiscountUpdateRate', abi.encode(_perSecondDiscountUpdateRate));
  }

  function test_Revert_UnrecognizedParam(bytes memory _data) public {
    vm.startPrank(authorizedAccount);

    vm.expectRevert(IModifiable.UnrecognizedParam.selector);

    collateralAuctionHouse.modifyParameters('unrecognizedParam', _data);
  }
}
