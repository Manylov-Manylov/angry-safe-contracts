// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "./interfaces/IUniswapV2Router.sol";

contract AngrySafe {
    struct Account {
        uint256 lastDepositTimestamp;
        uint256 depositsLeft;
        uint256 usdcTotal;
        uint256 ethTotal;
        uint256 minDeposit;
    }

    mapping(address => Account) public accounts;

    address private constant UNISWAP_V2_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IUniswapV2Router private router = IUniswapV2Router(UNISWAP_V2_ROUTER);
    IERC20 private weth = IERC20(WETH);
    IERC20 private usdc = IERC20(USDC);

    event Initialized(
        address indexed user,
        uint256 minDeposit,
        uint256 depositsAmount
    );
    event Deposit(address indexed user, uint256 amountUSDC, uint256 amountWETH);
    event Withdraw(address indexed user, uint256 amount);

    error WithdrawalIsNotReady();
    error DepositError();
    error NotInitialized();
    error AlreadyInitialized();

    function initialize(uint256 minDeposit_, uint256 depositsAmount_) external {
        Account memory account = accounts[msg.sender];

        if (account.depositsLeft > 0) {
            revert AlreadyInitialized();
        }

        account.depositsLeft = depositsAmount_;
        account.minDeposit = minDeposit_;

        accounts[msg.sender] = account;

        emit Initialized(msg.sender, minDeposit_, depositsAmount_);
    }

    function deposit(uint256 amount_) external {
        (uint256 wethAmount, Account memory account) = _deposit(amount_);
        accounts[msg.sender] = account;
        emit Deposit(msg.sender, amount_, wethAmount);
    }

    function _deposit(uint256 amount_)
        internal
        returns (uint256, Account memory)
    {
        Account memory account = accounts[msg.sender];

        if (account.depositsLeft == 0) {
            revert NotInitialized();
        }

        uint256 wethAmount = _swapExactAmountIn(amount_);

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
        if (block.timestamp < account.lastDepositTimestamp + 30 days) {
            return (wethAmount, account);
        }

        // OK case: deposited just in time
        // here block.timestamp less than 31 days and more than 30 days
        account.lastDepositTimestamp = block.timestamp;
        account.depositsLeft = account.depositsLeft - 1;

        return (wethAmount, account);
    }

    function _swapExactAmountIn(uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        usdc.transferFrom(msg.sender, address(this), amountIn);
        usdc.approve(address(router), amountIn);

        address[] memory path;
        path = new address[](2);
        path[0] = USDC;
        path[1] = WETH;

        uint256[] memory amounts = router.swapExactTokensForTokens(
            amountIn,
            uint256(0),
            path,
            address(this),
            block.timestamp
        );

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
}
