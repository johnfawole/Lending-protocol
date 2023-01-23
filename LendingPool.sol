//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "src/AggregateV3Interface.sol";

contract LendingPool is ERC20{

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    AggregatorV3Interface internal DAI_USD;

    uint public borrowCount = 1;

    address public comptroller;

    modifier onlyComptroller(){
        require(msg.sender == comptroller, "!Comptroller");
        _;
    }

    
    struct borrowInfo{
        uint totalBorrow; //keeps value in USD
        uint timestamp;
        uint perc_borrow; 
    }

    struct LoanInfo{
        address borrower;
        uint amountBorrowed;
        uint timeBorrow;
    }

    mapping (address => borrowInfo) loanDetails;
    
    mapping (uint => LoanInfo) Loans;
    
    uint public constant FEE = 30;

    uint private constant CRatio = 8000;

    uint private constant BASE = 10000;

    event Deposit (address depositor, uint amountDeposited);
    event Withdraw (address withdrawer, uint amountWithdrawn);
    event Borrow (address borrower, uint amountBorrowed_in_USD);
    event LoanRepaid (address borrower, uint amountBorrowed_in_USD, uint amountRepaid);

    /**
     * Network: Ethereum Mainnet
     * Aggregator: DAI/USD
     * Address: 0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6
     */
    constructor () ERC20 ("Placeholder DAI", "pDAI") {
        DAI_USD = AggregatorV3Interface(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9);
        comptroller = msg.sender;
    }

    function deposit(
        uint amount
    ) external {
        require(amount > 0, "ERR: Invalid Amount");
        require(IERC20(DAI).transferFrom(msg.sender, address(this), amount), "ERR: Transfer Failed...");
        _mint(msg.sender, amount);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint amount) external {
        uint userBalance = IERC20(address(this)).balanceOf(msg.sender);
        require(userBalance >= amount && amount > 0, "ERR: Invalid Amount or You have been Liquidated");

        //check that the user doesnt have any pending borrows here...
        require(loanDetails[msg.sender].totalBorrow == 0, "ERR: You have Outstanding Loans...");
        _burn(msg.sender, amount);
        IERC20(DAI).transfer(msg.sender, amount);
        emit Withdraw(msg.sender, amount);
    }

   function borrow(uint borrowAmount_in_USD) external {
        uint userBalance = IERC20(address(this)).balanceOf(msg.sender);
        require(loanDetails[msg.sender].perc_borrow <= CRatio, "ERR: You are trying to borrow more than you are allowed to");
        uint collateralValue = (userBalance/1e18) * uint(_getLatestDAIPrice());
        require(loanDetails[msg.sender].totalBorrow + borrowAmount_in_USD <= (collateralValue * CRatio) / BASE, "ERR: You cannot borrow more than you can");
        loanDetails[msg.sender].totalBorrow += borrowAmount_in_USD;
        loanDetails[msg.sender].perc_borrow = loanDetails[msg.sender].totalBorrow / collateralValue * BASE;
        loanDetails[msg.sender].timestamp = block.timestamp;
        Loans[borrowCount].borrower = msg.sender;
        Loans[borrowCount].amountBorrowed += borrowAmount_in_USD;
        Loans[borrowCount].timeBorrow = block.timestamp;
        IERC20(DAI).transfer(msg.sender, borrowAmount_in_USD * 1 ether);
        borrowCount++;
        emit Borrow(msg.sender, borrowAmount_in_USD);
    }

    function repay() external {
        uint initialBorrow = loanDetails[msg.sender].totalBorrow;
        require(initialBorrow > 0, "ERR: Zero Amount");
        uint timeDiff = getTimestampDifference(block.timestamp, loanDetails[msg.sender].timestamp);
        require(timeDiff > 0, "ERR: This is not a flash Borrow");
        uint debtToRepay = initialBorrow * 1 ether + ((initialBorrow* 1 ether) * timeDiff * FEE / BASE);
        require(IERC20(DAI).transferFrom(msg.sender, address(this), debtToRepay), "ERR: Transfer Failed...");
        loanDetails[msg.sender].totalBorrow = 0;
        loanDetails[msg.sender].perc_borrow = 0;
        loanDetails[msg.sender].timestamp = 0;
        emit LoanRepaid(msg.sender, initialBorrow, debtToRepay);
    }

    function checkForLiquidations() public onlyComptroller {
        _liquidateCall();
    }

    function getTimestampDifference(uint current, uint previous) public pure returns (uint) {
        return (current - previous) / 1 days;
    }

    function getBorrowerDetails(address _account) public view returns(uint amountBorrowed, uint time, uint collateralRatio){
        amountBorrowed = loanDetails[_account].totalBorrow;
        time = loanDetails[_account].timestamp;
        collateralRatio = loanDetails[_account].perc_borrow;
    }

    function getLoanDetails(uint loanID) public view returns(address borrower, uint amountBorrowed, uint time){
        borrower = Loans[loanID].borrower;
        amountBorrowed = Loans[loanID].amountBorrowed;
        time = Loans[loanID].timeBorrow;
    }

    function _liquidateCall() internal {
        for (uint i; i < borrowCount; i++) {
            if(Loans[i].timeBorrow != 0 && block.timestamp > Loans[i].timeBorrow + 30 days){
                address borrower = Loans[i].borrower;
                _burn(borrower, IERC20(address(this)).balanceOf(borrower));
                loanDetails[borrower].totalBorrow = 0;
                loanDetails[borrower].perc_borrow = 0;
                loanDetails[borrower].timestamp = 0;
                Loans[i].timeBorrow = 0;
            }
        }
    }

    function withdrawRemainingBalance(address to) public onlyComptroller {
        IERC20(DAI).transfer(to, IERC20(DAI).balanceOf(address(this)));
    }

    function _getLatestDAIPrice() private view returns (int) {
        //Ignore: The return data from the latest round data function.
        (
            /* uint80 roundID */,
            int price,
            /*uint startedAt*/,
            /*uint timeStamp*/,
            /*uint80 answeredInRound*/
        ) = DAI_USD.latestRoundData();
        return price/1e8;
    }

    //OVERRIDEN FUNCTIONS
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        //Transfer of placeholder tokens is forbidden
    }
}
