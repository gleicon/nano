// Phase 1: Basic evaluation tests
// Status: Should PASS after Phase 1 complete

// Test: Arithmetic
1 + 1 === 2;

// Test: Multiplication
6 * 7 === 42;

// Test: String concatenation
"hello" + " " + "world" === "hello world";

// Test: Template literals
`sum: ${1 + 1}` === "sum: 2";

// Test: JSON.stringify
JSON.stringify({a: 1}) === '{"a":1}';

// Test: JSON.parse
JSON.parse('{"a":1}').a === 1;

// Test: Array methods
[1,2,3].map(n => n * 2).join(",") === "2,4,6";

// Test: Math
Math.sqrt(16) === 4;
