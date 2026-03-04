#!/bin/bash

# Validate the project setup and configurations

# Check for required files
REQUIRED_FILES=("package.json" "README.md" ".gitignore" "src/workflow/index.ts")

for FILE in "${REQUIRED_FILES[@]}"; do
    if [[ ! -f "$FILE" ]]; then
        echo "Error: Required file '$FILE' is missing."
        exit 1
    fi
done

# Check for required dependencies
if ! command -v npm &> /dev/null; then
    echo "Error: npm is not installed. Please install npm to proceed."
    exit 1
fi

# Validate coding standards (example using eslint)
if ! command -v eslint &> /dev/null; then
    echo "Warning: eslint is not installed. Please install eslint for coding standards validation."
else
    eslint src/**/*.ts
    if [[ $? -ne 0 ]]; then
        echo "Error: Coding standards validation failed."
        exit 1
    fi
fi

echo "Validation completed successfully."