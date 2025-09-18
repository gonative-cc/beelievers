// Beelievers Complete Setup Script - Test & Production
// author: Native team + Dead labs

import fs from "fs/promises";
import { bech32 } from "bech32";
import { TransactionBlock } from "@mysten/sui.js/transactions";
import { SuiClient } from "@mysten/sui.js/client";
import { KioskClient, Network } from "@mysten/kiosk";
import { fromHex } from "@mysten/sui/utils";
import { KioskTransaction } from "@mysten/kiosk";
import { TransferPolicyTransaction } from "@mysten/kiosk";
// import { Secp256k1Keypair } from "@mysten/sui.js/keypairs/secp256k1";
import { Ed25519Keypair } from "@mysten/sui.js/keypairs/ed25519";

const ADMIN_PRIVATE_KEY = "";
const MODULE_NAME = "mint";
// on localnet kiosk is not published.
// 1. Download https://github.com/MystenLabs/apps
// 2. cd kiosk
// 3. sui move publish and copy the published pkg
const LOCAL_KIOSK_PKG = "0xc25518ca0079c243b7973f5ebe3e8a390c71ab2f2a2cad1dcd11a6066a98ca15";
const RANDOM_OBJ = "0x8";
const CLOCK_OBJ = "0x6";
// Environment-specific configurations
const CONFIGS = {
	testnet: {
		AUCTION_CONTRACT: "0x60f6241088efad8dea782dfbf0071aaf58cb1baa60388f4b5e66959f7eec7ef6",
		PACKAGE_ID: "0xae0aab765399e42c536b26ee8044efbcdfd4346926a88b26847bf5541cde45ed",
		ADMIN_CAP: "0xb71162810cf2683a763bd7b2400e918e8c5d95a7890450bb8d888e84c0cfd253",
		TRANSFER_POLICY_CAP: "0x3d35d99f054e3c7ee6fe18c4c8f1fb1900da6d219b8a84b03051cf932d3b56fd",
		TRANSFER_POLICY_ID: "0x23039cf016e97829afb865ba1db63e342914c11eca76f87cd4b3d3b4e8e63741",
		COLLECTION_ID: "0x565d980198d3bd1ec33107110ccc5ad448dacb19f1495da313cb015971bcd146",
		KIOSK: "0x5f3f8963055c7fac44340e82e88e4b79d7abfa36382b006a8e0b9b803cdfb088",
		KIOSK_CAP: "0x81a267691ff67fd44faf14ba4ab773c22ec306907c8b59af8690b8213e8a6efd",
		RPC_URL: "https://fullnode.testnet.sui.io:443",
		BATCH_SIZE: 200, // batch size for setting metadata (attributes + image urls)
		DELAY_BETWEEN_BATCHES: 2000,
		TOTAL_NFTS: 6021, // Full collection (same as production)
		MINT_START_TIME: 1744088400000, //timestamp ms
		TEST_ATTRIBUTES_LIMIT: 10, // Only process first 21 NFTs for attributes on testnet
		TEST_URLS_LIMIT: 10, // Only process first 21 NFTs for URLs on testnet
	},
	local: {
		AUCTION_CONTRACT: "0x5f549af160e14603de6102874ff5ec25d8f89c2d137d4a9bfb75977abdab385b",
		PACKAGE_ID: "0xd0af67c0281e294200260fc18f2760aa9f8ae7e7a6addd472486154dcf12b50a",
		ADMIN_CAP: "0xb30b32bc7a69871eb46647f16997adfed3407f0252052d745f62e62674a04b6a",
		TRANSFER_POLICY_CAP: "0x36f9da986f880c01ee2530c475ce005828fc517792c88d5573d950d4fce0bd58",
		TRANSFER_POLICY_ID: "0x64b8df7d67c5ae69f8c4dfe82401361341a936ed2a2c90be24b5e9f60ae39b8d",
		COLLECTION_ID: "0x567076a52f4952b1f93fafc1f116c1c82c54c945bef2db84830a1ce79c5d867b",
		KIOSK: "0xa20173e280e076af4c8a293c6a03569ea2a64bdad571daae9c9d341317171360",
		KIOSK_CAP: "0xf353f31e1a78d02ea1322cb3e744c4faa52186673ee328bd6cd7ffdd70f0437a",
		RPC_URL: "http://127.0.0.1:9000", // https://fullnode.testnet.sui.io:443
		BATCH_SIZE: 200,
		DELAY_BETWEEN_BATCHES: 2000,
		TOTAL_NFTS: 6021, // Full collection (same as production)
		MINT_START_TIME: 1744088400000, //timestamp ms
		TEST_ATTRIBUTES_LIMIT: 30, // limit amount of attrs processed and sent
		TEST_URLS_LIMIT: 30, // limit amount of urls processed and sent
	},
	production: {
		AUCTION_CONTRACT: "0x161524be15687cca96dec58146568622458905c30479452351f231cac5d64c41",
		PACKAGE_ID: "0x3aeca4699ce5f914b56ee04b8ccd4b2eba1b93cabbab9f1a997735c52ef76253",
		ADMIN_CAP: "0x9e0e0b8c9b68465caaf1e28cfff2c05f7a135503977995670884f57fc8b8ceb6",
		TRANSFER_POLICY_CAP: "0xe83a713d437607737229a4ae32c056b7893417c14dc399c4696f74a238e4a9a7",
		TRANSFER_POLICY_ID: "0xd9fe40ec079a6959940260c29be5a782cb79a7951906a0ac380a3961dbd78914",
		COLLECTION_ID: "0xe896f82d681a0562a3062fff61a72c3ac324be5a4f00fa6db0f9520a4124ce7b",
		KIOSK: "0x6384ef33995306a29c4e979aee39bec4b04d4094aaa1a6062d995f985dd9b343",
		KIOSK_CAP: "0x5410c13fd6156a8baa44091ee6682129ffded0dacbcca7944c339aa444208a7f",
		RPC_URL: "https://fullnode.mainnet.sui.io:443",
		BATCH_SIZE: 200,
		DELAY_BETWEEN_BATCHES: 4000,
		TOTAL_NFTS: 6021, // Full collection
		MINT_START_TIME: 1757192400000, //timestamp ms
		TEST_ATTRIBUTES_LIMIT: 30,
		TEST_URLS_LIMIT: 30,
	},
};

