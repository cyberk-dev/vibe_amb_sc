/** @type {import('ts-jest').JestConfigWithTsJest} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/scripts/**/*.test.ts'],
  testTimeout: 300000, // 5 minutes for testnet
  verbose: true,
};