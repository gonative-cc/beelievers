import { Transaction } from '@mysten/sui/transactions';
import { SuiClient, getFullnodeUrl } from '@mysten/sui/client';
import { Ed25519Keypair } from "@mysten/sui/keypairs/ed25519";

// PLACEHOLDER: Update these values
const NFT_TYPE = '0x3aeca4699ce5f914b56ee04b8ccd4b2eba1b93cabbab9f1a997735c52ef76253::mint::BeelieverNFT';
const DISPLAY_ID = '0x1282058e65d80c3937f00e5da5bb3df1cbf0228294e9c9b43babf118f07d3487';
const FIELD_NAME = 'image_url';
const NEW_VALUE = '';

import 'dotenv/config';
// Load keypair from mnemonic
function getKeypair(): Ed25519Keypair {
	return Ed25519Keypair.deriveKeypair(process.env.MNEMONIC!);
}

// Edit display fields
export async function editDisplay(displayId: string, field: string, newValue: string) {
	const client = new SuiClient({ url: getFullnodeUrl('mainnet') });
	const keypair = getKeypair();
	console.log(keypair.toSuiAddress())
	const txb = new Transaction();

	if (newValue === '') {
		throw new Error("You should set the new image_url value");
	}
	// Call display::edit with type parameters
	txb.moveCall({
		target: '0x2::display::edit',
		typeArguments: [NFT_TYPE],
		arguments: [txb.object(displayId), txb.pure.string(field), txb.pure.string(newValue)],
	});

	// Call display::update_version
	txb.moveCall({
		target: '0x2::display::update_version',
		typeArguments: [NFT_TYPE],
		arguments: [txb.object(displayId)],
	});

	const result = await client.signAndExecuteTransaction({
		signer: keypair,
		transaction: txb,
		options: { showEffects: true },
	});

	console.log('✅ Display edited successfully!');
	console.log('Transaction digest:', result.digest);
	console.log('Status:', result.effects?.status?.status);

	return result;
}

// CLI usage
if (import.meta.main) {
	editDisplay(DISPLAY_ID, FIELD_NAME, NEW_VALUE)
		.then(() => process.exit(0))
		.catch((error) => {
			console.log(error)
			process.exit(1);
		});
}