// Configuration
const SKIP_PREMINT = process.argv.includes("--skip-premint");
const SKIP_MINTING = process.argv.includes("--skip-minting");
const IS_TEST = process.argv.includes("--test");

function getConfig() {
	let environment = process.argv[2];

	let cfg = CONFIGS[environment];
	if (cfg === undefined) {
		throw Error("Wrong environment: " + environment);
	}

	return cfg;
}

// Enhanced logging with environment and timestamps
function log(message, type = "INFO") {
	const timestamp = new Date().toISOString();
	const emoji =
		type === "SUCCESS" ? "✅" : type === "ERROR" ? "❌" : type === "WARNING" ? "⚠️" : "ℹ️";
	const environment = process.argv[2];
	const env = environment.toUpperCase();
	console.log(`[${timestamp}] [${env}] ${emoji} ${message}`);
}

function suiprivkeyToHex(suiprivkey) {
	const decoded = bech32.decode(suiprivkey);
	const bytes = bech32.fromWords(decoded.words);
	const privateKeyBytes = bytes.slice(1);
	return fromHex(Buffer.from(privateKeyBytes).toString("hex"));
}

// Initialize client and signer
function getClientAndSigner() {
	const config = getConfig();
	const client = new SuiClient({ url: config.RPC_URL });
	// const signer = Secp256k1Keypair.fromSecretKey(suiprivkeyToHex(ADMIN_PRIVATE_KEY));
	const signer = Ed25519Keypair.fromSecretKey(suiprivkeyToHex(ADMIN_PRIVATE_KEY));
	console.log(">>>>>>>>>>> public key", signer.getPublicKey().toSuiAddress());
	return { client, signer };
}

// Add test mythic eligible (for test environment)
async function addTestMythicEligible() {
	const { client, signer } = getClientAndSigner();

	const testMythicEligible = [
		"0x8a80d50ac4e36b3b6257f8e9a3afb429e717c08db9e2cc7643c0fd414767f7de",
		"0x8e2ccd32e13ba1b9273bffb21ed1a850b18d319df026c39ecc279bc25d3ab8e2",
		"0x7d42d4a91119cd4b5ca4ec637be61add4fdce404b70ebe84bfd7a8ac6dfa3d54",
		"0x4a707ac63cca5b55559fbafffd35b166a8222f538f3a397ff7952ae9e4c0efda",
		"0xe670405731f97182a4e5056b63385ddd6f7929dfa1a64f82c5f0bdd780dc79f4",
		"0x1d62d59890e0e8adeace350653d05027846004887ed17b92abb3fdc803ffefa6",
		"0x38b0b0a95e18fea78a63c69a43fb2e7412733dc4e5d2b5faeaf4ba867f85432a",
		"0xa3585953487cf72b94233df0895ae7f6bb05c873772f6ad956dac9cafb946d5d",
		"0x9728ec13d7321c7ee46669454e6d49857cc29fed09ba13696af7692c55e61a24",
	];

	const txb = new TransactionBlock();
	txb.setGasBudget(1000000000);

	const config = getConfig();
	txb.moveCall({
		target: `${config.PACKAGE_ID}::${MODULE_NAME}::add_mythic_eligible`,
		arguments: [
			txb.object(config.ADMIN_CAP),
			txb.object(config.COLLECTION_ID),
			txb.pure(testMythicEligible),
		],
	});

	try {
		const result = await client.signAndExecuteTransactionBlock({
			signer,
			transactionBlock: txb,
			options: { showEffects: true },
		});
		log(
			`Successfully added ${testMythicEligible.length} test mythic eligible addresses`,
			"SUCCESS",
		);
		log(`Transaction digest: ${result.digest}`, "INFO");
		return result;
	} catch (error) {
		log(`Error adding test mythic eligible: ${error.message}`, "ERROR");
		throw error;
	}
}

