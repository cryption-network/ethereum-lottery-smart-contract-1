pragma solidity ^0.6.0;

import "./interfaces/IERC20.sol";
import "./VRFConsumerBase.sol";
import "@openzeppelin/contracts/utils/Address.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LotteryContract is VRFConsumerBase, ReentrancyGuard, Ownable {
    using Address for address;
    using SafeMath for uint256;

    struct LotteryConfig {
        uint256 numOfWinners;
        uint256 playersLimit;
        uint256 registrationAmount;
        uint256 adminFeePercentage;
        uint256 randomSeed;
        uint256 startedAt;
    }

    address[] public lotteryPlayers;
    address public feeAddress;
    enum LotteryStatus {
        NOTSTARTED,
        INPROGRESS,
        CLOSED
    }
    mapping(uint256 => address) public winnerAddresses;
    uint256[] public winnerIndexes;
    uint256 public totalLotteryPool;
    uint256 public adminFeesAmount;
    uint256 public rewardPoolAmount;

    IERC20 public lotteryToken;
    IERC20 public buyToken;
    LotteryStatus public lotteryStatus;
    LotteryConfig public lotteryConfig;

    bytes32 internal keyHash;
    uint256 internal fee;
    uint256 internal randomResult;
    bool internal areWinnersGenerated;
    bool internal isRandomNumberGenerated;

    bool public pauseLottery;

    uint256 public loserLotteryAmount;
    // event MaxParticipationCompleted(address indexed _from);

    event RandomNumberGenerated(uint256 indexed randomness);

    event WinnersGenerated(uint256[] winnerIndexes);

    event LotterySettled(
        uint256 _rewardPoolAmount,
        uint256 _players,
        uint256 _adminFees
    );

    event LotteryPaused();

    event LotteryUnPaused();

    event EmergencyWithdrawn();

    // LotterySettled(rewardPoolAmount, players, adminFeesAmount);

    event LotteryStarted(
        uint256 playersLimit,
        uint256 numOfWinners,
        uint256 registrationAmount,
        uint256 startedAt
    );

    event LotteryReset();

    /**
     * @dev Sets the value for adminAddress which establishes the Admin of the contract
     * Only the adminAddress will be able to set the lottery configuration,
     * start the lottery and reset the lottery.
     *
     * It also sets the required fees, keyHash etc. for the ChainLink Oracle RNG
     *
     * Also initializes the LOT ERC20 TOKEN that is minted/burned by the participating lottery players.
     *
     * The adminAdress value is immutable along with the initial
     * configuration of VRF Smart Contract. They can only be set once during
     * construction.
     */
    constructor(
        IERC20 _buyToken,
        IERC20 _lotteryToken,
        address _feeAddress,
        address _vrfCoordinator,
        address _link,
        bytes32 _keyHash
    )
        public
        VRFConsumerBase(
            _vrfCoordinator, // VRF Coordinator
            _link // LINK Token
        )
        Ownable()
    {
        feeAddress = _feeAddress;
        lotteryStatus = LotteryStatus.NOTSTARTED;
        totalLotteryPool = 0;
        keyHash = _keyHash;
        fee = 0.0001 * 10**18; // 0.0001 LINK
        areWinnersGenerated = false;
        isRandomNumberGenerated = false;
        buyToken = _buyToken; // ERC20 contract
        lotteryToken = _lotteryToken; // ERC20 contract
        // isOnlyETHAccepted = _isOnlyETHAccepted;
    }

    function pauseNextLottery() public onlyOwner {
        // require(
        //     msg.sender == adminAddress,
        //     "Starting the Lottery requires Admin Access"
        // );
        pauseLottery = true;
        emit LotteryPaused();
    }

    function unPauseNextLottery() public onlyOwner {
        // require(
        //     msg.sender == adminAddress,
        //     "Starting the Lottery requires Admin Access"
        // );
        pauseLottery = false;
        emit LotteryUnPaused();
        // resetLottery();
    }

    function withdrawLink() external onlyOwner {
        LINK.transfer(owner(), LINK.balanceOf(address(this)));
    }

    function changeFeeAddress(address _feeAddress) public onlyOwner {
        require(_feeAddress != address(0), "Incorrect fee address");
        feeAddress = _feeAddress;
    }

    /**
     * @dev Calls ChainLink Oracle's inherited function for
     * Random Number Generation.
     *
     * Requirements:
     *
     * - the contract must have a balance of at least `fee` required for VRF.
     */
    function getRandomNumber(uint256 userProvidedSeed)
        internal
        returns (bytes32 requestId)
    {
        require(
            LINK.balanceOf(address(this)) >= fee,
            "Not enough LINK - fill contract with faucet"
        );
        isRandomNumberGenerated = false;
        return requestRandomness(keyHash, fee, userProvidedSeed);
    }

    /**
     * @dev The callback function of ChainLink Oracle when the
     * Random Number Generation is completed. An event is fired
     * to notify the same and the randomResult is saved.
     *
     * Emits an {RandomNumberGenerated} event indicating the random number is
     * generated by the Oracle.
     *
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        randomResult = randomness;
        isRandomNumberGenerated = true;
        emit RandomNumberGenerated(randomness);
    }

    /**
     * @dev Sets the Lottery Config, initializes an instance of
     * ERC20 contract that the lottery is based on and starts the lottery.
     *
     * Emits an {LotteryStarted} event indicating the Admin has started the Lottery.
     *
     * Requirements:
     *
     * - Cannot be called if the lottery is in progress.
     * - Only the address set at `adminAddress` can call this function.
     * - Number of winners `numOfWinners` should be less than or equal to half the number of
     *   players `playersLimit`.
     */
    function setLotteryRules(
        uint256 numOfWinners,
        uint256 playersLimit,
        uint256 registrationAmount,
        uint256 adminFeePercentage,
        uint256 randomSeed
    ) public onlyOwner {
        // require(
        //     msg.sender == adminAddress,
        //     "Starting the Lottery requires Admin Access"
        // );
        require(
            lotteryStatus == LotteryStatus.NOTSTARTED,
            "Error: An existing lottery is in progress"
        );
        require(
            numOfWinners <= playersLimit.div(2),
            "Number of winners should be less than or equal to half the number of players"
        );
        lotteryConfig = LotteryConfig(
            numOfWinners,
            playersLimit,
            registrationAmount,
            adminFeePercentage,
            // lotteryTokenAddress,
            randomSeed,
            block.timestamp
        );
        lotteryStatus = LotteryStatus.INPROGRESS;

        loserLotteryAmount = (registrationAmount.mul(1e18)).div(
            10**buyToken.decimals()
        );

        emit LotteryStarted(
            // lotteryTokenAddress,
            playersLimit,
            numOfWinners,
            registrationAmount,
            block.timestamp
        );
    }

    /**
     * @dev Player enters the lottery and the registration amount is
     * transferred from the player to the contract.
     *
     * Returns participant's index. This is similar to unique registration id.
     * Emits an {MaxParticipationCompleted} event indicating that all the required players have entered the lottery.
     *
     * The participant is also issued an equal amount of LOT tokens once he registers for the lottery.
     * This LOT tokens are fundamental to the lottery contract and are used internally.
     * The winners will need to burn their LOT tokens to claim the lottery winnings.
     * The other participants of the lottery can keep hold of these tokens and use for other applications.
     *
     * Requirements:
     *
     * - The player has set the necessary allowance to the Contract.
     * - The Lottery is in progress.
     * - Number of players allowed to enter in the lottery should be
     *   less than or equal to the allowed players `lotteryConfig.playersLimit`.
     */
    function enterLottery() public returns (uint256) {
        require(
            lotteryPlayers.length < lotteryConfig.playersLimit,
            "Max Participation for the Lottery Reached"
        );

        // require(
        //     lotteryPlayers.length == 0 && !pauseLottery,
        //     "Lottery is paused"
        // );

        if (lotteryPlayers.length == 0) {
            require(!pauseLottery, "Lottery is paused");
        }

        require(
            lotteryStatus == LotteryStatus.INPROGRESS,
            "The Lottery is not started or closed"
        );
        lotteryPlayers.push(msg.sender);

        buyToken.transferFrom(
            msg.sender,
            address(this),
            lotteryConfig.registrationAmount
        );

        totalLotteryPool = totalLotteryPool.add(
            lotteryConfig.registrationAmount
        );
        // call _mint from constructor ERC20
        // Not giving loser lottery tokens !!
        // lotteryToken.mint(msg.sender, lotteryConfig.registrationAmount);

        if (lotteryPlayers.length == lotteryConfig.playersLimit) {
            // emit MaxParticipationCompleted(msg.sender); // this is not needed now
            getRandomNumber(lotteryConfig.randomSeed);
        }
        return (lotteryPlayers.length).sub(1);
    }

    /**
     * @dev Settles the lottery, the winners are calculated based on
     * the random number generated. The Admin fee is calculated and
     * transferred back to Admin `adminAddress`.
     *
     * Emits an {WinnersGenerated} event indicating that the winners for the lottery have been generated.
     * Emits {LotterySettled} event indicating that the winnings have been transferred to the Admin and the Lottery is closed.
     *
     * Requirements:
     *
     * - The random number has been generated
     * - The Lottery is in progress.
     */
    function settleLottery() external {
        require(
            isRandomNumberGenerated,
            "Lottery Configuration still in progress. Please try in a short while"
        );
        require(
            lotteryStatus == LotteryStatus.INPROGRESS,
            "The Lottery is not started or closed"
        );
        for (uint256 i = 0; i < lotteryConfig.numOfWinners; i = i.add(1)) {
            uint256 winningIndex = randomResult.mod(lotteryConfig.playersLimit);
            uint256 counter = 0;
            while (winnerAddresses[winningIndex] != address(0)) {
                randomResult = getRandomNumberBlockchain(i, randomResult);
                winningIndex = randomResult.mod(lotteryConfig.playersLimit);
                counter = counter.add(1);
                if (counter == lotteryConfig.playersLimit) {
                    while (winnerAddresses[winningIndex] != address(0)) {
                        winningIndex = (winningIndex.add(1)).mod(
                            lotteryConfig.playersLimit
                        );
                    }
                    counter = 0;
                }
            }
            winnerAddresses[winningIndex] = lotteryPlayers[winningIndex];
            winnerIndexes.push(winningIndex);
            randomResult = getRandomNumberBlockchain(i, randomResult);
        }
        areWinnersGenerated = true;
        emit WinnersGenerated(winnerIndexes);
        adminFeesAmount = (
            (totalLotteryPool.mul(lotteryConfig.adminFeePercentage)).div(100)
        );
        rewardPoolAmount = (totalLotteryPool.sub(adminFeesAmount)).div(
            lotteryConfig.numOfWinners
        );
        lotteryStatus = LotteryStatus.CLOSED;

        // if (isOnlyETHAccepted) {
        //     (bool status, ) = payable(adminAddress).call{
        //         value: adminFeesAmount
        //     }("");
        //     require(status, "Admin fees not transferred");
        // } else {
        buyToken.transfer(feeAddress, adminFeesAmount);
        // }

        emit LotterySettled(
            rewardPoolAmount,
            lotteryConfig.numOfWinners,
            adminFeesAmount
        );
        collectRewards();
    }

    function getWinningAmount() public view returns (uint256) {
        uint256 expectedTotalLotteryPool = lotteryConfig.playersLimit.mul(
            lotteryConfig.registrationAmount
        );
        uint256 adminFees = (
            (expectedTotalLotteryPool.mul(lotteryConfig.adminFeePercentage))
                .div(100)
        );
        uint256 rewardPool = (expectedTotalLotteryPool.sub(adminFees)).div(
            lotteryConfig.numOfWinners
        );

        return rewardPool;
    }

    function getCurrentlyActivePlayers() public view returns (uint256) {
        return lotteryPlayers.length;
    }

    /**
     * @dev The winners of the lottery can call this function to transfer their winnings
     * from the lottery contract to their own address. The winners will need to burn their
     * LOT tokens to claim the lottery rewards. This is executed by the lottery contract itself.
     *
     *
     * Requirements:
     *
     * - The Lottery is settled i.e. the lotteryStatus is CLOSED.
     */
    /**
     * @dev The winners of the lottery can call this function to transfer their winnings
     * from the lottery contract to their own address. The winners will need to burn their
     * LOT tokens to claim the lottery rewards. This is executed by the lottery contract itself.
     *
     *
     * Requirements:
     *
     * - The Lottery is settled i.e. the lotteryStatus is CLOSED.
     */
    function collectRewards() private nonReentrant {
        // require(
        //     lotteryStatus == LotteryStatus.CLOSED,
        //     "The Lottery is not settled. Please try in a short while."
        // );

        bool isWinner = false;

        for (uint256 i = 0; i < lotteryConfig.playersLimit; i = i.add(1)) {
            address player = lotteryPlayers[i];
            // if (address(msg.sender) == winnerAddresses[winnerIndexes[i]]) {
            for (uint256 j = 0; j < lotteryConfig.numOfWinners; j = j.add(1)) {
                address winner = winnerAddresses[winnerIndexes[j]];

                if (winner != address(0) && winner == player) {
                    isWinner = true;
                    winnerAddresses[winnerIndexes[j]] = address(0);
                    break;
                }
            }

            if (isWinner) {
                // _burn(address(msg.sender), lotteryConfig.registrationAmount);
                // lotteryToken.burnFrom(msg.sender, lotteryConfig.registrationAmount);
                // if (isOnlyETHAccepted) {
                //     (bool status, ) = payable(player).call{
                //         value: rewardPoolAmount
                //     }("");
                //     require(status, "Amount not transferred to winner");
                // } else {
                buyToken.transfer(address(player), rewardPoolAmount);
                // }
            } else {
                lotteryToken.mint(player, loserLotteryAmount);
            }

            isWinner = false;
        }

        resetLottery();
    }

    /**
     * @dev Generates a random number based on the blockHash and random offset
     */
    function getRandomNumberBlockchain(uint256 offset, uint256 randomness)
        internal
        view
        returns (uint256)
    {
        bytes32 offsetBlockhash = blockhash(block.number.sub(offset));
        uint256 randomBlockchainNumber = uint256(offsetBlockhash);
        uint256 finalRandomNumber = randomness + randomBlockchainNumber;
        if (finalRandomNumber >= randomness) {
            return finalRandomNumber;
        } else {
            if (randomness >= randomBlockchainNumber) {
                return randomness.sub(randomBlockchainNumber);
            }
            return randomBlockchainNumber.sub(randomness);
        }
    }

    /**
     * It can be called by admin to withdraw all the amount in case of
     * any failure to play lottery. It will be distributed later on amongst the
     * participants.
     */
    function emergencyWithdraw() external onlyOwner {
        buyToken.transfer(msg.sender, buyToken.balanceOf(address(this)));
        emit EmergencyWithdrawn();
    }

    /**
     * @dev Resets the lottery, clears the existing state variable values and the lottery
     * can be initialized again.
     *
     * Emits {LotteryReset} event indicating that the lottery config and contract state is reset.
     *
     * Requirements:
     *
     * - Only the address set at `adminAddress` can call this function.
     * - The Lottery has closed.
     */
    function resetLottery() private {
        // require(
        //     msg.sender == adminAddress,
        //     "Resetting the Lottery requires Admin Access"
        // );
        // require(
        //     lotteryStatus == LotteryStatus.CLOSED,
        //     "Lottery Still in Progress"
        // );
        uint256 tokenBalance = lotteryToken.balanceOf(address(this));
        if (tokenBalance > 0) {
            buyToken.transfer(feeAddress, tokenBalance);
        }
        // delete lotteryConfig;
        delete randomResult;
        lotteryStatus = LotteryStatus.INPROGRESS;
        delete totalLotteryPool;
        delete adminFeesAmount;
        delete rewardPoolAmount;
        for (uint256 i = 0; i < lotteryPlayers.length; i = i.add(1)) {
            delete winnerAddresses[i];
        }
        isRandomNumberGenerated = false;
        areWinnersGenerated = false;
        delete winnerIndexes;
        delete lotteryPlayers;
        emit LotteryReset();
    }
}
