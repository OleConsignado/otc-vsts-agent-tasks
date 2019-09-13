# directory-exists
# Usage: directory-exists dir

DIRECTORY_EXISTS_EMPTY_PATH_STRING=2
DIRECTORY_EXISTS_DIR_NOT_FOUND=3

# Param dir
function directory-exists
{
	dir=$1

	if [ -z "$dir" ]
	then
		echo "Empty path string." >&2
		return $DIRECTORY_EXISTS_EMPTY_PATH_STRING
	fi

	if ! [ -d "$dir" ]
	then
		echo "'$dir' directory not found." >&2
		return $DIRECTORY_EXISTS_DIR_NOT_FOUND
	fi
	return 0
}