// Add production mythic eligible from file
async function addProductionMythicEligible() {
	const { client, signer } = getClientAndSigner();

	try {
		log("Reading mythic eligible from mythic_eligible.txt...", "INFO");
		const fileContent = await fs.readFile("mythic_eligible.txt", "utf8");
		const mythicEligible = fileContent
			.split("\n")
			.map((line) => line.trim())
			.filter((line) => line.length > 0)
			.map((addr) => (addr.startsWith("0x") ? addr : "0x" + addr));

		if (mythicEligible.length === 0) {
			throw new Error("No mythic eligible addresses found in mythic_eligible.txt");
		}

		log(`Found ${mythicEligible.length} mythic eligible addresses to add`, "INFO");

		const MYTHIC_ELIGIBLE_BATCH_SIZE = 500;
		let totalProcessed = 0;

		for (let i = 0; i < mythicEligible.length; i += MYTHIC_ELIGIBLE_BATCH_SIZE) {
			const batchEnd = Math.min(i + MYTHIC_ELIGIBLE_BATCH_SIZE, mythicEligible.length);
			const batchMythicEligible = mythicEligible.slice(i, batchEnd);

			log(
				`Processing mythic eligible batch ${i + 1}-${batchEnd} (${batchMythicEligible.length} addresses)`,
				"INFO",
			);

			const txb = new TransactionBlock();
			txb.setGasBudget(5000000000);

			const config = getConfig();
			txb.moveCall({
				target: `${config.PACKAGE_ID}::${MODULE_NAME}::add_mythic_eligible`,
				arguments: [
					txb.object(config.ADMIN_CAP),
					txb.object(config.COLLECTION_ID),
					txb.pure(batchMythicEligible),
				],
			});

			try {
				const result = await client.signAndExecuteTransactionBlock({
					signer,
					transactionBlock: txb,
					options: { showEffects: true },
				});

				totalProcessed += batchMythicEligible.length;
				log(
					`Added ${batchMythicEligible.length} mythic eligible addresses in current batch`,
					"SUCCESS",
				);
				log(
					`Progress: ${totalProcessed}/${mythicEligible.length} addresses processed`,
					"INFO",
				);
				log(`Transaction digest: ${result.digest}`, "INFO");

				// Add delay between batches to avoid rate limiting
				if (batchEnd < mythicEligible.length) {
					await new Promise((resolve) =>
						setTimeout(resolve, config.DELAY_BETWEEN_BATCHES),
					);
				}
			} catch (error) {
				log(
					`Error processing mythic eligible batch ${i + 1}-${batchEnd}: ${error.message}`,
					"ERROR",
				);
				throw error;
			}
		}

		log(
			`Successfully added all ${totalProcessed} mythic eligible addresses in batches`,
			"SUCCESS",
		);
		return { totalProcessed };
	} catch (error) {
		log(`Error adding mythic eligible: ${error.message}`, "ERROR");
		throw error;
	}
}

// Set badge names from JSON file
async function setBadgeNamesFromJson() {
	const { client, signer } = getClientAndSigner();

	try {
		log("Reading badge names from badge_names.json...", "INFO");
		const badgeNamesData = JSON.parse(await fs.readFile("badge_names.json", "utf8"));
		const badgeNames = badgeNamesData.badge_names;

		if (!badgeNames) {
			throw new Error("No badge_names found in badge_names.json");
		}

		log(`Found ${Object.keys(badgeNames).length} badge name entries`, "INFO");

		const config = getConfig();
		const badgeIds = Object.keys(badgeNames).map((id) => parseInt(id));
		const badgeNameStrings = Object.values(badgeNames);

		log(`Setting ${badgeIds.length} badge names...`, "INFO");

		const txb = new TransactionBlock();
		txb.setGasBudget(1000000000);

		txb.moveCall({
			target: `${config.PACKAGE_ID}::${MODULE_NAME}::set_bulk_badge_names`,
			arguments: [
				txb.object(config.ADMIN_CAP),
				txb.object(config.COLLECTION_ID),
				txb.pure(badgeIds),
				txb.pure(badgeNameStrings),
			],
		});

		try {
			const result = await client.signAndExecuteTransactionBlock({
				signer,
				transactionBlock: txb,
				options: { showEffects: true },
			});
			log(`Successfully set ${badgeIds.length} badge names`, "SUCCESS");
			log(`Transaction digest: ${result.digest}`, "INFO");
		} catch (error) {
			log(`Error setting badge names: ${error.message}`, "ERROR");
			throw error;
		}
	} catch (error) {
		log(`Error reading or processing badge_names.json: ${error.message}`, "ERROR");
		throw error;
	}
}

