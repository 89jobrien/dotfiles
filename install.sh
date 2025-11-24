#!/bin/bash
# Dotfiles installation script

set -e

echo "🔧 Dotfiles Installation"
echo "========================"
echo ""

# Check if stow is installed
if ! command -v stow &> /dev/null; then
    echo "❌ GNU Stow is not installed. Install it with: brew install stow"
    exit 1
fi

# Get the directory where this script is located
DOTFILES_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DOTFILES_DIR"

echo "📁 Dotfiles directory: $DOTFILES_DIR"
echo ""

# Function to stow a package
stow_package() {
    local package=$1
    echo "  📦 Stowing $package..."

    # Dry run first to check for conflicts
    if stow -n "$package" 2>&1 | grep -q "WARNING\|ERROR"; then
        echo "  ⚠️  Conflicts detected for $package. Run manually with: stow $package"
    else
        stow "$package"
        echo "  ✅ $package stowed successfully"
    fi
}

# Stow all packages
echo "📌 Stowing packages..."
echo ""

for dir in */; do
    # Skip non-directories and hidden directories
    [[ -d "$dir" ]] || continue
    package="${dir%/}"

    # Skip if not a package directory (contains dotfiles)
    if [[ -d "$package" ]] && [[ ! "$package" =~ ^\. ]]; then
        stow_package "$package"
    fi
done

echo ""
echo "✨ Installation complete!"
echo ""
echo "💡 Tips:"
echo "  - Run 'stow -D <package>' to uninstall a package"
echo "  - Run 'stow -R <package>' to restow (update) a package"
echo "  - Run 'stow -n <package>' to dry-run (see what would happen)"
