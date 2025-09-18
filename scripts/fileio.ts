import { promises as fs } from "fs";

export async function writeToFile(filename: string, content: string) {
	try {
		await fs.writeFile(filename, content);
		console.log(`✅ File ${filename} saved successfully.`);
	} catch (error) {
		console.error(`❌ Error writing to file ${filename}:`, error);
	}
}