// Set minter badges from JSON file
async function setMinterBadgesFromJson() {
	const { client, signer } = getClientAndSigner();

	try {
		const filename = IS_TEST ? "badges.json" : "badges-all.json";

		log("Reading minter badges from ${filename}...", "INFO");
		const badgeData = JSON.parse(await fs.readFile(filename, "utf8"));

		if (!badgeData || Object.keys(badgeData).length === 0) {
			log("No badge data found in badges.json, skipping minter badge assignment", "WARNING");
			return;
		}

		log(`Found ${Object.keys(badgeData).length} address entries with badge data`, "INFO");

		const config = getConfig();
		const addresses = Object.keys(badgeData);
		const badgeNumbers = Object.values(badgeData);

		// Filter out empty badge arrays
		const validEntries = addresses.filter((_, index) => badgeNumbers[index].length > 0);
		const validBadgeNumbers = badgeNumbers.filter((badges) => badges.length > 0);

		if (validEntries.length != validBadgeNumbers.length) {
			throw new Error("Wrong badges");
		}

		if (validEntries.length === 0) {
			log("No valid badge assignments found, skipping", "WARNING");
			return;
		}

		log(`Setting badges for ${validEntries.length} addresses...`, "INFO");

		const BATCH_SIZE = 500;
		let totalProcessed = 0;

		for (let i = 0; i < validEntries.length; i += BATCH_SIZE) {
			const batchEnd = Math.min(i + BATCH_SIZE, validEntries.length);
			totalProcessed += batchEnd - i;

			log(`Setting badges batch ${i + 1}-${batchEnd}`, "INFO");

			const txb = new TransactionBlock();
			txb.setGasBudget(1000000000);

			txb.moveCall({
				target: `${config.PACKAGE_ID}::${MODULE_NAME}::set_bulk_preset_badges`,
				arguments: [
					txb.object(config.ADMIN_CAP),
					txb.object(config.COLLECTION_ID),
					txb.pure(validEntries.slice(i, batchEnd)),
					txb.pure(validBadgeNumbers.slice(i, batchEnd)),
				],
			});

			try {
				const result = await client.signAndExecuteTransactionBlock({
					signer,
					transactionBlock: txb,
					options: { showEffects: true },
				});
				log(
					`Set badges batch tx diges: ${result.digest} .... Progress: ${totalProcessed}/${validEntries.length}`,
					"INFO",
				);
				await new Promise((resolve) => setTimeout(resolve, config.DELAY_BETWEEN_BATCHES));
			} catch (error) {
				log(`Error setting minter badges: ${error.message}`, "ERROR");
				throw error;
			}
		}
		log(`Successfully added all ${totalProcessed} badges`, "SUCCESS");
	} catch (error) {
		log(`Error reading or processing badges.json: ${error.message}`, "ERROR");
		throw error;
	}
}

