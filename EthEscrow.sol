// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.0.0/contracts/token/ERC20/IERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v3.0.0/contracts/math/SafeMath.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract EthEscrow is ReentrancyGuard {
    
    using SafeMath for uint256;

    address public agent;
    uint public feeInPercent = 2;
    bool public isPaused = false;
    enum Status {CANCELLED, COMPLETED, PROCESSING}
    struct Trade {
        address payee;
        address payeer;
        uint amount;
        Status status;
        address tokenAddress;
    }
    
    struct Token {
        bool allowed;
        uint fee;
    }
    
    mapping(string => Trade)  public trades;
    
    mapping(address => Token) public allowedToken;  // (tokenAddress => Token) Pair
    
    constructor() public {
        agent = msg.sender;
    }
    
    event Deposited(string tradeId, address payee, address payeer,uint amount,Status status,address tokenAddress);
    event Withdrawed(string tradeId, address payee, address payeer,uint amount,Status status,address tokenAddress);
    event Cancelled(string tradeId, address payee, address payeer,uint amount,Status status,address tokenAddress);

    function changeEthFee(uint fee)
        external onlyAgent() 
    {
        feeInPercent = fee;
    }
    
    function escrowFee(uint256 amount)
        private view returns(uint256) {
        uint256 x = amount.mul(feeInPercent);
        uint256 adminFee = x.div(100);
        return adminFee;
    }
    
    function escrowTokenFee(uint amount, address _tokenAddress) private view onlyPermitToken(_tokenAddress) returns(uint256)  {
        uint fee = allowedToken[_tokenAddress].fee;
        uint256 x = amount.mul(fee);
        uint256 adminFee = x.div(100);
        return adminFee;
    }
    
    function deposit(address payee, string memory tradeId)
        public payable notPaused() {
        require(trades[tradeId].payee == address(0),'trade already exists');
        trades[tradeId] = Trade(payee,msg.sender,msg.value,Status.PROCESSING,address(0));
        emit Deposited(tradeId, payee, msg.sender,msg.value,Status.PROCESSING,address(0));
    }
    
    function depositToken(address payee,uint256 amount,string memory tradeId, address _tokenAddress)
        external onlyPermitToken(_tokenAddress) notPaused() {
        require(trades[tradeId].payee == address(0),'trade already exists');
        IERC20 token = IERC20(_tokenAddress);
        uint allowed = token.allowance(msg.sender, address(this));
        require(allowed >= amount, 'Contract is not approved, please approved first');
        trades[tradeId] = Trade(payee,msg.sender,amount,Status.PROCESSING,_tokenAddress);
        token.transferFrom(msg.sender,address(this),amount);
        emit Deposited(tradeId, payee, msg.sender,amount,Status.PROCESSING,_tokenAddress );
    }
    
    function withdraw(string memory tradeId)
        external notPaused() nonReentrant {
        require(trades[tradeId].status == Status.PROCESSING, "Trade already completed!");
        require(trades[tradeId].payeer == msg.sender, "You are not payeer or buyer");

        address payable payee = address(uint160(trades[tradeId].payee));
        address payable admin = address(uint160(agent));


        trades[tradeId].status = Status.COMPLETED;
        if(trades[tradeId].tokenAddress == address(0)){
            uint fee = escrowFee(trades[tradeId].amount);
            uint amount = trades[tradeId].amount - fee;
            payee.transfer(amount);
            admin.transfer(fee);
            emit Withdrawed(tradeId,payee,msg.sender,trades[tradeId].amount,Status.COMPLETED,address(0));
        }else {
            require(trades[tradeId].tokenAddress != address(0), "Invalid token address");
            require(allowedToken[trades[tradeId].tokenAddress].allowed,"Token is not allowed");
            uint fee = escrowTokenFee(trades[tradeId].amount, trades[tradeId].tokenAddress);
            uint amount = trades[tradeId].amount - fee;
            IERC20 token = IERC20(trades[tradeId].tokenAddress);
            token.transfer(payee,amount);
            token.transfer(admin,fee);
            emit Withdrawed(tradeId,payee,msg.sender,trades[tradeId].amount,Status.COMPLETED,trades[tradeId].tokenAddress);
        }
        
    }
    
    
    
    function withdrawFromAgent(string memory tradeId)
        external onlyAgent() nonReentrant {
        require(trades[tradeId].status == Status.PROCESSING, "Trade already completed!");
        address payable payee = address(uint160(trades[tradeId].payee));
        address payable admin = address(uint160(agent));
        trades[tradeId].status = Status.COMPLETED;
        if(trades[tradeId].tokenAddress == address(0)){
            uint fee = escrowFee(trades[tradeId].amount);
            uint amount = trades[tradeId].amount - fee;
            payee.transfer(amount);
            admin.transfer(fee);
            emit Withdrawed(tradeId,payee,trades[tradeId].payeer,trades[tradeId].amount,Status.COMPLETED,address(0));
        }else {
            require(trades[tradeId].tokenAddress != address(0), "Invalid token address");
            require(allowedToken[trades[tradeId].tokenAddress].allowed,"Token is not allowed");
            uint fee = escrowTokenFee(trades[tradeId].amount, trades[tradeId].tokenAddress);
            uint amount = trades[tradeId].amount - fee;
            IERC20 token = IERC20(trades[tradeId].tokenAddress);
            token.transfer(payee,amount);
            token.transfer(admin,fee);
            emit Withdrawed(tradeId,payee,trades[tradeId].payeer,trades[tradeId].amount,Status.COMPLETED,trades[tradeId].tokenAddress);
        }
        
    }
    


    function cancel(string memory tradeId) external notPaused() nonReentrant {
        require(trades[tradeId].status == Status.PROCESSING, "Trade already completed!");
        require(trades[tradeId].payee == msg.sender || agent == msg.sender,'You are not buyer or admin');
        address payable payeer = address(uint160(trades[tradeId].payeer));
        trades[tradeId].status = Status.CANCELLED;
        if(trades[tradeId].tokenAddress == address(0)){
            payeer.transfer(trades[tradeId].amount);
            emit Cancelled(tradeId,trades[tradeId].payee,payeer,trades[tradeId].amount,Status.COMPLETED,address(0));

        }else{
            IERC20 token = IERC20(trades[tradeId].tokenAddress);
            token.transfer(trades[tradeId].payeer,trades[tradeId].amount);
            emit Cancelled(tradeId,trades[tradeId].payee,payeer,trades[tradeId].amount,Status.COMPLETED,trades[tradeId].tokenAddress);
        }
        
    }
    
    
    
     function changeAgent(address _agent)
        external onlyAgent() {
        agent = _agent;
     }
     
     function addToken(address _tokenAddress, uint fee)
        external onlyAgent(){
        allowedToken[_tokenAddress] = Token(true,fee);
     }
     
     function removeToken(address _tokenAddress)
        external onlyAgent(){
        delete allowedToken[_tokenAddress];
     }
     
     function changeFee(address _tokenAddress, uint _fee)
        external onlyAgent(){
        allowedToken[_tokenAddress].fee = _fee;
     }
     
     function pause()
        external onlyAgent() {
        isPaused = true;
     }
     
     function resume()
        external onlyAgent() {
        isPaused = false;
     }
     
     modifier onlyAgent(){
        require(msg.sender == agent, "You are not admin");
        _;
     }
     
     modifier notPaused(){
         require(!isPaused,"Contract is paused");
         _;
     }
     
     modifier onlyPermitToken(address _tokenAddress){
        require(allowedToken[_tokenAddress].allowed, "Token not allowed for Trading");
         _;
     }
    
}
