//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "src/LendingPool.sol";
import "forge-std/Test.sol";

contract TestlendingPool is Test {

    LendingPool pool;
    address user;

    function setUp () public {
        pool = new LendingPool();
        user = address(12);
        deal(pool.DAI(), user, 1_000e18);
    }

    function deposit() public {
        IERC20(pool.DAI()).approve(address(pool), 1_000e18);
        pool.deposit(1_000e18);
    }

    function testDeposit() public {
        vm.startPrank(user);
        deposit();
        assertEq(IERC20(pool.DAI()).balanceOf(user), 0);
        assertEq(IERC20(address(pool)).balanceOf(user), 1_000e18);
        vm.stopPrank();
    }

    function testWithdrawal () public {
        vm.startPrank(user);
        deposit();
        assertEq(IERC20(pool.DAI()).balanceOf(user), 0);
        assertEq(IERC20(address(pool)).balanceOf(user), 1_000e18);
        pool.withdraw(IERC20(address(pool)).balanceOf(user));
        assertEq(IERC20(pool.DAI()).balanceOf(user), 1_000e18);
        assertEq(IERC20(address(pool)).balanceOf(user), 0);
        vm.stopPrank();
    }

    function testBorrow() public {
        vm.startPrank(user);
        deposit();
        pool.borrow(800);
        assertEq(pool.borrowCount(), 2);
        assertEq(IERC20(pool.DAI()).balanceOf(user), 800e18);
        vm.stopPrank();
    }

    function testRepay() public {
        vm.startPrank(user);
        deposit();
        pool.borrow(800);
        deal(pool.DAI(), user, 1_000e18);
        IERC20(pool.DAI()).approve(address(pool), 1_000e18);
        vm.warp(block.timestamp + 16 days);
        pool.repay();
        emit log_named_uint ("Balance of the borrower is ", IERC20(pool.DAI()).balanceOf(user));
        vm.stopPrank();
    }

    function testLiquidate() public {
        vm.startPrank(user);
        deposit();
        pool.borrow(800);
        vm.stopPrank();
        vm.warp(block.timestamp + 31 days);
        vm.startPrank(pool.comptroller());
        pool.checkForLiquidations();
        vm.stopPrank();
        vm.startPrank(user);
        pool.withdraw(1_000e18);
        vm.stopPrank();
    }
}
