// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/AngrySafe.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        uint256 mode = vm.envUint("mode"); // 1 - mainnet, 2 - testnet

        vm.startBroadcast(deployerPrivateKey);

        (address router, address weth, address usdc) = getAddresses(mode);

        AngrySafe safe = new AngrySafe(router, weth, usdc);

        console.logAddress(address(safe));

        vm.stopBroadcast();
    }

    function getAddresses(uint256 mode) internal pure returns (address router, address weth, address usdc) {
        if (mode == 1) {
            router = 0x10ED43C718714eb63d5aA57B78B54704E256024E;
            weth = 0x2170Ed0880ac9A755fd29B2688956BD959F933F8;
            usdc = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
            return (router, weth, usdc);
        }

        // testnet
        router = 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3;
        weth = 0x8BaBbB98678facC7342735486C851ABD7A0d17Ca;
        usdc = 0x8a9424745056Eb399FD19a0EC26A14316684e274; //dai
        return (router, weth, usdc);
    }
}
