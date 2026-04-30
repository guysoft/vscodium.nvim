#!/usr/bin/env python3
"""Test script for debug-reach skill verification."""


def calculate_sum(a, b):
    """Add two numbers."""
    result = a + b  # Line 7 - target breakpoint line
    return result


def process_items(items):
    """Process a list of items."""
    total = 0
    for item in items:
        total = calculate_sum(total, item)  # Line 15
    return total


def main():
    """Entry point."""
    numbers = [1, 2, 3, 4, 5]
    result = process_items(numbers)  # Line 22
    print(f"Sum of {numbers} = {result}")  # Line 23 - should reach here
    return result


if __name__ == "__main__":
    main()