// Set attributes from JSON files
async function setAttributesFromJson() {
	const config = getConfig();
	const { client, signer } = getClientAndSigner();

	try {
		log("Processing NFT attributes from JSON files...", "INFO");
		const processedNfts = new Set();

		const maxNfts =
			IS_TEST && config.TEST_ATTRIBUTES_LIMIT
				? config.TEST_ATTRIBUTES_LIMIT
				: config.TOTAL_NFTS;

		log(
			`Processing attributes for first ${maxNfts} NFTs (${IS_TEST ? "test limit" : "full collection"})`,
			"INFO",
		);

		for (let i = 1; i <= maxNfts; i += config.BATCH_SIZE) {
			const batchEnd = Math.min(i + config.BATCH_SIZE - 1, maxNfts);
			const batchNftIds = [];
			const batchKeys = [];
			const batchValues = [];

			for (let j = i; j <= batchEnd; j++) {
				if (processedNfts.has(j)) continue;

				try {
					const jsonData = JSON.parse(await fs.readFile(`JSON/${j}.json`, "utf8"));

					if (jsonData.attributes && Array.isArray(jsonData.attributes)) {
						const nftKeys = [];
						const nftValues = [];

						jsonData.attributes.forEach((attr) => {
							nftKeys.push(attr.trait_type);
							nftValues.push(attr.value);
						});

						batchNftIds.push(j);
						batchKeys.push(nftKeys);
						batchValues.push(nftValues);
						processedNfts.add(j);
					}
				} catch (error) {
					log(`Error reading attributes for NFT #${j}: ${error.message}`, "WARNING");
					continue;
				}
			}

			if (batchNftIds.length > 0) {
				log(
					`Processing attributes batch from NFT #${i} to #${batchEnd} (${batchNftIds.length} NFTs)`,
					"INFO",
				);

				const txb = new TransactionBlock();
				txb.setGasBudget(1000000000);

				txb.moveCall({
					target: `${config.PACKAGE_ID}::${MODULE_NAME}::set_bulk_nft_attributes`,
					arguments: [
						txb.object(config.ADMIN_CAP),
						txb.object(config.COLLECTION_ID),
						txb.pure(batchNftIds),
						txb.pure(batchKeys),
						txb.pure(batchValues),
					],
				});

				try {
					const result = await client.signAndExecuteTransactionBlock({
						signer,
						transactionBlock: txb,
						options: { showEffects: true },
					});
					log(`Batch: processed attributes for ${batchNftIds.length} NFTs`, "SUCCESS");

					if (i + config.BATCH_SIZE <= config.TOTAL_NFTS) {
						// log(
						// 	`Waiting ${config.DELAY_BETWEEN_BATCHES / 1000} seconds before next batch...`,
						// 	"INFO",
						// );
						await new Promise((resolve) =>
							setTimeout(resolve, config.DELAY_BETWEEN_BATCHES),
						);
					}
				} catch (error) {
					log(
						`Error processing attributes batch ${i}-${batchEnd}: ${error.message}`,
						"ERROR",
					);
					throw error;
				}
			}
		}

		log(
			`Completed processing attributes. Total NFTs processed: ${processedNfts.size}`,
			"SUCCESS",
		);
	} catch (error) {
		log(`Error processing NFT attributes: ${error.message}`, "ERROR");
		throw error;
	}
}

// Set URLs from JSON file
async function setUrlsFromJson() {
	const config = getConfig();
	const { client, signer } = getClientAndSigner();

	try {
		log("Reading URLs from imagelinks.json...", "INFO");
		const imageLinksData = JSON.parse(await fs.readFile("imagelinks.json", "utf8"));
		const processedUrls = new Set();

		log(`Found ${Object.keys(imageLinksData).length} URL entries in imagelinks.json`, "INFO");

		const maxNfts =
			IS_TEST && config.TEST_URLS_LIMIT ? config.TEST_URLS_LIMIT : config.TOTAL_NFTS;

		log(
			`Processing URLs for first ${maxNfts} NFTs (${IS_TEST ? "test limit" : "full collection"})`,
			"INFO",
		);

		for (let i = 1; i <= maxNfts; i += config.BATCH_SIZE) {
			const batchEnd = Math.min(i + config.BATCH_SIZE - 1, maxNfts);
			const nftIds = [];
			const urls = [];

			for (let j = i; j <= batchEnd; j++) {
				if (imageLinksData[j.toString()] && !processedUrls.has(j)) {
					nftIds.push(j);
					urls.push(imageLinksData[j.toString()]);
					processedUrls.add(j);
				}
			}

			if (nftIds.length > 0) {
				log(
					`Processing URLs batch from NFT #${i} to #${batchEnd} (${nftIds.length} NFTs)`,
					"INFO",
				);

				const txb = new TransactionBlock();
				txb.setGasBudget(1000000000);

				txb.moveCall({
					target: `${config.PACKAGE_ID}::${MODULE_NAME}::set_bulk_nft_images`,
					arguments: [
						txb.object(config.ADMIN_CAP),
						txb.object(config.COLLECTION_ID),
						txb.pure(nftIds),
						txb.pure(urls.map((url) => Array.from(Buffer.from(url)))),
					],
				});

				try {
					const result = await client.signAndExecuteTransactionBlock({
						signer,
						transactionBlock: txb,
						options: { showEffects: true },
					});
					log(`Batch: processed ${nftIds.length} URLs`, "SUCCESS");

					if (i + config.BATCH_SIZE <= config.TOTAL_NFTS) {
						// log(
						// 	`Waiting ${config.DELAY_BETWEEN_BATCHES / 1000} seconds before next batch...`,
						// 	"INFO",
						// );
						await new Promise((resolve) =>
							setTimeout(resolve, config.DELAY_BETWEEN_BATCHES),
						);
					}
				} catch (error) {
					log(`Error processing batch ${i}-${batchEnd}: ${error.message}`, "ERROR");
					throw error;
				}
			}
		}

		log(`Completed processing URLs. Total NFTs processed: ${processedUrls.size}`, "SUCCESS");
	} catch (error) {
		log(`Error reading or processing imagelinks.json: ${error.message}`, "ERROR");
		throw error;
	}
}

