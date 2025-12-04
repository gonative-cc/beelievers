#!/usr/bin/env bun
import { SuiClient } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import { Command } from "commander";
import { CONFIGS, ADMIN_PRIVATE_KEY, suiprivkeyToHex } from "../mint/mint.config.js";

interface Arguments {
	tokenId?: number;
	badgeIds: number[];
	badgeNames?: string[];
	env: string;
}

function parseArguments(): Arguments {
	const program = new Command();
	program
		.option("--token-id <number>", "Token ID to set badges for", (val) => parseInt(val, 10))
		.requiredOption("--badge-ids <numbers>", "Badge IDs to assign (comma-separated)")
		.option(
			"--badge-names <names>",
			"Badge names (comma-separated, must match badge-ids count)",
		)
		.option("--env <environment>", "Environment (testnet, local, production)", "production");

	program.parse(process.argv);
	const opts = program.opts();

	const tokenId: number | undefined = opts.tokenId;
	const badgeIds: number[] = opts.badgeIds
		.split(",")
		.map((id: string) => parseInt(id.trim(), 10));
	const badgeNames: string[] | undefined = opts.badgeNames
		? opts.badgeNames.split(",").map((name: string) => name.trim())
		: undefined;
	const env: string = opts.env;

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
