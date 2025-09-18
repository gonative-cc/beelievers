import { promises as fs } from "fs";
import * as path from "path";
import { Command } from "commander";
import { parse } from "csv-parse/sync";

async function main() {
  const program = new Command();
  program
    .argument("<file>", "Path to the input CSV file containing Sui addresses.")
    .option(
      "--typ <number>",
      "The integer type to be assigned to each bidder.",
      (val) => parseInt(val, 10),
    )
    .option(
      "--batch-size <number>",
      "The number of rows per SQL INSERT statement.",
      (val) => parseInt(val, 10),
      10000,
    );

  program.parse(process.argv);
  const inputFile = program.args[0];
  const { amount, typ, batchSize } = program.opts();

  if (typeof amount === "undefined" || typeof typ === "undefined") {
    console.error("❌ Error: --amount and --typ are required arguments.");
    program.help();
    process.exit(1);
  }

  const inputFilename = path.basename(inputFile, path.extname(inputFile));
  const sanitizedFilename = inputFilename.replace(/[^a-zA-Z0-9_-]/g, "");
  const outputDir = `${sanitizedFilename}_sql`;

  await createSqlFiles(inputFile, outputDir, amount, typ, batchSize);

  console.log("\n🎉 SQL generation complete!");
}

main().catch((error) => {
  console.error("A fatal error occurred:", error);
});

async function createSqlFiles(
  inputFile: string,
  outputDir: string,
  amount: number,
  typ: number,
  batchSize: number,
) {
  console.log(`Reading addresses from: ${inputFile}`);
  let addresses: string[];
  try {
    const content = await fs.readFile(inputFile, "utf8");
    const records = parse(content, { columns: false, skip_empty_lines: true });
    addresses = records.flat().map((entry: string) => entry.trim());
  } catch (error) {
    console.error(
      `❌ Error reading or parsing file: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
    return;
  }

  if (addresses.length === 0) {
    console.log("No addresses found in the input file. Exiting.");
    return;
  }

  await fs.mkdir(outputDir, { recursive: true });
  console.log(`Output directory created at: ./${outputDir}`);

  let fileCounter = 1;

  for (let i = 0; i < addresses.length; i += batchSize) {
    const batch = addresses.slice(i, i + batchSize);

    const sqlStatement =
      `INSERT INTO bids (bidder, amount, timestamp, typ) VALUES\n` +
      batch
        .map((address) => `  ('${address}', 0, strftime('%s', 'now'), ${typ})`)
        .join(",\n") +
      ";";

    const outputFilename = path.join(outputDir, `${fileCounter}.sql`);
    try {
      await fs.writeFile(outputFilename, sqlStatement);
      console.log(
        `✅ Successfully wrote batch ${fileCounter} to ${outputFilename}`,
      );
      fileCounter++;
    } catch (error) {
      console.error(
        `❌ Error writing to file ${outputFilename}: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }
}
