#!/usr/bin/env bun

import { parse } from "csv-parse";
import { promises as fs } from "fs";
import { writeToFile } from "../fileio.ts";

enum Badge {
	first_place = 1,
	top_3 = 2,
	top_10 = 3,
	top_21 = 4,
	top_100 = 5,
	top_5810 = 6,
	highest_bid = 7,
	bid_over_10 = 8,
	bid_over_5 = 9,
	bid_over_3 = 10,
	made_5_bids = 13,
	made_10_bids = 11,
	made_20_bids = 12,
	partner_wl = 14,
	first_500 = 15,
	first_1000 = 16,
	climb_up_210 = 17,
	climb_up_10 = 18,
	last_bid = 20,
	every_10th_position = 21,
	nbtc_every_21st_bidder = 22,
	made_2_bids = 23,
	made_3_bids = 24,
	made_4_bids = 25,
	dethrone = 26,
}

interface BidderData {
	bidder: string;
	amount: number;
	timestamp: number;
	wlStatus: number;
	note: string;
	badges: number[];
	bids: number;
	rank: number;
}

async function readCSVData(filePath: string): Promise<BidderData[]> {
	const fileContent = await fs.readFile(filePath, "utf-8");
	const records: BidderData[] = [];

	const data = await new Promise<any[]>((resolve, reject) => {
		parse(
			fileContent,
			{
				columns: true,
				skip_empty_lines: true,
				trim: true,
			},
			(err, data) => {
				if (err) {
					reject(err);
					return;
				}
				resolve(data);
			},
		);
	});

	for (const row of data) {
		let badges: number[] = [];
		if (row.badges && row.badges.trim() !== "") {
			badges = JSON.parse(row.badges);
		}

		records.push({
			bidder: row.bidder.toLowerCase(),
			amount: parseInt(row.amount),
			timestamp: parseInt(row.timestamp),
			wlStatus: parseInt(row.wlStatus),
			note: row.note || "",
			badges,
			bids: parseInt(row.bids),
			rank: parseInt(row.rank),
		});
	}

	return records;
}

function processAndCleanBadges(bidders: BidderData[]): BidderData[] {
	// We are excluding the non-relevant badges for the NFT:
	// - 6 (top_5810 - because everyone gets it)
	// - 14 (WL - not needed for NFT)
	const excludedBadges = new Set([6, 14]);

	return bidders.map((bidder) => {
		//  existing badges, filtered
		const badges = new Set(bidder.badges.filter((badge) => !excludedBadges.has(badge)));

		// Rank-based dynamic badges
		if (bidder.rank === 1) {
			badges.add(Badge.first_place);
		} else if (bidder.rank >= 2 && bidder.rank <= 3) {
			badges.add(Badge.top_3);
		} else if (bidder.rank >= 4 && bidder.rank <= 10) {
			badges.add(Badge.top_10);
		} else if (bidder.rank >= 22 && bidder.rank <= 100) {
			badges.add(Badge.top_100);
		}

		if (bidder.rank >= 1 && bidder.rank <= 21) {
			badges.add(Badge.top_21);
		}

		if (bidder.bids >= 20) {
			badges.add(Badge.made_20_bids);
		} else if (bidder.bids >= 10) {
			badges.add(Badge.made_10_bids);
		} else if (bidder.bids >= 5) {
			badges.add(Badge.made_5_bids);
		} else if (bidder.bids >= 4) {
			badges.add(Badge.made_4_bids);
		} else if (bidder.bids >= 3) {
			badges.add(Badge.made_3_bids);
		} else if (bidder.bids >= 2) {
			badges.add(Badge.made_2_bids);
		}

		if (bidder.rank === 5810) {
			badges.add(Badge.last_bid);
		}
		if (bidder.rank > 0 && (bidder.rank - 1) % 10 === 0) {
			badges.add(Badge.every_10th_position);
		}
		if (bidder.rank > 0 && (bidder.rank - 1) % 21 === 0) {
			badges.add(Badge.nbtc_every_21st_bidder);
		}

		const sortedBadges = Array.from(badges).sort((a, b) => a - b);

		return {
			...bidder,
			badges: sortedBadges,
		};
	});
}

async function main() {
	const inputFile = "scripts/auction_reconcillation/db-with-badges.csv";
	const outputFile = "scripts/auction_reconcillation/processed-badges.csv";

	console.log("Reading CSV data...");
	const bidders = await readCSVData(inputFile);
	console.log(`Loaded ${bidders.length} bidders`);

	console.log("Processing...");
	const first5810Bidders = bidders.filter((b) => b.rank >= 1 && b.rank <= 5810);
	const processedBidders = processAndCleanBadges(first5810Bidders);
	const sortedBidders = processedBidders.sort((b1, b2) => b1.rank - b2.rank);

	console.log("Generating output CSV...");
	let csvLines = ["address,badges"];

	for (const bidder of sortedBidders) {
		const badgesJson = JSON.stringify(bidder.badges);
		csvLines.push(`${bidder.bidder},${badgesJson}`);
	}

	await writeToFile(outputFile, csvLines.join("\n"));

	console.log("Generating badges JSON...");
	const bidderBadges: { [address: string]: number[] } = {};
	for (const bidder of sortedBidders) {
		bidderBadges[bidder.bidder] = bidder.badges;
	}

	const badgesJsonPath = "scripts/auction_reconcillation/badges.json";
	await writeToFile(badgesJsonPath, JSON.stringify(bidderBadges));
	console.log("Badges JSON generation complete!");
}

if (import.meta.main) {
	main().catch(console.error);
}
