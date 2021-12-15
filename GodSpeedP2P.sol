// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract GodspeedP2P is ReentrancyGuard {
    using SafeMath for uint256;
    // Variable
    
    address public owner;
    using Counters for Counters.Counter;
    Counters.Counter public tradeId;
    
    constructor(){
        owner = msg.sender;
    }
    
    enum Status{
        pending,processing,paid,cancelled,completed,disputed,waiting
    }
    
    struct Trade {
        uint tradeId;
        address seller;
        address buyer;
        uint amount;
        address tokenContractAddress;
        Status status;
        string offerId;
    }
    
    uint public feeInPercent = 25;
    uint public percentFraction = 1000;
    
    mapping(uint => Trade) public trades;
    
    
    // Events
    
    event TradeCreated(
        uint tradeId,
        address seller,
        address buyer,
        uint amount,
        address tokenContractAddress,
        Status status
        );
    
    event TradeStarted(
        uint tradeId,
        address seller,
        address buyer,
        uint amount,
        address tokenContractAddress,
        Status status
        );
    
    event TradePaid(
        uint tradeId,
        address seller,
        address buyer,
        uint amount,
        address tokenContractAddress,
        Status status
        );
    
    event TradeCompleted(
        uint tradeId,
        address seller,
        address buyer,
        uint amount,
        address tokenContractAddress,
        Status status);
    
    event TradeCancelled(
        uint tradeId,
        address seller,
        address buyer,
        uint amount,
        address tokenContractAddress,
        Status status);
    
    event TradeDisputed(
        uint tradeId,
        address seller,
        address buyer,
        uint amount,
        address tokenContractAddress,
        Status status);
    
    
    // Public functions
    
    // Seller : Who sells token for money / other items    
    // Buyer : Who Buys token
    
    
    // @ Method :Trade create
    // @ Description: Seller will create a trade for a Buyer
    // @ Params : Buyer Address, Amount (token amount * decimals) , token contract Address
    
    function createTrade(
        address _buyer,
        uint _amount,
        address _tokenAddress, string memory _offerId)
        external {
        require(_amount > 0,"Amount must be greater than zero");
        require(_buyer != address(0), "Buyer must be an valid address");
        require(_tokenAddress != address(0), "Token Address must be an valid address");
        tradeId.increment();
        uint currentId =  tradeId.current();
        trades[currentId] = Trade(currentId,msg.sender,_buyer,_amount,_tokenAddress, Status.pending, _offerId);
        emit TradeCreated(currentId,msg.sender,_buyer,_amount, _tokenAddress, Status.pending);
    }



    // @ Method : Trade create by  buyer
    // @ Description: Buyer will create a trade for a Seller
    // @ Params : Seller Address, Amount (token amount * decimals) , token contract Address

    function createTradeByBuyer(
        address _seller,
        uint _amount,
        address _tokenAddress, string memory _offerId)
        external {
        require(_amount > 0,"Amount must be greater than zero");
        require(_seller != address(0), "Seller must be an valid address");
        require(_tokenAddress != address(0), "Token Address must be an valid address");
        tradeId.increment();
        uint currentId =  tradeId.current();
        trades[currentId] = Trade(currentId,_seller,msg.sender,_amount,_tokenAddress, Status.waiting, _offerId);
        emit TradeCreated(currentId,_seller,msg.sender,_amount, _tokenAddress, Status.waiting);
    }

    // @ Method : start trade By seller
    // @ Description : Seller will start the trade. Seller need to approve this contract first then this method to deposit.
    // @ Params : tradeId
    
    function startTradeBySeller(uint _tradeId) external nonReentrant {
        require(trades[_tradeId].seller == msg.sender, "You are not seller");
        require(trades[_tradeId].status == Status.waiting, "Trade already proceed");
        trades[_tradeId].status = Status.processing;
        IERC20(trades[_tradeId].tokenContractAddress).transferFrom(trades[_tradeId].seller,address(this),trades[_tradeId].amount);
        emit TradeStarted(
            _tradeId,
            trades[_tradeId].seller,
            trades[_tradeId].buyer,
            trades[_tradeId].amount,
            trades[_tradeId].tokenContractAddress,
            Status.processing);
    }
    
    
    
    // @ Method : Start trade
    // @ Description : Buyer will start the trade. Seller need to approve this contract with the trade amount . Otherwise this action can't be done.
    // @ Params : tradeId
    
    function startTrade(uint _tradeId) external nonReentrant {
        require(trades[_tradeId].buyer == msg.sender, "You are not buyer");
        require(trades[_tradeId].status == Status.pending, "Trade already proceed or not deposited");
        trades[_tradeId].status = Status.processing;
        IERC20(trades[_tradeId].tokenContractAddress).transferFrom(trades[_tradeId].seller,address(this),trades[_tradeId].amount);
        emit TradeStarted(
            _tradeId,
            trades[_tradeId].seller,
            trades[_tradeId].buyer,
            trades[_tradeId].amount,
            trades[_tradeId].tokenContractAddress,
            Status.processing);
    }
    
    
    
    // @ Method : Mark the trade as paid
    // @ Description : Buyer will mark the trade as paid when he give the service / money to Token Seller
     // @ Params : tradeId
    
    function markedPaidTrade(uint _tradeId) external {
        require(trades[_tradeId].buyer == msg.sender, "You are not buyer");
        require(trades[_tradeId].status == Status.processing, "Trade is not processing");
        trades[_tradeId].status = Status.paid;
        emit TradePaid(
            _tradeId,
            trades[_tradeId].seller,
            trades[_tradeId].buyer,
            trades[_tradeId].amount,
            trades[_tradeId].tokenContractAddress,
            Status.paid);
    }
    
    
    // @Method : Complete the trades
    // @Description : Seller will complete the trade when seller paid him / her
    // @ Params : tradeId
    function completeTrade(uint _tradeId) external nonReentrant {
        require(trades[_tradeId].seller == msg.sender, "You are not seller");
        require(trades[_tradeId].status == Status.paid, "Buyer not paid yet");
        uint fee = escrowFee(trades[_tradeId].amount);
        uint amount = trades[_tradeId].amount - fee;
        IERC20 token = IERC20(trades[_tradeId].tokenContractAddress);
        token.transfer(trades[_tradeId].buyer, amount);
        token.transfer(owner,fee);
        trades[_tradeId].status = Status.completed;
        emit TradeCompleted(
            _tradeId,
            trades[_tradeId].seller,
            trades[_tradeId].buyer,
            trades[_tradeId].amount,
            trades[_tradeId].tokenContractAddress,
            Status.completed);
    }
    
    
    // @Method: Dispute the trades
    // @Description :  Buyer or seller can dispute the trade (processing and paid stage)
    // @ Params : tradeId
    
    function disputeTrade(uint _tradeId) external {
        require(
            trades[_tradeId].seller == msg.sender ||
            trades[_tradeId].buyer == msg.sender,
            "You are not buyer or seller");
        require(
            trades[_tradeId].status == Status.processing ||
            trades[_tradeId].status == Status.paid,
            "Trade is not processing nor marked as paid"
                );
                
        trades[_tradeId].status = Status.disputed;
        emit TradeDisputed(
            _tradeId,
            trades[_tradeId].seller,
            trades[_tradeId].buyer,
            trades[_tradeId].amount,
            trades[_tradeId].tokenContractAddress,
            Status.disputed);
    }
    
    
    
    // @Method: Cancel the trades by seller
    // @Description :  Seller can cancel the trade only before start the trade
    // @ Params : tradeId
    
    function cancelTradeBySeller(uint _tradeId) external {
        require(trades[_tradeId].seller == msg.sender, "You are not seller");
        require(trades[_tradeId].status == Status.pending, "Trade already started");
        trades[_tradeId].status = Status.cancelled;
        emit TradeCancelled(
            _tradeId,
            trades[_tradeId].seller,
            trades[_tradeId].buyer,
            trades[_tradeId].amount,
            trades[_tradeId].tokenContractAddress,
            Status.cancelled
            );
    }
    
    // @Method:  Cancel the trades by buyer
    // @Description : Buyer can cancel the trade if the trade on pending or paid stage. Token will reverted to Seller.
    // @ Params : tradeId
    
    function cancelTradeByBuyer(uint _tradeId) external nonReentrant {
        require(trades[_tradeId].buyer == msg.sender, "You are not buyer");
        require(trades[_tradeId].status == Status.processing || trades[_tradeId].status == Status.paid, "Trade not strated or already finished");
        trades[_tradeId].status = Status.cancelled;
        IERC20(trades[_tradeId].tokenContractAddress).transfer(trades[_tradeId].seller, trades[_tradeId].amount);
        emit TradeCancelled(
            _tradeId,
            trades[_tradeId].seller,
            trades[_tradeId].buyer,
            trades[_tradeId].amount,
            trades[_tradeId].tokenContractAddress,
            Status.cancelled
            );
    }
    
    
    // @ Method:  Cancel the trades by Admin
    // @ Description : Admin can cancel the trade. only for disputed trade. Token will reverted to Seller.
    // @ Params : tradeId
    
    function cancelTradeByAdmin(uint _tradeId) external onlyOwner() {
        require(trades[_tradeId].status == Status.disputed, "Trade not disputed");
        trades[_tradeId].status = Status.cancelled;
        IERC20(trades[_tradeId].tokenContractAddress).transfer(trades[_tradeId].seller,trades[_tradeId].amount);
        emit TradeCancelled(
            _tradeId,
            trades[_tradeId].seller,
            trades[_tradeId].buyer,
            trades[_tradeId].amount,
            trades[_tradeId].tokenContractAddress,
            Status.cancelled);
    }
    
    
    // @ Method: Complete the trades by Admin
    // @ Description : admin can complete the trades
    // @ Params : tradeId
    
    function completeTradeByAdmin(uint _tradeId) external onlyOwner() {
        require(trades[_tradeId].status == Status.disputed, "Trade not disputed");
        trades[_tradeId].status = Status.cancelled;
        IERC20(trades[_tradeId].tokenContractAddress).transfer(trades[_tradeId].buyer,trades[_tradeId].amount);
        emit TradeCompleted(
            _tradeId,
            trades[_tradeId].seller,
            trades[_tradeId].buyer,
            trades[_tradeId].amount,
            trades[_tradeId].tokenContractAddress,
            Status.completed
            );
    }
    
    // Private Function
    
    function escrowFee(uint256 amount)
        private view returns(uint256) {
        uint256 x = amount.mul(feeInPercent);
        uint256 adminFee = x.div(percentFraction);
        return adminFee;
    }
    
    
    // Admin function 
    function changeFee(uint fee, uint fraction)
        external onlyOwner() 
    {
        feeInPercent = fee;
        percentFraction = fraction;
    }
    
    
    modifier onlyOwner() {
        require(owner == msg.sender, "You are not owner");
        _;
    }
}
