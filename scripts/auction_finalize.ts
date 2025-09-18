import { SuiClient, getFullnodeUrl } from "@mysten/sui/client";
import { isValidSuiAddress } from "@mysten/sui/utils";
import * as dotenv from "dotenv";
import { promises as fs } from "fs";
import { Command } from "commander";
import { Transaction } from "@mysten/sui/transactions";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { auctionConfMainnet, auctionConfTestnet, type AuctionConf } from "./auction.config.js";

import { chunk } from "./utils";

const MAX_ADDRESSES_PER_VECTOR = 500;

dotenv.config();

async function main() {
	const program = new Command();

	const { MNEMONIC, NETWORK, SK } = process.env;

	const auctionCfg = NETWORK == "mainnet" ? auctionConfMainnet : auctionConfTestnet;

	if (!MNEMONIC && !SK) {
		console.error("❌ Error: Missing required environment variables. Check your .env file.");
		process.exit(1);
	}

	const rpcUrl = getFullnodeUrl(
		auctionCfg.network as "mainnet" | "testnet" | "devnet" | "localnet",
	);

	const client = new SuiClient({ url: rpcUrl });
	let keypair: Ed25519Keypair;
	if (SK) {
		keypair = Ed25519Keypair.fromSecretKey(SK);
	} else {
		keypair = Ed25519Keypair.deriveKeypair(MNEMONIC!);
	}

	program
		.command("set-winners")
		.argument("<file...>", "file with list of winners")
		.action(async (options) => {
			const file = options[0];
			console.log(`📦 Package ID: ${auctionCfg.packageId}`);
			console.log("---");
			try {
				let addresses = await readAddressesFromFile(file);
				addresses = preprocessAddresses(addresses);
				let bAddreses = batchAddresses(addresses, MAX_ADDRESSES_PER_VECTOR);

				await set_winner(client, keypair, auctionCfg, bAddreses);
			} catch (err) {
				console.error("❌ Error: ", err);
				process.exit(1);
			}
		});

	program.command("finalize").action(async () => {
		await finalizeEnd(client, keypair, auctionCfg);
	});

	program.command("raffle").action(async () => {
		await raffle(client, keypair, auctionCfg);
	});

	program.parse(process.argv);
}

export async function readAddressesFromFile(filePath: string): Promise<string[]> {
	const content = await fs.readFile(filePath, "utf8");

	return content
		.trim()
		.split("\n")
		.map((addr) => addr.trim());
}

export function preprocessAddresses(addresses: string[]): string[] {
	addresses.forEach((address) => {
		if (!isValidSuiAddress(address)) {
			throw new Error("invalid sui address in finalize list");
		}
	});

	addresses.sort((x, y) => {
		const xx = BigInt(x);
		const yy = BigInt(y);
		if (xx < yy) return -1;
		return xx > yy ? 1 : 0;
	});
	return addresses;
}

export function batchAddresses(addresses: string[], slot: number): string[][] {
	if (addresses.length == 0) {
		return [];
	}
	return chunk(addresses, slot);
}

async function set_winner(
	client: SuiClient,
	keypair: Ed25519Keypair,
	acfg: AuctionConf,
	winners: string[][],
) {
	let number_txn = winners.length;

	await finalizeStart(client, keypair, acfg, winners[0]!);
	for (let i = 1; i < number_txn; i++) {
		await finalizeNext(client, keypair, acfg, winners[i]!);
	}
}

async function finalizeStart(
	client: SuiClient,
	keypair: Ed25519Keypair,
	acfg: AuctionConf,
	addresses: string[],
) {
	let txn = new Transaction();

	let auction = txn.object(acfg.auctionId);
	let adminCap = txn.object(acfg.adminCapId);
	txn.moveCall({
		target: `${acfg.packageId}::auction::finalize_start`,
		arguments: [adminCap, auction, txn.pure("vector<address>", addresses), txn.object.clock()],
	});

	const result = await client.signAndExecuteTransaction({
		transaction: txn,
		signer: keypair,
		options: {
			showEvents: true,
			showEffects: true,
		},
	});

	await client.waitForTransaction({ digest: result.digest });
	if (result.effects?.status.status === "success") {
		console.log(`   🔗 Digest: ${result.digest}`);
	} else {
		throw new Error(`Transaction failed: ${result.effects?.status.error}`);
	}
}
async function finalizeNext(
	client: SuiClient,
	keypair: Ed25519Keypair,
	acfg: AuctionConf,
	addresses: string[],
) {
	let txn = new Transaction();
	let auction = txn.object(acfg.auctionId);
	let adminCap = txn.object(acfg.adminCapId);

	txn.moveCall({
		target: `${acfg.packageId}::auction::finalize_continue`,
		arguments: [adminCap, auction, txn.pure("vector<address>", addresses), txn.object.clock()],
	});

	const result = await client.signAndExecuteTransaction({
		transaction: txn,
		signer: keypair,
		options: { showEvents: true, showEffects: true },
	});
	await client.waitForTransaction({ digest: result.digest });
	if (result.effects?.status.status === "success") {
		console.log(`   🔗 Digest: ${result.digest}`);
	} else {
		throw new Error(`Transaction failed: ${result.effects?.status.error}`);
	}
}

async function finalizeEnd(client: SuiClient, keypair: Ed25519Keypair, acfg: AuctionConf) {
	let txn = new Transaction();
	let auction = txn.object(acfg.auctionId);
	let adminCap = txn.object(acfg.adminCapId);
	if (acfg.clearingPrice < 1e9) {
		throw new Error("Invalid clearing price");
	}
	if (acfg.discounts < 0) {
		throw new Error("discounts must be postive");
	}

	txn.moveCall({
		target: `${acfg.packageId}::auction::finalize_end`,
		arguments: [
			adminCap,
			auction,
			txn.pure("u64", acfg.clearingPrice),
			txn.pure("u64", acfg.discounts),
		],
	});

	const result = await client.signAndExecuteTransaction({
		transaction: txn,
		signer: keypair,
		options: { showEvents: true, showEffects: true },
	});
	await client.waitForTransaction({ digest: result.digest });
	if (result.effects?.status.status === "success") {
		console.log(`✅ Auction finalize successful!`);
		console.log(`   🔗 Digest: ${result.digest}`);
	} else {
		throw new Error(`Transaction failed: ${result.effects?.status.error}`);
	}
}

async function raffle(client: SuiClient, keypair: Ed25519Keypair, acfg: AuctionConf) {
	let txn = new Transaction();
	let auction = txn.object(acfg.auctionId);
	let adminCap = txn.object(acfg.adminCapId);

	txn.moveCall({
		target: `${acfg.packageId}::auction::run_raffle`,
		arguments: [
			auction,
			adminCap,
			txn.pure("u32", acfg.raffleSize),
			// txn.object(SUI_RANDOMNESS_STATE_OBJECT_ID),
			// txn.object.random(),
			txn.object("0x0000000000000000000000000000000000000000000000000000000000000008"),
		],
	});

	const result = await client.signAndExecuteTransaction({
		transaction: txn,
		signer: keypair,
		options: { showEvents: true, showEffects: true },
	});
	await client.waitForTransaction({ digest: result.digest });
	if (result.effects?.status.status === "success") {
		console.log(`✅ Auction raffle successful!`);
		console.log(`   🔗 Digest: ${result.digest}`);
		console.log(`   🔗 Event: ${result.events?.[0]}`);
	} else {
		throw new Error(`Transaction failed: ${result.effects?.status.error}`);
	}
}

if (import.meta.main) {
	main().catch((error) => {
		console.error("A fatal error occurred in the main function:", error);
	});
}
