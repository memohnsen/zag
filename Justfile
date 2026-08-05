# Run the editor opening a test file
run:
    zig build run -- ./test.txt

# Run the editor opening the welcome screen
welcome:
    zig build run

# Build the project
build:
    zig build

# Run the full test suite
test:
    zig build test
