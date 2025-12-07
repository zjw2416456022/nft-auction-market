module.exports = async ({ getNamedAccounts, deployments, getChainId }) => {
  const { deploy, get } = deployments;
  const { deployer } = await getNamedAccounts();

  const nft = await get('NFT');

  // Sepolia 测试网地址
  const USDC_ADDRESS     = "0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238";     // Sepolia USDC
  const ETH_USD_FEED     = "0x694AA1769357215DE4FAC081bf1f309aDC325306";     // ETH/USD
  const USDC_USD_FEED    = "0xA2F78ab2355fe2f984D808B5CeE7FD0A93D5270E";     // USDC/USD

  await deploy('Auction', {
    from: deployer,
    proxy: {
      proxyContract: "OpenZeppelinTransparentProxy",
      execute: {
        methodName: "initialize",
        args: [
          nft.address,
          USDC_ADDRESS,
          ETH_USD_FEED,
          USDC_USD_FEED
        ],
      },
    },
    log: true,
  });
};
module.exports.tags = ['Auction'];
module.exports.dependencies = ['NFT'];