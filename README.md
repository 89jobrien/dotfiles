# Dotfiles

Managed with GNU Stow for easy symlink management.

## Structure

Each directory represents a "package" that can be independently stowed/unstowed:

```
dotfiles/
├── git/           # Git configuration
├── zsh/           # Zsh shell configuration
├── vim/           # Vim configuration
├── vector/        # Vector logging configuration
└── README.md
```

## How Stow Works

Stow creates symlinks from your home directory to files in these packages. The directory structure inside each package mirrors where files should go in `$HOME`.

For example:
- `dotfiles/git/.gitconfig` → `~/.gitconfig`
- `dotfiles/zsh/.zshrc` → `~/.zshrc`
- `dotfiles/vector/.config/vector/` → `~/.config/vector/`

## Usage

### Install (stow) a package
```bash
cd ~/dotfiles
stow git       # Creates symlinks for git config
stow zsh       # Creates symlinks for zsh config
stow vector    # Creates symlinks for vector config
```

### Uninstall (unstow) a package
```bash
cd ~/dotfiles
stow -D git    # Removes git symlinks
```

### Restow (useful after updates)
```bash
cd ~/dotfiles
stow -R git    # Remove and recreate symlinks
```

### Stow all packages at once
```bash
cd ~/dotfiles
stow */        # Stow everything
```

## Adding New Dotfiles

1. Create a package directory if needed: `mkdir ~/dotfiles/newapp`
2. Move your dotfile there with proper structure:
   ```bash
   # If file goes in ~/, put it directly in package dir
   mv ~/.configfile ~/dotfiles/newapp/.configfile

   # If file goes in ~/.config/app/, create that structure
   mkdir -p ~/dotfiles/newapp/.config/app
   mv ~/.config/app/config ~/dotfiles/newapp/.config/app/config
   ```
3. Stow it: `cd ~/dotfiles && stow newapp`
4. Commit: `git add . && git commit -m "Add newapp config"`

## Git Commands

```bash
# Check status
git status

# Add and commit changes
git add .
git commit -m "Update config"

# Push to remote (after setting up remote)
git remote add origin <your-repo-url>
git push -u origin main
```

## Notes

- Stow will NOT overwrite existing files - you must move or delete them first
- Always run stow commands from the `~/dotfiles` directory
- Test with `stow -n <package>` (dry run) to see what would happen
- Each package can be managed independently
