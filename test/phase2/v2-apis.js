// Phase 2 v2: Extended API tests
// Tests for Blob, File, FormData, AbortController, crypto.subtle.sign/verify

// === Blob API ===
const blob = new Blob(['hello', ' ', 'world']);
console.log('Blob size:', blob.size()); // Should be 11
console.log('Blob type:', blob.type()); // Should be empty string

const typedBlob = new Blob(['test'], { type: 'text/plain' });
console.log('Typed Blob type:', typedBlob.type()); // Should be 'text/plain'

// === File API ===
const file = new File(['file content'], 'document.txt', { type: 'text/plain' });
console.log('File name:', file.name()); // Should be 'document.txt'
console.log('File size:', file.size()); // Should be 12
console.log('File type:', file.type()); // Should be 'text/plain'
console.log('File lastModified:', typeof file.lastModified()); // Should be 'number'

// === FormData API ===
const formData = new FormData();
formData.append('username', 'john');
formData.append('email', 'john@example.com');
formData.append('tags', 'javascript');
formData.append('tags', 'web');

console.log('FormData get username:', formData.get('username')); // Should be 'john'
console.log('FormData has email:', formData.has('email')); // Should be true
console.log('FormData has missing:', formData.has('missing')); // Should be false
console.log('FormData getAll tags:', formData.getAll('tags').length); // Should be 2

// FormData.set replaces all values
formData.set('username', 'jane');
console.log('FormData after set:', formData.get('username')); // Should be 'jane'

// FormData.delete
formData.delete('email');
console.log('FormData after delete:', formData.has('email')); // Should be false

// === AbortController API ===
// Note: controller.signal() is a method, but signal.aborted/reason are plain properties (Web API compatible)
const controller = new AbortController();
const signal = controller.signal(); // Call as method

console.log('Signal initial aborted:', signal.aborted); // Should be false
console.log('Signal initial reason:', signal.reason); // Should be undefined

controller.abort('User cancelled');
// Get signal again after abort to see updated state
const signalAfter = controller.signal();
console.log('Signal after abort:', signalAfter.aborted); // Should be true
console.log('Signal reason:', signalAfter.reason); // Should be 'User cancelled'

// === crypto.subtle.sign/verify ===
const key = 'my-secret-key';
const data = 'message to sign';

// Sign with default HMAC-SHA256
const signature = crypto.subtle.sign('HMAC', key, data);
console.log('Signature length (SHA-256):', signature.byteLength); // Should be 32

// Verify valid signature
const isValid = crypto.subtle.verify('HMAC', key, signature, data);
console.log('Verify valid signature:', isValid); // Should be true

// Verify with wrong key
const isInvalid = crypto.subtle.verify('HMAC', 'wrong-key', signature, data);
console.log('Verify wrong key:', isInvalid); // Should be false

// Verify with wrong data
const isWrongData = crypto.subtle.verify('HMAC', key, signature, 'different message');
console.log('Verify wrong data:', isWrongData); // Should be false

// Sign with SHA-512
const sig512 = crypto.subtle.sign({ name: 'HMAC', hash: 'SHA-512' }, key, data);
console.log('Signature length (SHA-512):', sig512.byteLength); // Should be 64

// Verify SHA-512
const valid512 = crypto.subtle.verify({ name: 'HMAC', hash: 'SHA-512' }, key, sig512, data);
console.log('Verify SHA-512:', valid512); // Should be true

console.log('All v2 API tests completed!');
'SUCCESS'
