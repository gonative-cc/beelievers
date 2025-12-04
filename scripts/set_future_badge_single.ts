#!/usr/bin/env bun
import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import { CONFIGS, ADMIN_PRIVATE_KEY, suiprivkeyToHex } from "../mint/setup_script.js";

interface Arguments {
	tokenId?: number;
	badgeIds: number[];
	badgeNames?: string[];
	env: string;
}

function parseArguments(): Arguments {
	const args = process.argv.slice(2);

	let tokenId: number | undefined;
	let badgeIds: number[] = [];
	let badgeNames: string[] = [];
	let env: string | undefined;

	for (let i = 0; i < args.length; i++) {
		const nextArg = args[i + 1];
		if (args[i] === "--token-id" && nextArg) {
			tokenId = parseInt(nextArg, 10);
			i++;
		} else if (args[i] === "--badge-ids" && nextArg) {
			badgeIds = nextArg.split(",").map((id) => parseInt(id.trim(), 10));
			i++;
		} else if (args[i] === "--badge-names" && nextArg) {
			badgeNames = nextArg.split(",").map((name) => name.trim());
			i++;
		} else if (args[i] === "--env" && nextArg) {
			env = nextArg;
			i++;
		}
	}

	if (badgeIds.length === 0 || !env) {
		console.error(
			'Usage: bun set_future_badge_single.ts --token-id 1 --badge-ids 1,2 --badge-names "Early,OG" --env testnet',
		);
		process.exit(1);
	}

	return { tokenId, badgeIds, badgeNames, env };
}

async function setFutureBadges(
	args: Arguments,
	config: any,
	client: SuiClient,
	keypair: Ed25519Keypair,
) {
	const tx = new Transaction();
	tx.moveCall({
		target: `${config.PACKAGE_ID}::mint::set_future_badges`,
		arguments: [
			tx.object(config.ADMIN_CAP),
			tx.object(config.COLLECTION_ID),
			tx.pure.u16(args.tokenId!),
			tx.pure.vector("u16", args.badgeIds),
		],
	});

	const result = await client.signAndExecuteTransaction({
		transaction: tx,
		signer: keypair,
		options: { showEffects: true },
	});

	if (result.effects?.status.status === "success") {
		console.log(result.digest);
	} else {
		console.error("Failed:", result.effects?.status.error);
		process.exit(1);
	}
}

async function setBadgeNames(
	args: Arguments,
	config: any,
	client: SuiClient,
	keypair: Ed25519Keypair,
) {
	console.log("Setting badge names:");
	args.badgeIds.forEach((id, i) => {
		console.log(`  Badge ID ${id}: "${args.badgeNames![i]}"`);
	});

	const tx = new Transaction();
	tx.moveCall({
		target: `${config.PACKAGE_ID}::mint::set_bulk_badge_names`,
		arguments: [
			tx.object(config.ADMIN_CAP),
			tx.object(config.COLLECTION_ID),
			tx.pure.vector("u16", args.badgeIds),
			tx.pure.vector("string", args.badgeNames!),
		],
	});

	const result = await client.signAndExecuteTransaction({
		transaction: tx,
		signer: keypair,
		options: { showEffects: true },
	});

	if (result.effects?.status.status === "success") {
		console.log("\nSuccess!");
		console.log(`Transaction digest: ${result.digest}`);
	} else {
		console.error("Failed:", result.effects?.status.error);
		process.exit(1);
	}
}

async function main() {
	const args = parseArguments();
	const config = CONFIGS[args.env as keyof typeof CONFIGS];

	if (!config) {
		console.error(`Invalid environment: ${args.env}`);
		process.exit(1);
	}

	const client = new SuiClient({ url: config.RPC_URL });
	const keypair = Ed25519Keypair.fromSecretKey(suiprivkeyToHex(ADMIN_PRIVATE_KEY));

	if (args.badgeNames && args.badgeNames.length > 0) {
		await setBadgeNames(args, config, client, keypair);
	}

	if (args.tokenId !== undefined) {
		await setFutureBadges(args, config, client, keypair);
	}

	if (args.tokenId === undefined && (!args.badgeNames || args.badgeNames.length === 0)) {
		console.error(
			"Must provide either --token-id (for future badges) or --badge-names (for setting names)",
		);
		process.exit(1);
	}
}

main();
