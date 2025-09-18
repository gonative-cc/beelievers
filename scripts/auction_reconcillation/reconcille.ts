import { readAndParseCSV } from "../csv";

interface EventCsvRecord {
	bidder: string;
	amount: number;
	timestamp: number;
}

// bidder , boost status
type Boost = [string, boolean];

interface GroupedBidder {
	rank: number;
	bidder: string;
	amount: number;
	boostedAmount: number;
	highestBid: number; // highest single bid
	timestamp: number;
	bids: number;
	boosted: boolean;
	txs: EventCsvRecord[];
}

async function readEvents(filePath: string): Promise<EventCsvRecord[]> {
	const parser = (row: string[]) => {
		return {
			bidder: row[0] || "",
			amount: Number(row[1]),
			timestamp: Number(row[2]),
		};
	};
	return readAndParseCSV(filePath, 3, parser);
}

async function readBoost(filePath: string): Promise<Map<string, boolean>> {
	const parser = (row: string[]): Boost => {
		return [row[0] || "", row[1] === "TRUE"];
	};
	const records = await readAndParseCSV(filePath, 2, parser);
	return new Map(records);
}

function groupByBidder(events: EventCsvRecord[]): GroupedBidder[] {
	const bidderMap = new Map<string, GroupedBidder>();

	// Group by bidder and calculate statistics
	for (const event of events) {
		const existing = bidderMap.get(event.bidder);

		if (!existing) {
			bidderMap.set(event.bidder, {
				bidder: event.bidder,
				amount: event.amount,
				boostedAmount: 0,
				timestamp: event.timestamp,
				bids: 1,
				rank: 0,
				boosted: false,
				txs: [event],
				highestBid: 0,
			});
		} else {
			existing.amount = Math.max(existing.amount, event.amount);
			existing.timestamp = Math.max(existing.timestamp, event.timestamp);
			existing.bids += 1;
			existing.txs.push(event);
		}
	}

	const bidders = Array.from(bidderMap.values());

	// set highest bid
	for (const b of bidders) {
		b.txs.sort((a, b) => a.timestamp - b.timestamp);
		let prev = b.txs[0] as EventCsvRecord;
		b.highestBid = prev.amount;
		for (const t of b.txs.slice(1)) {
			const diff = t.amount - prev.amount;
			if (diff > b.highestBid) b.highestBid = diff;
		}
	}

	return bidders;
}

async function applyBoost(bidders: GroupedBidder[], boostFilename: string) {
	const boostMapping = await readBoost(boostFilename);
	for (const b of bidders) {
		if (boostMapping.get(b.bidder)) {
			b.boostedAmount = Math.floor(b.amount * 1.05);
			b.boosted = true;
		} else {
			b.boostedAmount = b.amount;
		}
	}
}

function computeRank(bidders: GroupedBidder[]) {
	// Sort by maxAmount (desc) then maxTimestamp (asc)
	bidders.sort((a, b) => {
		if (b.boostedAmount !== a.boostedAmount) {
			return b.boostedAmount - a.boostedAmount; // Descending by amount
		}
		return a.timestamp - b.timestamp; // Ascending by timestamp
	});

	bidders.forEach((bidder, index) => {
		bidder.rank = index + 1;
	});
}

async function saveToCSV(bidders: GroupedBidder[], filePath: string): Promise<void> {
	const headers = [
		"rank",
		"bidder",
		// "amount",
		"boostedAmount",
		"timestamp",
		// "date",
		"boosted",
		"bids",
		"highestSingleBid",
	];
	const lines = [headers.join(",")];

	for (const bidder of bidders) {
		const row = [
			bidder.rank.toString(),
			bidder.bidder,
			// bidder.amount,
			bidder.boostedAmount.toString(),
			bidder.timestamp.toString(),
			// new Date(bidder.timestamp).toISOString(),
			bidder.boosted.toString(),
			bidder.bids.toString(),
			bidder.highestBid.toString(),
		];
		lines.push(row.join(","));
	}

	const csvContent = lines.join("\n");
	await Bun.write(filePath, csvContent);
	console.log(`Results saved to ${filePath}`);
}

function assureArray2<T>(arr: T[]): arr is [T, T] {
	return arr.length === 2;
}

async function main() {
	const args = process.argv.slice(2) as string[] & { length: 5 };

	if (!assureArray2(args)) {
		console.error("Usage: bun run ./reconcille.ts <events-csv-file> <out-csv-file>");
		console.error("Example: bun run ./reconcille.ts ./bid_events.csv output.csv");
		process.exit(1);
	}

	const csvInputFile = args[0];
	const csvOutputFile = args[1];

	try {
		console.log("Reading CSV file...");
		const events = await readEvents(csvInputFile);

		console.log("\nGrouping by bidder...");
		let groupedBidders = groupByBidder(events);

		await applyBoost(groupedBidders, "boosted.csv");

		console.log("Computing ranks...");
		computeRank(groupedBidders);

		// check order is correct
		let prev = groupedBidders[0] as GroupedBidder;
		for (let b of groupedBidders) {
			//if (prev.rank >= b.rank) console.error("rank not in order", b.bidder);
			if (prev.boostedAmount < b.boostedAmount)
				console.error("amount not in order", b.bidder);
			if (prev.boostedAmount === b.boostedAmount && prev.timestamp > b.timestamp)
				console.error("timestamp not in order", b.bidder);
			prev = b;
		}

		await saveToCSV(groupedBidders, csvOutputFile);

		console.log(`\nSummary:`);
		console.log(`  Unique bidders: ${groupedBidders.length}`);
		console.log("  Amount of bids:", events.length);
		// NOTE: clearing price is a price of auctionSize + 1 rank. But in the array we index
		// from 0, so the 5811 rank is indexed as auctionSize
		const clearingPriceIndex = 5810;
		console.log("  Clearing Price:", groupedBidders[clearingPriceIndex]?.amount);
	} catch (error) {
		console.error("Error:", error);
	}
}

//
// START
//

main();

// expected amount of bidders: 10208
//  -- this is what we have in the contract.bidders.fields.size
//     https://suivision.xyz/object/0x161524be15687cca96dec58146568622458905c30479452351f231cac5d64c41
