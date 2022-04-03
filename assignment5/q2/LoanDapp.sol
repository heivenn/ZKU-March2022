pragma solidity >=0.5.0 <0.7.0;

import "@aztec/protocol/contracts/interfaces/IAZTEC.sol";
import "@aztec/protocol/contracts/libs/NoteUtils.sol";
import "@aztec/protocol/contracts/ERC1724/ZkAsset.sol";
import "./ZKERC20/ZKERC20.sol";
import "./Loan.sol";

contract LoanDapp is IAZTEC {
    using NoteUtils for bytes;

    event SettlementCurrencyAdded(uint256 id, address settlementAddress);

    event LoanApprovedForSettlement(address loanId);

    event LoanCreated(
        address id,
        address borrower,
        bytes32 notional,
        string borrowerPublicKey,
        uint256[] loanVariables,
        uint256 createdAt
    );

    event ViewRequestCreated(
        address loanId,
        address lender,
        string lenderPublicKey
    );

    event ViewRequestApproved(
        uint256 accessId,
        address loanId,
        address user,
        string sharedSecret
    );

    event NoteAccessApproved(
        uint256 accessId,
        bytes32 note,
        address user,
        string sharedSecret
    );

    address owner = msg.sender;
    address aceAddress;
    // addresses of Loan objects
    address[] public loans;
    // settlement currency id => address of settlement currency contract
    mapping(uint256 => address) public settlementCurrencies;

    uint24 MINT_PRO0F = 66049;
    uint24 BILATERAL_SWAP_PROOF = 65794;

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    modifier onlyBorrower(address _loanAddress) {
        Loan loanContract = Loan(_loanAddress);
        require(msg.sender == loanContract.borrower());
        _;
    }

    constructor(address _aceAddress) public {
        aceAddress = _aceAddress;
    }

    function _getCurrencyContract(uint256 _settlementCurrencyId)
        internal
        view
        returns (address)
    {
        require(
            settlementCurrencies[_settlementCurrencyId] != address(0),
            "Settlement Currency is not defined"
        );
        return settlementCurrencies[_settlementCurrencyId];
    }

    function _generateAccessId(bytes32 _note, address _user)
        internal
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encodePacked(_note, _user)));
    }

    function _approveNoteAccess(
        bytes32 _note,
        address _userAddress,
        string memory _sharedSecret
    ) internal {
        // returns hash of note and user address
        uint256 accessId = _generateAccessId(_note, _userAddress);
        emit NoteAccessApproved(accessId, _note, _userAddress, _sharedSecret);
    }

    // Mints new loan, adds its address to loans array
    function _createLoan(
        bytes32 _notional,
        uint256[] memory _loanVariables,
        bytes memory _proofData
    ) private returns (address) {
        address loanCurrency = _getCurrencyContract(_loanVariables[3]);

        // initialize new Loan
        Loan newLoan = new Loan(
            _notional,
            _loanVariables,
            msg.sender,
            aceAddress,
            loanCurrency
        );
        // address of new loan instance gets added to loans array
        loans.push(address(newLoan));
        Loan loanContract = Loan(address(newLoan));

        loanContract.setProofs(1, uint256(-1));
        // Using mint proof, mints new AZTEC note to represent loan, adds it to note registry and increase total note supply
        loanContract.confidentialMint(MINT_PROOF, bytes(_proofData));

        return address(newLoan);
    }

    // Only DApp owner can add a new settlement currency and its corresponding contract address
    function addSettlementCurrency(uint256 _id, address _address)
        external
        onlyOwner
    {
        settlementCurrencies[_id] = _address;
        emit SettlementCurrencyAdded(_id, _address);
    }

    function createLoan(
        bytes32 _notional,
        string calldata _viewingKey,
        string calldata _borrowerPublicKey,
        uint256[] calldata _loanVariables,
        // [0] interestRate
        // [1] interestPeriod
        // [2] loanDuration
        // [3] settlementCurrencyId
        bytes calldata _proofData
    ) external {
        // creates new loan and gets address of new loan instance
        address loanId = _createLoan(_notional, _loanVariables, _proofData);

        emit LoanCreated(
            loanId,
            msg.sender,
            _notional,
            _borrowerPublicKey,
            _loanVariables,
            block.timestamp
        );
        // loan request creator has view access of the note
        _approveNoteAccess(_notional, msg.sender, _viewingKey);
    }

    function approveLoanNotional(
        bytes32 _noteHash,
        bytes memory _signature,
        address _loanId
    ) public {
        Loan loanContract = Loan(_loanId);
        // allows loan instance to spend the note
        loanContract.confidentialApprove(_noteHash, _loanId, true, _signature);
        emit LoanApprovedForSettlement(_loanId);
    }

    function submitViewRequest(
        address _loanId,
        string calldata _lenderPublicKey
    ) external {
        emit ViewRequestCreated(_loanId, msg.sender, _lenderPublicKey);
    }

    function approveViewRequest(
        address _loanId,
        address _lender,
        bytes32 _notionalNote,
        string calldata _sharedSecret
    ) external onlyBorrower(_loanId) {
        // returns hash of notional note and lender
        uint256 accessId = _generateAccessId(_notionalNote, _lender);

        emit ViewRequestApproved(accessId, _loanId, _lender, _sharedSecret);
    }

    event SettlementSuccesfull(
        address indexed from,
        address indexed to,
        address loanId,
        uint256 timestamp
    );

    struct LoanPayment {
        address from;
        address to;
        bytes notional;
    }

    mapping(uint256 => mapping(uint256 => LoanPayment)) public loanPayments;

    // borrower receives settlement assets and lender receives loan ownership
    function settleInitialBalance(
        address _loanId,
        bytes calldata _proofData,
        bytes32 _currentInterestBalance
    ) external {
        Loan loanContract = Loan(_loanId);
        loanContract.settleLoan(
            _proofData,
            _currentInterestBalance,
            msg.sender
        );
        emit SettlementSuccesfull(
            msg.sender,
            loanContract.borrower(),
            _loanId,
            block.timestamp
        );
    }

    // emits note access approved event
    function approveNoteAccess(
        bytes32 _note,
        string calldata _viewingKey,
        string calldata _sharedSecret,
        address _sharedWith
    ) external {
        // if viewing key is provided, caller gets access event
        if (bytes(_viewingKey).length != 0) {
            _approveNoteAccess(_note, msg.sender, _viewingKey);
        }
        // if sharedSecret is provided, the _sharedWith address gets access event
        if (bytes(_sharedSecret).length != 0) {
            _approveNoteAccess(_note, _sharedWith, _sharedSecret);
        }
    }
}
