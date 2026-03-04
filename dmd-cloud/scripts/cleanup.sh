#!/bin/bash

# Cleanup script to remove unnecessary files from the project directory

# Define the directories to clean
directories_to_clean=(
    "node_modules"
    "dist"
    "build"
    "coverage"
)

# Remove unnecessary directories
for dir in "${directories_to_clean[@]}"; do
    if [ -d "$dir" ]; then
        echo "Removing directory: $dir"
        rm -rf "$dir"
    fi
done

# Remove unnecessary files
find . -type f \( -name "*.log" -o -name "*.tmp" -o -name "*.bak" \) -exec rm -f {} +

echo "Cleanup completed."