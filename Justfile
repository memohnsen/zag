# Enter the Nix development shell without direnv.
nix:
    nix develop

# Run the editor opening a test file
run:
    zig build run -- ./test.zig

# Run the editor opening the welcome screen
welcome:
    zig build run

# Build the project
build:
    zig build

# Run the full test suite
test:
    zig build check
    zig build test
