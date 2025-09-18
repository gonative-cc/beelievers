export type AuctionConf = {
	packageId: string;
	auctionId: string;
	adminCapId: string;
	clearingPrice: number;
	discounts: number; // see finalize_end function docs
	startMs: number;
	durationMs: number;
	auctionSize: number;
	network: string;
	raffleSize: number;
};

export const auctionConfMainnet: AuctionConf = {
	packageId: "0x1b4cbd991bb7e31ff60b6685bcfef6c9c724bc04a6daabb7c815eae0213001ea",
	auctionId: "0x161524be15687cca96dec58146568622458905c30479452351f231cac5d64c41",
	adminCapId: "0xe0b2e857aaa3120b7c4e3f2e5f5073e2b603719bbfcdcd0ce8e138b49922f27c",
	clearingPrice: 5260500000,
	discounts: 0,
	network: "mainnet",
	startMs: 0,
	durationMs: 0,
	auctionSize: 5810,
	raffleSize: 21,
};

export const auctionConfTestnet: AuctionConf = {
	packageId: "",
	auctionId: "",
	adminCapId: "",
	clearingPrice: 0,
	discounts: 1e9,
	network: "testnet",
	startMs: 0,
	durationMs: 0,
	auctionSize: 0,
	raffleSize: 21,
};
