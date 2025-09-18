// columns: expected amount of columns
export async function readAndParseCSV<T>(
	filePath: string,
	columns: number,
	parser: (row: string[]) => T,
): Promise<T[]> {
	const file = Bun.file(filePath);
	const text = await file.text();

	const lines = text.trim().split("\n");
	// const headers = lines[0]?.split(",").map((h) => h.trim());

	const records: T[] = [];

	for (let i = 1; i < lines.length; i++) {
		const values = lines[i]?.split(",").map((v) => v.trim());
		if (!values || values.length != columns) {
			throw new Error("Wrong length of record at line " + i);
		}
		records.push(parser(values));
	}

	return records;
}
