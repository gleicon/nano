// Phase 1: Basic execution tests
// Run: nano eval "$(cat test/fixtures/basic.js)"

// Arithmetic
const sum = 1 + 1;
const product = 6 * 7;

// Strings
const greeting = "hello" + " " + "world";

// Objects
const config = { name: "nano", version: 1 };

// Arrays
const numbers = [1, 2, 3, 4, 5];
const doubled = numbers.map(n => n * 2);

// JSON
const json = JSON.stringify({ result: sum, greeting });

json