// Add royalty and lock rules
async function addRoyaltyAndLockRules() {
	const config = getConfig();
	const { client, signer } = getClientAndSigner();
	const environment = process.argv[2];
	let network =
		environment === "production"
			? Network.MAINNET
			: environment === "testnet"
				? Network.TESTNET
				: Network.CUSTOM;

	let packageIds = undefined;
	if (network === Network.CUSTOM) {
		packageIds = {
			royaltyRulePackageId: LOCAL_KIOSK_PKG,
			kioskLockRulePackageId: LOCAL_KIOSK_PKG,
		};
	}

	const kioskClient = new KioskClient({ client, network, packageIds });

	log("Adding royalty and lock rules...", "INFO");

	// NOTE: we don't need to query Policy ID - it's created and shared on mint init
	// const policyType = `${config.PACKAGE_ID}::${MODULE_NAME}::BeelieverNFT`;
	// const policyCaps = await kioskClient.getOwnedTransferPoliciesByType({
	// 	type: policyType,
	// 	address: signer.getPublicKey().toSuiAddress(),
	// });
	// console.log("policy caps", policyCaps);
	// if (!policyCaps || policyCaps.length === 0) {
	// 	throw new Error("No transfer policy caps found for this type");
	// }
	// const cap = policyCaps[0];
	// console.log(" >>>>> POLICY: ", cap);

	const cap = {
		policyId: config.TRANSFER_POLICY_ID,
		policyCapId: config.TRANSFER_POLICY_CAP,
		type: config.PACKAGE_ID + "::mint::BeelieverNFT",
	};

	const transaction = new TransactionBlock();
	transaction.setGasBudget(100000000);

	const tpTx = new TransferPolicyTransaction({ kioskClient, transaction, cap });
	tpTx.addRoyaltyRule(500, 0) // 5% royalty
		.addLockRule();

	try {
		const result = await client.signAndExecuteTransactionBlock({
			signer,
			transactionBlock: transaction,
			options: { showEffects: true },
		});
		log("Successfully added royalty and lock rules", "SUCCESS");
		log(`Transaction digest: ${result.digest}`, "INFO");
		return result;
	} catch (error) {
		log(`Error adding rules: ${error}`, "ERROR");
		throw error;
	}
}

// Execute premint
async function executePremint() {
	if (SKIP_PREMINT) {
		log("Skipping premint as requested", "INFO");
		return;
	}

	const config = getConfig();
	const { client, signer } = getClientAndSigner();
	const kioskId = config.KIOSK;
	const kioskCapId = config.KIOSK_CAP;
	if (!kioskId || !kioskCapId) {
		throw new Error("Failed to retrieve kiosk or kiosk cap ID");
	}

	try {
		log(`Starting premint process...`, "INFO");

		const tx2 = new TransactionBlock();
		tx2.setGasBudget(5000000000); // 5 sui budget
		tx2.moveCall({
			target: `${config.PACKAGE_ID}::${MODULE_NAME}::premint_to_native`,
			arguments: [
				tx2.object(config.ADMIN_CAP),
				tx2.object(config.COLLECTION_ID),
				tx2.object(config.TRANSFER_POLICY_ID),
				tx2.object(kioskId),
				tx2.object(kioskCapId),
				tx2.object(RANDOM_OBJ),
			],
		});

		const result2 = await client.signAndExecuteTransactionBlock({
			signer,
			transactionBlock: tx2,
			options: { showEffects: true },
		});

		if (result2.errors) {
			console.log("Premint ERROR:", result2.errors);
			return false;
		}
		// console.log("premint effects:", result2.effects);
		log(`Premint completed successfully, tx: ${result2.digest}`, "SUCCESS");
		return true;
	} catch (error) {
		log(`Error in premint process: ${error.message}`, "ERROR");
		throw error;
	}
}

