// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";

contract FairDistribution is ReentrancyGuard, VRFConsumerBase {
    // 常量定义
    uint256 public constant PARTICIPATION_FEE = 0.1 ether; // 参与费用：0.1 BNB
    uint256 public constant INITIAL_REWARD = 6_480 * 10**18; // 首日奖励：6,480 NBTC（18位小数）
    uint256 public constant DAILY_DECREASE = 1 * 10**18;    // 每日减少：1 NBTC
    uint256 public constant TOTAL_DAYS = 6_480;             // 总分发天数：6,480 天
    address public constant TRANSFER_ADDRESS = 0xF113275FECc41f396603B677df15eCd1B4A966DB; // 指定转账地址

    // 状态变量
    IERC20 public nbtcToken;              // NBTC 代币合约实例
    uint256 public currentDay;            // 当前天数，从 0 开始
    uint256 public dayEndTimestamp;       // 当前窗口的结束时间戳
    address[] public participants;        // 当天参与者地址列表
    mapping(uint256 => bool) public dayProcessed; // 记录某天是否已处理

    // Chainlink VRF 参数
    bytes32 internal keyHash;             // VRF 请求的 key hash
    uint256 internal fee;                 // VRF 请求费用（LINK）

    // 事件定义
    event Participated(address indexed participant, uint256 day);       // 用户参与事件
    event WinnerSelected(address indexed winner, uint256 reward, uint256 day); // 获胜者选中事件
    event BNBTransferred(uint256 amount, uint256 day);                 // BNB 转账事件
    event RewardTransferred(uint256 amount, uint256 day);              // 奖励转账事件

    // 构造函数
    constructor(
        address _nbtcToken,        // NBTC 代币地址
        address _vrfCoordinator,   // Chainlink VRF 协调者地址
        address _linkToken,        // LINK 代币地址
        bytes32 _keyHash,          // VRF key hash
        uint256 _fee               // VRF 费用
    ) VRFConsumerBase(_vrfCoordinator, _linkToken) {
        nbtcToken = IERC20(_nbtcToken);
        currentDay = 0;
        // 设置第一天的结束时间为下一次北京时间 00:00（UTC 前一天 16:00）
        uint256 secondsInDay = 86_400; // 一天 86,400 秒
        // 计算当天的 UTC 16:00（北京时间 00:00）时间戳
        uint256 targetTimeToday = (block.timestamp / secondsInDay) * secondsInDay + 57_600; // 57,600 = 16小时
        if (block.timestamp >= targetTimeToday) {
            // 如果当前时间已过当天 00:00，设为明天 00:00
            dayEndTimestamp = targetTimeToday + secondsInDay;
        } else {
            // 如果未到当天 00:00，设为今天 00:00
            dayEndTimestamp = targetTimeToday;
        }
        keyHash = _keyHash;
        fee = _fee;
    }

    // 用户参与函数
    function participate() external payable nonReentrant {
        require(msg.value == PARTICIPATION_FEE, "Must send exactly 0.1 BNB"); // 检查发送的 BNB 是否为 0.1
        require(block.timestamp < dayEndTimestamp, "Participation window closed"); // 检查是否在窗口内
        require(currentDay < TOTAL_DAYS, "Distribution ended"); // 检查分发是否已结束

        participants.push(msg.sender); // 将参与者添加到列表
        emit Participated(msg.sender, currentDay); // 触发参与事件
    }

    // 处理当天结果函数
    function processDay() external nonReentrant {
        require(block.timestamp >= dayEndTimestamp, "Day not yet ended"); // 检查当天是否已结束
        require(!dayProcessed[currentDay], "Day already processed"); // 检查当天是否已处理
        require(LINK.balanceOf(address(this)) >= fee, "Insufficient LINK"); // 检查 LINK 余额是否足够

        uint256 reward = getCurrentReward(); // 获取当前奖励
        require(nbtcToken.balanceOf(address(this)) >= reward, "Insufficient NBTC balance"); // 检查 NBTC 余额

        if (participants.length == 0) {
            // 如果没有参与者，将奖励转到指定地址
            nbtcToken.transfer(TRANSFER_ADDRESS, reward);
            emit RewardTransferred(reward, currentDay);
            // 更新状态
            dayProcessed[currentDay] = true;
            currentDay++;
            dayEndTimestamp += 86_400; // 下一天 00:00（增加一天）
        } else {
            // 有参与者，请求 Chainlink VRF 随机数
            requestRandomness(keyHash, fee);
        }
    }

    // Chainlink VRF 回调函数
    function fulfillRandomness(bytes32 /* requestId */, uint256 randomness) internal override {
        uint256 winnerIndex = randomness % participants.length; // 根据随机数选择获胜者索引
        address winner = participants[winnerIndex]; // 获取获胜者地址
        uint256 reward = getCurrentReward(); // 获取当前奖励

        // 发放奖励给获胜者
        nbtcToken.transfer(winner, reward);
        emit WinnerSelected(winner, reward, currentDay);

        // 将所有参与者的 BNB 转到指定地址
        uint256 bnbAmount = address(this).balance;
        if (bnbAmount > 0) {
            (bool success, ) = TRANSFER_ADDRESS.call{value: bnbAmount}("");
            require(success, "BNB transfer failed");
            emit BNBTransferred(bnbAmount, currentDay);
        }

        // 更新状态
        dayProcessed[currentDay] = true;
        currentDay++;
        dayEndTimestamp += 86_400; // 下一天 00:00（增加一天）
        delete participants; // 清空参与者列表
    }

    // 计算当前奖励的函数
    function getCurrentReward() public view returns (uint256) {
        if (currentDay >= TOTAL_DAYS) return 0; // 如果超过总天数，返回 0
        return INITIAL_REWARD - (currentDay * DAILY_DECREASE); // 计算当前奖励：首日奖励 - 已过天数 * 每日减少量
    }

    // 获取当天参与者数量
    function getParticipantsCount() external view returns (uint256) {
        return participants.length;
    }

    // 接收 BNB 的回退函数
    receive() external payable {}
}