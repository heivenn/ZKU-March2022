pragma solidity >=0.5.0 <0.7.0;
import "@aztec/protocol/contracts/ERC1724/ZkAssetMintable.sol";
import "@aztec/protocol/contracts/libs/NoteUtils.sol";
import "@aztec/protocol/contracts/interfaces/IZkAsset.sol";
import "./LoanUtilities.sol";

contract Loan is ZkAssetMintable {
    using SafeMath for uint256;
    using NoteUtils for bytes;
    using LoanUtilities for LoanUtilities.LoanVariables;
    LoanUtilities.LoanVariables public loanVariables;
    IZkAsset public settlementToken;
    // [0] interestRate
    // [1] interestPeriod
    // [2] duration
    // [3] settlementCurrencyId
    // [4] loanSettlementDate
    // [5] lastInterestPaymentDate address public borrower;
    address public lender;
    address public borrower;

    // address of lender => shared secret
    mapping(address => bytes) lenderApprovals;

    event LoanPayment(string paymentType, uint256 lastInterestPaymentDate);
    event LoanDefault();
    event LoanRepaid();

    struct Note {
        address owner; // Ethereum address of note owner
        bytes32 noteHash; // hash of the note's public key
    }

    function _noteCoderToStruct(bytes memory note)
        internal
        pure
        returns (Note memory codedNote)
    {
        // returns address of note owner and hash of note's public key
        (address owner, bytes32 noteHash, ) = note.extractNote();
        return Note(owner, noteHash);
    }

    // initializes loan
    constructor(
        bytes32 _notional,
        uint256[] memory _loanVariables,
        address _borrower,
        address _aceAddress,
        address _settlementCurrency
    ) public ZkAssetMintable(_aceAddress, address(0), 1, true, false) {
        // ace address, token address, scaling factor, canAdjustSupply, canConvert
        loanVariables.loanFactory = msg.sender;
        loanVariables.notional = _notional;
        loanVariables.id = address(this);
        loanVariables.interestRate = _loanVariables[0];
        loanVariables.interestPeriod = _loanVariables[1];
        loanVariables.duration = _loanVariables[2];
        loanVariables.borrower = _borrower;
        borrower = _borrower;
        loanVariables.settlementToken = IZkAsset(_settlementCurrency);
        loanVariables.aceAddress = _aceAddress;
    }

    // lender requests access to see value of loan notional
    function requestAccess() public {
        lenderApprovals[msg.sender] = "0x";
    }

    function approveAccess(address _lender, bytes memory _sharedSecret) public {
        lenderApprovals[_lender] = _sharedSecret;
    }

    // loan ownership will go to lender and settlement assets go to borrower
    function settleLoan(
        bytes calldata _proofData,
        bytes32 _currentInterestBalance,
        address _lender
    ) external {
        // settler must be loan initializer
        LoanUtilities.onlyLoanDapp(msg.sender, loanVariables.loanFactory);
        // validates bilateral swap proof to show that settlement asset is equal to loan multiplied by loan price (notional amount)
        LoanUtilities._processLoanSettlement(_proofData, loanVariables);

        loanVariables.loanSettlementDate = block.timestamp;
        loanVariables.lastInterestPaymentDate = block.timestamp;
        loanVariables.currentInterestBalance = _currentInterestBalance;
        loanVariables.lender = _lender;
        lender = _lender;
    }

    // Mints new AZTEC note to represent loan, adds it to note registry and increase confidentialTotalSupply note
    function confidentialMint(uint24 _proof, bytes calldata _proofData)
        external
    {
        // minter must be the loan initializer
        LoanUtilities.onlyLoanDapp(msg.sender, loanVariables.loanFactory);
        // owner should also be loanVariables.loanFactory from ZkAssetMintable constructor
        require(
            msg.sender == owner,
            "only owner can call the confidentialMint() method"
        );
        require(_proofData.length != 0, "proof invalid");
        // overide this function to change the mint method to msg.sender
        // Mints the new AZTEC notes
        bytes memory _proofOutputs = ace.mint(_proof, _proofData, msg.sender);

        // newTotal equals the new confidentialTotalSupply note
        (, bytes memory newTotal, , ) = _proofOutputs
            .get(0)
            .extractProofOutput();
        // mintedNotes are the notes we just minted
        (, bytes memory mintedNotes, , ) = _proofOutputs
            .get(1)
            .extractProofOutput();

        // get hash of confidentialTotalSupply note's public key and confidentialTotalSupply note-specific metadata
        (, bytes32 noteHash, bytes memory metadata) = newTotal.extractNote();

        // Emit events for all output notes, which represent notes being created and added to the note registry
        logOutputNotes(mintedNotes);
        emit UpdateTotalMinted(noteHash, metadata);
    }

    // Proves we are
    function withdrawInterest(
        bytes memory _proof1,
        bytes memory _proof2,
        uint256 _interestDurationToWithdraw
    ) public {
        // Dividend proof used to prove NotionalNote = AccruedInterest * Ratio
        (, bytes memory _proof1OutputNotes) = LoanUtilities
            ._validateInterestProof(
                _proof1,
                _interestDurationToWithdraw,
                loanVariables
            );

        // Ensure lender is not trying to withdraw is more than the actual accrued interest
        require(
            _interestDurationToWithdraw.add(
                loanVariables.lastInterestPaymentDate
            ) < block.timestamp,
            " withdraw is greater than accrued interest"
        );

        // Uses Join-Split proof to withdraw interest by splitting current interest balance into accrued interest and remainder note, and passing on transfer instructions from output of verifying '_proof2'
        bytes32 newCurrentInterestNoteHash = LoanUtilities
            ._processInterestWithdrawal(
                _proof2,
                _proof1OutputNotes, // accrued interest note
                loanVariables
            );

        loanVariables.currentInterestBalance = newCurrentInterestNoteHash;
        // update loan interest payment date by duration of amount withdrawn
        loanVariables.lastInterestPaymentDate = loanVariables
            .lastInterestPaymentDate
            .add(_interestDurationToWithdraw);
        // indicate a loan interest payment has occurred at the payment date
        emit LoanPayment("INTEREST", loanVariables.lastInterestPaymentDate);
    }

    function adjustInterestBalance(bytes memory _proofData) public {
        // only borrower can adjust interest balance
        LoanUtilities.onlyBorrower(msg.sender, borrower);

        // uses join-split proof to allow borrower to pay into interest balance
        bytes32 newCurrentInterestBalance = LoanUtilities
            ._processAdjustInterest(_proofData, loanVariables);
        loanVariables.currentInterestBalance = newCurrentInterestBalance;
    }

    function repayLoan(bytes memory _proof1, bytes memory _proof2) public {
        // ensures only the borrower can repay the loan
        LoanUtilities.onlyBorrower(msg.sender, borrower);

        uint256 remainingInterestDuration = loanVariables
            .loanSettlementDate
            .add(loanVariables.duration)
            .sub(loanVariables.lastInterestPaymentDate);

        // Dividend proof used to prove NotionalNote = AccruedInterest * Ratio
        (, bytes memory _proof1OutputNotes) = LoanUtilities
            ._validateInterestProof(
                _proof1,
                remainingInterestDuration,
                loanVariables
            );

        // ensures loan is not already overdue
        require(
            loanVariables.loanSettlementDate.add(loanVariables.duration) <
                block.timestamp,
            "loan has not matured"
        );

        // use join-split proof to confidentially transfer repayment of loan and interest with the lender as recipient
        LoanUtilities._processLoanRepayment(
            _proof2,
            _proof1OutputNotes,
            loanVariables
        );

        emit LoanRepaid();
    }

    // Dividend Proof as used before to validate the currently accrued interest, and the Private Range Proof, to validate that the accrued interest is greater than the available balance inside the interest account. Thus, the loan is considered to be in default.
    function markLoanAsDefault(
        bytes memory _proof1,
        bytes memory _proof2,
        uint256 _interestDurationToWithdraw
    ) public {
        // Ensure lender is not trying to withdraw is more than the actual accrued interest
        require(
            _interestDurationToWithdraw.add(
                loanVariables.lastInterestPaymentDate
            ) < block.timestamp,
            "withdraw is greater than accrued interest"
        );
        //_proof1 is used for _validateInterestProof, _proof2 is used with private range proof
        LoanUtilities._validateDefaultProofs(
            _proof1,
            _proof2,
            _interestDurationToWithdraw,
            loanVariables
        );
        emit LoanDefault();
    }
}