async function enableMinting() {
	if (SKIP_MINTING) {
		log("Skipping minting as requested", "INFO");
		return;
	}

	const config = getConfig();
	const { client, signer } = getClientAndSigner();

	// Use start time from config (convert from milliseconds to seconds)
	const startTime = Math.floor(config.MINT_START_TIME);

	log(`Minting will start at ${new Date(startTime).toISOString()} (${startTime})`, "INFO");

	const txb = new TransactionBlock();
	txb.setGasBudget(100000000);

	txb.moveCall({
		target: `${config.PACKAGE_ID}::${MODULE_NAME}::start_minting`,
		arguments: [
			txb.object(config.ADMIN_CAP),
			txb.object(config.COLLECTION_ID),
			txb.pure(startTime),
		],
	});

	try {
		const result = await client.signAndExecuteTransactionBlock({
			signer,
			transactionBlock: txb,
			options: { showEffects: true },
		});
		log("Successfully started minting", "SUCCESS");
		log(`Transaction digest: ${result.digest}`, "INFO");
		return result;
	} catch (error) {
		log(`Error starting minting: ${error.message}`, "ERROR");
		throw error;
	}
}

// Perform actual test mint
async function testMinting() {
	const config = getConfig();
	const { client, signer } = getClientAndSigner();

	log("Performing test mint...", "INFO");
	await checkCollectionStats();

	try {
		// Step 1: Create kiosk
		log("Creating kiosk for test mint...", "INFO");
		const [kioskId, kioskCapId] = createKiosk();

		// Step 2: Perform the actual mint
		log("Attempting to mint NFT...", "INFO");
		const tx2 = new TransactionBlock();
		tx2.setGasBudget(1000000000); // 1 SUI budget
		tx2.moveCall({
			target: `${config.PACKAGE_ID}::${MODULE_NAME}::mint`,
			arguments: [
				tx2.object(config.COLLECTION_ID),
				tx2.object(config.TRANSFER_POLICY_ID),

				tx2.object(config.AUCTION_CONTRACT), // auction contract
				tx2.object(kioskId),
				tx2.object(kioskCapId),
				tx2.object(CLOCK_OBJ), // clock
				tx2.object(RANDOM_OBJ),
			],
		});

		const result2 = await client.signAndExecuteTransactionBlock({
			signer,
			transactionBlock: tx2,
			options: { showEffects: true },
		});

		log("🎉 Test mint successful!", "SUCCESS");
		log(`Mint transaction digest: ${result2.digest}`, "INFO");

		// Check what was minted
		if (result2.effects && result2.effects.created) {
			result2.effects.created.forEach((obj) => {
				if (obj.owner.AddressOwner === signer.getPublicKey().toSuiAddress()) {
					log(`Minted object: ${obj.reference.objectId}`, "INFO");
				}
			});
		}

		// Wait and check updated stats
		await new Promise((resolve) => setTimeout(resolve, 1000));
		await checkCollectionStats();

		return result2;
	} catch (error) {
		log(`Error performing test mint: ${error.message}`, "ERROR");
		throw error;
	}
}

// Check collection stats
async function checkCollectionStats() {
	const config = getConfig();
	const { client } = getClientAndSigner();

	try {
		log("Checking collection stats...", "INFO");

		const txb = new TransactionBlock();
		txb.setGasBudget(1000000000);

		txb.moveCall({
			target: `${config.PACKAGE_ID}::${MODULE_NAME}::get_collection_stats`,
			arguments: [txb.object(config.COLLECTION_ID)],
		});

		const result = await client.dryRunTransactionBlock({
			transactionBlock: txb,
		});

		console.log(result);

		if (result.results && result.results.length > 0) {
			const returnValues = result.results[0].returnValues;
			if (returnValues && returnValues.length >= 5) {
				const totalMinted = parseInt(returnValues[0]);
				const mythicMinted = parseInt(returnValues[1]);
				const normalMinted = parseInt(returnValues[2]);
				const availableMythics = parseInt(returnValues[3]);
				const availableNormals = parseInt(returnValues[4]);

				log(`📊 Collection Stats:`, "INFO");
				log(`   Total Minted: ${totalMinted}`, "INFO");
				log(`   Mythics Minted: ${mythicMinted}`, "INFO");
				log(`   Normals Minted: ${normalMinted}`, "INFO");
				log(`   Available Mythics: ${availableMythics}`, "INFO");
				log(`   Available Normals: ${availableNormals}`, "INFO");
			}
		}
	} catch (error) {
		log(`Error checking collection stats: ${error.message}`, "WARNING");
	}
}

