#!/usr/bin/env bun

import { promises as fs } from "fs";
import { writeToFile } from "../fileio.ts";

interface WinnerData {
	attributes?: {
		position: "top_21";
	};
	badges: number[];
}

interface WinnersJson {
	[address: string]: WinnerData;
}

async function readProcessedBadges(filePath: string): Promise<Map<string, number[]>> {
	const fileContent = await fs.readFile(filePath, "utf-8");
	const lines = fileContent.trim().split("\n");
	const addressBadgeMap = new Map<string, number[]>();

	for (let i = 1; i < lines.length; i++) {
		const line = lines[i];
		if (!line?.trim()) continue;

		try {
			const firstCommaIndex = line.indexOf(",");
			if (firstCommaIndex === -1) continue;

			const address = line.substring(0, firstCommaIndex).trim().toLowerCase();
			const badgesJsonStr = line.substring(firstCommaIndex + 1).trim();

			const badges = JSON.parse(badgesJsonStr) as number[];
			addressBadgeMap.set(address, badges);
		} catch (error) {
			console.error(`Error parsing line ${i + 1}: ${line}`, error);
		}
	}

	return addressBadgeMap;
}

function generateWinnersJson(addressBadgeMap: Map<string, number[]>): WinnersJson {
	const winnersJson: WinnersJson = {};

	for (const [address, badges] of addressBadgeMap) {
		const winnerData: WinnerData = {
			badges: badges,
		};

		// Add attributes field only if the address has top_21 badge (4)
		if (badges.includes(4)) {
			winnerData.attributes = {
				position: "top_21",
			};
		}

		winnersJson[address] = winnerData;
	}

	return winnersJson;
}

async function main() {
	const inputFile = "scripts/auction_reconcillation/processed-badges.csv";
	const outputFile = "scripts/auction_reconcillation/winners.json";

	console.log("Reading processed badge data...");
	const addressBadgeMap = await readProcessedBadges(inputFile);
	console.log(`Loaded ${addressBadgeMap.size} winning bidders`);

	console.log("Generating winners JSON...");
	const winnersJson = generateWinnersJson(addressBadgeMap);

	// Count how many have top_21 badge (4)
	const top21Count = Object.values(winnersJson).filter(
		(winner) => winner.attributes?.position === "top_21",
	).length;
	console.log(`${top21Count} bidders have top_21 attributes`);

	console.log("Writing JSON file...");
	const jsonContent = JSON.stringify(winnersJson, null, 2);
	await writeToFile(outputFile, jsonContent);

	console.log("Winners JSON generation complete!");
	console.log(`Output saved to: ${outputFile}`);
	console.log(`Total winners: ${Object.keys(winnersJson).length}`);
	console.log(`Top 21 winners with attributes: ${top21Count}`);
}

if (import.meta.main) {
	main().catch(console.error);
}
