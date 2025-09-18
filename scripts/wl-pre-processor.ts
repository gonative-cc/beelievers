import { SuiClient, getFullnodeUrl } from "@mysten/sui/client";
import { isValidSuiAddress } from "@mysten/sui/utils";
import * as dotenv from "dotenv";
import { promises as fs } from "fs";
import { Command } from "commander";

import { writeToFile } from "./fileio.js";

dotenv.config();

async function main() {
	const program = new Command();
	program
		.argument("<files...>", "A list of CSV files to process")
		.option(
			"-o, --output <filename>",
			"The name of the output CSV file",
			"cleaned_whitelist.csv",
		);

	program.parse(process.argv);
	const files = program.args;
	const { output: outputFilename } = program.opts();

	if (files.length === 0) {
		console.error("❌ Error: Please provide at least one file to process.");
		process.exit(1);
	}

	const { NETWORK } = process.env;
	if (!NETWORK) {
		console.error("❌ Error: SUI_RPC_URL is not set in your .env file.");
		process.exit(1);
	}

	const client = new SuiClient({ url: getFullnodeUrl(NETWORK as any) });

	const rawEntries = await readAllFiles(files);

	const cleanedAndUniqueEntries = cleanAndDeduplicate(rawEntries);
	console.log(`\nFound ${cleanedAndUniqueEntries.length} unique entries after cleaning.`);

	const resolvedEntries = await resolveSuiNSNames(client, cleanedAndUniqueEntries);
	console.log(`\nResolved ${resolvedEntries.length} entries to potential addresses.`);

	const finalAddresses = validateAddresses(resolvedEntries);
	console.log(`\nFound ${finalAddresses.length} final valid addresses.`);

	await writeToCsv(finalAddresses, outputFilename);

	console.log("\n🎉 Pre-processing complete!");
}

async function readAllFiles(filePaths: string[]): Promise<string[]> {
	let allEntries: string[] = [];
	for (const filePath of filePaths) {
		try {
			console.log(`📄 Reading file: ${filePath}...`);
			const content = await fs.readFile(filePath, "utf8");
			const entries = content.split(/\r?\n/).filter((line) => line.trim().length > 0);
			allEntries = allEntries.concat(entries);
		} catch (error) {
			console.warn(`   ⚠️ Could not read file ${filePath}. Skipping.`);
		}
	}
	return allEntries;
}

function cleanAndDeduplicate(rawEntries: string[]): string[] {
	console.log("\n✨ Cleaning and deduplicating entries...");
	const cleanedEntries = new Set<string>();

	for (const rawEntry of rawEntries) {
		// Expand lines that might contain multiple space-separated addresses
		const parts = rawEntry.split(/\s+/).filter((p) => p.length > 0);

		for (let part of parts) {
			if (part.includes(".sui")) {
				const match = part.match(/([a-zA-Z0-9-]+\.sui)/);
				if (match && match[0]) {
					part = match[0].toLowerCase();
				} else {
					part = "";
				}
			} else {
				part = part.replace(/[^a-fA-F0-9x]/g, "");
				if (part.toLowerCase().startsWith("ox")) {
					part = "0x" + part.substring(2);
				}
			}

			if (part) {
				cleanedEntries.add(part);
			}
		}
	}

	return Array.from(cleanedEntries);
}

async function resolveSuiNSNames(client: SuiClient, entries: string[]): Promise<string[]> {
	console.log("\n🔍 Resolving SuiNS names...");
	const resolvedPromises = entries.map(async (entry) => {
		if (entry.trim().endsWith(".sui")) {
			try {
				const address = await client.resolveNameServiceAddress({ name: entry });
				if (address) {
					console.log(`   ✅ Resolved ${entry} -> ${address}`);
					return address;
				}
				console.warn(`   ⚠️ Could not resolve SuiNS name: ${entry}`);
				return null;
			} catch {
				console.warn(`   ⚠️ Error resolving SuiNS name: ${entry}`);
				return null;
			}
		}
		return entry;
	});

	const results = await Promise.all(resolvedPromises);
	return results.filter((r): r is string => r !== null);
}

function validateAddresses(addresses: string[]): string[] {
	console.log("\n🛡️  Validating final addresses...");
	return addresses.filter((addr) => {
		const isValid = isValidSuiAddress(addr);
		if (!isValid) {
			console.warn(`   ⚠️ Discarding invalid address: ${addr}`);
		}
		return isValid;
	});
}

async function writeToCsv(addresses: string[], filename: string) {
	return writeToFile(filename, addresses.join("\n"));
}

main().catch((error) => {
	console.error("A fatal error occurred:", error);
});
