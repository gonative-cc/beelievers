#!/usr/bin/env bun

import { SuiClient, getFullnodeUrl } from "@mysten/sui/client";
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";
import { Transaction } from "@mysten/sui/transactions";
import * as dotenv from "dotenv";

dotenv.config();

interface Arguments {
	tokenId: number;
	badgeIds: number[];
}

function parseArguments(): Arguments {
	const args = process.argv.slice(2);

	let tokenId: number | undefined;
	let badgeIds: number[] = [];

	for (let i = 0; i < args.length; i++) {
		const nextArg = args[i + 1];
		if (args[i] === "--token-id" && nextArg) {
			tokenId = parseInt(nextArg, 10);
			i++;
		} else if (args[i] === "--badge-ids" && nextArg) {
			badgeIds = nextArg.split(",").map((id) => parseInt(id.trim(), 10));
			i++;
		}
	}

	if (tokenId === undefined || badgeIds.length === 0) {
		console.error("Missing required arguments");
		process.exit(1);
	}

	return { tokenId, badgeIds };
}

async function setFutureBadgeSingle() {
	const { tokenId, badgeIds } = parseArguments();
	const { MNEMONIC, PACKAGE_ID, COLLECTION_ID, ADMIN_CAP_ID, NETWORK } = process.env;

	if (!MNEMONIC || !PACKAGE_ID || !COLLECTION_ID || !ADMIN_CAP_ID || !NETWORK) {
		process.exit(1);
	}

	const client = new SuiClient({ url: getFullnodeUrl(NETWORK as any) });
	const keypair = Ed25519Keypair.deriveKeypair(MNEMONIC);

	const tx = new Transaction();
	tx.moveCall({
		target: `${PACKAGE_ID}::mint::set_future_badges`,
		arguments: [
			tx.object(ADMIN_CAP_ID),
			tx.object(COLLECTION_ID),
			tx.pure.u16(tokenId),
			tx.pure.vector("u16", badgeIds),
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

setFutureBadgeSingle();
