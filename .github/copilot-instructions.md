# Copilot Instructions for cpu-x-z-converter

## Project Overview
- **Purpose:** Converts `cpu-x` output to `cpu-z` format for cross-tool compatibility.
- **Key Directories:**
  - `src/`: (Currently empty) Intended for main source code.
  - `data/`: (Currently empty) Reserved for data or intermediate files.
  - `tests/`: Contains test cases with real-world input/output samples.
    - Each `case N/` folder contains paired files: one from `cpu-x`, one from `cpu-z`.

## Test Data Structure
- Example: `tests/case 1/cpu-x.txt` and `tests/case 1/CPU-Z.txt` are input/output pairs.
- Other cases include variations (e.g., system info, OS differences).
- Use these files to validate conversion logic and edge cases.

## Development Patterns
- **No build system or scripts** are present; add scripts to `src/` as needed.
- **Testing:**
  - Use the `tests/` directory for regression and validation.
  - Add new cases by creating a new `case N/` folder with matching input/output files.
- **Conventions:**
  - File naming is case-sensitive and matches the tool (e.g., `cpu-x.txt`, `cpu-z.txt`).
  - Keep test case structure consistent for automation.

## Getting Started
- Implement conversion logic in `src/`.
- Use test files in `tests/` to verify correctness.
- Update this file as project structure evolves.

## Example Workflow
1. Add/modify code in `src/` to perform conversion.
2. Run your code against files in `tests/case N/`.
3. Compare output to the provided `cpu-z.txt` (or equivalent) for validation.

