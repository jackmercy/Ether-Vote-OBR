pragma solidity ^0.4.24;
pragma experimental ABIEncoderV2; // Allow passing struct as argument

// We have to specify what version of compiler this code will compile with

contract BallotContract {


// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~Ballot Management~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ //

    address private owner;

    bytes32 private ballotName;
    uint    private limitCandidate;

    // Time: seconds since 1970-01-01
    uint private    startRegPhase;
    uint private    endRegPhase;
    uint private    startVotingPhase;
    uint private    endVotingPhase;

    // Ballot status
    bool private    canPublish;
    bool private    isFinalized;            // Whether the owner can still add voting options.
    uint private    registeredVoterCount;   // Total number of voter addresses registered.
    uint private    votedVoterCount;
    //uint private    fundedVoterCount;
    uint private    amount; // in GWei
    uint256 private storedAmount;

    // Candidate list
    bytes32[] private candidateIDs;
    mapping (bytes32 => address[]) voteReceived; //map candidateId to array of address of whom has voted for them


    constructor ()
    {
        owner = msg.sender;       // Set the owner to the address creating the contract.
        ballotName = 'Not set';
        limitCandidate = 0;

        startRegPhase = 0;
        endRegPhase = 0;
        startVotingPhase = 0;
        endVotingPhase = 0;

        isFinalized = false;
        registeredVoterCount = 0;
        votedVoterCount = 0;
        //fundedVoterCount = 0;
        storedAmount = address(this).balance;
        amount = 0;

    }

    function close(bytes32 phrase) onlyOwner public {
        require( keccak256(phrase) == keccak256(bytes32('close')));
        require(storedAmount > 0);
        owner.transfer(storedAmount);
        selfdestruct(owner);
    }

    function () payable {
        storedAmount += msg.value;
    }

    function claimStoredAmount(bytes32 phrase) onlyOwner {
        require(now > endVotingPhase);
        require(storedAmount > 0);
        require(  keccak256(phrase) == keccak256(bytes32('claim')) );

        owner.transfer(storedAmount); // Transfer back remaining amount
    }

    function setupBallot (
        bytes32 _ballotName,
        uint _fundAmount,
        uint _limitCandidate,
        uint _startVotingPhase,
        uint _endVotingPhase,
        uint _startRegPhase,
        uint _endRegPhase,
        bytes32[] _candidateIDs
    ) onlyOwner public {

        ballotName = _ballotName;
        amount = _fundAmount*1000000000; //convert to wei
        limitCandidate = _limitCandidate;
        startRegPhase = _startRegPhase;
        endRegPhase = _endRegPhase;
        startVotingPhase = _startVotingPhase;
        endVotingPhase = _endVotingPhase;

        canPublish = false;
        isFinalized = false;
        registeredVoterCount = 0;
        votedVoterCount = 0;
        //fundedVoterCount = 0;
        storedAmount = address(this).balance;

        addCandidates(_candidateIDs);
    }

    function setTransferAmount(uint _amount) onlyOwner public {
        amount = _amount*1000000000; //convert Gwei to wei
    }

    function addCandidates(bytes32[] _candidateIDs) onlyOwner public {
        require (now < endRegPhase, 'Ballot setup time has ended!');
        require (isFinalized == false);    // Check we are allowed to add options.

        candidateIDs = _candidateIDs;
    }

    function finalizeBallot(bytes32 phrase) onlyOwner public {
        require(candidateIDs.length > 2);
        require( keccak256(phrase) == keccak256(bytes32('finalize')));
        require (now < startVotingPhase);
        require (now > startRegPhase);

        isFinalized = true;    // Stop the addition of any more change.
    }

    function publishBallot() onlyOwner public {
        require (now > endRegPhase);
        canPublish = true;
    }

    function resetTime(bytes32 phrase) onlyOwner public {
        if (keccak256(phrase) == keccak256(bytes32('startRegPhase'))) {
            startRegPhase = 0;
        }
        if (keccak256(phrase) == keccak256(bytes32('endRegPhase'))) {
            endRegPhase = 0;
        }
        if (keccak256(phrase) == keccak256(bytes32('startVotingPhase'))) {
            startVotingPhase = 0;
        }
        if (keccak256(phrase) == keccak256(bytes32('endVotingPhase'))) {
            endVotingPhase = 0;
        }
    }


    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Voting Management ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ //

    /*
    *  Structure which represents a single voter.
    */
    struct Voter
    {
        bool eligibleToVote;    // Is this voter allowed to vote?
        bool isVoted;           // State of whether this voter has voted.
        bool isFunded;
        bytes32[] votedFor;     // List candidates' IDs this voter voted for.
    }

    address[] private voterAddressList;
    mapping(address => Voter) public voters; // State variable which maps any address to a 'Voter' struct.

    function giveRightToVote(address _voter) onlyOwner public {
        require (now < endRegPhase, 'Ballot setup time has ended!');
        require(address(this).balance >= storedAmount);
        require(storedAmount > amount);

        voters[_voter].eligibleToVote = true;
        registeredVoterCount += 1;      // Increment registered voters.
        voterAddressList.push(_voter);

        // Fund user with money
        giveFund(_voter);

    }

    function giveFund(address _voter) onlyOwner private {
        require(voters[_voter].eligibleToVote); // User already had the right to vote
        require(address(this).balance >= storedAmount);
        require(!voters[_voter].isFunded);

        voters[_voter].isFunded = true;
        storedAmount -= amount;
        _voter.transfer(amount);
        //fundedVoterCount += 1;
    }

    function voteForCandidate(bytes32 _candidateID) private {
        require(validCandidate(_candidateID));
        voters[msg.sender].votedFor.push(_candidateID); //Add candidateID to list whom voter voted
        voteReceived[_candidateID].push(msg.sender);
    }

    function voteForCandidates(bytes32[] _candidateIDs) public {
        require(validTime());
        require(isFinalized);
        require(hasRightToVote(msg.sender));

        for (uint i = 0; i < _candidateIDs.length; i++) {
            voteForCandidate(_candidateIDs[i]);
        }
        voters[msg.sender].isVoted = true;
        votedVoterCount += 1;
    }

    function validCandidate(bytes32 _candidateID) private view returns (bool) {
        for (uint i = 0; i < candidateIDs.length; i++) {
            if (candidateIDs[i] == _candidateID) {
                return true;
            }
        }
        return false;
    }

    function hasRightToVote(address voterAddress) public view returns (bool) {
        if (voters[voterAddress].eligibleToVote && !voters[voterAddress].isVoted) {
            return true;
        } else {
            return false;
        }
    }

    // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ Getters & Validators Functions ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ //

    /*------Validators-------*/
    function validTime() private returns (bool) {
        if ( now < endVotingPhase || now > startVotingPhase) {
            return true;
        } else { return false; }
    }

    modifier onlyOwner {
        require(msg.sender == owner );
        _;
    }

    /*------Getters-------*/

    //Get ballot info
    function getBallotOverview() public view returns (
        bytes32, uint, bool, uint, uint, uint, uint, uint, uint, uint, uint
    ) {
        require (msg.sender == owner || canPublish);
        return ( // Do not change the return order
        /*Ballot Info*/
        ballotName,
        limitCandidate,
        isFinalized,
        amount,
        storedAmount,

        /*Phase Info*/
        startRegPhase,
        endRegPhase,
        startVotingPhase,
        endVotingPhase,

        /*Voter Info*/
        registeredVoterCount,
        votedVoterCount
        );
    }

    //Get ballot timeline info
    function getBallotPhases() public view returns (uint, uint, uint, uint) {
        return (
        /*Phase Info*/
        startRegPhase,
        endRegPhase,
        startVotingPhase,
        endVotingPhase
        );
    }

    //Get total number of candidates
    function getCandidateLength() public view returns (uint)  {
        return candidateIDs.length;
    }

    //Get list of candidate for that ballot
    function getCandidateList() public view returns (bytes32[]) {
        return candidateIDs;
    }

    //Get total vote count for that candidate
    function getCandidateResult(bytes32 _candidateID) public view returns (uint, address[])
    {
        return (voteReceived[_candidateID].length, voteReceived[_candidateID]);
    }

    //Whether ballot is finalized
    function isBallotFinalized() public view returns (bool)
    {
        return isFinalized;
    }

    //Get list of candidate that a voter has voted for
    function getVotedForList(address voterAddress) public view returns (bytes32[]) {
        require(canPublish);
        return voters[voterAddress].votedFor;
    }

    //Get list of voterAddress that has voted for a candidate
    function getAddressForCandidate(bytes32 candidateID) public view returns (address[]) {
        require(canPublish);
        return voteReceived[candidateID];
    }

    //Get list of eligible candidate for that ballot
    function getEligibleVoterList() onlyOwner public view returns (address[]) {
        require(canPublish);
        return voterAddressList;
    }


}
