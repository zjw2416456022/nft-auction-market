module.exports = async ({ deployments, getNamedAccounts }) => {
  const { deploy } = deployments;
  const { deployer } = await getNamedAccounts();

  // 部署实现合约（无初始化，无代理）
  await deploy("NftAuction", {
    from: deployer,
    args: [],
    log: true,
  });
};

module.exports.tags = ["NftAuctionImpl"];