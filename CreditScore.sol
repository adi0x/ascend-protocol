// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

contract CreditScore {
    
    address public owner;
    IERC20 public lendingToken;
    
    uint256 public totalLiquidity;
    uint256 public loanIdCounter;
    
    struct Loan {
        uint256 id;
        address borrower;
        uint256 amount;
        uint256 amountToRepay;
        uint256 deadline;
        bool repaid;
        bool defaulted;
    }
    
    struct UserProfile {
        uint256 creditScore;
        uint256 totalBorrowed;
        uint256 totalRepaid;
        uint256 loansCount;
        uint256 onTimePayments;
        uint256 latePayments;
        uint256 accountAge;
    }
    
    mapping(uint256 => Loan) public loans;
    mapping(address => UserProfile) public profiles;
    mapping(address => uint256[]) public userLoans;
    
    event LiquidityAdded(address indexed provider, uint256 amount);
    event LoanRequested(uint256 indexed loanId, address indexed borrower, uint256 amount);
    event LoanRepaid(uint256 indexed loanId, address indexed borrower, bool onTime);
    event ScoreUpdated(address indexed user, uint256 newScore);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    constructor(address _tokenAddress) {
        owner = msg.sender;
        lendingToken = IERC20(_tokenAddress);
    }
    
    function addLiquidity(uint256 _amount) external {
        require(_amount > 0, "Amount must be > 0");
        require(lendingToken.transferFrom(msg.sender, address(this), _amount), "Transfer failed");
        
        totalLiquidity += _amount;
        emit LiquidityAdded(msg.sender, _amount);
    }
    
    function getInterestRate(uint256 _score) public pure returns (uint256) {
        if (_score >= 800) return 5;
        if (_score >= 600) return 7;
        if (_score >= 300) return 10;
        return 15;
    }
    
    function getMaxLoanAmount(uint256 _score) public pure returns (uint256) {
        if (_score >= 800) return 10000 * 10**18;
        if (_score >= 600) return 5000 * 10**18;
        if (_score >= 300) return 1000 * 10**18;
        return 100 * 10**18;
    }
    
    function requestLoan(uint256 _amount, uint256 _durationDays) external {
        UserProfile storage profile = profiles[msg.sender];
        
        if (profile.accountAge == 0) {
            profile.accountAge = block.timestamp;
        }
        
        uint256 maxAmount = getMaxLoanAmount(profile.creditScore);
        require(_amount <= maxAmount, "Amount exceeds credit limit");
        require(_amount <= totalLiquidity, "Insufficient liquidity");
        require(_durationDays >= 7 && _durationDays <= 365, "Invalid duration");
        
        uint256 interestRate = getInterestRate(profile.creditScore);
        uint256 interest = (_amount * interestRate * _durationDays) / (365 * 100);
        uint256 amountToRepay = _amount + interest;
        
        loanIdCounter++;
        uint256 loanId = loanIdCounter;
        
        loans[loanId] = Loan({
            id: loanId,
            borrower: msg.sender,
            amount: _amount,
            amountToRepay: amountToRepay,
            deadline: block.timestamp + (_durationDays * 1 days),
            repaid: false,
            defaulted: false
        });
        
        userLoans[msg.sender].push(loanId);
        profile.totalBorrowed += _amount;
        profile.loansCount++;
        
        totalLiquidity -= _amount;
        
        require(lendingToken.transfer(msg.sender, _amount), "Transfer failed");
        
        emit LoanRequested(loanId, msg.sender, _amount);
    }
    
    function repayLoan(uint256 _loanId) external {
        Loan storage loan = loans[_loanId];
        require(loan.borrower == msg.sender, "Not your loan");
        require(!loan.repaid, "Already repaid");
        require(!loan.defaulted, "Loan defaulted");
        
        require(
            lendingToken.transferFrom(msg.sender, address(this), loan.amountToRepay),
            "Transfer failed"
        );
        
        loan.repaid = true;
        totalLiquidity += loan.amountToRepay;
        
        UserProfile storage profile = profiles[msg.sender];
        profile.totalRepaid += loan.amountToRepay;
        
        bool onTime = block.timestamp <= loan.deadline;
        
        if (onTime) {
            profile.onTimePayments++;
            _updateScore(msg.sender, true);
        } else {
            profile.latePayments++;
            _updateScore(msg.sender, false);
        }
        
        emit LoanRepaid(_loanId, msg.sender, onTime);
    }
    
    function _updateScore(address _user, bool _goodPayment) internal {
        UserProfile storage profile = profiles[_user];
        
        if (_goodPayment) {
            if (profile.creditScore < 1000) {
                profile.creditScore += 50;
                if (profile.creditScore > 1000) {
                    profile.creditScore = 1000;
                }
            }
        } else {
            if (profile.creditScore >= 100) {
                profile.creditScore -= 100;
            } else {
                profile.creditScore = 0;
            }
        }
        
        uint256 accountAgeBonus = (block.timestamp - profile.accountAge) / 30 days * 10;
        if (accountAgeBonus > 200) accountAgeBonus = 200;
        
        profile.creditScore += accountAgeBonus;
        if (profile.creditScore > 1000) profile.creditScore = 1000;
        
        emit ScoreUpdated(_user, profile.creditScore);
    }
    
    function markAsDefaulted(uint256 _loanId) external onlyOwner {
        Loan storage loan = loans[_loanId];
        require(!loan.repaid, "Already repaid");
        require(block.timestamp > loan.deadline + 30 days, "Too early to default");
        
        loan.defaulted = true;
        
        UserProfile storage profile = profiles[loan.borrower];
        if (profile.creditScore >= 200) {
            profile.creditScore -= 200;
        } else {
            profile.creditScore = 0;
        }
        
        emit ScoreUpdated(loan.borrower, profile.creditScore);
    }
    
    function getUserProfile(address _user) external view returns (
        uint256 creditScore,
        uint256 totalBorrowed,
        uint256 totalRepaid,
        uint256 loansCount,
        uint256 onTimePayments,
        uint256 latePayments,
        uint256 maxLoanAmount,
        uint256 interestRate
    ) {
        UserProfile memory profile = profiles[_user];
        return (
            profile.creditScore,
            profile.totalBorrowed,
            profile.totalRepaid,
            profile.loansCount,
            profile.onTimePayments,
            profile.latePayments,
            getMaxLoanAmount(profile.creditScore),
            getInterestRate(profile.creditScore)
        );
    }
    
    function getLoanDetails(uint256 _loanId) external view returns (
        address borrower,
        uint256 amount,
        uint256 amountToRepay,
        uint256 deadline,
        bool repaid,
        bool defaulted,
        bool isOverdue
    ) {
        Loan memory loan = loans[_loanId];
        return (
            loan.borrower,
            loan.amount,
            loan.amountToRepay,
            loan.deadline,
            loan.repaid,
            loan.defaulted,
            block.timestamp > loan.deadline && !loan.repaid
        );
    }
    
    function getUserLoans(address _user) external view returns (uint256[] memory) {
        return userLoans[_user];
    }
    
    function withdrawLiquidity(uint256 _amount) external onlyOwner {
        require(_amount <= totalLiquidity, "Insufficient liquidity");
        totalLiquidity -= _amount;
        require(lendingToken.transfer(owner, _amount), "Transfer failed");
    }
}
