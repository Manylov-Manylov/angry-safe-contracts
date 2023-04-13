// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "./interfaces/IUniswapV2Router.sol";

contract AngrySafe is Ownable {
    struct Account {
        uint256 lastDepositTimestamp;
        uint256 depositsLeft;
        uint256 usdcTotal;
        uint256 ethTotal;
        uint256 minDeposit;
        bool withdrawOnly;
    }

    mapping(address => Account) public accounts;

    // address private constant PANCAKESWAP_V2_ROUTER =
    //     0x10ED43C718714eb63d5aA57B78B54704E256024E;
    // address private constant WETH = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
    // address constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    IUniswapV2Router private router;
    IERC20 private weth;
    IERC20 private usdc;

    event Initialized(address indexed user, uint256 minDeposit, uint256 depositsAmount);
    event Deposit(address indexed user, uint256 amountUSDC, uint256 amountWETH);
    event Withdraw(address indexed user, uint256 amount);

    error WithdrawalIsNotReady();
    error WithdrawOnly();
    error DepositLessThanMinimal();
    error NotInitialized();
    error AlreadyInitialized();
    error WrongParams();

    constructor(address router_, address weth_, address usdc_) {
        router = IUniswapV2Router(router_);
        weth = IERC20(weth_);
        usdc = IERC20(usdc_);
    }

    function initialize(uint256 minDeposit_, uint256 depositsAmount_) external {
        Account memory account = accounts[msg.sender];

        if (account.withdrawOnly) revert WithdrawOnly();

        if (account.depositsLeft > 0) {
            revert AlreadyInitialized();
        }

        if (minDeposit_ == 0) revert WrongParams();
        if (depositsAmount_ == 0) revert WrongParams();

        account.depositsLeft = depositsAmount_;
        account.minDeposit = minDeposit_;

        accounts[msg.sender] = account;

        emit Initialized(msg.sender, minDeposit_, depositsAmount_);
    }
    
    function resetInitialize() external {
        delete accounts[msg.sender];
    }

    function deposit(uint256 amount_) external {
        (uint256 wethAmount, Account memory account) = _deposit(amount_);
        accounts[msg.sender] = account;
        emit Deposit(msg.sender, amount_, wethAmount);
    }

    function _deposit(uint256 amount_) internal returns (uint256, Account memory) {
        Account memory account = accounts[msg.sender];

        if (account.withdrawOnly) revert WithdrawOnly();

        if (account.depositsLeft == 0) {
            revert NotInitialized();
        }

        // console.log("amount", amount_);
        if (amount_ < account.minDeposit) {
            revert DepositLessThanMinimal();
        }

        uint256 wethAmount = _swapExactAmountIn(amount_);

        // console.log("weth amount", wethAmount);

        account.usdcTotal = account.usdcTotal + amount_;
        account.ethTotal = account.ethTotal + wethAmount;

        if (account.lastDepositTimestamp == 0) {
            account.lastDepositTimestamp = block.timestamp;
            account.depositsLeft = account.depositsLeft - 1;
            return (wethAmount, account);
        }

        // check if deadline f..ed up
        // then add penalty - deposits left is not decreasing
        if (block.timestamp > account.lastDepositTimestamp + 31 days) {
            account.lastDepositTimestamp = block.timestamp;
            return (wethAmount, account);
        }

        // check if deposit in the same month - then just add deposit to this month deposit,
        // not decreasing deposits left
        // console.log("block timestamp", block.timestamp);
        // console.log("account.lastDepositTimestamp", account.lastDepositTimestamp);

        if (block.timestamp < account.lastDepositTimestamp + 30 days) {
            return (wethAmount, account);
        }

        // OK case: deposited just in time
        // here block.timestamp less than 31 days and more than 30 days
        account.lastDepositTimestamp = block.timestamp;
        account.depositsLeft = account.depositsLeft - 1;

        if (account.depositsLeft == 0) account.withdrawOnly = true;

        return (wethAmount, account);
    }

    function _swapExactAmountIn(uint256 amountIn) internal returns (uint256 amountOut) {
        usdc.transferFrom(msg.sender, address(this), amountIn);
        usdc.approve(address(router), amountIn);

        address[] memory path;
        path = new address[](2);
        path[0] = address(usdc);
        path[1] = address(weth);

        uint256[] memory amounts =
            router.swapExactTokensForTokens(amountIn, uint256(0), path, address(this), block.timestamp);

        return amounts[1];
    }

    function withdraw() external {
        Account memory account = accounts[msg.sender];

        if (account.depositsLeft > 0) {
            revert WithdrawalIsNotReady();
        }

        if (account.lastDepositTimestamp == 0) {
            revert NotInitialized();
        }

        uint256 withrawAmount = account.ethTotal;

        delete accounts[msg.sender];

        weth.transfer(msg.sender, withrawAmount);
        emit Withdraw(msg.sender, withrawAmount);
    }

    function sweepToken(address token) external onlyOwner {
        require(address(token) != address(weth), "can not sweep underlying token");
        require(address(token) != address(usdc), "can not sweep underlying token");
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).transfer(owner(), balance);
    }

    function reset() external {
        delete accounts[msg.sender];
    }
}
