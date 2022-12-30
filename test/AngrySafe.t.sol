// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/AngrySafe.sol";
import "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract AngrySafeTest is Test {
    using stdStorage for StdStorage;
    StdStorage stdst;

    AngrySafe public safe;
    AngrySafe.Account public account;

    uint256 minDeposit_ = 1e18;
    uint256 depositsAmount_ = 2;

    IERC20 private weth;
    IERC20 private usdc;
    IERC20 private sweepToken;

    IUniswapV2Router private router;

    uint256 initialUsdcBalance = 50e50;

    function writeTokenBalance(
        address who,
        address token,
        uint256 amt
    ) internal {
        stdst
            .target(token)
            .sig(IERC20(token).balanceOf.selector)
            .with_key(who)
            .checked_write(amt);
    }

    function getAddresses(uint256 mode)
        internal
        pure
        returns (
            address routerAddress,
            address wethAddress,
            address usdcAddress,
            address sweepTokenAddress
        )
    {
        if (mode == 1) {
            routerAddress = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
            wethAddress = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
            usdcAddress = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
            sweepTokenAddress = 0x1CE0c2827e2eF14D5C4f29a091d735A204794041;
            return (routerAddress, wethAddress, usdcAddress, sweepTokenAddress);
        }

        // testnet
        routerAddress = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;
        wethAddress = 0x8BaBbB98678facC7342735486C851ABD7A0d17Ca;
        usdcAddress = 0x8a9424745056Eb399FD19a0EC26A14316684e274; //dai
        sweepTokenAddress = 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7; // busd
        return (routerAddress, wethAddress, usdcAddress, sweepTokenAddress);
    }

    function setUp() public {
        uint256 mode = 2; // 1 - mainnet, 2 - testnet
        (
            address routerAddress,
            address wethAddress,
            address usdcAddress,
            address sweepTokenAddress
        ) = getAddresses(mode);

        usdc = IERC20(usdcAddress);
        weth = IERC20(wethAddress);
        sweepToken = IERC20(sweepTokenAddress);

        if (mode == 1) {
            vm.createSelectFork("bsc");
        }
        if (mode == 2) {
            vm.createSelectFork("bsc_testnet");
        }

        safe = new AngrySafe(routerAddress, wethAddress, usdcAddress);

        writeTokenBalance(address(this), usdcAddress, initialUsdcBalance);
        writeTokenBalance(address(safe), sweepTokenAddress, initialUsdcBalance);

        usdc.approve(address(safe), type(uint256).max);
    }

    function testSetup() public {
        uint256 usdcBalance = usdc.balanceOf(address(this));
        // console.log("initial usdc balance", usdcBalance);
        assertEq(usdcBalance, initialUsdcBalance);
    }

    function testMain() public {
        _testFailDepositIfNotInitialized();
        _testInitialize();
        _testFailAlreadyInitialized();
        _testFirstDeposit();
        _testFailWithdrawBefore();
        _testFailDepositLessThanMinimum();
        _testAddToDepositInTheNextMonth();
        _testFailDepositIfCompleted();
        _testFailInitializeIfWithdrawOnly();
        _testWithdrawSuccess();
        _testFailSweepTokenIfNotOwner();
        _testSweepTokenByOwner();
    }

    function _testFailDepositIfNotInitialized() public {
        vm.expectRevert(AngrySafe.NotInitialized.selector);
        safe.deposit(1);
    }

    function _testInitialize() public {
        (
            account.lastDepositTimestamp,
            account.depositsLeft,
            account.usdcTotal,
            account.ethTotal,
            account.minDeposit,
            account.withdrawOnly
        ) = safe.accounts(address(this));

        assertEq(account.lastDepositTimestamp, 0);
        assertEq(account.depositsLeft, 0);
        assertEq(account.usdcTotal, 0);
        assertEq(account.ethTotal, 0);
        assertEq(account.minDeposit, 0);
        assertEq(account.withdrawOnly, false);

        // should set minDeposit and depositsAmount for msg.sender

        safe.initialize(minDeposit_, depositsAmount_);

        (
            account.lastDepositTimestamp,
            account.depositsLeft,
            account.usdcTotal,
            account.ethTotal,
            account.minDeposit,
            account.withdrawOnly
        ) = safe.accounts(address(this));

        assertEq(account.minDeposit, minDeposit_);
        assertEq(account.depositsLeft, depositsAmount_);
        assertEq(account.withdrawOnly, false);
    }

    function _testFailAlreadyInitialized() public {
        vm.expectRevert(AngrySafe.AlreadyInitialized.selector);
        safe.initialize(minDeposit_, depositsAmount_);
    }

    function _testFirstDeposit() public {
        safe.deposit(minDeposit_);

        (
            account.lastDepositTimestamp,
            account.depositsLeft,
            account.usdcTotal,
            account.ethTotal,
            account.minDeposit,
            account.withdrawOnly
        ) = safe.accounts(address(this));

        assertEq(account.lastDepositTimestamp, block.timestamp);
        assertEq(account.depositsLeft, depositsAmount_ - 1);
        assertEq(account.usdcTotal, minDeposit_);
        assertGt(account.ethTotal, 0);
        assertEq(account.minDeposit, minDeposit_);
        assertEq(account.withdrawOnly, false);
    }

    function _testFailWithdrawBefore() public {
        vm.expectRevert(AngrySafe.WithdrawalIsNotReady.selector);
        safe.withdraw();
    }

    function _testFailDepositLessThanMinimum() public {
        vm.expectRevert(AngrySafe.DepositLessThanMinimal.selector);
        safe.deposit(1);
    }

    function _testAddToDepositInTheSameMonth() public {
        vm.roll(1);
        vm.warp(block.timestamp + 4 days);

        (
            uint256 lastDepositTimestamp,
            uint256 depositsLeft,
            uint256 usdcTotal,
            uint256 ethTotal,
            uint256 minDeposit,
            bool withdrawOnly
        ) = safe.accounts(address(this));

        safe.deposit(minDeposit_);

        (
            account.lastDepositTimestamp,
            account.depositsLeft,
            account.usdcTotal,
            account.ethTotal,
            account.minDeposit,
            account.withdrawOnly
        ) = safe.accounts(address(this));

        assertEq(account.lastDepositTimestamp, lastDepositTimestamp);
        assertEq(account.depositsLeft, depositsLeft);
        assertEq(account.usdcTotal, usdcTotal + minDeposit_);
        assertGt(account.ethTotal, ethTotal);
        assertEq(account.minDeposit, minDeposit_);
        assertEq(account.withdrawOnly, false);
    }

    function _testAddToDepositInTheNextMonth() public {
        vm.roll(1);
        vm.warp(block.timestamp + 30 days + 1);
        {
            (
                uint256 lastDepositTimestamp,
                uint256 depositsLeft,
                uint256 usdcTotal,
                uint256 ethTotal,
                uint256 minDeposit,
                bool withdrawOnly
            ) = safe.accounts(address(this));

            safe.deposit(minDeposit_);

            (
                account.lastDepositTimestamp,
                account.depositsLeft,
                account.usdcTotal,
                account.ethTotal,
                account.minDeposit,
                account.withdrawOnly
            ) = safe.accounts(address(this));

            assertEq(account.lastDepositTimestamp, block.timestamp);
            assertEq(account.depositsLeft, depositsLeft - 1);
            assertEq(account.usdcTotal, usdcTotal + minDeposit_);
            assertGt(account.ethTotal, ethTotal);
            assertEq(account.minDeposit, minDeposit_);
            assertEq(account.withdrawOnly, true);
        }
    }

    function _testFailDepositIfCompleted() public {
        vm.roll(1);
        vm.warp(block.timestamp + 1);

        vm.expectRevert(AngrySafe.WithdrawOnly.selector);
        safe.deposit(minDeposit_);
    }

    function _testFailInitializeIfWithdrawOnly() public {
        vm.expectRevert(AngrySafe.WithdrawOnly.selector);
        safe.initialize(minDeposit_, depositsAmount_);
    }

    function _testWithdrawSuccess() public {
        uint256 wethBalanceBefore = weth.balanceOf(address(this));
        console.log("balance before withdraw", wethBalanceBefore);

        safe.withdraw();

        (
            account.lastDepositTimestamp,
            account.depositsLeft,
            account.usdcTotal,
            account.ethTotal,
            account.minDeposit,
            account.withdrawOnly
        ) = safe.accounts(address(this));

        assertEq(account.lastDepositTimestamp, 0);
        assertEq(account.depositsLeft, 0);
        assertEq(account.usdcTotal, 0);
        assertEq(account.ethTotal, 0);
        assertEq(account.minDeposit, 0);
        assertEq(account.withdrawOnly, false);

        uint256 wethBalanceAfter = weth.balanceOf(address(this));
        console.log("balance after withdraw", wethBalanceAfter);

        assertGt(wethBalanceAfter, wethBalanceBefore);
    }

    function _testFailSweepTokenIfNotOwner() public {
        vm.prank(address(0x69));
        vm.expectRevert("Ownable: caller is not the owner");
        safe.sweepToken(address(sweepToken));
    }

    function _testSweepTokenByOwner() public {
        uint256 contractSweepTokenBalanceBefore = sweepToken.balanceOf(
            address(safe)
        );
        uint256 ownerSweepTokenBalanceBefore = sweepToken.balanceOf(
            address(this)
        );

        console.log("safe sweepToken before", contractSweepTokenBalanceBefore);
        console.log("owner sweepToken before", ownerSweepTokenBalanceBefore);

        safe.sweepToken(address(sweepToken));

        uint256 contractSweepTokenBalanceAfter = sweepToken.balanceOf(
            address(safe)
        );
        uint256 ownerSweepTokenBalanceAfter = sweepToken.balanceOf(
            address(this)
        );

        console.log("safe sweepToken After", contractSweepTokenBalanceAfter);
        console.log("owner sweepToken After", ownerSweepTokenBalanceAfter);

        assertEq(contractSweepTokenBalanceAfter, 0);
        assertGt(ownerSweepTokenBalanceAfter, ownerSweepTokenBalanceBefore);
    }
}