async function createKiosk() {
	const config = getConfig();
	const { client, signer } = getClientAndSigner();
	const kioskClient = new KioskClient({ url: config.RPC_URL });

	const tx1 = new TransactionBlock();
	tx1.setGasBudget(5000000);
	const kioskTx = new KioskTransaction({ transaction: tx1, kioskClient });

	kioskTx.create();
	kioskTx.shareAndTransferCap(signer.getPublicKey().toSuiAddress());
	kioskTx.finalize();

	const result = await client.signAndExecuteTransactionBlock({
		signer,
		transactionBlock: tx1,
		options: { showEffects: true },
	});
	if (result.errors) {
		console.log("Kiosk creation failed, tx id:", result.digest, "\nError:", result.errors);
		return;
	}

	await new Promise((resolve) => setTimeout(resolve, 1000));
	const txEffects = await client.getTransactionBlock({
		digest: result.digest,
		options: { showEffects: true, showInput: true },
	});
	if (txEffects.errors) {
		console.log("Kiosk creation failed, tx id:", result.digest, "\nError:", txEffects.errors);
		return;
	}

	console.log("Kiosk creation successful, tx id:", result.digest, "\nEffects.created:");
	console.dir(txEffects.effects.created, { depth: 3 });
	let kioskId, kioskCapId;
	txEffects.effects.created.forEach((obj) => {
		if (obj.owner.Shared) {
			kioskId = obj.reference.objectId;
		} else if (obj.owner.AddressOwner === signer.getPublicKey().toSuiAddress()) {
			kioskCapId = obj.reference.objectId;
		}
	});
	console.log("KioskID:", kioskId, "  KioskCap:", kioskCapId);

	return [kioskId, kioskCapId];
}

// Run complete setup
async function runCompleteSetup() {
	const config = getConfig();

	if (SKIP_PREMINT) log("⚠️ Premint will be skipped", "WARNING");
	if (SKIP_MINTING) log("⚠️ Minting will be skipped", "WARNING");

	try {
		/*
		 */
		log("\n[1] Adding mythic eligible...", "INFO");
		if (IS_TEST) {
			await addTestMythicEligible();
		} else {
			await addProductionMythicEligible();
		}
		await new Promise((resolve) => setTimeout(resolve, 2000));

		log("\n[2.1] Setting badge names...", "INFO");
		await setBadgeNamesFromJson();
		await new Promise((resolve) => setTimeout(resolve, 2000));

		log("\n[2.2] Setting minter badges...", "INFO");
		await setMinterBadgesFromJson();
		await new Promise((resolve) => setTimeout(resolve, 2000));

		log("\n[3] Setting NFT attributes...", "INFO");
		await setAttributesFromJson();
		await new Promise((resolve) => setTimeout(resolve, 2000));

		log("\n[4] Setting NFT URLs...", "INFO");
		await setUrlsFromJson();
		await new Promise((resolve) => setTimeout(resolve, 2000));

		log("\n[6] Adding royalty and lock rules...", "INFO");
		await addRoyaltyAndLockRules();
		await new Promise((resolve) => setTimeout(resolve, 2000));

		// if (IS_TEST) {
		// 	log("\n[7] Skipping premint on testnet, setting premint_completed to true...", "INFO");
		// 	// await setPremintCompleted(true);
		// } else {
		log("\n[7] Executing premint...", "INFO");
		await executePremint();
		//}
		await new Promise((resolve) => setTimeout(resolve, 2000));

		log("\n[8] Enable minting...", "INFO");
		await enableMinting();
	} catch (error) {
		log(`\n❌ Setup failed: ${error.message}`, "ERROR");
		throw error;
	}
}

// Main function
async function main() {
	const env = process.argv[2];
	let operation = undefined;
	for (const a of process.argv.slice(3)) {
		if (!a.startsWith("--")) {
			operation = a;
			break;
		}
	}

	if (
		env === undefined ||
		(operation !== undefined && operation != "kiosk-create" && operation !== "test-minting")
	) {
		console.log(
			`
🏭 Beelievers Setup Script

Usage:
  Test Setup:        node setup_script.js <env> <operation>

env: testnet, localnet, production

Options:
  --skip-premint     Skip the premint process
  --skip-minting     Skip starting the minting process
  --test             Run reduced test setup (mythic eligible, badges, attributes, URLs, premint, minting)

Commands:
  test-minting      - Test minting functionality
  kiosk-create

Required Files:
  - badges.json: Token ID to badge mapping
  - imagelinks.json: Token ID to Walrus URL mapping
  - JSON/: Directory with individual NFT JSON files
  - mythic_eligible.txt: Mythic eligible addresses (for production only)

Test Environment:
  - Uses testnet RPC
  - Processes first 21 NFTs for attributes and URLs only
  - Uses 2 test mythic eligible addresses
  - Same batch sizes and delays as production
`,
		);
		return;
	}

	try {
		if (operation === "test-minting") {
			log("🧪 Testing minting functionality...", "INFO");
			await testMinting();
		} else if (operation == "kiosk-create") {
			await createKiosk();
		} else {
			await runCompleteSetup();
		}
	} catch (error) {
		log(`Script execution failed: ${error.message}`, "ERROR");
		process.exit(1);
	}
}

main();
