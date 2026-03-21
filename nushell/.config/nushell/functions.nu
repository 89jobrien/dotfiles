# Custom functions

# Quick directory listing with size
def dirsize [] {
    ls | select name size type | sort-by size -r
}

# Make a directory and cd into it
def --env mkcd [dir: string] {
    mkdir $dir
    cd $dir
}
